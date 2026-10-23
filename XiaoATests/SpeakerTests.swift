import AVFoundation
import Foundation
import Testing
@testable import XiaoA

@Suite("Helferlein's voice · Speaker", .serialized)
@MainActor
struct SpeakerTests {

    @Test("Blank text says nothing")
    func blank() {
        let voice = FakeVoice()
        voice.speaker.speak("   \n", language: "zh-CN")
        #expect(voice.allSpoken.isEmpty)
        #expect(voice.speaker.pendingCount == 0)
    }

    @Test("Text is trimmed and read at the normal pace; slow English is slower")
    func paces() {
        let voice = FakeVoice(autoFinish: false)
        voice.speaker.speak("  Guten Tag  ", language: "de-DE")
        #expect(voice.current.spoken == ["Guten Tag"])
        #expect(voice.current.utterances.last?.rate == Speaker.normalRate)
        voice.speaker.speakEnglish("Hello", slow: true)
        #expect(voice.current.utterances.last?.rate == Speaker.slowRate)
        #expect(Speaker.slowRate < Speaker.normalRate)
    }

    @Test("A sequence is read in order, each part in its own language and pace")
    func sequence() {
        let voice = FakeVoice(autoFinish: false)
        voice.speaker.speakSequence([("请跟我说：", "zh-CN", 0.46), ("Hello!", "en-US", 0.36), ("", "en-US", 0.3)])
        let u = voice.current.utterances
        #expect(u.map(\.speechString) == ["请跟我说：", "Hello!"])       // empty parts skipped
        #expect(u.map(\.rate) == [0.46, 0.36])
        #expect(u.allSatisfy { $0.postUtteranceDelay == 0.25 })
        #expect(voice.speaker.pendingCount == 2)
    }

    @Test("isSpeaking follows the voice, and the interpreter is told (to mute its mic)")
    func speakingSignal() {
        let voice = FakeVoice(autoFinish: false)
        var changes: [Bool] = []
        voice.speaker.onSpeakingChange = { changes.append($0) }
        voice.speaker.speakSequence([("一", "zh-CN", 0.46), ("二", "zh-CN", 0.46)])
        #expect(!voice.speaker.isSpeaking)
        voice.start()
        #expect(voice.speaker.isSpeaking)
        let first = voice.current.utterances[0]
        voice.speaker.finished(ObjectIdentifier(first), from: ObjectIdentifier(voice.current))
        #expect(voice.speaker.isSpeaking)                                  // one still to go
        voice.finishAll()
        #expect(!voice.speaker.isSpeaking)
        #expect(changes == [true, false])
    }

    @Test("Stopping hands over to a fresh voice; late signals from the old one are ignored")
    func stopAndLateSignals() {
        let voice = FakeVoice(autoFinish: false)
        voice.speaker.speak("第一句", language: "zh-CN")
        let old = voice.current
        voice.start(old)
        voice.speaker.stop()
        #expect(old.stopCount == 1)
        #expect(!voice.speaker.isSpeaking)
        voice.speaker.speak("第二句", language: "zh-CN")
        let fresh = voice.current
        #expect(fresh !== old)
        #expect(fresh.spoken == ["第二句"])
        // The old voice's "finished" arrives late: it must not count for the new sentence.
        voice.speaker.finished(ObjectIdentifier(fresh.utterances[0]), from: ObjectIdentifier(old))
        voice.speaker.started(from: ObjectIdentifier(old))
        #expect(voice.speaker.pendingCount == 1)
        #expect(!voice.speaker.isSpeaking)
        voice.finishAll(fresh)
        #expect(voice.speaker.pendingCount == 0)
    }

    @Test("Waiting is instant when nothing is being said")
    func waitWhenQuiet() async {
        let voice = FakeVoice()
        let start = Date()
        await voice.speaker.waitUntilDone()
        #expect(Date().timeIntervalSince(start) < 1)
    }

    @Test("Waiting ends when the sentence ends, and stops early if the lesson is left")
    func waitEnds() async {
        let voice = FakeVoice(autoFinish: false)
        voice.speaker.speak("Hello", language: "en-US")
        let waiting = Task { await voice.speaker.waitUntilDone(timeout: 10) }
        try? await Task.sleep(nanoseconds: 300_000_000)
        voice.finishAll()
        let start = Date()
        await waiting.value
        #expect(Date().timeIntervalSince(start) < 1)

        voice.speaker.speak("Again", language: "en-US")
        let cancelled = Task { await voice.speaker.waitUntilDone(timeout: 10) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        cancelled.cancel()
        let t = Date()
        await cancelled.value
        #expect(Date().timeIntervalSince(t) < 1)
    }

    @Test("Speech that has started is never asked for twice, however long it takes")
    func startedSpeechNotRepeated() async {
        let voice = FakeVoice(autoFinish: false)
        voice.speaker.retryAfter = 0.3
        voice.speaker.speak("A long sentence", language: "en-US")
        voice.start()
        let waiting = Task { await voice.speaker.waitUntilDone(timeout: 5) }
        try? await Task.sleep(nanoseconds: 900_000_000)
        #expect(voice.engines.count == 1)
        #expect(voice.allSpoken == ["A long sentence"])
        voice.finishAll()
        await waiting.value
    }

    @Test("Word by word: one part per word, all English")
    func wordByWord() {
        let parts = Speaker.shared.wordByWord("Where is the restroom?", rate: 0.3)
        #expect(parts.map { $0.text } == ["Where", "is", "the", "restroom?"])
        #expect(parts.allSatisfy { $0.language == "en-US" && $0.rate == 0.3 })
    }

    @Test("Unit tests run the real code: the simulator demo is off")
    func demoOffInTests() {
        #expect(!Demo.isOn)
    }
}
