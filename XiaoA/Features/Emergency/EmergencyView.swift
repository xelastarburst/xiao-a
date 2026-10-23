import SwiftUI

struct EmergencyView: View {
    /// Practice drill: every button explains what would happen instead of calling or texting.
    var practice: Bool

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var store: ConfigStore
    @State private var practiceNote: String?
    @State private var locating = false
    @State private var locationSent = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if practice {
                    Text("Übung: Es wird nicht wirklich angerufen oder geschrieben")
                        .font(.xa(19, .heavy))
                        .foregroundStyle(Palette.warnInk)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.butter))
                }

                MascotSays(text: "Keine Sorge, ich bin da.", mood: .calm, mascotSize: 68)

                EmergencyRow(title: "911 anrufen", subtitle: "Polizei · Krankenwagen · Feuerwehr", symbol: "phone.fill",
                             style: .red) {
                    app.go(.call911(practice: practice))
                }

                EmergencyRow(title: "\(store.config.contactLabel) anrufen", subtitle: "Sofort verbunden", symbol: "phone.fill",
                             style: .teal) {
                    practiceNote = EmergencyActions.callContact(practice: practice, config: store.config)
                }
                .disabled(store.config.contactPhone.isEmpty)

                EmergencyRow(title: "SMS an \(store.config.contactLabel)", subtitle: "Mit Ihrem Standort", symbol: "message.fill",
                             style: .outlineTeal) {
                    textContact(help: true)
                }
                .disabled(store.config.contactPhone.isEmpty)

                EmergencyRow(title: "Mein Notfallausweis", subtitle: "Versicherung · Medikamente · Allergien", symbol: "cross.case.fill",
                             style: .outlineRed) {
                    app.go(.medical)
                }

                Button { textContact(help: false) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: locating ? "location.circle" : "mappin.and.ellipse")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Palette.tealInk)
                            .symbolEffect(.pulse, isActive: locating)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Standort an \(store.config.contactLabel)").font(.xa(19, .heavy))
                            Text(locationSent ? "Ihr Standort wurde geschickt" : "Hier tippen: jetzigen Standort senden")
                                .font(.xa(18, .bold)).foregroundStyle(Palette.tealInk)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.mint))
                }
                .buttonStyle(Squish())
                .disabled(store.config.contactPhone.isEmpty)

                Button { app.go(.addressCard(nil)) } label: {
                    Label("Meine Adresse zeigen", systemImage: "house.fill")
                        .font(.xa(20, .heavy))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(Capsule().strokeBorder(Palette.redLine, lineWidth: 3).background(Capsule().fill(.white)))
                }
                .buttonStyle(Squish())

                if !practice {
                    Button("Einmal üben (es wird nicht wirklich angerufen)") { app.go(.emergency(practice: true)) }
                        .font(.xa(18, .bold))
                        .foregroundStyle(Palette.ink2)
                        .underline()
                        .frame(minHeight: 48)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            TopBar(title: practice ? "Notfall · Übung" : "Notfall", showEmergency: false)
                .padding(.bottom, 8)
                .background(Palette.redWash)
        }
        .background(ScreenBackground(color: Palette.redWash))
        .alert("Übung", isPresented: Binding(get: { practiceNote != nil }, set: { if !$0 { practiceNote = nil } })) {
            Button("Verstanden") { practiceNote = nil }
        } message: {
            Text(practiceNote ?? "")
        }
    }

    private func textContact(help: Bool) {
        if practice {
            practiceNote = help ? "Hier öffnet sich eine SMS mit „Ich brauche Hilfe!“ und Ihrem Standort. Sie tippen nur noch auf Senden."
                                : "Hier wird Ihr jetziger Standort an \(store.config.contactLabel) geschickt."
            return
        }
        locating = true
        Task {
            let location = await LocationService.shared.current()
            var address: String?
            if let location { address = await LocationService.shared.address(for: location) }
            let body = EmergencyActions.message(help: help, contactName: store.config.contactName, address: address,
                                                mapsLink: location.map(LocationService.mapsLink))
            locating = false
            app.text(store.config.contactPhone, body: body) { sent in
                if sent && !help { locationSent = true }
            }
        }
    }
}

private struct EmergencyRow: View {
    enum Style { case red, teal, outlineTeal, outlineRed }
    var title: String
    var subtitle: String
    var symbol: String
    var style: Style
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(iconColor)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(iconBackground))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.xa(30, .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(subtitle).font(.xa(18, .semibold)).opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(textColor)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 100)
            .chunky(fill, depth: depth, radius: 28, border: border)
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(Squish())
    }

    private var fill: Color {
        switch style {
        case .red: return Palette.red
        case .teal: return Palette.teal
        case .outlineTeal, .outlineRed: return .white
        }
    }
    private var depth: Color? {
        switch style {
        case .red: return Palette.redDeep
        case .teal: return Palette.tealDeep
        default: return nil
        }
    }
    private var border: Color? {
        switch style {
        case .outlineTeal: return Palette.teal
        case .outlineRed: return Palette.redLine
        default: return nil
        }
    }
    private var textColor: Color {
        switch style {
        case .red, .teal: return .white
        default: return Palette.ink
        }
    }
    private var iconColor: Color {
        switch style {
        case .red: return Palette.red
        case .teal, .outlineTeal: return Palette.teal
        case .outlineRed: return Palette.red
        }
    }
    private var iconBackground: Color {
        switch style {
        case .red, .teal: return .white
        case .outlineTeal: return Palette.mint
        case .outlineRed: return Palette.redSoft
        }
    }
}

/// What the emergency buttons do, apart from the screen. Practice mode never dials or texts.
@MainActor
enum EmergencyActions {
    /// Calls her contact, or in practice mode returns the note explaining what would happen.
    static func callContact(practice: Bool, config: AppConfig) -> String? {
        if practice { return "Hier würde Helferlein \(config.contactLabel) direkt anrufen." }
        Phone.call(config.contactPhone)
        return nil
    }

    /// Dials 911, or in practice mode returns true (show the practice note) without dialling.
    static func call911(practice: Bool) -> Bool {
        if practice { return true }
        Phone.call("911")
        return false
    }

    /// The text to her contact: a call for help or "I'm here", the address and a map link when
    /// known, otherwise a request to call her. Family writes "du", so the text does too.
    static func message(help: Bool, contactName: String, address: String?, mapsLink: String?) -> String {
        let name = contactName.trimmingCharacters(in: .whitespaces)
        let helpLine = name.isEmpty ? "[Helferlein] Ich brauche Hilfe!" : "[Helferlein] \(name), ich brauche Hilfe!"
        var lines: [String] = [help ? helpLine : "[Helferlein] Ich bin gerade hier:"]
        if let mapsLink {
            if let address { lines.append("Adresse: \(address)") }
            lines.append(mapsLink)
        } else {
            lines.append("(Standort nicht gefunden – bitte ruf mich an)")
        }
        return lines.joined(separator: "\n")
    }
}
