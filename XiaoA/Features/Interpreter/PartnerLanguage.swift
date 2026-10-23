import Foundation

/// The language of the person she is talking to. She always speaks German.
/// Each case carries the words shown and spoken to that person.
enum PartnerLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh"

    var id: String { rawValue }

    /// The phone's own voice for this language (ready-made phrases, and if the OpenAI voice fails).
    var voice: String {
        switch self {
        case .english: return "en-US"
        case .chinese: return "zh-CN"
        }
    }

    /// The language as OpenAI's voice says it.
    var spoken: SpokenLanguage {
        switch self {
        case .english: return .english
        case .chinese: return .mandarin
        }
    }

    /// For her: Englisch / Chinesisch.
    var nameDE: String {
        switch self {
        case .english: return "Englisch"
        case .chinese: return "Chinesisch"
        }
    }

    /// For Claude and the transcriber.
    var promptName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "Mandarin Chinese (simplified characters)"
        }
    }

    // MARK: The other person's half of the screen

    var badge: String {
        switch self {
        case .english: return "Live interpreter"
        case .chinese: return "实时翻译"
        }
    }

    var invitation: String {
        switch self {
        case .english: return "Speak English. I'll translate."
        case .chinese: return "请说中文，我来翻译。"
        }
    }

    /// Label over what she said, translated.
    var sheSaid: String {
        switch self {
        case .english: return "SHE SAID"
        case .chinese: return "她说"
        }
    }

    /// Label over what the other person said, as heard.
    var youSaid: String {
        switch self {
        case .english: return "YOU SAID"
        case .chinese: return "您说"
        }
    }

    /// Button for the other person to hear her last sentence again.
    var playAgain: String {
        switch self {
        case .english: return "Play again"
        case .chinese: return "再听一遍"
        }
    }

    // MARK: Her ready-made phrases

    var slowDown: String {
        switch self {
        case .english: return "Could you please speak a little more slowly?"
        case .chinese: return "请您说慢一点，好吗？"
        }
    }

    /// Button label: Ich spreche kein Englisch / Ich spreche kein Chinesisch.
    var cantSpeakLabel: String { "Ich spreche kein \(nameDE)" }

    var cantSpeakPhrase: String {
        switch self {
        case .english:
            return "Hi! I don't speak English. This phone will translate for us. Please just talk normally."
        case .chinese:
            return "您好！我不会说中文。这个手机会帮我们翻译，请您正常说话就好。"
        }
    }

    /// The same, in German, for her side of the conversation.
    var cantSpeakGerman: String { "Ich spreche kein \(nameDE). Dieses Handy übersetzt für uns." }
}
