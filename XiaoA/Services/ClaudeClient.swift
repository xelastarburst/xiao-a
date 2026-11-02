import Foundation
import UIKit

/// Minimal Claude Messages API client with streaming.
struct ClaudeClient {
    enum Model {
        /// Photos and questions: strong vision and Chinese writing.
        static let vision = "claude-sonnet-5-5"
        /// Short coaching tips: lowest latency.
        static let fast = "claude-haiku-5-5"
    }

    enum ClaudeError: LocalizedError {
        case noKey, http(Int, String), api(String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "还没有设置 Claude 密钥。请让 Alex 在设置里填写。"
            case .http(let code, _): return code == 401 ? "Claude 密钥不对，请让 Alex 检查。" : "网络出了点问题（\(code)），请再试一次。"
            case .api(let message): return message
            }
        }
    }

    let apiKey: String

    init() throws {
        guard let key = APIKeys.get(.anthropic) else { throw ClaudeError.noKey }
        apiKey = key
    }

    static func imageBlock(_ image: UIImage) -> [String: Any]? {
        let resized = image.resizedForUpload(maxSide: 1568)
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return nil }
        return ["type": "image",
                "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]]
    }

    func stream(model: String, system: String, messages: [[String: Any]], maxTokens: Int = 800) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    req.httpMethod = "POST"
                    req.timeoutInterval = 60
                    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    req.setValue("application/json", forHTTPHeaderField: "content-type")
                    let body: [String: Any] = ["model": model, "max_tokens": maxTokens, "system": system,
                                               "messages": messages, "stream": true]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let log = Self.Log(model: model, requestBytes: req.httpBody?.count ?? 0)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    log.status(status)
                    if status != 200 {
                        var data = Data()
                        for try await b in bytes { data.append(b) }
                        let detail = String(data: data, encoding: .utf8) ?? ""
                        log.failed("HTTP \(status): \(detail.prefix(300))")
                        throw ClaudeError.http(status, detail)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = obj["type"] as? String else { continue }
                        log.event(type, obj)
                        if type == "content_block_delta",
                           let delta = obj["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            log.text(text)
                            continuation.yield(text)
                        } else if type == "error" {
                            let message = (obj["error"] as? [String: Any])?["message"] as? String ?? "出错了"
                            log.failed("stream error: \(message)")
                            throw ClaudeError.api(message)
                        } else if type == "message_stop" {
                            break
                        }
                    }
                    log.finished()
                    continuation.finish()
                } catch {
                    if !(error is ClaudeError) { print("[XA] Claude \(model): FAILED: \(error.localizedDescription)") }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One console line per request, for debugging from Xcode: size sent, status, time to the
    /// first text, total time, length and why it stopped. Never logs the key or the prompt.
    final class Log: @unchecked Sendable {
        private let model: String
        private let requestBytes: Int
        private let started = Date()
        private var httpStatus = 0
        private var firstText: TimeInterval?
        private var chars = 0
        private var stopReason = "?"
        private var otherDeltas: [String: Int] = [:]

        init(model: String, requestBytes: Int) {
            self.model = model
            self.requestBytes = requestBytes
            print("[XA] Claude \(model): sending \(requestBytes / 1024) KB")
        }

        private var elapsed: String { String(format: "%.1f s", Date().timeIntervalSince(started)) }

        func status(_ code: Int) {
            httpStatus = code
            print("[XA] Claude \(model): HTTP \(code) after \(elapsed)")
        }

        func event(_ type: String, _ obj: [String: Any]) {
            if type == "content_block_delta", let delta = obj["delta"] as? [String: Any],
               let kind = delta["type"] as? String, kind != "text_delta" {
                otherDeltas[kind, default: 0] += 1
            }
            if type == "message_delta", let reason = (obj["delta"] as? [String: Any])?["stop_reason"] as? String {
                stopReason = reason
            }
        }

        func text(_ piece: String) {
            if firstText == nil {
                firstText = Date().timeIntervalSince(started)
                print("[XA] Claude \(model): first text after \(elapsed)")
            }
            chars += piece.count
        }

        func failed(_ why: String) {
            print("[XA] Claude \(model): FAILED after \(elapsed): \(why)")
        }

        func finished() {
            let other = otherDeltas.isEmpty ? "" : ", other deltas \(otherDeltas)"
            print("[XA] Claude \(model): HTTP \(httpStatus) done after \(elapsed), \(chars) chars, stop \(stopReason)\(other)")
        }
    }

    func complete(model: String, system: String, messages: [[String: Any]], maxTokens: Int = 300) async throws -> String {
        var text = ""
        for try await chunk in stream(model: model, system: system, messages: messages, maxTokens: maxTokens) {
            text += chunk
        }
        return text
    }
}

extension UIImage {
    func resizedForUpload(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
