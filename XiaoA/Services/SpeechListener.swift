import AVFoundation
import Speech

/// Push-to-talk speech recognition, used for her German questions (Fragen).
@MainActor
final class SpeechListener: ObservableObject {
    enum ListenError: LocalizedError {
        case notAllowed, unavailable
        var errorDescription: String? {
            switch self {
            case .notAllowed: return "Mikrofon und Spracherkennung sind nicht erlaubt. Bitte lassen Sie Ihre Familie das in den iPhone-Einstellungen einschalten."
            case .unavailable: return "Ich kann gerade nicht zuhören. Bitte versuchen Sie es gleich noch einmal."
            }
        }
    }

    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    /// The last press, recorded, so another recognizer can try when Apple's hears nothing.
    private(set) var lastRecording: URL?

    /// A fresh engine for every listen: one reused across the switches between speaking and
    /// listening can end up handing over empty audio.
    private var engine = AVAudioEngine()
    /// Whether this engine's microphone was opened. Stopping never touches the mic otherwise:
    /// just asking for the input node starts up the audio hardware.
    private var tapInstalled = false
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var waiter: CheckedContinuation<String, Never>?
    private var startPending = false
    /// Changes with every press. Results and errors from an earlier press (e.g. the "cancelled"
    /// error of the one before) are ignored, so they can't switch off the microphone mid-sentence.
    private(set) var currentSession: UUID?

    /// Default mode, like the interpreter: on Mom's iPhone the measurement mode handed the app
    /// empty audio buffers.
    static let sessionMode: AVAudioSession.Mode = .default
    private var recorder: TapRecorder?
    private var levels = LevelWatch()

    /// True if the microphone heard someone talking during the last listen.
    var heardSound: Bool { levels.spoke }

    static func requestPermissions() async -> Bool {
        let speech: Bool = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }

    /// locale: "de-DE" for her questions.
    /// preferOnDevice: insist on the phone's own recognizer (offline). Off by default: the
    /// on-device English model is often missing on a Chinese-language iPhone.
    /// record: also keep the audio of this press in `lastRecording`.
    func start(locale: String, preferOnDevice: Bool = false, record: Bool = false) async throws {
        cancel()
        startPending = true
        let allowed = await Self.requestPermissions()
        // She may already have let go while the permission check ran.
        guard startPending else { return }
        startPending = false
        guard allowed else { throw ListenError.notAllowed }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
            throw ListenError.unavailable
        }
        Speaker.shared.stop()
        transcript = ""
        lastRecording = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: Self.sessionMode, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw ListenError.unavailable }
        AudioCoordinator.listening = true

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        request = req

        let recorder = record ? TapRecorder(format: format) : nil
        self.recorder = recorder
        let levels = LevelWatch()
        self.levels = levels
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard buffer.frameLength > 0 else {
                levels.countEmpty()
                return
            }
            req.append(buffer)
            recorder?.write(buffer)
            levels.feed(buffer)
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
        isListening = true
        let sessionID = UUID()
        currentSession = sessionID
        print("[SpeechListener] listening (\(locale), \(recognizer.isAvailable ? "recognizer ready" : "recognizer offline")), mic \(format)")

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || (result?.isFinal ?? false)
            let message = error?.localizedDescription
            Task { @MainActor in
                self?.received(text: text, error: message, done: done, session: sessionID)
            }
        }

        // Safety net: never keep the microphone open for more than a minute.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if self.currentSession == sessionID && self.isListening { _ = await self.stop() }
        }
    }

    /// A result or error from the recognizer. Anything from an earlier press is ignored: the
    /// previous press's "cancelled" error used to arrive late and switch off the new recording.
    func received(text: String?, error: String?, done: Bool, session: UUID) {
        guard currentSession == session else { return }
        if let text { transcript = text }
        if let error, text == nil, transcript.isEmpty {
            print("[SpeechListener] recognizer error: \(error)")
        }
        guard done else { return }
        if isListening {
            // The recognizer gave up (e.g. offline) while she is still talking: keep
            // recording, so the recording can still be checked when she lets go.
            task = nil
        } else {
            finish()
        }
    }

    /// Hands-free: opens the microphone, waits for her to speak, and returns what she said once
    /// she pauses (`endPause`, generous because beginners pause between words).
    /// Returns nil if cancelled, "" if nobody spoke within `waitForSpeech` seconds.
    func listenOnce(locale: String, endPause: TimeInterval = 1.8, waitForSpeech: TimeInterval = 12) async throws -> String? {
        if Demo.isOn {
            startDemo()
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, isListening else { return nil }
            return stopDemo()
        }
        try await start(locale: locale, record: true)
        guard isListening, let session = currentSession else { return nil }
        var detector = TurnEndDetector(began: Date(), endPause: endPause, waitForSpeech: waitForSpeech)
        while true {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if Task.isCancelled {
                cancel()
                return nil
            }
            guard currentSession == session, isListening else { return nil }
            switch detector.update(now: Date(), transcript: transcript, spoke: levels.spoke,
                                   lastLoud: levels.lastLoud, firstLoud: levels.firstLoud) {
            case .keepListening:
                continue
            case .nobodySpoke:
                _ = await stop()
                return ""
            case .done:
                return await stop()
            }
        }
    }

    /// Simulator demo: shows the listening state without opening the microphone.
    func startDemo() {
        cancel()
        transcript = ""
        isListening = true
    }

    func stopDemo() -> String {
        isListening = false
        return ""
    }

    /// Stops listening and waits briefly for the final words.
    func stop() async -> String {
        if startPending {
            startPending = false
            return ""
        }
        guard isListening || task != nil else { return transcript }
        stopAudio()
        request?.endAudio()
        if task == nil {
            finish()
            return transcript
        }
        if waiter != nil { return transcript }
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            waiter = cont
            let sessionID = currentSession
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if self.currentSession == sessionID { self.finish() }
            }
        }
    }

    #if DEBUG
    /// Tests: pretend a press is in progress, without a microphone.
    func beginPressForTests() -> UUID {
        let id = UUID()
        currentSession = id
        isListening = true
        transcript = ""
        return id
    }
    #endif

    func cancel() {
        currentSession = nil
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
        finish()
    }

    private func stopAudio() {
        if isListening { print("[SpeechListener] stopped: \(levels.summary)") }
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        isListening = false
        AudioCoordinator.listening = false
        if let recorder {
            lastRecording = recorder.close()
            self.recorder = nil
        }
    }

    private func finish() {
        stopAudio()
        task = nil
        request = nil
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: transcript)
        }
    }
}

/// Decides when she has finished a try: after a pause, once the recognizer's words stop changing,
/// or at a hard cap. Gives up if nobody speaks at all.
struct TurnEndDetector {
    enum Decision: Equatable { case keepListening, done, nobodySpoke }

    let began: Date
    var endPause: TimeInterval = 1.8
    var waitForSpeech: TimeInterval = 12
    var cap: TimeInterval = 20
    private var lastText = ""
    private var lastChange: Date

    init(began: Date, endPause: TimeInterval = 1.8, waitForSpeech: TimeInterval = 12, cap: TimeInterval = 20) {
        self.began = began
        self.endPause = endPause
        self.waitForSpeech = waitForSpeech
        self.cap = cap
        lastChange = began
    }

    mutating func update(now: Date, transcript: String, spoke: Bool, lastLoud: Date, firstLoud: Date?) -> Decision {
        if transcript != lastText {
            lastText = transcript
            lastChange = now
        }
        let hasWords = !transcript.isEmpty
        guard spoke || hasWords else {
            return now.timeIntervalSince(began) > waitForSpeech ? .nobodySpoke : .keepListening
        }
        // Her last sound, or the last time the recognizer added a word, whichever is later.
        let lastActivity = max(lastLoud, hasWords ? lastChange : .distantPast)
        let quiet = now.timeIntervalSince(lastActivity) > endPause
        let wordsSettled = hasWords && now.timeIntervalSince(lastChange) > endPause + 1
        let tooLong = now.timeIntervalSince(firstLoud ?? began) > cap
        return quiet || wordsSettled || tooLong ? .done : .keepListening
    }
}

/// Notices when someone is talking: sound clearly above the room's background level.
private final class LevelWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var room: Float = 0.003
    private var loudRun = 0
    private var _firstLoud: Date?
    private var _lastLoud = Date.distantPast

    private var buffers = 0
    private var empty = 0
    private var loudest: Float = 0

    var spoke: Bool { lock.lock(); defer { lock.unlock() }; return _firstLoud != nil }
    var summary: String {
        lock.lock(); defer { lock.unlock() }
        return String(format: "%d buffers (%d empty), loudest %.3f, room %.4f, speech %@",
                      buffers, empty, loudest, room, _firstLoud == nil ? "no" : "yes")
    }

    func countEmpty() {
        lock.lock(); empty += 1; buffers += 1; lock.unlock()
    }
    var firstLoud: Date? { lock.lock(); defer { lock.unlock() }; return _firstLoud }
    var lastLoud: Date { lock.lock(); defer { lock.unlock() }; return _lastLoud }

    /// Audio thread.
    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += samples[i] * samples[i] }
        let level = (sum / Float(n)).squareRoot()
        lock.lock(); defer { lock.unlock() }
        buffers += 1
        loudest = max(loudest, level)
        // The room level follows quiet moments quickly and loud ones slowly.
        room = level < room ? 0.8 * room + 0.2 * level : min(level, room * 1.002)
        room = max(room, 0.0005)
        loudRun = level > max(0.006, room * 3) ? loudRun + 1 : 0
        if loudRun >= 2 {
            let now = Date()
            if _firstLoud == nil { _firstLoud = now }
            _lastLoud = now
        }
    }
}

/// Writes the microphone's buffers to a 16-bit WAV file (audio thread in, main thread closes).
private final class TapRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private let url: URL
    private var frames: AVAudioFramePosition = 0
    private let sampleRate: Double

    init?(format: AVAudioFormat) {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("practice-\(UUID().uuidString).wav")
        sampleRate = format.sampleRate
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        guard let file = try? AVAudioFile(forWriting: url, settings: settings,
                                          commonFormat: format.commonFormat, interleaved: format.isInterleaved) else {
            return nil
        }
        self.file = file
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let file else { return }
        try? file.write(from: buffer)
        frames += AVAudioFramePosition(buffer.frameLength)
    }

    /// Closes the file. Nil if less than 0.3 s was recorded.
    func close() -> URL? {
        lock.lock(); defer { lock.unlock() }
        file = nil
        return Double(frames) >= sampleRate * 0.3 ? url : nil
    }
}
