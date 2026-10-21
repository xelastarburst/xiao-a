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
                    Text("练习模式：不会真的打电话或发短信")
                        .font(.xa(19, .heavy))
                        .foregroundStyle(Palette.warnInk)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.butter))
                }

                MascotSays(text: "别着急，我在这里。", mood: .calm, mascotSize: 68)

                EmergencyRow(title: "拨打 911", subtitle: "警察 · 救护车 · 火警", symbol: "phone.fill",
                             style: .red) {
                    app.go(.call911(practice: practice))
                }

                EmergencyRow(title: "打电话给 \(store.config.alexName)", subtitle: "马上接通", symbol: "phone.fill",
                             style: .teal) {
                    practiceNote = EmergencyActions.callAlex(practice: practice, config: store.config)
                }
                .disabled(store.config.alexPhone.isEmpty)

                EmergencyRow(title: "发短信给 \(store.config.alexName)", subtitle: "自动带上你的位置", symbol: "message.fill",
                             style: .outlineTeal) {
                    textAlex(help: true)
                }
                .disabled(store.config.alexPhone.isEmpty)

                EmergencyRow(title: "我的医疗卡", subtitle: "保险卡 · 用药 · 过敏", symbol: "cross.case.fill",
                             style: .outlineRed) {
                    app.go(.medical)
                }

                Button { textAlex(help: false) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: locating ? "location.circle" : "mappin.and.ellipse")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Palette.tealInk)
                            .symbolEffect(.pulse, isActive: locating)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(store.config.alexName) 一直能看到你的位置").font(.xa(19, .heavy))
                            Text(locationSent ? "位置已经发出去了" : "点这里，发送现在的位置")
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
                .disabled(store.config.alexPhone.isEmpty)

                Button { app.go(.addressCard(nil)) } label: {
                    Label("给别人看我家地址", systemImage: "house.fill")
                        .font(.xa(20, .heavy))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(Capsule().strokeBorder(Palette.redLine, lineWidth: 3).background(Capsule().fill(.white)))
                }
                .buttonStyle(Squish())

                if !practice {
                    Button("练习一下（不会真的打出去）") { app.go(.emergency(practice: true)) }
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
            TopBar(title: practice ? "紧急 · 练习" : "紧急", showEmergency: false)
                .padding(.bottom, 8)
                .background(Palette.redWash)
        }
        .background(ScreenBackground(color: Palette.redWash))
        .alert("练习", isPresented: Binding(get: { practiceNote != nil }, set: { if !$0 { practiceNote = nil } })) {
            Button("知道了") { practiceNote = nil }
        } message: {
            Text(practiceNote ?? "")
        }
    }

    private func textAlex(help: Bool) {
        if practice {
            practiceNote = help ? "这里会打开短信，自动写好“我需要帮忙”和你的位置，你只要按发送。"
                                : "这里会把你现在的位置发给 \(store.config.alexName)。"
            return
        }
        locating = true
        Task {
            let location = await LocationService.shared.current()
            var address: String?
            if let location { address = await LocationService.shared.address(for: location) }
            let body = EmergencyActions.message(help: help, alexName: store.config.alexName, address: address,
                                                mapsLink: location.map(LocationService.mapsLink))
            locating = false
            app.text(store.config.alexPhone, body: body) { sent in
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
    /// Calls Alex, or in practice mode returns the note explaining what would happen.
    static func callAlex(practice: Bool, config: AppConfig) -> String? {
        if practice { return "这里会直接打电话给 \(config.alexName)。" }
        Phone.call(config.alexPhone)
        return nil
    }

    /// Dials 911, or in practice mode returns true (show the practice note) without dialling.
    static func call911(practice: Bool) -> Bool {
        if practice { return true }
        Phone.call("911")
        return false
    }

    /// The text to Alex: a call for help or "I'm here", the address and a map link when known,
    /// otherwise a request to call her.
    static func message(help: Bool, alexName: String, address: String?, mapsLink: String?) -> String {
        var lines: [String] = [help ? "【小A】\(alexName)，我需要帮忙！" : "【小A】我现在在这里："]
        if let mapsLink {
            if let address { lines.append("地址：\(address)") }
            lines.append(mapsLink)
        } else {
            lines.append("（找不到位置，请给我打电话）")
        }
        return lines.joined(separator: "\n")
    }
}
