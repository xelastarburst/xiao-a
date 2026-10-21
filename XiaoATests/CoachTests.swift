import Foundation
import Testing
@testable import XiaoA

/// The hands-free lesson loop, with a fake voice and scripted tries instead of the speaker and mic.
@Suite("学英语 · Lesson loop", .serialized)
@MainActor
struct CoachTests {

    struct NoMic: LocalizedError {
        var errorDescription: String? { "需要打开麦克风" }
    }

    /// A coach on a fresh store, with a fake voice, the given tries and a fixed tip.
    @MainActor
    final class Lesson {
        let voice = FakeVoice()
        let mic: ScriptedMic
        let store = LearningStore(fileURL: TestFiles.temporaryURL())
        let coach = CoachModel()
        var tipsAsked: [(attempt: Int, missed: [String])] = []

        init(_ tries: [String], config: AppConfig = AppConfig()) {
            mic = ScriptedMic(tries)
            coach.speaker = voice.speaker
            coach.listenOverride = { [mic] in try await mic.listen() }
            coach.tipProvider = { [weak self] _, _, missed, attempt in
                self?.tipsAsked.append((attempt: attempt, missed: missed))
                return "TIP"
            }
            coach.prepareIfNeeded(store: store, config: config)
        }

        func scene(_ index: Int) -> LessonUnit { Curriculum.units(for: AppConfig())[index] }

        var passedStars: Int? {
            if case .passed(let stars) = coach.stage { return stars }
            return nil
        }

        /// Stops the loop, so nothing keeps running after the test.
        func end() { coach.stopLoop() }
    }

    @Test("It says 请跟我说 and the phrase, then listens")
    func introThenListen() async {
        let lesson = Lesson([])
        defer { lesson.end() }
        lesson.coach.startScene(lesson.scene(0), store: lesson.store)
        #expect(lesson.coach.current?.phrase.en == "Hello!")
        #expect(await waitUntil { lesson.mic.calls == 1 })
        #expect(Array(lesson.voice.allSpoken.prefix(2)) == ["请跟我说：", "Hello!"])
        #expect(lesson.coach.phase == .listening)
    }

    @Test("Right first time: 3 stars, praise, saved as learned, and it waits for 下一句")
    func rightFirstTime() async {
        let lesson = Lesson(["Hello"])
        defer { lesson.end() }
        lesson.coach.startScene(lesson.scene(0), store: lesson.store)
        #expect(await waitUntil { lesson.passedStars != nil && lesson.coach.phase == .idle })
        #expect(lesson.passedStars == 3)
        #expect(lesson.coach.starsToday == 3)
        #expect(lesson.store.stat("g1").mastered)
        #expect(lesson.voice.allSpoken.last?.contains("下一句") == true)
        try? await Task.sleep(nanoseconds: 800_000_000)
        #expect(lesson.mic.calls == 1)                       // no more listening after she got it
        #expect(lesson.coach.index == 0)                     // she moves on when she's ready
    }

    @Test("Not yet: a tip, the phrase again, and it keeps listening until she gets it")
    func retryUntilRight() async {
        let lesson = Lesson(["Yellow", "Hollow", "Hello"])
        defer { lesson.end() }
        lesson.coach.startScene(lesson.scene(0), store: lesson.store)
        #expect(await waitUntil(8) { lesson.passedStars != nil })
        #expect(lesson.passedStars == 2)
        #expect(lesson.coach.tries == 3)
        #expect(lesson.tipsAsked.map { $0.attempt } == [1, 2])
        #expect(lesson.tipsAsked.first?.missed == ["hello"])
        #expect(lesson.voice.allSpoken.filter { $0 == "TIP" }.count == 2)
        #expect(lesson.voice.allSpoken.contains("再听一遍："))
        #expect(lesson.coach.heard == "Hello")
        #expect(lesson.store.stat("g1").attempts == 3)
    }

    @Test("From the second miss, the phrase is read word by word")
    func wordByWordAfterSecondMiss() async throws {
        let lesson = Lesson(["no", "no"])
        defer { lesson.end() }
        lesson.coach.startScene(lesson.scene(1), store: lesson.store)     // "I don't speak English."
        #expect(lesson.coach.current?.phrase.en == "I don't speak English.")
        #expect(await waitUntil(8) { lesson.mic.calls == 2 && lesson.tipsAsked.count == 2 })
        #expect(await waitUntil { lesson.mic.calls == 3 })
        let spoken = lesson.voice.allSpoken
        let firstTip = try #require(spoken.firstIndex(of: "TIP"))
        let secondTip = try #require(spoken.lastIndex(of: "TIP"))
        #expect(!spoken[firstTip...].prefix(secondTip - firstTip).contains("don't"))
        #expect(Array(spoken[secondTip...].prefix(6)) == ["TIP", "再听一遍：", "I", "don't", "speak", "English."])
        if case .retry(let tip, let close) = lesson.coach.stage {
            #expect(tip == "TIP" && !close)
        } else {
            Issue.record("expected the retry stage, got \(lesson.coach.stage)")
        }
    }

    @Test("Strict mode needs every word; normal mode accepts a small slip")
    func strictMode() async {
        let normal = Lesson(["I do speak English"])
        defer { normal.end() }
        normal.coach.startScene(normal.scene(1), store: normal.store)
        #expect(await waitUntil { normal.passedStars == 3 })

        var strictConfig = AppConfig()
        strictConfig.strictPronunciation = true
        let strict = Lesson(["I do speak English", "I don't speak English"], config: strictConfig)
        defer { strict.end() }
        strict.coach.startScene(strict.scene(1), store: strict.store)
        #expect(await waitUntil(8) { strict.passedStars != nil })
        #expect(strict.passedStars == 2)
        #expect(strict.tipsAsked.first?.missed == ["not"])
    }

    @Test("Silence: one nudge, then it stops and waits for 开始跟读; resume listens again")
    func silenceThenResume() async {
        let lesson = Lesson(["", "", "Hello"])
        defer { lesson.end() }
        lesson.coach.startScene(lesson.scene(0), store: lesson.store)
        #expect(await waitUntil { lesson.mic.calls == 2 && lesson.coach.phase == .idle })
        #expect(lesson.voice.allSpoken.filter { $0 == "我在听呢，你跟我说：" }.count == 1)
        #expect(lesson.coach.tries == 0)                    // silence isn't a failed try
        lesson.coach.resume()
        #expect(await waitUntil { lesson.passedStars == 3 })
    }

    @Test("A microphone problem is shown, not a frozen screen")
    func micError() async {
        let lesson = Lesson([])
        defer { lesson.end() }
        lesson.coach.listenOverride = { throw NoMic() }
        lesson.coach.startScene(lesson.scene(0), store: lesson.store)
        #expect(await waitUntil { lesson.coach.listenError != nil })
        #expect(lesson.coach.listenError == "需要打开麦克风")
        #expect(lesson.coach.phase == .idle)
    }

    @Test("Pause stops talking and listening; carrying on reads the phrase and listens again")
    func pauseAndCarryOn() async {
        let lesson = Lesson([])
        defer { lesson.end() }
        lesson.coach.startScene(lesson.scene(0), store: lesson.store)
        #expect(await waitUntil { lesson.mic.calls == 1 })
        lesson.coach.pause()
        #expect(lesson.coach.paused && lesson.coach.phase == .idle)
        let spokenBefore = lesson.voice.allSpoken.count
        try? await Task.sleep(nanoseconds: 600_000_000)
        #expect(lesson.mic.calls == 1)
        lesson.coach.unpause()
        #expect(await waitUntil { lesson.mic.calls == 2 })
        #expect(lesson.voice.allSpoken.count > spokenBefore)
    }

    @Test("Skipping a phrase she tried brings it back in review; one never tried stays new")
    func skipping() async {
        let lesson = Lesson(["Yellow"])
        defer { lesson.end() }
        lesson.coach.startScene(lesson.scene(0), store: lesson.store)
        #expect(await waitUntil { lesson.coach.tries == 1 && lesson.mic.calls == 2 })
        lesson.coach.skip(store: lesson.store)
        #expect(lesson.coach.index == 1)
        #expect(lesson.store.stat("g1").needsReview)
        lesson.coach.skip(store: lesson.store)
        #expect(lesson.coach.index == 2)
        #expect(lesson.store.data.stats["g2"] == nil)
    }

    @Test("The end of a scene: 这一组练完啦, progress full")
    func endOfScene() async {
        let lesson = Lesson([])
        defer { lesson.end() }
        let unit = lesson.scene(0)
        lesson.coach.startScene(unit, store: lesson.store)
        for _ in unit.phrases { lesson.coach.skip(store: lesson.store) }
        #expect(lesson.coach.stage == .finished)
        #expect(lesson.coach.progress == 1)
        #expect(lesson.voice.allSpoken.last == "这一组练完啦！你真棒！")
        #expect(!lesson.store.doneToday)                    // a scene isn't today's lesson
    }

    @Test("Today's lesson from start to finish: four phrases, 12 stars, day marked done")
    func todaysLesson() async {
        let lesson = Lesson(["Hello", "Good morning", "Thank you", "You're welcome"])
        defer { lesson.end() }
        #expect(lesson.coach.newCount == 4 && lesson.coach.reviewCount == 0)
        lesson.coach.startToday()
        for i in 0..<4 {
            #expect(await waitUntil { lesson.passedStars != nil && lesson.coach.phase == .idle }, "phrase \(i)")
            lesson.coach.next(store: lesson.store)
        }
        #expect(lesson.coach.stage == .finished)
        #expect(lesson.coach.starsToday == 12)
        #expect(lesson.store.doneToday)
        #expect(lesson.voice.allSpoken.last == "今天的课学完啦！你真棒！")
    }

    @Test("Leaving today's lesson for a scene and coming back resumes where she was")
    func todayResumes() async {
        let lesson = Lesson(["Hello"])
        defer { lesson.end() }
        lesson.coach.startToday()
        #expect(await waitUntil { lesson.passedStars != nil && lesson.coach.phase == .idle })
        lesson.coach.next(store: lesson.store)
        #expect(lesson.coach.index == 1)
        lesson.coach.startScene(lesson.scene(5), store: lesson.store)
        #expect(lesson.coach.session == .scene(lesson.scene(5).id))
        lesson.coach.showOverview()
        #expect(lesson.coach.session == .today && lesson.coach.index == 1)
        #expect(lesson.coach.todayStarted)
    }

    @Test("再学几句新的 picks up after the phrases she has already met")
    func morePhrases() async {
        let lesson = Lesson([])
        defer { lesson.end() }
        for id in ["g1", "g2", "g3", "g4"] { lesson.store.recordAttempt(id, passed: true) }
        lesson.coach.startMore(store: lesson.store, config: AppConfig())
        #expect(lesson.coach.session == .more)
        #expect(lesson.coach.items.first?.phrase.id == "g5")
        #expect(lesson.coach.items.allSatisfy { !$0.isReview })
    }

    @Test("An empty scene does nothing")
    func emptyScene() {
        let lesson = Lesson([])
        defer { lesson.end() }
        lesson.coach.startScene(LessonUnit(id: 99, title: "空", phrases: []), store: lesson.store)
        #expect(lesson.coach.stage == .overview)
        #expect(lesson.voice.allSpoken.isEmpty)
    }
}
