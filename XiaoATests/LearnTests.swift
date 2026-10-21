import Foundation
import Testing
@testable import XiaoA

// MARK: - Pronunciation check

@Suite("学英语 · Pronunciation check")
struct PronunciationTests {

    @Test("What the recognizer writes for a good try passes")
    func goodTriesPass() {
        let cases: [(target: String, heard: String)] = [
            ("Where is the restroom?", "where is the rest room"),
            ("I don't understand.", "I do not understand"),
            ("It's $5.", "it's five dollars"),
            ("Me too.", "me two"),
            ("Me too.", "Me to."),
            ("Excuse me.", "excuses me"),
            ("Nice to meet you.", "nice to meat you"),
            ("See you at 3:00.", "see you at three o'clock"),
            ("My son's name is Alex.", "my sons name is Alex"),
            ("Thank you!", "THANK YOU")
        ]
        for c in cases {
            let r = PronunciationCheck.score(target: c.target, heard: c.heard)
            #expect(r.score == 1 && r.missed.isEmpty, "\(c.target) / heard \(c.heard): \(r.missed)")
        }
    }

    @Test("Missing words are reported as written, with a fair score")
    func missingWords() {
        let r = PronunciationCheck.score(target: "I don't speak English.", heard: "I speak English")
        #expect(r.missed == ["do", "not"])
        #expect(abs(r.score - 0.6) < 0.0001)
        let hello = PronunciationCheck.score(target: "Hello!", heard: "Yellow")
        #expect(hello.score == 0 && hello.missed == ["hello"])
        let silence = PronunciationCheck.score(target: "Good morning!", heard: "")
        #expect(silence.score == 0 && silence.missed == ["good", "morning"])
    }

    @Test("Short words must be exact; only long words get one letter of slack")
    func shortWordsExact() {
        #expect(!PronunciationCheck.score(target: "Yes, please.", heard: "yet please").missed.isEmpty)
        #expect(PronunciationCheck.score(target: "Please speak slowly.", heard: "please speak slowy").missed.isEmpty)
    }

    @Test("An empty target always passes (never a crash or a divide by zero)")
    func emptyTarget() {
        #expect(PronunciationCheck.score(target: "", heard: "anything").score == 1)
        #expect(PronunciationCheck.score(target: "!?", heard: "").score == 1)
    }

    @Test("Normalising: contractions, possessives, prices, times and cents")
    func normalises() {
        #expect(PronunciationCheck.normalize("I’m here") == ["i", "am", "here"])
        #expect(PronunciationCheck.normalize("Alex's car") == ["alex", "car"])
        #expect(PronunciationCheck.normalize("$20") == ["twenty", "dollars"])
        #expect(PronunciationCheck.normalize("at 9:00") == ["at", "nine", "o'clock"])
        #expect(PronunciationCheck.normalize("50¢") == ["fifty", "cents"])
        #expect(PronunciationCheck.normalize("to too two") == ["two", "two", "two"])
    }

    @Test("Tips name the word the way it's written in the phrase")
    func asWritten() {
        #expect(PronunciationCheck.asWritten("hello", in: "Hello!") == "Hello")
        #expect(PronunciationCheck.asWritten("restroom", in: "Where is the restroom?") == "restroom")
        #expect(PronunciationCheck.asWritten("zzz", in: "Hello!") == "zzz")
    }
}

// MARK: - Curriculum

@Suite("学英语 · Curriculum")
@MainActor
struct CurriculumTests {

    @Test("29 everyday scenes, about 175 phrases, every id unique")
    func size() {
        let units = Curriculum.units(for: AppConfig())
        #expect(units.count == 29)
        #expect(Set(units.map(\.id)).count == units.count)
        let phrases = units.flatMap(\.phrases)
        #expect(phrases.count >= 150)
        #expect(Set(phrases.map(\.id)).count == phrases.count)
        #expect(units.allSatisfy { !$0.phrases.isEmpty && !$0.title.isEmpty })
    }

    @Test("Mom's and Alex's names go into the 介绍自己 phrases")
    func names() {
        var config = AppConfig()
        #expect(!Curriculum.allPhrases(for: config).contains { $0.id == "me2" })
        config.momNameEN = "Lin"
        config.alexName = "Bob"
        let all = Curriculum.allPhrases(for: config)
        #expect(all.first { $0.id == "me2" }?.en == "My name is Lin.")
        #expect(all.first { $0.id == "me5" }?.en == "My son's name is Bob.")
        config.alexName = ""
        #expect(Curriculum.allPhrases(for: config).first { $0.id == "me5" }?.en == "My son's name is Alex.")
    }

    @Test("Every phrase: English to say, Chinese meaning, when to say it, and a stressed beat")
    func everyPhraseComplete() {
        for p in Curriculum.allPhrases(for: AppConfig()) {
            #expect(!p.en.isEmpty && !InterpreterEngine.hasChinese(p.en), "\(p.id)")
            #expect(InterpreterEngine.hasChinese(p.zh), "\(p.id)")
            #expect(InterpreterEngine.hasChinese(p.scene), "\(p.id)")
            #expect(p.beats.contains { $0.isUppercase }, "\(p.id) has no stressed beat")
            let hasNumber = p.en.contains { $0.isNumber }
            if !hasNumber {
                #expect(p.beats.components(separatedBy: " · ").count == p.en.split(separator: " ").count,
                        "\(p.id): beats don't line up with the words")
            }
        }
    }

    @Test("Saying any phrase exactly, the way the recognizer writes it, passes")
    func everyPhrasePassesItself() {
        for p in Curriculum.allPhrases(for: AppConfig()) {
            let asTyped = p.en.lowercased().filter { !".,!?".contains($0) }
            let r = PronunciationCheck.score(target: p.en, heard: asTyped)
            #expect(r.score == 1, "\(p.id) \"\(p.en)\" fails against \"\(asTyped)\": \(r.missed)")
        }
    }

    @Test("Every phrase shows the whole coaching loop in the simulator demo: a miss, then right")
    func demoTries() {
        for p in Curriculum.allPhrases(for: AppConfig()) {
            #expect(Demo.heard(for: p.en, attempt: 2) == p.en)
            let first = PronunciationCheck.score(target: p.en, heard: Demo.heard(for: p.en, attempt: 1))
            #expect(!first.missed.isEmpty, "\(p.id): the demo's first try is already perfect")
        }
        #expect(Demo.heard(for: "Hello!", attempt: 1) == "uh")
    }
}

// MARK: - Rules

@Suite("学英语 · Rules")
@MainActor
struct LearnRuleTests {

    @Test("Pass mark: 75% of words normally, every word in strict mode")
    func passMark() {
        #expect(CoachModel.passes(score: 0.75, missedCount: 1, strict: false))
        #expect(!CoachModel.passes(score: 0.74, missedCount: 1, strict: false))
        #expect(!CoachModel.passes(score: 0.8, missedCount: 1, strict: true))
        #expect(CoachModel.passes(score: 1, missedCount: 0, strict: true))
    }

    @Test("Stars: 3 first time, 2 for the second or third try, then 1")
    func stars() {
        #expect([1, 2, 3, 4, 10].map { CoachModel.stars(forTries: $0) } == [3, 2, 2, 1, 1])
    }

    @Test("Speeds: slow by default, each slower than the last")
    func speeds() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: LearnSpeed.key)
        defer { defaults.set(saved, forKey: LearnSpeed.key) }
        defaults.removeObject(forKey: LearnSpeed.key)
        #expect(LearnSpeed.current == .slow)
        defaults.set("verySlow", forKey: LearnSpeed.key)
        #expect(LearnSpeed.current == .verySlow)
        defaults.set("bogus", forKey: LearnSpeed.key)
        #expect(LearnSpeed.current == .slow)
        #expect(LearnSpeed.normal.rate > LearnSpeed.slow.rate && LearnSpeed.slow.rate > LearnSpeed.verySlow.rate)
        #expect(LearnSpeed.verySlow.rate < Speaker.normalRate)
    }
}

// MARK: - When she has finished a try

@Suite("学英语 · End of a try")
struct TurnEndTests {
    let t0 = Date(timeIntervalSince1970: 1_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    @Test("Nobody speaks for 12 s: give up quietly")
    func nobodySpoke() {
        var d = TurnEndDetector(began: t0)
        #expect(d.update(now: at(5), transcript: "", spoke: false, lastLoud: .distantPast, firstLoud: nil) == .keepListening)
        #expect(d.update(now: at(12.2), transcript: "", spoke: false, lastLoud: .distantPast, firstLoud: nil) == .nobodySpoke)
    }

    @Test("She speaks, then pauses 1.8 s: done")
    func pauseEndsTry() {
        var d = TurnEndDetector(began: t0)
        #expect(d.update(now: at(1), transcript: "", spoke: true, lastLoud: at(1), firstLoud: at(1)) == .keepListening)
        #expect(d.update(now: at(2), transcript: "hello", spoke: true, lastLoud: at(2), firstLoud: at(1)) == .keepListening)
        #expect(d.update(now: at(3.5), transcript: "hello", spoke: true, lastLoud: at(2), firstLoud: at(1)) == .keepListening)
        #expect(d.update(now: at(3.9), transcript: "hello", spoke: true, lastLoud: at(2), firstLoud: at(1)) == .done)
    }

    @Test("A beginner's pause between words doesn't cut her off while words keep coming")
    func wordsKeepComing() {
        var d = TurnEndDetector(began: t0)
        #expect(d.update(now: at(1), transcript: "where", spoke: true, lastLoud: at(1), firstLoud: at(1)) == .keepListening)
        #expect(d.update(now: at(2.5), transcript: "where is", spoke: true, lastLoud: at(1), firstLoud: at(1)) == .keepListening)
        #expect(d.update(now: at(4), transcript: "where is the", spoke: true, lastLoud: at(2.5), firstLoud: at(1)) == .keepListening)
    }

    @Test("A noisy room can't keep the mic open: once her words settle, it's done")
    func noiseCantHoldOpen() {
        var d = TurnEndDetector(began: t0)
        #expect(d.update(now: at(2), transcript: "hello", spoke: true, lastLoud: at(2), firstLoud: at(1)) == .keepListening)
        #expect(d.update(now: at(4.5), transcript: "hello", spoke: true, lastLoud: at(4.5), firstLoud: at(1)) == .keepListening)
        #expect(d.update(now: at(4.9), transcript: "hello", spoke: true, lastLoud: at(4.9), firstLoud: at(1)) == .done)
    }

    @Test("Never longer than 20 s from her first sound")
    func hardCap() {
        var d = TurnEndDetector(began: t0)
        var words = ""
        var decision = TurnEndDetector.Decision.keepListening
        var time = 1.0
        while time <= 21.5 {
            words += " la"
            decision = d.update(now: at(time), transcript: words, spoke: true, lastLoud: at(time), firstLoud: at(1))
            if time < 20.9 { #expect(decision == .keepListening, "stopped at \(time) s") }
            time += 0.5
        }
        #expect(decision == .done)
    }

    @Test("Words without a loud sound still count as speech")
    func wordsWithoutLevel() {
        var d = TurnEndDetector(began: t0)
        _ = d.update(now: at(1), transcript: "hi", spoke: false, lastLoud: .distantPast, firstLoud: nil)
        #expect(d.update(now: at(13), transcript: "hi", spoke: false, lastLoud: .distantPast, firstLoud: nil) == .done)
    }
}

// MARK: - Progress

@Suite("学英语 · Progress", .serialized)
@MainActor
struct LearningStoreTests {

    @Test("First day: four new phrases in curriculum order, nothing to review")
    func firstDay() {
        let store = LearningStore(fileURL: TestFiles.temporaryURL())
        let plan = store.todaysPlan(for: AppConfig())
        #expect(plan.review.isEmpty)
        #expect(plan.new.map(\.id) == ["g1", "g2", "g3", "g4"])
        var more = AppConfig()
        more.newPhrasesPerDay = 6
        #expect(store.todaysPlan(for: more).new.count == 6)
    }

    @Test("Review comes back weakest first, at most four; new phrases continue in order")
    func review() {
        let store = LearningStore(fileURL: TestFiles.temporaryURL())
        for id in ["g1", "g2", "g3", "g4", "g5"] {
            store.recordAttempt(id, passed: true)
            store.finishPhrase(id, passed: true, triesToday: 1)
        }
        store.recordAttempt("g6", passed: false)
        store.finishPhrase("g6", passed: false, triesToday: 4)
        let plan = store.todaysPlan(for: AppConfig())
        #expect(plan.review.count == 4)
        #expect(plan.review.first?.id == "g6")
        #expect(plan.new.first?.id == "s1")
        #expect(store.strugglingPhrases(for: AppConfig()).map(\.id) == ["g6"])
    }

    @Test("Learned after 3+ tries: mastered but reviewed again; skipped after trying: reviewed")
    func finishRules() {
        let store = LearningStore(fileURL: TestFiles.temporaryURL())
        store.finishPhrase("a", passed: true, triesToday: 1)
        store.finishPhrase("b", passed: true, triesToday: 3)
        store.finishPhrase("c", passed: false, triesToday: 2)
        #expect(store.stat("a").mastered && !store.stat("a").needsReview)
        #expect(store.stat("b").mastered && store.stat("b").needsReview)
        #expect(!store.stat("c").mastered && store.stat("c").needsReview)
        #expect(store.masteredCount == 2)
        store.recordAttempt("a", passed: false)
        store.recordAttempt("a", passed: true)
        #expect(store.stat("a").attempts == 2 && store.stat("a").passes == 1)
        #expect(store.stat("a").lastPracticed != nil)
    }

    @Test("Progress survives closing the app; a damaged file starts fresh instead of crashing")
    func persistence() throws {
        let url = TestFiles.temporaryURL()
        let store = LearningStore(fileURL: url)
        store.recordAttempt("g1", passed: true)
        store.markDayDone()
        let reopened = LearningStore(fileURL: url)
        #expect(reopened.stat("g1").attempts == 1)
        #expect(reopened.doneToday)

        let broken = TestFiles.temporaryURL()
        try Data("{ not json".utf8).write(to: broken)
        #expect(LearningStore(fileURL: broken).data.stats.isEmpty)
    }

    @Test("Streak: consecutive days, counting from today or yesterday")
    func streak() {
        let cal = Calendar.current
        let today = Date()
        func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: today)! }

        let store = LearningStore(fileURL: TestFiles.temporaryURL())
        #expect(store.streak(asOf: today) == 0)
        for n in [1, 2, 3, 5] { store.markDayDone(on: daysAgo(n)) }
        #expect(store.streak(asOf: today) == 3)          // today not done yet: yesterday still counts
        store.markDayDone(on: today)
        store.markDayDone(on: today)
        #expect(store.streak(asOf: today) == 4)
        #expect(store.data.daysDone.count == 5)          // the same day twice counts once
        #expect(store.streak(asOf: cal.date(byAdding: .day, value: 2, to: today)!) == 0)
    }
}
