import SwiftUI

/// How fast 小A reads English in lessons (Alex mode › Learning).
enum LearnSpeed: String, CaseIterable, Identifiable {
    case normal, slow, verySlow
    var id: String { rawValue }
    static let key = "learnSpeed"

    var rate: Float {
        switch self {
        case .normal: return 0.42
        case .slow: return 0.36
        case .verySlow: return 0.30
        }
    }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .slow: return "Slow"
        case .verySlow: return "Very slow"
        }
    }

    static var current: LearnSpeed {
        LearnSpeed(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .slow
    }
}

/// Runs a lesson, hands-free, like a patient teacher:
/// 1. 小A says the phrase (slowly), then listens on its own. No button to hold.
/// 2. When she pauses, it checks what she said against the phrase.
/// 3. Not yet? One specific tip, the phrase again (word by word after the second try), and it
///    listens again, for as long as it takes. Right? Stars, and 下一句 when she's ready.
/// 跳过这句 is always there, and a phrase she skips or struggles with comes back in review.
///
/// Three ways in:
/// - 今天的课: a few review phrases plus a few new ones, in curriculum order (resumable).
/// - 按场景练: every phrase of one everyday scene (supermarket, doctor, bus…), in order.
/// - 再学几句新的: the next new phrases, any time, even after today's lesson.
@MainActor
final class CoachModel: ObservableObject {
    enum Stage: Equatable {
        case overview
        case ready
        case checking
        case retry(tip: String, close: Bool)
        case passed(stars: Int)
        case finished
    }

    /// What the phone is doing right now during a phrase.
    enum Phase: Equatable {
        /// Waiting for her to tap 开始跟读 (e.g. she walked away, or after a pause).
        case idle
        case speaking
        case listening
        case checking
    }

    enum Session: Equatable {
        case today
        case scene(Int)
        case more
    }

    struct Item: Identifiable {
        let phrase: Phrase
        let isReview: Bool
        var id: String { (isReview ? "r-" : "n-") + phrase.id }
    }

    /// After this many tries, 跳过这句 is suggested (listening still goes on).
    static let suggestSkipAfter = 5

    let listener = SpeechListener()
    /// Who reads aloud (a speaker with a fake engine in tests).
    var speaker: Speaker = .shared
    /// Tests: replaces the microphone with scripted tries.
    var listenOverride: (() async throws -> String?)?
    /// Tests: replaces the Claude tip.
    var tipProvider: ((Phrase, String, [String], Int) async -> String)?

    @Published private(set) var items: [Item] = []
    @Published private(set) var index = 0
    @Published private(set) var stage: Stage = .overview
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var session: Session = .today
    @Published private(set) var sessionTitle: String?
    @Published private(set) var tries = 0
    @Published private(set) var missed: Set<String> = []
    /// What the phone heard on the last try, shown under the sentence.
    @Published private(set) var heard = ""
    @Published private(set) var listenError: String?
    @Published private(set) var starsToday = 0
    @Published var paused = false

    private(set) var startedAt: Date?
    private var preparedDay = ""
    /// Today's lesson is kept aside while she practises a scene, so she can come back to it.
    private(set) var todayItems: [Item] = []
    private(set) var todayIndex = 0

    private var loop: Task<Void, Never>?
    private weak var store: LearningStore?
    private var config: AppConfig?

    var current: Item? { items.indices.contains(index) ? items[index] : nil }
    var progress: Double {
        guard !items.isEmpty else { return 0 }
        let done: Int
        switch stage {
        case .passed, .finished: done = index + 1
        default: done = index
        }
        return min(1, Double(done) / Double(items.count))
    }
    var newCount: Int { todayItems.filter { !$0.isReview }.count }
    var reviewCount: Int { todayItems.filter(\.isReview).count }
    var todayStarted: Bool { todayIndex > 0 }

    func minutesLeft(at now: Date) -> Int {
        guard let startedAt else { return 30 }
        return max(0, 30 - Int(now.timeIntervalSince(startedAt) / 60))
    }

    /// Builds today's plan once per day, so leaving and coming back resumes where she was.
    func prepareIfNeeded(store: LearningStore, config: AppConfig) {
        self.store = store
        self.config = config
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let today = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        guard preparedDay != today else { return }
        preparedDay = today
        let plan = store.todaysPlan(for: config)
        todayItems = plan.review.map { Item(phrase: $0, isReview: true) } + plan.new.map { Item(phrase: $0, isReview: false) }
        todayIndex = 0
        starsToday = 0
        startedAt = nil
        showOverview()
    }

    /// Keeps the latest settings (e.g. strict pronunciation) for checking.
    func update(config: AppConfig) { self.config = config }

    // MARK: Starting

    func startToday() {
        session = .today
        sessionTitle = nil
        items = todayItems
        index = todayIndex
        if startedAt == nil { startedAt = Date() }
        guard current != nil else {
            stage = .finished
            return
        }
        beginPhrase()
    }

    /// Every phrase of one everyday scene, in order.
    func startScene(_ unit: LessonUnit, store: LearningStore) {
        guard !unit.phrases.isEmpty else { return }
        session = .scene(unit.id)
        sessionTitle = unit.title
        items = unit.phrases.map { Item(phrase: $0, isReview: store.stat($0.id).attempts > 0) }
        index = 0
        if startedAt == nil { startedAt = Date() }
        print("[XA] Learn: scene \(unit.id) \(unit.title), \(items.count) phrases")
        beginPhrase()
    }

    /// The next new phrases in curriculum order; if she has tried them all, a mix of learned ones.
    func startMore(store: LearningStore, config: AppConfig) {
        let all = store.allPhrases(for: config)
        var pick = all.filter { store.data.stats[$0.id] == nil }.prefix(max(4, config.newPhrasesPerDay))
            .map { Item(phrase: $0, isReview: false) }
        if pick.isEmpty {
            pick = all.filter { store.stat($0.id).attempts > 0 }.shuffled().prefix(6)
                .map { Item(phrase: $0, isReview: true) }
        }
        guard !pick.isEmpty else { return }
        session = .more
        sessionTitle = "再学几句"
        items = pick
        index = 0
        if startedAt == nil { startedAt = Date() }
        beginPhrase()
    }

    /// Back to the 学英语 start screen. Today's lesson keeps its place.
    func showOverview() {
        stopLoop()
        session = .today
        sessionTitle = nil
        items = todayItems
        index = todayIndex
        paused = false
        stage = .overview
    }

    private func beginPhrase() {
        tries = 0
        missed = []
        heard = ""
        stage = .ready
        practise(.intro)
    }

    // MARK: Controls

    /// 听一遍 / 慢慢听. While practising, she hears it and then 小A listens again.
    func playModel(slow: Bool = false) {
        guard current != nil else { return }
        if case .passed = stage {
            stopLoop()
            speak(.phrase(slow: slow))
            return
        }
        practise(.phrase(slow: slow))
    }

    /// 开始跟读: start listening again after it stopped.
    func resume() {
        listenError = nil
        practise(.phrase(slow: false))
    }

    func pause() {
        stopLoop()
        paused = true
    }

    func unpause() {
        paused = false
        if case .passed = stage { return }
        practise(.phrase(slow: false))
    }

    /// Stops speaking and listening (leaving the screen, pausing, skipping).
    func stopLoop() {
        loop?.cancel()
        loop = nil
        listener.cancel()
        speaker.stop()
        AudioCoordinator.lessonActive = false
        phase = .idle
    }

    /// 跳过这句: move on now. A phrase she tried comes back in review; one she never tried stays new.
    func skip(store: LearningStore) {
        guard let item = current else { return }
        stopLoop()
        if tries > 0 { store.finishPhrase(item.phrase.id, passed: false, triesToday: tries) }
        print("[XA] Learn: skipped \"\(item.phrase.en)\" after \(tries) tries")
        next(store: store)
    }

    func next(store: LearningStore) {
        stopLoop()
        if index + 1 < items.count {
            index += 1
            if session == .today { todayIndex = index }
            beginPhrase()
        } else {
            if session == .today {
                todayIndex = items.count
                store.markDayDone()
                speaker.speakChinese("今天的课学完啦！你真棒！")
            } else {
                speaker.speakChinese("这一组练完啦！你真棒！")
            }
            stage = .finished
        }
    }

    // MARK: - The practice loop

    private enum Say {
        /// 请跟我说 + the phrase.
        case intro
        case phrase(slow: Bool)
        /// The tip, then the phrase (word by word first, after the second try).
        case tip(String, slow: Bool)
        /// 我在听 + the phrase.
        case nudge
    }

    private func practise(_ first: Say) {
        stopLoop()
        guard let itemID = current?.id else { return }
        AudioCoordinator.lessonActive = true
        listenError = nil
        loop = Task { [weak self] in
            await self?.run(first, itemID: itemID)
        }
    }

    private func run(_ first: Say, itemID: String) async {
        var say = first
        var quietRounds = 0
        while !Task.isCancelled && current?.id == itemID && !paused {
            // 1. Say it, and wait until the phone is completely quiet.
            phase = .speaking
            speak(say)
            await speaker.waitUntilDone()
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            // 2. Listen until she has said something and paused.
            phase = .listening
            let result: String?
            do {
                result = try await listenOnce()
            } catch {
                listenError = error.localizedDescription
                phase = .idle
                return
            }
            guard var text = result, !Task.isCancelled, current?.id == itemID else { return }

            // Apple's recognizer heard nothing although she spoke: let OpenAI check the recording.
            if text.isEmpty, listener.heardSound, let recording = listener.lastRecording,
               let key = APIKeys.get(.openAI) {
                phase = .checking
                do {
                    text = try await OpenAITranscribe.transcribe(recording, apiKey: key, language: "en")
                    print("[XA] Learn: Apple heard nothing; OpenAI heard \"\(text)\"")
                } catch {
                    print("[XA] Learn: OpenAI check failed: \(error.localizedDescription)")
                }
                guard !Task.isCancelled, current?.id == itemID else { return }
            }
            if Demo.isOn && text.isEmpty, let phrase = current?.phrase {
                text = Demo.heard(for: phrase.en, attempt: tries + 1)
            }

            if text.isEmpty {
                quietRounds += 1
                print("[XA] Learn: nothing heard (\(quietRounds))")
                if quietRounds >= 2 {
                    // She may have stepped away: stop and wait for 开始跟读.
                    phase = .idle
                    return
                }
                say = .nudge
                continue
            }
            quietRounds = 0

            // 3. Check it.
            phase = .checking
            guard let nextSay = await check(text, itemID: itemID) else {
                phase = .idle
                return
            }
            say = nextSay
        }
    }

    /// Scores one try. Nil when she got it (the loop ends); otherwise what to say next.
    private func check(_ text: String, itemID: String) async -> Say? {
        guard let item = current, let store else { return nil }
        tries += 1
        heard = text
        let result = PronunciationCheck.score(target: item.phrase.en, heard: text)
        missed = Set(result.missed)
        let strict = config?.strictPronunciation ?? false
        let passed = Self.passes(score: result.score, missedCount: result.missed.count, strict: strict)
        store.recordAttempt(item.phrase.id, passed: passed)
        print(String(format: "[XA] Learn: \"%@\" try %ld: heard \"%@\" — %.0f%%%@", item.phrase.en, tries, text,
                     result.score * 100, passed ? " PASS" : " (missed: \(result.missed.joined(separator: ", ")))"))

        if passed {
            let stars = Self.stars(forTries: tries)
            starsToday += stars
            stage = .passed(stars: stars)
            store.finishPhrase(item.phrase.id, passed: true, triesToday: tries)
            Haptics.success()
            let praise = ["太棒了！", "说得真好！", "很清楚！", "好极了！"].randomElement()!
            speaker.speakChinese(praise + "准备好了就点“下一句”。")
            return nil
        }

        stage = .checking
        let tip = await (tipProvider ?? Self.tip)(item.phrase, text, result.missed, tries)
        guard current?.id == itemID else { return nil }
        stage = .retry(tip: tip, close: result.score >= 0.5)
        return .tip(tip, slow: tries >= 2)
    }

    private func speak(_ say: Say) {
        guard let phrase = current?.phrase else { return }
        typealias Part = (text: String, language: String, rate: Float)
        func chinese(_ text: String) -> Part { (text, "zh-CN", Speaker.normalRate) }
        let rate = LearnSpeed.current.rate
        let wordRate = max(0.26, rate - 0.06)
        let english: [Part] = [(phrase.en, "en-US", rate)]
        let words: [Part] = speaker.wordByWord(phrase.en, rate: wordRate)
        var parts: [Part] = []
        switch say {
        case .intro:
            parts = [chinese("请跟我说：")] + english
        case .phrase(let slow):
            parts = slow ? words + english : english
        case .tip(let tip, let slow):
            parts = [chinese(tip), chinese("再听一遍：")] + (slow ? words : []) + english
        case .nudge:
            parts = [chinese("我在听呢，你跟我说：")] + english
        }
        speaker.speakSequence(parts)
    }

    private func listenOnce() async throws -> String? {
        if let listenOverride { return try await listenOverride() }
        return try await listener.listenOnce(locale: "en-US")
    }

    /// Normal mode passes when the recognizer understood at least 75% of the words; strict needs all.
    static func passes(score: Double, missedCount: Int, strict: Bool) -> Bool {
        strict ? missedCount == 0 : score >= 0.75
    }

    /// 3 stars first time, 2 for the second or third try, 1 after that.
    static func stars(forTries tries: Int) -> Int {
        tries <= 1 ? 3 : (tries <= 3 ? 2 : 1)
    }

    // MARK: - Tips

    private static func tip(for phrase: Phrase, heard: String, missed: [String], attempt: Int) async -> String {
        let fallback = missed.first.map { "注意“\(PronunciationCheck.asWritten($0, in: phrase.en))”这个词。慢慢说，每个词都说清楚。" }
            ?? "很接近了！再说一次。"
        guard let client = try? ClaudeClient() else { return fallback }
        let system = "你是一位耐心、温暖的英语发音老师。学生是一位中国妈妈，英语零基础。"
        let prompt = """
        目标句子：\(phrase.en)
        语音识别听到她说的是："\(heard)"
        没被听出来的词：\(missed.isEmpty ? "无" : missed.joined(separator: ", "))
        这是她第\(attempt)次尝试。

        请用简体中文给她一个最具体、最简单的发音建议：只讲一个要点（比如嘴巴、舌头怎么做，或者哪个音要重一点、长一点），不超过30个字，语气鼓励。只输出建议本身，不要引号。
        """
        do {
            let text = try await withTimeout(seconds: 4) {
                try await client.complete(model: ClaudeClient.Model.fast, system: system,
                                          messages: [["role": "user", "content": prompt]], maxTokens: 120)
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? fallback : trimmed
        } catch {
            return fallback
        }
    }

    private static func withTimeout<T>(seconds: Double, _ operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            guard let first = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return first
        }
    }
}
