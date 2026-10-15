import Foundation

/// The language of the person Mom is talking to. Mom always speaks Chinese.
/// Each case carries the words shown and spoken to that person.
enum PartnerLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"

    var id: String { rawValue }

    /// Output language for the gpt-realtime-translate session that speaks to the other person.
    var translationCode: String { rawValue }

    /// Voice for the ready-made phrases.
    var voice: String {
        switch self {
        case .english: return "en-US"
        case .german: return "de-DE"
        }
    }

    /// For Mom: 英语 / 德语.
    var nameZH: String {
        switch self {
        case .english: return "英语"
        case .german: return "德语"
        }
    }

    // MARK: The other person's half of the screen

    var badge: String {
        switch self {
        case .english: return "Live interpreter"
        case .german: return "Live-Dolmetscher"
        }
    }

    var invitation: String {
        switch self {
        case .english: return "Speak English. I'll translate."
        case .german: return "Sprechen Sie Deutsch. Ich übersetze."
        }
    }

    /// Label over what Mom said, translated.
    var sheSaid: String {
        switch self {
        case .english: return "SHE SAID"
        case .german: return "SIE SAGT"
        }
    }

    /// Label over what the other person said, as heard.
    var youSaid: String {
        switch self {
        case .english: return "YOU SAID"
        case .german: return "SIE HABEN GESAGT"
        }
    }

    /// Button for the other person to hear Mom's last sentence again.
    var playAgain: String {
        switch self {
        case .english: return "Play again"
        case .german: return "Nochmal anhören"
        }
    }

    // MARK: Mom's ready-made phrases

    var slowDown: String {
        switch self {
        case .english: return "Could you please speak a little more slowly?"
        case .german: return "Könnten Sie bitte etwas langsamer sprechen?"
        }
    }

    /// Button label: 我不会说英语 / 我不会说德语.
    var cantSpeakLabel: String { "我不会说\(nameZH)" }

    var cantSpeakPhrase: String {
        switch self {
        case .english:
            return "Hi! I don't speak English. This phone will translate for us. Please just talk normally."
        case .german:
            return "Hallo! Ich spreche kein Deutsch. Dieses Handy übersetzt für uns. Sprechen Sie einfach ganz normal."
        }
    }

    var cantSpeakChinese: String { "我不会说\(nameZH)，这个手机会帮我们翻译。" }
}
