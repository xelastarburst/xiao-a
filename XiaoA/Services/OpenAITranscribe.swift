import Foundation

/// One-shot transcription of a short recording with OpenAI (gpt-4o-transcribe).
/// One-shot transcription of a short recording (kept from 小A; not used by a screen here).
enum OpenAITranscribe {
    static let model = "gpt-4o-transcribe"

    static func transcribe(_ file: URL, apiKey: String, language: String) async throws -> String {
        let audio = try Data(contentsOf: file)
        let boundary = "xiaoa-\(UUID().uuidString)"
        let body = multipartBody(audio: audio, boundary: boundary, language: language)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "XiaoA.Transcribe", code: status,
                          userInfo: [NSLocalizedDescriptionKey: String(decoding: data.prefix(300), as: UTF8.self)])
        }
        return (json["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The upload: model, language and JSON reply as fields, then the WAV file.
    static func multipartBody(audio: Data, boundary: String, language: String) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", model)
        field("language", language)
        field("response_format", "json")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"try.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}
