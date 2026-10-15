import AVFoundation
import Speech

/// Push-to-talk speech recognition, used for Mandarin questions (Ask) and English practice (Learn).
@MainActor
final class SpeechListener: ObservableObject {
    enum ListenError: LocalizedError {
        case notAllowed, unavailable
        var errorDescription: String? {
            switch self {
            case .notAllowed: return "需要打开麦克风和语音识别权限。请让 Alex 在“设置”里打开。"
            case .unavailable: return "现在听不了，请稍后再试。"
            }
        }
    }

    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    /// The last press, recorded, so another recognizer can try when Apple's hears nothing.
    private(set) var lastRecording: URL?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var waiter: CheckedContinuation<String, Never>?
    private var startPending = false
    /// Changes with every press. Results and errors from an earlier press (e.g. the "cancelled"
    /// error of the one before) are ignored, so they can't switch off the microphone mid-sentence.
    private var currentSession: UUID?
    private var recorder: TapRecorder?

    static func requestPermissions() async -> Bool {
        let speech: Bool = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }

    /// locale: "zh-CN" for Mom's questions, "en-US" for practice.
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
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

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
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
            recorder?.write(buffer)
        }
        engine.prepare()
        try engine.start()
        isListening = true
        let sessionID = UUID()
        currentSession = sessionID
        print("[SpeechListener] listening (\(locale), \(recognizer.isAvailable ? "recognizer ready" : "recognizer offline"))")

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                guard let self, self.currentSession == sessionID else { return }
                if let text { self.transcript = text }
                if let error, text == nil, self.transcript.isEmpty {
                    print("[SpeechListener] recognizer error: \(error.localizedDescription)")
                }
                guard done else { return }
                if self.isListening {
                    // The recognizer gave up (e.g. offline) while she is still talking: keep
                    // recording, so the recording can still be checked when she lets go.
                    self.task = nil
                } else {
                    self.finish()
                }
            }
        }

        // Safety net: never keep the microphone open for more than a minute.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if self.currentSession == sessionID && self.isListening { _ = await self.stop() }
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

    func cancel() {
        currentSession = nil
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
        finish()
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
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
