#if canImport(FluidAudio)
// Parked 2026-10-14: voiceprint interpreter. Builds only once the FluidAudio package is added back.
import SwiftUI
import AVFoundation

/// 让小A认识你的声音: Mom reads three short sentences (about 20 seconds). The phone keeps her
/// voiceprint (numbers, not the recording) so 翻译官 knows when she is the one talking.
struct VoiceEnrollmentView: View {
    var onDone: () -> Void

    private enum Step: Equatable {
        case preparing
        case ready(Int)        // waiting to read sentence n
        case recording(Int)
        case checking
        case done
        case problem(String)
    }

    static let sentences = [
        "今天天气很好，我想出去走一走。",
        "请问附近有没有超市？我想买点水果。",
        "谢谢你帮我，认识你很高兴。"
    ]

    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = EnrollmentRecorder()
    @State private var step: Step = .preparing
    @State private var clips: [[Float]] = []

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button { recorder.stop(); dismiss() } label: {
                    Text("关闭").font(.xa(20, .heavy)).foregroundStyle(Palette.ink2)
                        .padding(.horizontal, 16).frame(height: 48)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(Squish())
                Spacer()
            }
            .padding(.top, 8)

            Text("让小A认识你的声音").font(.xa(28, .heavy)).foregroundStyle(Palette.ink)

            content
                .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(ScreenBackground())
        .task { await prepare() }
        .onDisappear { recorder.stop() }
        .interactiveDismissDisabled(step == .checking)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .preparing:
            VStack(spacing: 16) {
                Spacer()
                ProgressView().controlSize(.large)
                Text("正在准备……").font(.xa(22, .bold)).foregroundStyle(Palette.ink2)
                Text("第一次要下载一点东西，请连着网络。").font(.xa(18, .medium)).foregroundStyle(Palette.ink2)
                Spacer()
            }

        case .ready(let n), .recording(let n):
            let recording = step == .recording(n)
            VStack(spacing: 18) {
                MascotSays(text: recording ? "好，请读出来" : "像平时聊天一样，读这句话",
                           detail: "手机放在面前就行。第 \(n + 1) 句，共 \(Self.sentences.count) 句。")
                Text(Self.sentences[n])
                    .font(.xa(32, .heavy))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28).padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(recording ? Palette.teal : Color.clear, lineWidth: 4)
                    )
                Spacer()
                if recording {
                    Image(systemName: "waveform")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Palette.teal)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                    BigButton(title: "读完了", systemImage: "checkmark", fill: Palette.ink, depth: nil,
                              height: 76, fontSize: 28) { finishSentence(n) }
                } else {
                    BigButton(title: "开始读", systemImage: "mic.fill", fill: Palette.teal, depth: Palette.tealDeep,
                              height: 76, fontSize: 28) { startSentence(n) }
                }
            }

        case .checking:
            VStack(spacing: 16) {
                Spacer()
                ProgressView().controlSize(.large)
                Text("小A 正在记住……").font(.xa(22, .bold)).foregroundStyle(Palette.ink2)
                Spacer()
            }

        case .done:
            VStack(spacing: 18) {
                Spacer()
                Mascot(mood: .happy, size: 120)
                Text("记住了！").font(.xa(34, .heavy)).foregroundStyle(Palette.ink)
                Text("以后你说话，小A 就知道是你。\n你的声音只存在这个手机里。")
                    .font(.xa(20, .medium)).foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center)
                Spacer()
                BigButton(title: "好的", systemImage: "checkmark", fill: Palette.teal, depth: Palette.tealDeep,
                          height: 76, fontSize: 28) {
                    dismiss()
                    onDone()
                }
            }

        case .problem(let message):
            VStack(spacing: 18) {
                Spacer()
                Mascot(mood: .calm, size: 100)
                Text(message).font(.xa(22, .bold)).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Spacer()
                BigButton(title: "再录一次", systemImage: "arrow.clockwise", fill: Palette.teal, depth: Palette.tealDeep,
                          height: 76, fontSize: 28) {
                    clips.removeAll()
                    Task { await prepare() }
                }
            }
        }
    }

    private func prepare() async {
        step = .preparing
        do {
            try await VoiceID.shared.prepare()
            step = .ready(0)
        } catch {
            step = .problem("需要连上网络，下载一次声音识别（约 35MB）。")
        }
    }

    private func startSentence(_ n: Int) {
        Task {
            guard await AVAudioApplication.requestRecordPermission() else {
                step = .problem("需要打开麦克风权限。请让 Alex 在 iPhone 设置 › 小A 里打开。")
                return
            }
            do {
                try recorder.start()
                step = .recording(n)
                // If she forgets to tap 读完了, stop by itself after 10 seconds.
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if step == .recording(n) { finishSentence(n) }
            } catch {
                step = .problem("麦克风打不开，请再试一次。")
            }
        }
    }

    private func finishSentence(_ n: Int) {
        let clip = recorder.stop()
        // At least ~1.5 s of sound, or it's too short to learn from.
        guard clip.count >= VoiceID.sampleRate * 3 / 2 else {
            step = .ready(n)
            return
        }
        clips.append(clip)
        if n + 1 < Self.sentences.count {
            step = .ready(n + 1)
        } else {
            Task { await learn() }
        }
    }

    private func learn() async {
        step = .checking
        var prints: [[Float]] = []
        for clip in clips {
            if let print = try? await VoiceID.shared.voiceprint(of: clip) { prints.append(print) }
        }
        guard prints.count == clips.count, !prints.isEmpty else {
            step = .problem("没录清楚，我们再录一次吧。")
            return
        }
        // The three sentences should sound like the same person. If not, it was too noisy.
        var worst: Float = 0
        for i in prints.indices {
            for j in prints.indices where j > i {
                worst = max(worst, VoiceID.distance(prints[i], prints[j]))
            }
        }
        print(String(format: "[XA] Mom's voiceprint: %d sentences, most different pair %.2f", prints.count, worst))
        guard worst < 0.5 else {
            step = .problem("周围有点吵，听不太清楚。找个安静的地方，我们再录一次吧。")
            return
        }
        MomVoiceprint.save(prints + [VoiceID.mean(prints)])
        Haptics.success()
        step = .done
    }
}

/// Records 16 kHz mono from the microphone, in the same mode the interpreter listens in.
final class EnrollmentRecorder: ObservableObject, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    /// Only touched on the audio thread once recording starts.
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var running = false

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        try session.setActive(true)
        lock.lock(); samples.removeAll(); lock.unlock()
        converter = nil
        let input = engine.inputNode
        guard input.outputFormat(forBus: 0).sampleRate > 0 else {
            throw NSError(domain: "XiaoA.Enroll", code: 1)
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    /// Stops and returns what was recorded.
    @discardableResult
    func stop() -> [Float] {
        if running {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            running = false
        }
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0, buffer.format.sampleRate > 0 else { return }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let p = out.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: p, count: Int(out.frameLength)))
        lock.lock(); samples.append(contentsOf: chunk); lock.unlock()
    }
}
#endif
