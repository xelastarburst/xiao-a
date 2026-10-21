import AVFoundation
import Foundation
import Testing
@testable import XiaoA

@Suite("翻译官 · Interpreter", .serialized)
@MainActor
struct InterpreterTests {

    // MARK: Server messages

    @Test("Every OpenAI message the app relies on is understood")
    func readsServerEvents() {
        typealias E = TranscribeSocket.Event
        func ev(_ json: String) -> E? { TranscribeSocket.event(from: json) }
        #expect(ev(#"{"type":"session.created"}"#) == .ready)
        #expect(ev(#"{"type":"transcription_session.updated"}"#) == .ready)
        #expect(ev(#"{"type":"input_audio_buffer.speech_started","item_id":"a","audio_start_ms":1200}"#)
                == .speechStarted(item: "a", atMs: 1200))
        #expect(ev(#"{"type":"input_audio_buffer.speech_stopped","item_id":"a","audio_end_ms":2900}"#)
                == .speechStopped(item: "a", atMs: 2900))
        #expect(ev(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"a","delta":"Hel"}"#)
                == .partial(item: "a", text: "Hel"))
        #expect(ev(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"a","transcript":"Hello there."}"#)
                == .sentence(item: "a", text: "Hello there."))
        #expect(ev(#"{"type":"error","error":{"message":"Invalid value: 'x'"}}"#) == .serverError("Invalid value: 'x'"))
        #expect(ev(#"{"type":"conversation.item.input_audio_transcription.failed","error":{"message":"bad audio"}}"#)
                == .serverError("bad audio"))
    }

    @Test("Unknown, broken or empty messages are ignored, never a crash")
    func ignoresJunk() {
        #expect(TranscribeSocket.event(from: #"{"type":"rate_limits.updated"}"#) == nil)
        #expect(TranscribeSocket.event(from: "not json") == nil)
        #expect(TranscribeSocket.event(from: "") == nil)
        #expect(TranscribeSocket.event(from: #"{"no_type":1}"#) == nil)
        #expect(TranscribeSocket.event(from: #"{"type":"conversation.item.input_audio_transcription.delta"}"#) == nil)
    }

    @Test("Errors: a wrong key stops, a model the account can't use is swapped once, anything else carries on")
    func serverErrorReactions() {
        typealias R = InterpreterEngine.ServerErrorReaction
        func r(_ m: String, heard: Bool = false, index: Int = 0) -> R {
            InterpreterEngine.reaction(to: m, heardSentence: heard, modelIndex: index, modelCount: 2)
        }
        #expect(r("Incorrect API key provided: sk-…") == .stopBadKey)
        #expect(r("Authentication failed") == .stopBadKey)
        #expect(r("The model gpt-4o-transcribe does not exist") == .switchModel)
        #expect(r("The model gpt-4o-transcribe does not exist", index: 1) == .carryOn)   // no backup left
        #expect(r("model overloaded", heard: true) == .carryOn)                          // it was working
        #expect(r("Rate limit reached") == .carryOn)
    }

    // MARK: Who spoke, and what counts as speech

    @Test("Chinese means Mom; anything else is the other person")
    func chineseMeansMom() {
        #expect(InterpreterEngine.hasChinese("我想买牛奶"))
        #expect(InterpreterEngine.hasChinese("OK 好的"))
        #expect(!InterpreterEngine.hasChinese("Where is the milk?"))
        #expect(!InterpreterEngine.hasChinese("Wie geht es Ihnen?"))
        #expect(!InterpreterEngine.hasChinese("123 !?"))
    }

    @Test("Made-up words from noise are dropped; real sentences are kept")
    func dropsHallucinations() {
        #expect(InterpreterEngine.isRealSpeech("Where is the bus stop?", milliseconds: 1500))
        #expect(InterpreterEngine.isRealSpeech("你好", milliseconds: 0))                 // length unknown
        #expect(!InterpreterEngine.isRealSpeech("Thanks for watching!", milliseconds: 1500))
        #expect(!InterpreterEngine.isRealSpeech("字幕由 Amara.org 社区提供", milliseconds: 2000))
        #expect(!InterpreterEngine.isRealSpeech("Hello", milliseconds: 150))             // a click
        #expect(!InterpreterEngine.isRealSpeech("...", milliseconds: 800))
    }

    // MARK: Translation requests

    @Test("Other people's words go into Simplified Chinese; context is the last 8 translated lines")
    func translationContext() {
        var earlier: [InterpreterEngine.Line] = []
        for i in 1...10 {
            earlier.append(.init(fromMom: i % 2 == 0, original: "o\(i)", translated: "t\(i)"))
        }
        earlier.append(.init(fromMom: false, original: "untranslated"))
        let line = InterpreterEngine.Line(fromMom: false, original: "Is this your bag?")
        let message = InterpreterEngine.translationMessage(for: line, earlier: earlier, partnerName: "German")
        #expect(message.hasSuffix("Translate the new line into Simplified Chinese (as used in mainland China)."))
        #expect(message.contains("New line from the other person:\nIs this your bag?"))
        #expect(!message.contains("o2 → t2"))                 // older than the last 8
        #expect(message.contains("Mom said: o4 → t4"))
        #expect(message.contains("Other said: o3 → t3"))
        #expect(message.contains("Mom said: o10 → t10"))
        #expect(!message.contains("untranslated"))
    }

    @Test("The first line has no empty 'conversation so far'")
    func firstLineHasNoHistory() {
        let line = InterpreterEngine.Line(fromMom: true, original: "你好")
        let message = InterpreterEngine.translationMessage(for: line, earlier: [], partnerName: "English")
        #expect(message.hasPrefix("New line from Mom (in Chinese):"))
    }

    @Test("Quotes and spaces around Claude's translation are removed, inner quotes kept")
    func cleansTranslation() {
        #expect(InterpreterEngine.cleanTranslation("  “Hello!”\n") == "Hello!")
        #expect(InterpreterEngine.cleanTranslation("「你好」") == "你好")
        #expect(InterpreterEngine.cleanTranslation("\"He said \"hi\" to me\"") == "He said \"hi\" to me")
        #expect(InterpreterEngine.cleanTranslation("   ") == "")
    }

    // MARK: Speaking order

    @Test("A failed or scrolled-away line is skipped; the queue can be cleared")
    func queueSkipsFailedLines() {
        let a = UUID(), b = UUID(), c = UUID()
        var queue = TurnQueue()
        [a, b, c].forEach { queue.add($0) }
        let states: [UUID: TurnQueue.LineState] = [a: .failed, b: .gone, c: .ready]
        #expect(queue.next { states[$0]! } == c)
        #expect(queue.next { states[$0]! } == nil)
        queue.add(a)
        queue.removeAll()
        #expect(queue.waiting.isEmpty)
    }

    // MARK: The voice

    @Test("Voice request: streamed PCM from gpt-4o-mini-tts, projected, Mandarin for Mom")
    func speechRequest() throws {
        let zh = try OpenAISpeech.request("你好", apiKey: "k", voice: "marin", chinese: true)
        #expect(zh.url?.absoluteString == "https://api.openai.com/v1/audio/speech")
        #expect(zh.httpMethod == "POST")
        #expect(zh.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        let body = try #require(JSONSerialization.jsonObject(with: zh.httpBody ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "gpt-4o-mini-tts")
        #expect(body["voice"] as? String == "marin")
        #expect(body["input"] as? String == "你好")
        #expect(body["response_format"] as? String == "pcm")
        let zhInstructions = try #require(body["instructions"] as? String)
        #expect(zhInstructions.contains("Mandarin"))
        #expect(zhInstructions.contains("Speak up"))

        let en = try OpenAISpeech.request("Hi", apiKey: "k", voice: "cedar", chinese: false)
        let enBody = try #require(JSONSerialization.jsonObject(with: en.httpBody ?? Data()) as? [String: Any])
        let enInstructions = try #require(enBody["instructions"] as? String)
        #expect(!enInstructions.contains("Mandarin"))
        #expect(enInstructions.contains("Speak up"))
    }

    @Test("Streamed audio is cut into 100 ms chunks; the end keeps whole samples only")
    func chunksAudio() {
        var chunker = PCMChunker()
        var chunks: [Data] = []
        for i in 0..<10_001 {
            if let c = chunker.add(UInt8(i % 256)) { chunks.append(c) }
        }
        #expect(chunks.map(\.count) == [4800, 4800])
        let last = chunker.finish()
        #expect(last?.count == 400)                    // 401 bytes left, odd byte dropped
        #expect(chunker.finish() == nil)
        #expect(chunks[1].first == UInt8(4800 % 256))  // nothing lost or repeated between chunks

        var tiny = PCMChunker(size: 4)
        _ = tiny.add(1)
        #expect(tiny.finish() == nil)                  // half a sample isn't audio
    }

    @Test("Loud speech is never pushed past the ceiling (no distortion)")
    func boosterNeverClips() throws {
        var booster = SpeechBooster()
        for level in [0.05, 0.9, 0.3, 1.0, 0.02, 0.99] {
            let boosted = booster.boost(pcm16(level: level))
            let out = try #require(boosted)
            #expect(peak(of: out) <= SpeechBooster.ceiling + 0.0001, "level \(level)")
        }
    }

    @Test("Quiet speech is lifted gently, up to about 10 dB, never jumping")
    func boosterLiftsGently() throws {
        var booster = SpeechBooster()
        var previous: Float = 0
        var last: Float = 0
        for i in 0..<30 {
            let boosted = booster.boost(pcm16(level: 0.05))
            let out = try #require(boosted)
            let p = peak(of: out)
            if i > 0 { #expect(p <= previous * 1.121, "chunk \(i) rose too fast") }
            previous = p
            last = p
        }
        let gain = last / 0.05
        #expect(abs(gain - SpeechBooster.maxGain) < 0.01)
        #expect(booster.boost(Data()) == nil)
    }

    // MARK: Microphone gate

    @Test("A quiet room never reaches OpenAI; it is sent as silence of the same length")
    func gateBlocksRoomNoise() {
        var gate = MicGate()
        var now = Date(timeIntervalSince1970: 0)
        for _ in 0..<50 {
            let raw = pcm16(level: 0.003)
            let out = gate.feed(raw, level: 100, muted: false, now: now)
            #expect(!out.open)
            #expect(out.send == [Data(count: raw.count)])
            now += 0.1
        }
    }

    @Test("Speech opens the gate with 0.3 s of lead-in, stays open through short pauses, then closes")
    func gateOpensWithLeadIn() {
        var gate = MicGate()
        var now = Date(timeIntervalSince1970: 0)
        let quiet = (1...5).map { pcm16(level: Double($0) / 10_000, count: 10) }
        for q in quiet {
            _ = gate.feed(q, level: 100, muted: false, now: now)
            now += 0.1
        }
        let word = pcm16(level: 0.2, count: 10)
        let first = gate.feed(word, level: 3000, muted: false, now: now)
        #expect(first.open)
        #expect(first.send == [quiet[2], quiet[3], quiet[4], word])
        // A pause between words: still open for 0.8 s.
        now += 0.5
        let pause = gate.feed(quiet[0], level: 100, muted: false, now: now)
        #expect(pause.open && pause.send == [quiet[0]])
        now += 0.4
        let after = gate.feed(quiet[1], level: 100, muted: false, now: now)
        #expect(!after.open)
    }

    @Test("Audio that was already sent is never sent again as lead-in")
    func gateNeverRepeatsAudio() {
        var gate = MicGate()
        var step = 0
        var sent: [Data] = []
        func feed(level: Float) {
            step += 1
            let chunk = Data((0..<8).map { _ in UInt8(step % 256) })     // every chunk is different
            let out = gate.feed(chunk, level: level, muted: false, now: Date(timeIntervalSince1970: Double(step) / 10))
            sent += out.send.filter { $0 != Data(count: $0.count) }      // ignore silence
        }
        // Talk, pause until the gate has just closed (or nearly), talk again.
        for pause in [8, 9, 10, 11, 12] {
            for _ in 0..<3 { feed(level: 3000) }
            for _ in 0..<pause { feed(level: 50) }
        }
        feed(level: 3000)
        #expect(Set(sent).count == sent.count, "a chunk was sent twice")
    }

    @Test("While the phone talks, nothing from the mic is sent, however loud")
    func gateSilentWhileMuted() {
        var gate = MicGate()
        let now = Date(timeIntervalSince1970: 0)
        let out = gate.feed(pcm16(level: 0.5, count: 100), level: 16_000, muted: true, now: now)
        #expect(!out.open)
        #expect(out.send == [Data(count: 200)])
        // And the phone's own voice doesn't become lead-in for the next sentence.
        let next = gate.feed(pcm16(level: 0.2, count: 100), level: 3000, muted: false, now: now + 0.1)
        #expect(next.send.count == 1)
    }

    @Test("A noisy room is learned, so steady noise stops opening the gate but a voice still does")
    func gateLearnsNoisyRoom() {
        var gate = MicGate()
        var now = Date(timeIntervalSince1970: 0)
        for _ in 0..<500 {                                  // 50 s of café noise
            _ = gate.feed(Data(count: 20), level: 800, muted: false, now: now)
            now += 0.1
        }
        #expect(gate.roomLevel > 700)
        now += 1
        #expect(!gate.feed(Data(count: 20), level: 1000, muted: false, now: now).open)
        #expect(gate.feed(Data(count: 20), level: 2500, muted: false, now: now + 0.1).open)
    }

    @Test("Very quiet sounds never open the gate, however quiet the room")
    func gateHasAFloor() {
        var gate = MicGate()
        var now = Date(timeIntervalSince1970: 0)
        for _ in 0..<100 {
            _ = gate.feed(Data(count: 20), level: 10, muted: false, now: now)
            now += 0.1
        }
        #expect(!gate.feed(Data(count: 20), level: 150, muted: false, now: now).open)
    }

    // MARK: Playback clock

    @Test("Stopping playback early reopens the mic after the short tail")
    func flushReopensMic() {
        let t0 = Date(timeIntervalSince1970: 0)
        var clock = PlaybackClock()
        clock.scheduled(seconds: 5, at: t0)
        clock.flush(at: t0 + 1)
        #expect(clock.isMuted(at: t0 + 1.5))
        #expect(!clock.isMuted(at: t0 + 1.7))
        #expect(clock.speechEnd(at: t0 + 2) == t0 + 1)
    }

    @Test("Audio scheduled after a gap starts from now, not from the old end")
    func scheduleAfterGap() {
        let t0 = Date(timeIntervalSince1970: 0)
        var clock = PlaybackClock()
        clock.scheduled(seconds: 1, at: t0)
        clock.scheduled(seconds: 1, at: t0 + 10)
        #expect(clock.playUntil == t0 + 11)
    }

    // MARK: Voices and languages

    @Test("Eight distinct voices; a missing or unknown choice falls back to Marin")
    func voices() {
        let ids = InterpreterVoice.all.map(\.id)
        #expect(ids.count == 8 && Set(ids).count == 8)
        #expect(ids.contains(InterpreterVoice.defaultID))
        #expect(InterpreterVoice.named("nope").id == "marin")
        #expect(InterpreterVoice.named("cedar").name == "Cedar")

        let defaults = UserDefaults.standard
        let saved = (defaults.object(forKey: InterpreterVoice.momKey), defaults.object(forKey: InterpreterVoice.othersKey))
        defer {
            defaults.set(saved.0, forKey: InterpreterVoice.momKey)
            defaults.set(saved.1, forKey: InterpreterVoice.othersKey)
        }
        defaults.removeObject(forKey: InterpreterVoice.momKey)
        #expect(InterpreterVoice.forMom == "marin")
        defaults.set("ash", forKey: InterpreterVoice.momKey)
        defaults.set("removed-voice", forKey: InterpreterVoice.othersKey)
        #expect(InterpreterVoice.forMom == "ash")
        #expect(InterpreterVoice.forOthers == "marin")
    }

    @Test("English and German partners each have their own words and voice")
    func partnerLanguages() {
        #expect(PartnerLanguage.english.voice == "en-US")
        #expect(PartnerLanguage.german.voice == "de-DE")
        #expect(PartnerLanguage.german.cantSpeakLabel == "我不会说德语")
        #expect(PartnerLanguage.english.cantSpeakLabel == "我不会说英语")
        for p in PartnerLanguage.allCases {
            #expect(!p.invitation.isEmpty && !p.slowDown.isEmpty && !p.cantSpeakPhrase.isEmpty)
            #expect(!InterpreterEngine.hasChinese(p.cantSpeakPhrase))
            #expect(InterpreterEngine.hasChinese(p.cantSpeakChinese))
        }
        #expect(InterpreterEngine.targetLanguage(fromMom: true, partnerName: "German") == "German")
        #expect(Demo.conversation(with: .german).contains { !$0.fromMom && $0.original.contains("Uhr") })
    }

    @Test("Audio sessions: record-and-play in default mode for both mic users")
    func audioModes() {
        #expect(InterpreterAudio.sessionMode == .default)
        #expect(SpeechListener.sessionMode == .default)
    }
}
