import Foundation

struct PhraseStat: Codable {
    var attempts = 0
    var passes = 0
    var mastered = false
    var needsReview = false
    var lastPracticed: Date?
}

struct LearningData: Codable {
    var stats: [String: PhraseStat] = [:]
    /// "yyyy-MM-dd" for each day a lesson was finished.
    var daysDone: [String] = []
}

/// Lesson progress, saved on the phone. Alex sees the summary in Alex mode.
@MainActor
final class LearningStore: ObservableObject {
    @Published private(set) var data = LearningData()

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XiaoA", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("learning.json")
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        if let raw = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(LearningData.self, from: raw) {
            data = decoded
        }
    }

    // MARK: Reading

    func stat(_ id: String) -> PhraseStat { data.stats[id] ?? PhraseStat() }

    var doneToday: Bool { data.daysDone.contains(Self.dayFormatter.string(from: Date())) }

    /// Consecutive days with a finished lesson, counting today or yesterday as the latest.
    var streak: Int {
        let done = Set(data.daysDone)
        let cal = Calendar.current
        var day = Date()
        if !done.contains(Self.dayFormatter.string(from: day)) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day),
                  done.contains(Self.dayFormatter.string(from: yesterday)) else { return 0 }
            day = yesterday
        }
        var count = 0
        while done.contains(Self.dayFormatter.string(from: day)) {
            count += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    var masteredCount: Int { data.stats.values.filter(\.mastered).count }

    func allPhrases(for config: AppConfig) -> [Phrase] { Curriculum.allPhrases(for: config) }

    func strugglingPhrases(for config: AppConfig) -> [Phrase] {
        allPhrases(for: config).filter { stat($0.id).needsReview }
    }

    /// Today's plan: review first (weakest first), then new phrases in curriculum order.
    func todaysPlan(for config: AppConfig) -> (review: [Phrase], new: [Phrase]) {
        let all = allPhrases(for: config)
        let learned = all.filter { data.stats[$0.id]?.attempts ?? 0 > 0 }
        let weak = learned.filter { stat($0.id).needsReview }
        let solid = learned.filter { !stat($0.id).needsReview }
            .sorted { (stat($0.id).lastPracticed ?? .distantPast) < (stat($1.id).lastPracticed ?? .distantPast) }
        let review = Array((weak + solid).prefix(4))
        let fresh = Array(all.filter { data.stats[$0.id] == nil }.prefix(config.newPhrasesPerDay))
        return (review, fresh)
    }

    // MARK: Writing

    func recordAttempt(_ id: String, passed: Bool) {
        var s = stat(id)
        s.attempts += 1
        s.lastPracticed = Date()
        if passed { s.passes += 1 }
        data.stats[id] = s
        save()
    }

    /// Called when the phrase is finished for today.
    func finishPhrase(_ id: String, passed: Bool, triesToday: Int) {
        var s = stat(id)
        if passed {
            s.mastered = true
            s.needsReview = triesToday >= 3
        } else {
            s.needsReview = true
        }
        data.stats[id] = s
        save()
    }

    func markDayDone() {
        let today = Self.dayFormatter.string(from: Date())
        if !data.daysDone.contains(today) {
            data.daysDone.append(today)
            save()
        }
    }

    private func save() {
        guard let raw = try? JSONEncoder().encode(data) else { return }
        try? raw.write(to: Self.fileURL, options: [.atomic])
    }
}
