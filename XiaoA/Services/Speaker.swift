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

/// What Speaker needs from a speech synthesizer (AVSpeechSynthesizer; a fake in tests).
@MainActor
protocol SpeechEngine: AnyObject {
    var isSpeaking: Bool { get }
    var delegate: AVSpeechSynthesizerDelegate? { get set }
    func speak(_ utterance: AVSpeechUtterance)
    @discardableResult func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
}

extension AVSpeechSynthesizer: SpeechEngine {}

/// Reads text aloud on-device (works offline).
@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    typealias Part = (text: String, language: String, rate: Float)

    @Published private(set) var isSpeaking = false
    /// Lets the interpreter mute its microphone while 小A is talking.
    var onSpeakingChange: ((Bool) -> Void)?

    private let makeEngine: () -> SpeechEngine
    private var synth: SpeechEngine
    /// Speech that hasn't started after this long was dropped, and is asked for once more.
    var retryAfter: TimeInterval = 3
    /// Utterances asked for and not yet finished. "Done" means this is empty, which works even
    /// when a voice takes a second or more to start (older iPhones, first use of a voice).
    private var pending = Set<ObjectIdentifier>()
    private var lastStart = Date.distantPast
    /// The last request, so speech that never starts can be asked for once more.
    private var lastRequest: (parts: [Part], gap: TimeInterval) = ([], 0)
    /// When it was asked for: speech that started after this is under way and is never repeated.
    private var requestedAt = Date.distantPast
    /// Sets up the audio session before speaking (tests replace it: a fake voice needs no audio).
    var preparePlayback: () -> Void = { AudioCoordinator.prepareForPlayback() }

    nonisolated static let normalRate: Float = 0.46
    nonisolated static let slowRate: Float = 0.34

    override convenience init() {
        self.init(makeEngine: { AVSpeechSynthesizer() })
    }

    init(makeEngine: @escaping () -> SpeechEngine) {
        self.makeEngine = makeEngine
        synth = makeEngine()
        super.init()
        synth.delegate = self
    }

    /// Sentences asked for and not yet finished.
    var pendingCount: Int { pending.count }

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
        preparePlayback()
        lastRequest = (parts, gap)
        requestedAt = Date()
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
            synth = makeEngine()
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
            if !retried && lastStart < requestedAt && Date().timeIntervalSince(asked) > retryAfter {
                retried = true
                print("[Speaker] speech didn't start within \(retryAfter) s; asking again")
                let request = lastRequest
                interrupt()
                preparePlayback()
                enqueue(request.parts, gap: request.gap)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if !Task.isCancelled { print("[Speaker] gave up waiting for speech to finish") }
    }

    /// The simulator demo keeps quiet (timing and callbacks unchanged) unless Alex turns sound on.
    private static var silent: Bool { Demo.isOn && !Demo.soundOn }

    /// The best installed voice per language, looked up once (listing every voice is slow).
    private static var voiceCache: [String: AVSpeechSynthesisVoice] = [:]

    private static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        if let cached = voiceCache[language] { return cached }
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        let best = voices.first(where: { $0.quality == .premium })
            ?? voices.first(where: { $0.quality == .enhanced })
            ?? AVSpeechSynthesisVoice(language: language)
        voiceCache[language] = best
        return best
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let from = ObjectIdentifier(synthesizer)
        Task { @MainActor in self.started(from: from) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(utterance: ObjectIdentifier(utterance), from: ObjectIdentifier(synthesizer))
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(utterance: ObjectIdentifier(utterance), from: ObjectIdentifier(synthesizer))
    }

    nonisolated private func finished(utterance: ObjectIdentifier, from synthesizer: ObjectIdentifier) {
        Task { @MainActor in self.finished(utterance, from: synthesizer) }
    }

    /// A sentence began (called by the synthesizer; directly by tests).
    func started(from synthesizer: ObjectIdentifier) {
        guard synthesizer == ObjectIdentifier(synth) else { return }
        lastStart = Date()
        if !isSpeaking { setSpeaking(true) }
    }

    /// A sentence finished or was cancelled. Late callbacks from a replaced synthesizer are ignored.
    func finished(_ utterance: ObjectIdentifier, from synthesizer: ObjectIdentifier) {
        guard synthesizer == ObjectIdentifier(synth) else { return }
        pending.remove(utterance)
        if pending.isEmpty && isSpeaking { setSpeaking(false) }
    }

    private func setSpeaking(_ value: Bool) {
        isSpeaking = value
        onSpeakingChange?(value)
    }
}
