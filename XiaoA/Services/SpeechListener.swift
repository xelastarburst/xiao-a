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

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var waiter: CheckedContinuation<String, Never>?
    private var startPending = false
    private var currentSession: UUID?

    static func requestPermissions() async -> Bool {
        let speech: Bool = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }

    /// locale: "zh-CN" for Mom's questions, "en-US" for practice.
    /// preferOnDevice: use the phone's own recognizer when it has one (works offline, faster).
    func start(locale: String, preferOnDevice: Bool = false) async throws {
        cancel()
        startPending = true
        let allowed = await Self.requestPermissions()
        // She may already have let go while the permission check ran.
        guard startPending else { return }
        startPending = false
        guard allowed else { throw ListenError.notAllowed }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
            throw ListenError.unavailable
        }
        Speaker.shared.stop()
        transcript = ""

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

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        try engine.start()
        isListening = true
        let sessionID = UUID()
        currentSession = sessionID

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                if done { self.finish() }
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
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            waiter = cont
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.finish()
            }
        }
    }

    func cancel() {
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
