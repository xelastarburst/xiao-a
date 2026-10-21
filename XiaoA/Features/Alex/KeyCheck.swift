import Foundation

/// Alex mode › Test keys: one tiny real request per key (a 5-token Claude reply, a one-word
/// OpenAI voice clip), so a wrong or unfunded key shows up before Mom needs it.
/// Tests both the key saved on this iPhone and the one built into the app. Costs well under a cent.
enum KeyCheck {
    struct Result: Identifiable {
        let id = UUID()
        let label: String
        let ok: Bool
        let detail: String
    }

    static func run() async -> [Result] {
        var results: [Result] = []
        for (source, key) in candidates(.anthropic) {
            results.append(await claude(key, label: "Claude · \(source) ···\(key.suffix(4))"))
        }
        for (source, key) in candidates(.openAI) {
            results.append(await openAI(key, label: "OpenAI · \(source) ···\(key.suffix(4))"))
        }
        if results.isEmpty {
            results.append(Result(label: "No keys", ok: false, detail: "Nothing saved on this iPhone and nothing built into the app."))
        }
        for r in results { print("[XA] key test: \(r.label): \(r.ok ? "OK" : "FAILED") \(r.detail)") }
        return results
    }

    private static func candidates(_ kind: APIKeys.Kind) -> [(String, String)] {
        candidates(saved: APIKeys.keychainValue(kind), builtIn: APIKeys.builtIn(kind))
    }

    /// The keys to test: the phone's own and the built-in one, once each if they are the same.
    static func candidates(saved: String?, builtIn: String?) -> [(String, String)] {
        var list: [(String, String)] = []
        if let saved { list.append(("saved on this iPhone", saved)) }
        if let builtIn, builtIn != saved { list.append(("built into the app", builtIn)) }
        return list
    }

    private static func claude(_ key: String, label: String) async -> Result {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": ClaudeClient.Model.fast,
            "max_tokens": 5,
            "messages": [["role": "user", "content": "Reply with just: OK"]]
        ])
        return await send(request, label: label, success: "Works (Claude replied)")
    }

    private static func openAI(_ key: String, label: String) async -> Result {
        // The transcription model the interpreter uses…
        var models = URLRequest(url: URL(string: "https://api.openai.com/v1/models/gpt-4o-transcribe")!)
        models.timeoutInterval = 20
        models.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let access = await send(models, label: label, success: "")
        guard access.ok else { return access }
        // …and a one-word voice clip, which also proves the account can pay for use.
        var speech = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        speech.httpMethod = "POST"
        speech.timeoutInterval = 20
        speech.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        speech.setValue("application/json", forHTTPHeaderField: "Content-Type")
        speech.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": OpenAISpeech.model, "voice": InterpreterVoice.defaultID,
            "input": "OK", "response_format": "pcm"
        ])
        return await send(speech, label: label, success: "Works (transcription and voice)")
    }

    private static func send(_ request: URLRequest, label: String, success: String) async -> Result {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 { return Result(label: label, ok: true, detail: success) }
            return Result(label: label, ok: false, detail: "Error \(code): \(message(from: data))")
        } catch {
            return Result(label: label, ok: false, detail: "No connection: \(error.localizedDescription)")
        }
    }

    /// The service's own error message (they never repeat the full key).
    static func message(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let text = error["message"] as? String {
            return String(text.prefix(200))
        }
        return String(String(decoding: data.prefix(200), as: UTF8.self))
    }
}
