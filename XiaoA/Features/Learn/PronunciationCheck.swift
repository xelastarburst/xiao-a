import Foundation

/// Scores an attempt by whether on-device English speech recognition understood each word.
/// That matches the pass bar in the PRD: "clearly understandable to a native speaker".
enum PronunciationCheck {
    struct Result {
        var score: Double
        var missed: [String]
    }

    static func score(target: String, heard: String) -> Result {
        let wantRaw = normalize(target, canonical: false)
        let want = wantRaw.map { homophones[$0] ?? $0 }
        let got = normalize(heard)
        guard !want.isEmpty else { return Result(score: 1, missed: []) }
        let gotSet = Set(got)
        let joined = got.joined()
        var missed: [String] = []
        for (i, word) in want.enumerated() {
            if gotSet.contains(word) { continue }
            if word.count >= 4 && joined.contains(word) { continue }          // "rest room" vs "restroom"
            if word.count >= 5 && got.contains(where: { distance($0, word) <= 1 }) { continue }
            missed.append(wantRaw[i])                                         // report the word as written
        }
        return Result(score: Double(want.count - missed.count) / Double(want.count), missed: missed)
    }

    /// The word as it appears in the phrase ("Hello" rather than "hello"), for tips.
    static func asWritten(_ token: String, in phrase: String) -> String {
        for word in phrase.split(separator: " ") {
            if normalize(String(word), canonical: false).contains(token) {
                return String(word).trimmingCharacters(in: .punctuationCharacters)
            }
        }
        return token
    }

    /// Lowercased word tokens with contractions expanded and small numbers spelled out.
    static func normalize(_ text: String, canonical: Bool = true) -> [String] {
        var s = text.lowercased().replacingOccurrences(of: "’", with: "'")
        s = s.replacingOccurrences(of: #"\$(\d+)"#, with: "$1 dollars", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d+):00"#, with: "$1 o'clock", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d+)\s*¢"#, with: "$1 cents", options: .regularExpression)
        let allowed = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "'"))
        let raw = s.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        var words: [String] = []
        for token in raw {
            var t = token.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            if let expanded = contractions[t] {
                words += expanded
                continue
            }
            if t.hasSuffix("'s") { t = String(t.dropLast(2)) }      // "Alex's" → "alex"
            if let spelled = numbers[t] {
                words.append(spelled)
            } else if !t.isEmpty {
                words.append(t)
            }
        }
        // Words that sound the same count as the same word ("two" / "too" / "to").
        return canonical ? words.map { homophones[$0] ?? $0 } : words
    }

    private static let contractions: [String: [String]] = [
        "i'm": ["i", "am"], "don't": ["do", "not"], "you're": ["you", "are"], "that's": ["that", "is"],
        "what's": ["what", "is"], "it's": ["it", "is"], "can't": ["can", "not"], "i'll": ["i", "will"],
        "let's": ["let", "us"], "isn't": ["is", "not"], "doesn't": ["does", "not"],
        "cannot": ["can", "not"], "i've": ["i", "have"], "we're": ["we", "are"]
    ]

    private static let numbers: [String: String] = [
        "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five",
        "6": "six", "7": "seven", "8": "eight", "9": "nine", "10": "ten",
        "11": "eleven", "12": "twelve", "13": "thirteen", "14": "fourteen", "15": "fifteen",
        "16": "sixteen", "17": "seventeen", "18": "eighteen", "19": "nineteen", "20": "twenty",
        "30": "thirty", "40": "forty", "50": "fifty", "100": "hundred"
    ]

    private static let homophones: [String: String] = [
        "to": "two", "too": "two",
        "four": "for",
        "won": "one",
        "write": "right",
        "hear": "here",
        "know": "no",
        "buy": "by", "bye": "by",
        "sea": "see",
        "ate": "eight",
        "their": "there", "they're": "there",
        "meat": "meet",
        "weak": "week",
        "weight": "wait",
        "male": "mail",
        "sense": "cents", "cent": "cents"
    ]

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var row = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = row
        }
        return previous[b.count]
    }
}
