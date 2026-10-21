import SwiftUI

/// Simulator demo. The simulator has no camera, no live-text scanner, no on-device translation
/// and (overnight) no one talking into the microphone, and there are no API keys on it.
/// When `isOn`, each feature plays a short scripted version of itself so every screen can be
/// tried and reviewed on a Mac. It is never on for a build installed on a real iPhone.
enum Demo {
    #if DEBUG && targetEnvironment(simulator)
    /// On in the simulator, except under unit tests, which exercise the real code paths.
    static let isOn = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    #else
    static let isOn = false
    #endif

    /// Simulator sound is off by default (the Mac may be in a sleeping house). Alex mode can turn it on.
    static var soundOn: Bool {
        get { UserDefaults.standard.bool(forKey: "demoSound") }
        set { UserDefaults.standard.set(newValue, forKey: "demoSound") }
    }

    // MARK: 看一看 — a pharmacy sign "seen" by the camera

    struct SignLine: Identifiable {
        let id: Int
        let en: String
        let zh: String
        /// Where the English sits in the photo, as fractions of the photo's width and height.
        let rect: CGRect
    }

    static let signImage = UIImage(named: "DemoSign")

    static let signLines: [SignLine] = [
        SignLine(id: 0, en: "PHARMACY", zh: "药房",
                 rect: CGRect(x: 0.2496, y: 0.2318, width: 0.6556, height: 0.0462)),
        SignLine(id: 1, en: "Prescription Pick-Up", zh: "处方药取药处",
                 rect: CGRect(x: 0.1128, y: 0.3325, width: 0.7453, height: 0.0434)),
        SignLine(id: 2, en: "Please wait here", zh: "请在这里等候",
                 rect: CGRect(x: 0.1128, y: 0.3914, width: 0.5009, height: 0.0324)),
        SignLine(id: 3, en: "Open 9 AM – 9 PM", zh: "营业时间：早上9点到晚上9点",
                 rect: CGRect(x: 0.1128, y: 0.4747, width: 0.5915, height: 0.0395)),
        SignLine(id: 4, en: "Closed for lunch 1:30 – 2:00 PM", zh: "午休：下午1:30到2:00不开放",
                 rect: CGRect(x: 0.1128, y: 0.5284, width: 0.7829, height: 0.0288))
    ]

    /// Maps a rect in photo fractions to a view showing the photo with `.scaledToFill()`.
    static func viewRect(for fraction: CGRect, imageSize: CGSize, in size: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = max(size.width / imageSize.width, size.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        let ox = (size.width - w) / 2, oy = (size.height - h) / 2
        return CGRect(x: ox + fraction.minX * w, y: oy + fraction.minY * h,
                      width: fraction.width * w, height: fraction.height * h)
    }

    // MARK: 问一问 — answers written the way the real prompt asks Claude to answer

    /// What she "says" when she holds the talk button in the simulator.
    static let spokenQuestion = "这个牌子上写的是什么？"

    static func askAnswer(question: String, aboutSign: Bool, hasPhoto: Bool, alexName: String) -> String {
        guard aboutSign else {
            return hasPhoto
                ? "这是模拟器里的示例回答，没有真的看照片。\n在 iPhone 上，小A 会看着你的照片，用中文告诉你上面写了什么，再回答你的问题。"
                : "这是模拟器里的示例回答。\n在 iPhone 上，小A 会用简单的中文回答你的问题。"
        }
        if question.contains("怎么用") {
            return """
            这是药房取药的地方，在这里排队取医生给你开的药。
            · 轮到你时，说出你的名字和生日
            · 不会说英语，可以打开“翻译官”帮你说
            · 拿到药，先看药袋上的名字对不对
            · 药怎么吃，先问\(alexName)或药剂师
            """
        }
        if question.contains("注意") {
            return """
            · 中午1:30到2:00休息，这个时间不能取药
            · 晚上9点关门，早点去
            · 取药时核对药袋上的名字是不是你
            · 吃药前先问\(alexName)或药剂师，不要自己猜
            """
        }
        return """
        这是药房的牌子。
        · PHARMACY：药房
        · Prescription Pick-Up：取处方药的地方
        · Please wait here：请在这里排队等
        · 营业时间：早上9点到晚上9点
        · 中午1:30到2:00休息，不能取药
        """
    }

    /// Small pieces, so the demo answer streams in like a real one.
    static func chunks(_ text: String) -> [String] {
        var out: [String] = []
        var piece = ""
        for ch in text {
            piece.append(ch)
            if piece.count >= 2 || ch == "\n" {
                out.append(piece)
                piece = ""
            }
        }
        if !piece.isEmpty { out.append(piece) }
        return out
    }

    // MARK: 翻译官 — a short conversation at the grocery store

    struct Exchange {
        let fromMom: Bool
        let original: String
        let translated: String
        let pause: Double
    }

    static let conversation: [Exchange] = [
        Exchange(fromMom: false, original: "Hi! Can I help you find something?",
                 translated: "你好！需要我帮你找什么吗？", pause: 1.2),
        Exchange(fromMom: true, original: "我想买牛奶，在哪里？",
                 translated: "I'd like to buy some milk. Where is it?", pause: 2.0),
        Exchange(fromMom: false, original: "It's in aisle five, at the back of the store.",
                 translated: "在5号通道，商店的最里面。", pause: 2.0),
        Exchange(fromMom: true, original: "谢谢你！",
                 translated: "Thank you!", pause: 2.0),
        Exchange(fromMom: false, original: "You're welcome. Have a nice day!",
                 translated: "不客气，祝你今天愉快！", pause: 1.6)
    ]

    /// 翻译官 in German — meeting a German-speaking neighbor.
    static let germanConversation: [Exchange] = [
        Exchange(fromMom: false, original: "Hallo! Schön, Sie wiederzusehen. Wie geht es Ihnen?",
                 translated: "你好！很高兴又见到你。你好吗？", pause: 1.2),
        Exchange(fromMom: true, original: "我很好，谢谢！你呢？",
                 translated: "Mir geht es gut, danke! Und Ihnen?", pause: 2.0),
        Exchange(fromMom: false, original: "Auch gut. Möchten Sie morgen mit uns spazieren gehen?",
                 translated: "我也很好。你明天想和我们一起去散步吗？", pause: 2.0),
        Exchange(fromMom: true, original: "好啊！几点？",
                 translated: "Gern! Um wie viel Uhr?", pause: 2.0),
        Exchange(fromMom: false, original: "Um zehn Uhr, im Park. Bis morgen!",
                 translated: "十点，在公园。明天见！", pause: 1.6)
    ]

    static func conversation(with partner: PartnerLanguage) -> [Exchange] {
        partner == .german ? germanConversation : conversation
    }

    // MARK: 学英语 — what the "microphone" hears

    /// First try misses the hardest words; the second try is right. Shows the whole coaching loop.
    static func heard(for phrase: String, attempt: Int) -> String {
        guard attempt == 1 else { return phrase }
        let words = phrase.split(separator: " ").map(String.init)
        if words.count <= 1 { return "uh" }
        let byLength = words.indices.sorted {
            PronunciationCheck.normalize(words[$0]).joined().count > PronunciationCheck.normalize(words[$1]).joined().count
        }
        let drop = Set(byLength.prefix(words.count >= 4 ? 2 : 1))
        return words.indices.filter { !drop.contains($0) }.map { words[$0] }.joined(separator: " ")
    }

    // MARK: 医疗卡 — sample insurance card photos

    static func cardImage(_ side: CardSide) -> UIImage? {
        UIImage(named: side == .front ? "DemoCardFront" : "DemoCardBack")
    }
}

/// A small tag on anything the simulator demo made up.
struct DemoTag: View {
    var body: some View {
        Text("模拟器示例")
            .font(.xa(14, .heavy))
            .foregroundStyle(Palette.warnInk)
            .padding(.horizontal, 8).frame(height: 24)
            .background(Capsule().fill(Palette.butter))
    }
}
