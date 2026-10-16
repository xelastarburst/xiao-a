import AVFoundation

/// Shared audio rules, so reading aloud never fights the interpreter's microphone.
enum AudioCoordinator {
    static var interpreterActive = false
    static var listening = false
    /// A lesson is going: 小A talks and listens in turn every few seconds.
    static var lessonActive = false

    static func prepareForPlayback() {
        guard !interpreterActive, !listening else { return }
        let session = AVAudioSession.sharedInstance()
        if lessonActive {
            // Stay in the same record-and-play setup the microphone uses, so switching between
            // talking and listening is instant and no reading gets cut off or silenced.
            try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        } else {
            // .playback ignores the silent switch, so Mom always hears 小A.
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        }
        try? session.setActive(true)
    }
}

/// Reads text aloud on-device (works offline).
@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    typealias Part = (text: String, language: String, rate: Float)

    @Published private(set) var isSpeaking = false
    /// Lets the interpreter mute its microphone while 小A is talking.
    var onSpeakingChange: ((Bool) -> Void)?

    private var synth = AVSpeechSynthesizer()
    /// Utterances asked for and not yet finished. "Done" means this is empty, which works even
    /// when a voice takes a second or more to start (older iPhones, first use of a voice).
    private var pending = Set<ObjectIdentifier>()
    private var lastStart = Date.distantPast
    /// The last request, so speech that never starts can be asked for once more.
    private var lastRequest: (parts: [Part], gap: TimeInterval) = ([], 0)

    nonisolated static let normalRate: Float = 0.46
    nonisolated static let slowRate: Float = 0.34

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String, language: String, rate: Float = Speaker.normalRate) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        start([(clean, language, rate)], gap: 0.1)
    }

    func speakChinese(_ text: String) { speak(text, language: "zh-CN") }
    func speakEnglish(_ text: String, slow: Bool = false) {
        speak(text, language: "en-US", rate: slow ? Self.slowRate : Self.normalRate)
    }

    /// Speaks several pieces back to back, e.g. a Chinese tip followed by the English phrase.
    func speakSequence(_ parts: [Part]) {
        start(parts, gap: 0.25)
    }

    func stop() {
        interrupt()
    }

    private func start(_ parts: [Part], gap: TimeInterval) {
        interrupt()
        AudioCoordinator.prepareForPlayback()
        lastRequest = (parts, gap)
        enqueue(parts, gap: gap)
    }

    private func enqueue(_ parts: [Part], gap: TimeInterval) {
        for part in parts where !part.text.isEmpty {
            let utterance = AVSpeechUtterance(string: part.text)
            utterance.voice = Self.bestVoice(for: part.language)
            utterance.rate = part.rate
            utterance.postUtteranceDelay = gap
            if Self.silent { utterance.volume = 0 }
            pending.insert(ObjectIdentifier(utterance))
            synth.speak(utterance)
        }
    }

    /// Stops whatever is being said. A fresh synthesizer takes over: asking the same one to
    /// speak right after stopping it sometimes plays nothing.
    private func interrupt() {
        if synth.isSpeaking || !pending.isEmpty {
            synth.delegate = nil
            synth.stopSpeaking(at: .immediate)
            synth = AVSpeechSynthesizer()
            synth.delegate = self
        }
        pending.removeAll()
        if isSpeaking { setSpeaking(false) }
    }

    /// English one word at a time (as sequence parts), for a beginner to follow.
    func wordByWord(_ english: String, rate: Float) -> [(text: String, language: String, rate: Float)] {
        english.split(separator: " ").map { (String($0), "en-US", rate) }
    }

    /// Waits until everything asked for has been said, plus a moment, so the microphone that
    /// opens next never hears the phone itself. If nothing has started after 3 seconds, the speech
    /// was dropped: it is asked for once more. Returns early if the task is cancelled.
    func waitUntilDone(timeout: TimeInterval = 40) async {
        let asked = Date()
        var retried = false
        while !Task.isCancelled && Date().timeIntervalSince(asked) < timeout {
            if pending.isEmpty {
                try? await Task.sleep(nanoseconds: 250_000_000)
                return
            }
            if !retried && lastStart < asked && Date().timeIntervalSince(asked) > 3 {
                retried = true
                print("[Speaker] speech didn't start within 3 s; asking again")
                let request = lastRequest
                interrupt()
                AudioCoordinator.prepareForPlayback()
                enqueue(request.parts, gap: request.gap)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if !Task.isCancelled { print("[Speaker] gave up waiting for speech to finish") }
    }

    /// The simulator demo keeps quiet (timing and callbacks unchanged) unless Alex turns sound on.
    private static var silent: Bool { Demo.isOn && !Demo.soundOn }

    private static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return voices.first(where: { $0.quality == .premium })
            ?? voices.first(where: { $0.quality == .enhanced })
            ?? AVSpeechSynthesisVoice(language: language)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let from = ObjectIdentifier(synthesizer)
        Task { @MainActor in
            guard from == ObjectIdentifier(self.synth) else { return }
            self.lastStart = Date()
            if !self.isSpeaking { self.setSpeaking(true) }
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(utterance: ObjectIdentifier(utterance), from: ObjectIdentifier(synthesizer))
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(utterance: ObjectIdentifier(utterance), from: ObjectIdentifier(synthesizer))
    }

    nonisolated private func finished(utterance: ObjectIdentifier, from synthesizer: ObjectIdentifier) {
        Task { @MainActor in
            // Ignore late callbacks from a synthesizer that was already replaced.
            guard synthesizer == ObjectIdentifier(self.synth) else { return }
            self.pending.remove(utterance)
            if self.pending.isEmpty && self.isSpeaking { self.setSpeaking(false) }
        }
    }

    private func setSpeaking(_ value: Bool) {
        isSpeaking = value
        onSpeakingChange?(value)
    }
}
