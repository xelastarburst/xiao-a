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

    /// Simulator sound is off by default (the Mac may be in a sleeping house). Settings can turn it on.
    static var soundOn: Bool {
        get { UserDefaults.standard.bool(forKey: "demoSound") }
        set { UserDefaults.standard.set(newValue, forKey: "demoSound") }
    }

    // MARK: Lesen — a pharmacy sign "seen" by the camera

    struct SignLine: Identifiable {
        let id: Int
        let en: String
        let de: String
        /// Where the English sits in the photo, as fractions of the photo's width and height.
        let rect: CGRect
    }

    static let signImage = UIImage(named: "DemoSign")

    static let signLines: [SignLine] = [
        SignLine(id: 0, en: "PHARMACY", de: "Apotheke",
                 rect: CGRect(x: 0.2496, y: 0.2318, width: 0.6556, height: 0.0462)),
        SignLine(id: 1, en: "Prescription Pick-Up", de: "Rezeptabholung",
                 rect: CGRect(x: 0.1128, y: 0.3325, width: 0.7453, height: 0.0434)),
        SignLine(id: 2, en: "Please wait here", de: "Bitte hier warten",
                 rect: CGRect(x: 0.1128, y: 0.3914, width: 0.5009, height: 0.0324)),
        SignLine(id: 3, en: "Open 9 AM – 9 PM", de: "Geöffnet 9–21 Uhr",
                 rect: CGRect(x: 0.1128, y: 0.4747, width: 0.5915, height: 0.0395)),
        SignLine(id: 4, en: "Closed for lunch 1:30 – 2:00 PM", de: "Mittagspause 13:30–14:00 Uhr",
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

    // MARK: Fragen — answers written the way the real prompt asks Claude to answer

    /// What she "says" when she holds the talk button in the simulator.
    static let spokenQuestion = "Was steht auf diesem Schild?"

    static func askAnswer(question: String, aboutSign: Bool, hasPhoto: Bool, contactName: String) -> String {
        let contact = contactName.isEmpty ? "Ihre Familie" : contactName
        guard aboutSign else {
            return hasPhoto
                ? "Das ist eine Beispiel-Antwort im Simulator, das Foto wurde nicht angesehen.\nAuf dem iPhone schaut Helferlein Ihr Foto an, sagt Ihnen auf Deutsch, was darauf steht, und beantwortet Ihre Frage."
                : "Das ist eine Beispiel-Antwort im Simulator.\nAuf dem iPhone beantwortet Helferlein Ihre Frage in einfachem Deutsch."
        }
        if question.contains("benutze") {
            return """
            Hier holen Sie Medikamente ab, die Ihr Arzt verschrieben hat.
            · Wenn Sie dran sind, nennen Sie Ihren Namen und Ihr Geburtsdatum
            · Wenn Sie kein Englisch sprechen: öffnen Sie den „Dolmetscher“
            · Prüfen Sie den Namen auf der Tüte
            · Wie Sie es einnehmen, fragen Sie zuerst \(contact) oder in der Apotheke
            """
        }
        if question.contains("achten") {
            return """
            · Mittagspause 13:30 bis 14:00 Uhr: dann keine Abholung
            · Um 21 Uhr wird geschlossen, gehen Sie lieber früher
            · Prüfen Sie bei der Abholung, ob Ihr Name auf der Tüte steht
            · Vor der Einnahme zuerst \(contact) oder die Apotheke fragen, nicht raten
            """
        }
        return """
        Das ist ein Schild in einer Apotheke.
        · PHARMACY: Apotheke
        · Prescription Pick-Up: hier holt man Rezept-Medikamente ab
        · Please wait here: bitte hier anstellen und warten
        · Geöffnet von 9 bis 21 Uhr
        · Mittagspause 13:30 bis 14:00 Uhr, dann keine Abholung
        """
    }

    /// Small pieces, so the demo answer streams in like a real one.
    static func chunks(_ text: String) -> [String] {
        var out: [String] = []
        var piece = ""
        for ch in text {
            piece.append(ch)
            if piece.count >= 4 || ch == "\n" {
                out.append(piece)
                piece = ""
            }
        }
        if !piece.isEmpty { out.append(piece) }
        return out
    }

    // MARK: Dolmetscher — short scripted conversations

    struct Exchange {
        let fromHer: Bool
        let original: String
        let translated: String
        let pause: Double
    }

    /// With an English speaker, at the bus stop.
    static let conversation: [Exchange] = [
        Exchange(fromHer: true, original: "Entschuldigung, wo ist die nächste Bushaltestelle?",
                 translated: "Excuse me, where is the nearest bus stop?", pause: 1.2),
        Exchange(fromHer: false, original: "It's just around the corner, on the left side.",
                 translated: "Die Haltestelle ist gleich um die Ecke, auf der linken Seite.", pause: 2.0),
        Exchange(fromHer: true, original: "Fährt der Bus zum Supermarkt?",
                 translated: "Does the bus go to the supermarket?", pause: 2.0),
        Exchange(fromHer: false, original: "Yes, the number 22. It comes every fifteen minutes.",
                 translated: "Ja, die Nummer 22. Sie kommt alle fünfzehn Minuten.", pause: 2.0),
        Exchange(fromHer: true, original: "Vielen Dank!",
                 translated: "Thank you so much!", pause: 1.6)
    ]

    /// With a Mandarin speaker: meeting a Chinese grandmother in the park.
    static let chineseConversation: [Exchange] = [
        Exchange(fromHer: true, original: "Schön, Sie kennenzulernen! Wie lange sind Sie schon in Amerika?",
                 translated: "很高兴认识您！您来美国多久了？", pause: 1.2),
        Exchange(fromHer: false, original: "两个月了。我来看我儿子。",
                 translated: "Seit zwei Monaten. Ich besuche meinen Sohn.", pause: 2.0),
        Exchange(fromHer: true, original: "Wie schön! Möchten Sie morgen mit mir spazieren gehen?",
                 translated: "太好了！您明天想和我一起去散步吗？", pause: 2.0),
        Exchange(fromHer: false, original: "好啊！几点？",
                 translated: "Gern! Um wie viel Uhr?", pause: 2.0),
        Exchange(fromHer: true, original: "Um zehn Uhr, hier im Park. Bis morgen!",
                 translated: "十点，就在这个公园。明天见！", pause: 1.6)
    ]

    static func conversation(with partner: PartnerLanguage) -> [Exchange] {
        partner == .chinese ? chineseConversation : conversation
    }

    // MARK: Notfallausweis — sample insurance card photos

    static func cardImage(_ side: CardSide) -> UIImage? {
        UIImage(named: side == .front ? "DemoCardFront" : "DemoCardBack")
    }
}

/// A small tag on anything the simulator demo made up.
struct DemoTag: View {
    var body: some View {
        Text("Beispiel")
            .font(.xa(14, .heavy))
            .foregroundStyle(Palette.warnInk)
            .padding(.horizontal, 8).frame(height: 24)
            .background(Capsule().fill(Palette.butter))
    }
}
