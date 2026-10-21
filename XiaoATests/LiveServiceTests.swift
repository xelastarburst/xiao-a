import Foundation
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

    @Test("Claude translates for the interpreter, in the requested direction")
    func claudeTranslates() async throws {
        let client = try ClaudeClient()
        let line = InterpreterEngine.Line(fromMom: true, original: "请问洗手间在哪里？")
        let message = InterpreterEngine.translationMessage(for: line, earlier: [], partnerName: "German")
        let reply = try await client.complete(model: ClaudeClient.Model.fast,
                                              system: "You are a live interpreter. Reply with the translation only.",
                                              messages: [["role": "user", "content": message]], maxTokens: 100)
        let clean = InterpreterEngine.cleanTranslation(reply)
        #expect(!clean.isEmpty && !InterpreterEngine.hasChinese(clean), "got: \(clean)")
        #expect(clean.lowercased().contains("toilette") || clean.lowercased().contains("wc")
                || clean.lowercased().contains("bad"), "got: \(clean)")
    }

    @Test("OpenAI's voice streams audio in whole chunks")
    func voiceStreams() async throws {
        let key = try #require(APIKeys.get(.openAI), "no OpenAI key in this build")
        final class Received { var chunks: [Data] = [] }
        let received = Received()
        try await OpenAISpeech.speak("Hello.", apiKey: key, voice: InterpreterVoice.defaultID, chinese: false) { chunk in
            received.chunks.append(chunk)
        }
        let chunks = received.chunks
        #expect(!chunks.isEmpty)
        #expect(chunks.allSatisfy { $0.count % 2 == 0 })
        #expect(chunks.dropLast().allSatisfy { $0.count == OpenAISpeech.chunkBytes })
    }
}
