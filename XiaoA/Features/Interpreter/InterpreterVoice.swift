import SwiftUI
import AVFoundation

/// The OpenAI voices Alex can pick for 翻译官 (Alex mode › Interpreter voices).
/// One voice says Mom's words to the other person; one says their words to Mom.
struct InterpreterVoice: Identifiable, Hashable {
    let id: String
    let name: String
    let about: String

    static let all: [InterpreterVoice] = [
        .init(id: "marin", name: "Marin", about: "Warm, natural woman's voice. OpenAI's best."),
        .init(id: "cedar", name: "Cedar", about: "Calm, natural man's voice. OpenAI's best."),
        .init(id: "coral", name: "Coral", about: "Bright, friendly woman's voice."),
        .init(id: "sage", name: "Sage", about: "Soft, gentle woman's voice."),
        .init(id: "shimmer", name: "Shimmer", about: "Light, clear woman's voice."),
        .init(id: "ash", name: "Ash", about: "Clear, steady man's voice."),
        .init(id: "ballad", name: "Ballad", about: "Soft, expressive man's voice."),
        .init(id: "verse", name: "Verse", about: "Lively, expressive man's voice.")
    ]

    static let defaultID = "marin"
    /// UserDefaults keys (also used with @AppStorage).
    static let momKey = "voiceForMom"
    static let othersKey = "voiceForOthers"

    /// Says Mom's words to the other person, in English or German.
    static var forMom: String { saved(momKey) }
    /// Says the other person's words to Mom, in Chinese.
    static var forOthers: String { saved(othersKey) }

    static func named(_ id: String) -> InterpreterVoice {
        all.first { $0.id == id } ?? all[0]
    }

    private static func saved(_ key: String) -> String {
        let id = UserDefaults.standard.string(forKey: key) ?? defaultID
        return all.contains { $0.id == id } ? id : defaultID
    }
}

/// Makes translated speech louder and evenly loud without distortion: quiet words are lifted by
/// up to ~10 dB, and loud moments are held just under the maximum. It sees each ~100 ms chunk
/// before it plays, so it turns down ahead of a loud moment instead of clipping it.
struct SpeechBooster {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000,
                                      channels: 1, interleaved: false)!
    static let maxGain: Float = 3.2
    static let ceiling: Float = 0.95
    private var gain: Float = 2

    /// 24 kHz mono PCM16 in, a louder buffer ready to play out.
    mutating func boost(_ pcm16: Data) -> AVAudioPCMBuffer? {
        let frames = pcm16.count / 2
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        var peak: Float = 0
        pcm16.withUnsafeBytes { raw in
            for i in 0..<frames {
                let v = Float(raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self)) / 32768
                channel[i] = v
                peak = max(peak, abs(v))
            }
        }
        let safe = peak > 0.0001 ? min(Self.maxGain, Self.ceiling / peak) : Self.maxGain
        let start = gain
        // Down at once, so nothing clips; back up gently, about 1 dB per chunk.
        let target = safe < start ? safe : min(safe, start * 1.12)
        let ramp = target < start ? min(frames, 120) : frames
        for i in 0..<frames {
            let g = i < ramp ? start + (target - start) * Float(i) / Float(ramp) : target
            channel[i] = max(-1, min(1, channel[i] * g))
        }
        gain = target
        return buffer
    }
}

/// Plays a short sample of a voice in Alex mode.
@MainActor
final class VoicePreview: ObservableObject {
    /// Which sample is playing (voice id + side), if any.
    @Published private(set) var playing: String?
    @Published private(set) var problem: String?

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var booster = SpeechBooster()
    private var endsAt = Date()
    private var task: Task<Void, Never>?

    func play(_ voice: String, chinese: Bool, partner: PartnerLanguage, tag: String) {
        stop()
        guard let apiKey = APIKeys.get(.openAI) else {
            problem = "Save the OpenAI key first."
            return
        }
        problem = nil
        let text: String
        if chinese {
            text = "您好！很高兴认识您。请问最近的地铁站怎么走？"
        } else if partner == .german {
            text = "Hallo! Schön, Sie kennenzulernen. Wie komme ich zur nächsten U-Bahn-Station?"
        } else {
            text = "Hi! Nice to meet you. Could you tell me how to get to the nearest train station?"
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: SpeechBooster.format)
        AudioCoordinator.prepareForPlayback()
        do {
            try engine.start()
        } catch {
            problem = "Couldn't play: \(error.localizedDescription)"
            return
        }
        player.play()
        self.engine = engine
        self.player = player
        booster = SpeechBooster()
        endsAt = Date()
        playing = tag
        task = Task { [weak self] in
            do {
                try await OpenAISpeech.speak(text, apiKey: apiKey, voice: voice, chinese: chinese) { chunk in
                    await self?.schedule(chunk)
                }
            } catch {
                if !Task.isCancelled { self?.problem = "Voice failed: \(error.localizedDescription)" }
            }
            while let self, !Task.isCancelled, Date() < self.endsAt {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if !Task.isCancelled { self?.stop() }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        playing = nil
    }

    private func schedule(_ chunk: Data) {
        guard let player, let buffer = booster.boost(chunk) else { return }
        endsAt = max(Date(), endsAt).addingTimeInterval(Double(buffer.frameLength) / SpeechBooster.format.sampleRate)
        player.scheduleBuffer(buffer, completionHandler: nil)
    }
}

/// Alex mode › Interpreter voices › (one side): every voice with a play button.
struct VoiceChooser: View {
    let title: String
    let key: String
    let chinese: Bool
    @AppStorage("interpreterPartner") private var partnerCode = PartnerLanguage.english.rawValue
    @AppStorage private var selected: String
    @StateObject private var preview = VoicePreview()

    init(title: String, key: String, chinese: Bool) {
        self.title = title
        self.key = key
        self.chinese = chinese
        _selected = AppStorage(wrappedValue: InterpreterVoice.defaultID, key)
    }

    var body: some View {
        List {
            Section {
                ForEach(InterpreterVoice.all) { voice in
                    HStack(spacing: 12) {
                        Button {
                            selected = voice.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(voice.name).foregroundStyle(.primary)
                                    Text(voice.about).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selected == voice.id {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            if preview.playing == voice.id {
                                preview.stop()
                            } else {
                                preview.play(voice.id, chinese: chinese,
                                             partner: PartnerLanguage(rawValue: partnerCode) ?? .english,
                                             tag: voice.id)
                            }
                        } label: {
                            Image(systemName: preview.playing == voice.id ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(preview.playing == voice.id ? "Stop" : "Play \(voice.name)")
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                if let problem = preview.problem {
                    Text(problem).foregroundStyle(.red)
                } else {
                    Text(chinese
                         ? "Tap ▶︎ to hear a Chinese sample. Tap a name to use it."
                         : "Tap ▶︎ to hear a sample in the other person's language. Tap a name to use it.")
                }
            }
        }
        .navigationTitle(title)
        .onDisappear { preview.stop() }
    }
}
