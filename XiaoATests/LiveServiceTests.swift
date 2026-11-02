import Foundation
import UIKit
import Testing
@testable import XiaoA

/// Real requests to Claude and OpenAI with the keys built into this build (costs well under a cent).
/// Off by default. Turn on: Product › Scheme › Edit Scheme › Test › Arguments › tick XIAOA_LIVE_API.
@Suite("Live services (opt-in)", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["XIAOA_LIVE_API"] == "1"))
@MainActor
struct LiveServiceTests {

    @Test("Both keys work: Claude replies; OpenAI transcription and voice are allowed")
    func keysWork() async {
        let results = await KeyCheck.run()
        #expect(!results.isEmpty)
        for r in results { #expect(r.ok, "\(r.label): \(r.detail)") }
    }

    @Test("OpenAI still accepts the interpreter's session settings (it rejected them twice before)")
    func openAIAcceptsSessionSettings() async throws {
        let key = try #require(APIKeys.get(.openAI), "no OpenAI key in this build")
        var events: [TranscribeSocket.Event] = []
        let socket = TranscribeSocket(apiKey: key, model: "gpt-4o-transcribe", prompt: "Mandarin and English.")
        socket.onEvent = { events.append($0) }
        socket.connect()
        defer { socket.close() }
        let settled = await waitUntil(15) { events.filter { $0 == .ready }.count >= 2 || events.contains { e in
            if case .serverError = e { return true }
            if case .failed = e { return true }
            return false
        } }
        #expect(settled, "no reply from OpenAI in 15 s")
        try? await Task.sleep(nanoseconds: 1_500_000_000)        // a late rejection would arrive now
        let problems = events.filter { e in
            if case .serverError = e { return true }
            if case .failed = e { return true }
            return false
        }
        #expect(problems.isEmpty, "OpenAI said: \(problems)")
        #expect(events.filter { $0 == .ready }.count >= 2, "session settings were not confirmed")
    }

    @Test("Claude translates for the interpreter, both ways, in the requested direction")
    func claudeTranslates() async throws {
        let client = try ClaudeClient()
        func translate(_ line: InterpreterEngine.Line, partner: PartnerLanguage) async throws -> String {
            let message = InterpreterEngine.translationMessage(for: line, earlier: [], partnerName: partner.promptName)
            let reply = try await client.complete(model: ClaudeClient.Model.fast,
                                                  system: "You are a live interpreter. Reply with the translation only.",
                                                  messages: [["role": "user", "content": message]], maxTokens: 100)
            return InterpreterEngine.cleanTranslation(reply)
        }
        let toEnglish = try await translate(.init(fromHer: true, original: "Entschuldigung, wo ist die Toilette?"), partner: .english)
        #expect(["restroom", "bathroom", "toilet"].contains { toEnglish.lowercased().contains($0) }, "got: \(toEnglish)")
        let toGerman = try await translate(.init(fromHer: false, original: "请问洗手间在哪里？"), partner: .chinese)
        #expect(!InterpreterEngine.hasChinese(toGerman), "got: \(toGerman)")
        #expect(["toilette", "wc", "bad"].contains { toGerman.lowercased().contains($0) }, "got: \(toGerman)")
    }

    @Test("OpenAI's voice streams audio in whole chunks")
    func voiceStreams() async throws {
        let key = try #require(APIKeys.get(.openAI), "no OpenAI key in this build")
        final class Received { var chunks: [Data] = [] }
        let received = Received()
        try await OpenAISpeech.speak("Guten Tag.", apiKey: key, voice: InterpreterVoice.defaultID, language: .german) { chunk in
            received.chunks.append(chunk)
        }
        let chunks = received.chunks
        #expect(!chunks.isEmpty)
        #expect(chunks.allSatisfy { $0.count % 2 == 0 })
        #expect(chunks.dropLast().allSatisfy { $0.count == OpenAISpeech.chunkBytes })
    }

    @Test("Fragen answers about a full-size camera photo (photo + question → Claude → German)")
    func askAboutPhoto() async throws {
        let sign = try #require(Demo.signImage, "sample photo missing")
        let photo = cameraSized(sign)
        let model = AskModel()
        model.startOver(with: photo)
        let started = Date()
        model.ask("Was bedeutet das?", config: AppConfig())
        let finished = await waitUntil(90) { !model.streaming }
        let answer = model.latestAnswer?.text ?? ""
        print("[XA] live Fragen: \(String(format: "%.1f", Date().timeIntervalSince(started))) s, error: \(model.error ?? "none"), answer: \(answer.prefix(160))")
        #expect(finished, "still no answer after 90 s")
        #expect(model.error == nil, "error: \(model.error ?? "")")
        #expect(answer.contains("Apotheke"), "answer: \(answer)")
    }
}

/// The sample sign drawn at the size of an iPhone camera photo (12 MP), like a real photo.
private func cameraSized(_ image: UIImage) -> UIImage {
    let size = CGSize(width: 3024, height: 4032)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }
}
