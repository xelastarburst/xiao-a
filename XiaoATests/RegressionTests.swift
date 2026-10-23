import AVFoundation
import Foundation
import Testing
@testable import XiaoA

/// One test per bug already fixed in the app. Each fails if that bug ever comes back.
@Suite("Regressions", .serialized)
@MainActor
struct RegressionTests {

    @Test("1 · Interpreter audio never uses voice processing / voice-chat mode (empty mic audio)")
    func interpreterUsesDefaultAudioMode() {
        #expect(InterpreterAudio.sessionMode == .default)
    }

    @Test("2 · The mic reopens 0.6 s after the phone stops talking; it can never stay muted")
    func micReopensAfterSpeech() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var clock = PlaybackClock()
        clock.scheduled(seconds: 0.5, at: t0)
        clock.scheduled(seconds: 0.5, at: t0)            // queued right after: ends at t0 + 1.0
        #expect(clock.isMuted(at: t0.addingTimeInterval(1.5)))
        #expect(!clock.isMuted(at: t0.addingTimeInterval(1.61)))
        clock.setExternalMute(true, at: t0)
        #expect(clock.isMuted(at: t0.addingTimeInterval(100)))
        clock.setExternalMute(false, at: t0.addingTimeInterval(100))
        #expect(clock.isMuted(at: t0.addingTimeInterval(100.4)))
        #expect(!clock.isMuted(at: t0.addingTimeInterval(100.51)))
    }

    @Test("3 · Her words are translated into the other person's language, never back into German")
    func herLinesGoToPartnerLanguage() {
        let line = InterpreterEngine.Line(fromHer: true, original: "Guten Tag")
        let message = InterpreterEngine.translationMessage(for: line, earlier: [], partnerName: "English")
        #expect(message.hasSuffix("Translate the new line into English."))
        #expect(!message.contains("into German"))
        let chinese = PartnerLanguage.chinese.promptName
        #expect(InterpreterEngine.targetLanguage(fromHer: true, partnerName: chinese) == chinese)
    }

    @Test("4 · Every sentence is spoken exactly once, in the order it was said")
    func everySentenceSpokenOnceInOrder() {
        let a = UUID(), b = UUID(), c = UUID()
        var queue = TurnQueue()
        [a, b, c].forEach { queue.add($0) }
        var ready: Set<UUID> = [b]                      // B's translation came back first
        var spoken: [UUID] = []
        func state(_ id: UUID) -> TurnQueue.LineState { ready.contains(id) ? .ready : .translating }
        #expect(queue.next(state: state) == nil)       // still waiting for A
        ready.insert(a)
        while let id = queue.next(state: state) { spoken.append(id) }
        ready.insert(c)
        while let id = queue.next(state: state) { spoken.append(id) }
        #expect(spoken == [a, b, c])
        #expect(queue.waiting.isEmpty)
    }

    @Test("5 · OpenAI session settings keep exactly the accepted shape (no noise_reduction, no threshold)")
    func sessionSettingsShape() throws {
        let update = TranscribeSocket.sessionUpdate(model: "gpt-4o-transcribe", prompt: "p")
        let session = try #require(update["session"] as? [String: Any])
        #expect(session["type"] as? String == "transcription")
        let input = try #require((session["audio"] as? [String: Any])?["input"] as? [String: Any])
        #expect(Set(input.keys) == ["format", "transcription", "turn_detection"])
        let turn = try #require(input["turn_detection"] as? [String: Any])
        #expect(Set(turn.keys) == ["type", "prefix_padding_ms", "silence_duration_ms"])
        #expect(input["noise_reduction"] == nil)
        #expect(turn["threshold"] == nil)
        #expect(JSONSerialization.isValidJSONObject(update))
    }

    @Test("6 · Look's reply parser survives quotes in a translation")
    func lookParserHandlesQuotes() {
        let result = ClearRead.parse("WHAT: Schild\n1: Er sagte \"Hallo\"\n2: „Angebot“ $5")
        #expect(result.translated[1] == "Er sagte \"Hallo\"")
        #expect(result.translated[2] == "„Angebot“ $5")
    }

    @Test("7 · A late signal from the previous mic press can't switch off the new one")
    func staleRecognizerSignalIgnored() {
        let listener = SpeechListener()
        let current = listener.beginPressForTests()
        listener.received(text: "old words", error: "cancelled", done: true, session: UUID())
        #expect(listener.isListening)
        #expect(listener.transcript.isEmpty)
        listener.received(text: "hello", error: nil, done: false, session: current)
        #expect(listener.transcript == "hello")
    }

    @Test("8 · The listener uses the default audio mode (measurement mode gave empty audio)")
    func listenerUsesDefaultAudioMode() {
        #expect(SpeechListener.sessionMode == .default)
    }

    @Test("10b · Speech that never starts is asked for again")
    func droppedSpeechIsRetried() async {
        let voice = FakeVoice(autoFinish: false)
        voice.speaker.retryAfter = 0.3
        voice.speaker.speakSequence([("Hello", "en-US", 0.4)])
        let waiting = Task { await voice.speaker.waitUntilDone(timeout: 5) }
        #expect(await waitUntil(2) { voice.engines.count >= 2 })
        #expect(voice.current.spoken == ["Hello"])
        voice.finishAll()
        await waiting.value
        #expect(voice.speaker.pendingCount == 0)
    }

    @Test("11 · The keys file still works if an editor curled the quotes")
    func keysFileWithCurlyQuotes() {
        let openAI = "sk-proj-" + String(repeating: "a", count: 40)
        let claude = "sk-ant-api03-" + String(repeating: "b", count: 40)
        let file = "{ “openai”: “ \(openAI) ”, “anthropic”: “\(claude)” }"
        let keys = APIKeys.parseBundled(file)
        #expect(keys[.openAI] == openAI)
        #expect(keys[.anthropic] == claude)
    }
}
