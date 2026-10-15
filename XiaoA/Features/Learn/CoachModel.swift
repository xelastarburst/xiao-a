import SwiftUI

/// Runs a lesson: she hears a phrase, says it, sees what 小A heard, gets one specific tip, and
/// tries again. After 4 tries (or whenever she taps 跳过) she moves on and the phrase comes
/// back in review.
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
        case gaveUp
        case finished
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

    static let maxTries = 4

    @Published private(set) var items: [Item] = []
    @Published private(set) var index = 0
    @Published private(set) var stage: Stage = .overview
    @Published private(set) var session: Session = .today
    @Published private(set) var sessionTitle: String?
    @Published private(set) var tries = 0
    @Published private(set) var missed: Set<String> = []
    /// What the phone heard on the last try, shown under the sentence.
    @Published private(set) var heard = ""
    @Published private(set) var starsToday = 0
    @Published var paused = false

    private(set) var startedAt: Date?
    private var preparedDay = ""
    /// Today's lesson is kept aside while she practises a scene, so she can come back to it.
    private(set) var todayItems: [Item] = []
    private(set) var todayIndex = 0

    var current: Item? { items.indices.contains(index) ? items[index] : nil }
    var progress: Double {
        guard !items.isEmpty else { return 0 }
        let done: Int
        switch stage {
        case .passed, .gaveUp, .finished: done = index + 1
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
        Speaker.shared.stop()
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
        playModel()
    }

    func playModel(slow: Bool = false) {
        guard let phrase = current?.phrase else { return }
        Speaker.shared.speakEnglish(phrase.en, slow: slow)
    }

    /// The phone is working out what she said (shown while a slower check runs).
    func showChecking() {
        stage = .checking
    }

    // MARK: Checking

    func evaluate(heard rawHeard: String, store: LearningStore, config: AppConfig) async {
        guard let item = current else { return }
        var clean = rawHeard.trimmingCharacters(in: .whitespacesAndNewlines)
        if Demo.isOn && clean.isEmpty {
            clean = Demo.heard(for: item.phrase.en, attempt: tries + 1)
        }
        tries += 1
        heard = clean

        if clean.isEmpty {
            print("[XA] Learn: \"\(item.phrase.en)\" try \(tries): heard nothing")
            if tries >= Self.maxTries {
                giveUp(item, store: store)
                return
            }
            stage = .retry(tip: "我没听清。按住橙色按钮，看到“正在听”再说，说完再松开。", close: false)
            Speaker.shared.speakChinese("我没听清，按住按钮，大声一点再说一次。")
            return
        }

        let result = PronunciationCheck.score(target: item.phrase.en, heard: clean)
        missed = Set(result.missed)
        let passed = config.strictPronunciation ? result.missed.isEmpty : result.score >= 0.75
        store.recordAttempt(item.phrase.id, passed: passed)
        print(String(format: "[XA] Learn: \"%@\" try %ld: heard \"%@\" — %.0f%%%@", item.phrase.en, tries, clean,
                     result.score * 100, passed ? " PASS" : " (missed: \(result.missed.joined(separator: ", ")))"))

        if passed {
            let stars = tries == 1 ? 3 : (tries == 2 ? 2 : 1)
            starsToday += stars
            stage = .passed(stars: stars)
            store.finishPhrase(item.phrase.id, passed: true, triesToday: tries)
            Haptics.success()
            Speaker.shared.speakChinese(["太棒了！", "说得真好！", "很清楚！", "好极了！"].randomElement()!)
            return
        }

        if tries >= Self.maxTries {
            giveUp(item, store: store)
            return
        }

        stage = .checking
        let tip = await Self.tip(for: item.phrase, heard: clean, missed: result.missed, attempt: tries)
        guard current?.id == item.id else { return }
        stage = .retry(tip: tip, close: result.score >= 0.5)
        // After the second miss, follow the tip with a slow model reading.
        Speaker.shared.speakSequence([
            (tip, "zh-CN", Speaker.normalRate),
            (item.phrase.en, "en-US", tries >= 2 ? Speaker.slowRate : Speaker.normalRate)
        ])
    }

    private func giveUp(_ item: Item, store: LearningStore) {
        stage = .gaveUp
        store.finishPhrase(item.phrase.id, passed: false, triesToday: tries)
        Speaker.shared.speakChinese("你很努力了！这句以后再练，我们先学下一句。")
    }

    /// 跳过这句: move on now. A phrase she tried comes back in review; one she never tried stays new.
    func skip(store: LearningStore) {
        guard let item = current else { return }
        Speaker.shared.stop()
        if tries > 0 { store.finishPhrase(item.phrase.id, passed: false, triesToday: tries) }
        print("[XA] Learn: skipped \"\(item.phrase.en)\" after \(tries) tries")
        next(store: store)
    }

    func next(store: LearningStore) {
        if index + 1 < items.count {
            index += 1
            if session == .today { todayIndex = index }
            beginPhrase()
        } else {
            if session == .today {
                todayIndex = items.count
                store.markDayDone()
                Speaker.shared.speakChinese("今天的课学完啦！你真棒！")
            } else {
                Speaker.shared.speakChinese("这一组练完啦！你真棒！")
            }
            stage = .finished
        }
    }

    // MARK: - Tips

    private static func tip(for phrase: Phrase, heard: String, missed: [String], attempt: Int) async -> String {
        let fallback = missed.first.map { "注意“\(PronunciationCheck.asWritten($0, in: phrase.en))”这个词。先听一遍，再慢慢说。" }
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
