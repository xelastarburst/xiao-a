import Foundation

/// One OpenAI realtime *transcription* session over WebSocket. It hears everyone through the
/// phone's microphone, decides on its own when each person has finished a sentence (server voice
/// activity detection), and sends back exactly what was said, in the language it was said in.
final class TranscribeSocket {
    enum Event: Equatable {
        case ready
        /// Someone started talking (the audio position, in ms since the session began).
        case speechStarted(item: String, atMs: Int)
        /// They paused long enough to count as the end of a sentence.
        case speechStopped(item: String, atMs: Int)
        case partial(item: String, text: String)
        case sentence(item: String, text: String)
        case closed
        /// The connection itself broke. The session is over.
        case failed(String)
        /// The server rejected something (e.g. a setting or a model). The session may go on.
        case serverError(String)
    }

    /// Delivered on the main queue.
    var onEvent: ((Event) -> Void)?

    let model: String
    private let apiKey: String
    private let prompt: String
    private let queue = DispatchQueue(label: "xiaoa.transcribe-socket")
    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var closing = false
    private var seenTypes: Set<String> = []

    /// - prompt: tells the transcriber what to expect (languages, names), which improves accuracy.
    init(apiKey: String, model: String, prompt: String) {
        self.apiKey = apiKey
        self.model = model
        self.prompt = prompt
    }

    func connect() {
        queue.async { [self] in
            var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Self.safetyIdentifier, forHTTPHeaderField: "OpenAI-Safety-Identifier")
            let task = session.webSocketTask(with: request)
            self.task = task
            task.resume()
            sendOnQueue(Self.sessionUpdate(model: model, prompt: prompt))
            receive(on: task)
        }
    }

    /// 24 kHz mono PCM16, little-endian. Keep sending, including silence.
    func append(pcm16: Data) {
        queue.async { [self] in
            guard !closing else { return }
            sendOnQueue(["type": "input_audio_buffer.append", "audio": pcm16.base64EncodedString()])
        }
    }

    func close() {
        queue.async { [self] in
            guard !closing else { return }
            closing = true
            task?.cancel(with: .normalClosure, reason: nil)
            task = nil
        }
    }

    /// The settings sent when the session opens. OpenAI has rejected extra keys here twice
    /// (`noise_reduction`, then `turn_detection.threshold`), so a test pins this shape exactly.
    static func sessionUpdate(model: String, prompt: String) -> [String: Any] {
        [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "transcription": ["model": model, "prompt": prompt],
                        // A sentence ends after 0.7 s of quiet (the phone also holds back room
                        // noise, see InterpreterAudio).
                        "turn_detection": [
                            "type": "server_vad",
                            "prefix_padding_ms": 300,
                            "silence_duration_ms": 700
                        ]
                    ]
                ]
            ]
        ]
    }

    /// One message from the server, as an event (nil for messages the app doesn't use).
    static func event(from text: String) -> Event? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return nil }
        let item = obj["item_id"] as? String ?? ""
        switch type {
        case "session.created", "session.updated", "transcription_session.created", "transcription_session.updated":
            return .ready
        case "input_audio_buffer.speech_started":
            return .speechStarted(item: item, atMs: obj["audio_start_ms"] as? Int ?? 0)
        case "input_audio_buffer.speech_stopped":
            return .speechStopped(item: item, atMs: obj["audio_end_ms"] as? Int ?? 0)
        case "conversation.item.input_audio_transcription.delta":
            guard let delta = obj["delta"] as? String else { return nil }
            return .partial(item: item, text: delta)
        case "conversation.item.input_audio_transcription.completed":
            return .sentence(item: item, text: obj["transcript"] as? String ?? "")
        case "conversation.item.input_audio_transcription.failed":
            return .serverError((obj["error"] as? [String: Any])?["message"] as? String ?? "transcription failed")
        case "error":
            return .serverError((obj["error"] as? [String: Any])?["message"] as? String ?? "error")
        default:
            return nil
        }
    }

    // MARK: - Private (queue only)

    private func sendOnQueue(_ object: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            guard let self, let error else { return }
            self.queue.async {
                if !self.closing { self.emit(.failed(error.localizedDescription)) }
            }
        }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.queue.async {
                    if !self.closing { self.emit(.failed(error.localizedDescription)) }
                }
            case .success(let message):
                switch message {
                case .string(let text): self.handle(text)
                case .data(let data): self.handle(String(decoding: data, as: UTF8.self))
                @unknown default: break
                }
                self.receive(on: task)
            }
        }
    }

    private func handle(_ text: String) {
        if let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = obj["type"] as? String, seenTypes.insert(type).inserted {
            print("[TranscribeSocket \(model)] first \(type)")
        }
        if let event = Self.event(from: text) { emit(event) }
    }

    private func emit(_ event: Event) {
        DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
    }

    /// A stable, anonymous per-install ID that OpenAI asks apps to send for abuse detection.
    private static var safetyIdentifier: String {
        let key = "xiaoa.safetyID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}

/// The language a translation is said in, and how the voice should say it.
enum SpokenLanguage: String, CaseIterable {
    /// To her: warm, clear, a little slow.
    case german
    case english
    case mandarin

    var instructions: String {
        let projection = " Speak up and project clearly, as if across a table in a busy café, "
            + "but stay friendly and relaxed, never shouting."
        switch self {
        case .german:
            return "Speak natural, warm German (standard Hochdeutsch), clearly and a little slowly, for an elderly listener." + projection
        case .english:
            return "Speak naturally and warmly, clearly and at a calm pace, like a friendly interpreter." + projection
        case .mandarin:
            return "Speak natural, warm Mandarin Chinese (standard Putonghua), clearly and at a calm pace, like a friendly interpreter." + projection
        }
    }

    /// The phone's own voice for the same language.
    var appleVoice: String {
        switch self {
        case .german: return "de-DE"
        case .english: return "en-US"
        case .mandarin: return "zh-CN"
        }
    }
}

/// OpenAI text-to-speech, streamed: the first words play while the rest is still arriving.
enum OpenAISpeech {
    static let model = "gpt-4o-mini-tts"
    /// Audio is handed on in chunks of this many bytes (100 ms of 24 kHz PCM16).
    static let chunkBytes = 4800

    /// The speech request: model, voice, raw PCM, and how to speak this language.
    static func request(_ text: String, apiKey: String, voice: String, language: SpokenLanguage) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "voice": voice,
            "input": text,
            "instructions": language.instructions,
            "response_format": "pcm"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Calls `onAudio` with 24 kHz mono PCM16 chunks (~100 ms each) as they arrive.
    static func speak(_ text: String, apiKey: String, voice: String, language: SpokenLanguage,
                      onAudio: @escaping (Data) async -> Void) async throws {
        let request = try request(text, apiKey: apiKey, voice: voice, language: language)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var data = Data()
            for try await b in bytes { data.append(b); if data.count > 2000 { break } }
            throw NSError(domain: "XiaoA.TTS", code: status,
                          userInfo: [NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)])
        }
        var chunker = PCMChunker()
        for try await byte in bytes {
            if let chunk = chunker.add(byte) { await onAudio(chunk) }
        }
        if let last = chunker.finish() { await onAudio(last) }
    }
}

/// Cuts a byte stream of 16-bit samples into fixed-size chunks; the last chunk keeps whole samples only.
struct PCMChunker {
    private var buffer = Data()
    let size: Int

    init(size: Int = OpenAISpeech.chunkBytes) {
        self.size = size
        buffer.reserveCapacity(size)
    }

    /// Returns a full chunk when one is ready.
    mutating func add(_ byte: UInt8) -> Data? {
        buffer.append(byte)
        guard buffer.count >= size else { return nil }
        let chunk = buffer
        buffer = Data()
        buffer.reserveCapacity(size)
        return chunk
    }

    /// Whatever is left, trimmed to whole samples (nil if less than one sample).
    mutating func finish() -> Data? {
        guard buffer.count >= 2 else { return nil }
        if buffer.count % 2 == 1 { buffer.removeLast() }
        defer { buffer = Data() }
        return buffer
    }
}
