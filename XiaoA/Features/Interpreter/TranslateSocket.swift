import Foundation

/// One OpenAI gpt-realtime-translate session over WebSocket. Each session has a single output
/// language, so the interpreter runs two: one into the other person's language (English or
/// German) and one into Chinese.
final class TranslateSocket {
    enum Event {
        case ready
        case inputText(String)
        case outputText(String)
        case outputAudio(Data)
        case closed
        /// The connection itself broke. The session is over.
        case failed(String)
        /// The server rejected one message (e.g. a setting it doesn't support). The session keeps going.
        case serverError(String)
    }

    static let model = "gpt-realtime-translate"
    static let transcriptionModel = "gpt-realtime-whisper"

    let targetLanguage: String
    /// Delivered on the main queue.
    var onEvent: ((Event) -> Void)?

    private let apiKey: String
    private let queue = DispatchQueue(label: "xiaoa.translate-socket")
    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var closing = false
    private var seenTypes: Set<String> = []

    init(apiKey: String, targetLanguage: String) {
        self.apiKey = apiKey
        self.targetLanguage = targetLanguage
    }

    func connect() {
        queue.async { [self] in
            var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime/translations?model=\(Self.model)")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Self.safetyIdentifier, forHTTPHeaderField: "OpenAI-Safety-Identifier")
            let task = session.webSocketTask(with: request)
            self.task = task
            task.resume()
            sendOnQueue([
                "type": "session.update",
                "session": [
                    "audio": [
                        "input": [
                            "transcription": ["model": Self.transcriptionModel],
                            "noise_reduction": ["type": "near_field"]
                        ],
                        "output": ["language": targetLanguage]
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
            sendOnQueue(["type": "session.input_audio_buffer.append", "audio": pcm16.base64EncodedString()])
        }
    }

    func close() {
        queue.async { [self] in
            guard !closing else { return }
            sendOnQueue(["type": "session.close"])
            closing = true
            queue.asyncAfter(deadline: .now() + 1.5) { [self] in
                task?.cancel(with: .normalClosure, reason: nil)
                task = nil
            }
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
            // Any message at all means the session is up. Log each event type once, for debugging.
            print("[TranslateSocket \(targetLanguage)] first \(type)")
            if seenTypes.count == 1 { emit(.ready) }
        }
        switch type {
        case "session.created", "session.updated":
            emit(.ready)
        case "session.output_audio.delta":
            if let b64 = obj["delta"] as? String, let audio = Data(base64Encoded: b64) { emit(.outputAudio(audio)) }
        case "session.output_transcript.delta":
            if let delta = obj["delta"] as? String { emit(.outputText(delta)) }
        case "session.input_transcript.delta":
            if let delta = obj["delta"] as? String { emit(.inputText(delta)) }
        case "session.closed":
            emit(.closed)
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
