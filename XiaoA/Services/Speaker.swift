import AVFoundation

/// Shared audio rules, so reading aloud never fights the interpreter's microphone.
enum AudioCoordinator {
    static var interpreterActive = false
    static var listening = false

    static func prepareForPlayback() {
        guard !interpreterActive, !listening else { return }
        let session = AVAudioSession.sharedInstance()
        // .playback ignores the silent switch, so Mom always hears 小A.
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }
}

/// Reads text aloud on-device (works offline).
@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    @Published private(set) var isSpeaking = false
    /// Lets the interpreter mute its microphone while 小A is talking.
    var onSpeakingChange: ((Bool) -> Void)?

    private let synth = AVSpeechSynthesizer()

    nonisolated static let normalRate: Float = 0.46
    nonisolated static let slowRate: Float = 0.34

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String, language: String, rate: Float = Speaker.normalRate) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        synth.stopSpeaking(at: .immediate)
        AudioCoordinator.prepareForPlayback()
        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = Self.bestVoice(for: language)
        utterance.rate = rate
        utterance.postUtteranceDelay = 0.1
        if Self.silent { utterance.volume = 0 }
        synth.speak(utterance)
    }

    func speakChinese(_ text: String) { speak(text, language: "zh-CN") }
    func speakEnglish(_ text: String, slow: Bool = false) {
        speak(text, language: "en-US", rate: slow ? Self.slowRate : Self.normalRate)
    }

    /// Speaks several pieces back to back, e.g. a Chinese tip followed by the English phrase.
    func speakSequence(_ parts: [(text: String, language: String, rate: Float)]) {
        synth.stopSpeaking(at: .immediate)
        AudioCoordinator.prepareForPlayback()
        for part in parts where !part.text.isEmpty {
            let utterance = AVSpeechUtterance(string: part.text)
            utterance.voice = Self.bestVoice(for: part.language)
            utterance.rate = part.rate
            utterance.postUtteranceDelay = 0.25
            if Self.silent { utterance.volume = 0 }
            synth.speak(utterance)
        }
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    /// English one word at a time (as sequence parts), for a beginner to follow.
    func wordByWord(_ english: String, rate: Float) -> [(text: String, language: String, rate: Float)] {
        english.split(separator: " ").map { (String($0), "en-US", rate) }
    }

    /// Waits until everything queued has been said, plus a moment, so the microphone that
    /// opens next never hears the phone itself. Returns early if the task is cancelled.
    func waitUntilDone(timeout: TimeInterval = 40) async {
        let started = Date()
        try? await Task.sleep(nanoseconds: 200_000_000)
        var quietPolls = 0
        while !Task.isCancelled && Date().timeIntervalSince(started) < timeout {
            if synth.isSpeaking {
                quietPolls = 0
            } else {
                quietPolls += 1
                if quietPolls >= 3 { return }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
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
        Task { @MainActor in self.setSpeaking(true) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.setSpeaking(false) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.setSpeaking(false) }
    }

    private func setSpeaking(_ value: Bool) {
        isSpeaking = value
        onSpeakingChange?(value)
    }
}
