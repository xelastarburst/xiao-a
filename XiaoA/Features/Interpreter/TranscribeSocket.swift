import Foundation

/// One OpenAI realtime *transcription* session over WebSocket. It hears everyone through the
/// phone's microphone, decides on its own when each person has finished a sentence (server voice
/// activity detection), and sends back exactly what was said, in the language it was said in.
final class TranscribeSocket {
    enum Event {
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
            sendOnQueue([
                "type": "session.update",
                "session": [
                    "type": "transcription",
                    "audio": [
                        "input": [
                            "format": ["type": "audio/pcm", "rate": 24_000],
                            "noise_reduction": ["type": "near_field"],
                            "transcription": ["model": model, "prompt": prompt],
                            // A sentence ends after 0.7 s of quiet; short "um"s don't count.
                            "turn_detection": [
                                "type": "server_vad",
                                "threshold": 0.5,
                                "prefix_padding_ms": 300,
                                "silence_duration_ms": 700
                            ]
                        ]
                    ]
                ]
            ])
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
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }
        if seenTypes.insert(type).inserted {
            print("[TranscribeSocket \(model)] first \(type)")
        }
        let item = obj["item_id"] as? String ?? ""
        switch type {
        case "session.created", "session.updated", "transcription_session.created", "transcription_session.updated":
            emit(.ready)
        case "input_audio_buffer.speech_started":
            emit(.speechStarted(item: item, atMs: obj["audio_start_ms"] as? Int ?? 0))
        case "input_audio_buffer.speech_stopped":
            emit(.speechStopped(item: item, atMs: obj["audio_end_ms"] as? Int ?? 0))
        case "conversation.item.input_audio_transcription.delta":
            if let delta = obj["delta"] as? String { emit(.partial(item: item, text: delta)) }
        case "conversation.item.input_audio_transcription.completed":
            emit(.sentence(item: item, text: obj["transcript"] as? String ?? ""))
        case "conversation.item.input_audio_transcription.failed":
            let message = (obj["error"] as? [String: Any])?["message"] as? String ?? "transcription failed"
            emit(.serverError(message))
        case "error":
            let message = (obj["error"] as? [String: Any])?["message"] as? String ?? "error"
            emit(.serverError(message))
        default:
            break
        }
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

/// OpenAI text-to-speech, streamed: the first words play while the rest is still arriving.
enum OpenAISpeech {
    static let model = "gpt-4o-mini-tts"

    /// Calls `onAudio` with 24 kHz mono PCM16 chunks (~100 ms each) as they arrive.
    static func speak(_ text: String, apiKey: String, chinese: Bool,
                      onAudio: @escaping (Data) async -> Void) async throws {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let instructions = chinese
            ? "Speak natural, warm Mandarin Chinese (standard Putonghua), clearly and a little slowly, for an elderly listener."
            : "Speak naturally and warmly, clearly and at a calm pace, like a friendly interpreter."
        let body: [String: Any] = [
            "model": model,
            "voice": "coral",
            "input": text,
            "instructions": instructions,
            "response_format": "pcm"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var data = Data()
            for try await b in bytes { data.append(b); if data.count > 2000 { break } }
            throw NSError(domain: "XiaoA.TTS", code: status,
                          userInfo: [NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)])
        }
        var buffer = Data()
        buffer.reserveCapacity(4800)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 4800 {
                await onAudio(buffer)
                buffer = Data()
                buffer.reserveCapacity(4800)
            }
        }
        if buffer.count >= 2 {
            if buffer.count % 2 == 1 { buffer.removeLast() }
            await onAudio(buffer)
        }
    }
}
