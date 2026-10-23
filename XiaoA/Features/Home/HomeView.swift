import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var store: ConfigStore
    @State private var showPIN = false

    private var greeting: String {
        let hello: String
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: hello = "Guten Morgen"
        case 11..<18: hello = "Guten Tag"
        default: hello = "Guten Abend"
        }
        let name = store.config.herName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "\(hello)!" : "\(hello), \(name)!"
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 8) {
                Mascot(size: 92)
                    .onLongPressGesture(minimumDuration: 2) {
                        Haptics.success()
                        showPIN = true
                    }
                    .accessibilityHint("Family: long-press for settings")
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(.xa(26, .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(store.isSetUp ? "Was möchten Sie heute machen?" : "Bitte lassen Sie Helferlein zuerst von Ihrer Familie einrichten.")
                        .font(.xa(19, .medium)).foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 26, bottomLeadingRadius: 8,
                                           bottomTrailingRadius: 26, topTrailingRadius: 26, style: .continuous)
                        .fill(.white)
                )
            }
            .padding(.top, 8)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    FeatureTile(title: "Lesen", subtitle: "Englisch auf Deutsch sehen", symbol: "camera.viewfinder",
                                fill: Palette.peach, depth: Palette.peachDeep) { app.go(.look) }
                    FeatureTile(title: "Fragen", subtitle: "Fragen Sie mich alles", symbol: "questionmark.bubble",
                                fill: Palette.sky, depth: Palette.skyDeep) { app.ask(about: nil) }
                }
                .frame(maxHeight: .infinity)
                WideTile(title: "Dolmetscher", subtitle: "Mit Englisch- und Chinesisch-Sprechenden",
                         symbol: "bubble.left.and.bubble.right",
                         fill: Palette.sage, depth: Palette.sageDeep) { app.go(.interpreter) }
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            // A slim bar, not another big tile: rides are occasional, the tiles above are daily.
            RideBar(contact: store.config.contactLabel) { app.go(.ride) }

            Button { app.go(.emergency(practice: false)) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill").font(.system(size: 28, weight: .bold))
                    Text("Notfall").font(.xa(30, .heavy)).tracking(0.5)
                    Text("Sofort Hilfe holen").font(.xa(19, .medium))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .chunky(Palette.red, depth: Palette.redDeep, radius: 40)
            }
            .buttonStyle(Squish())
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 16)
        .background(ScreenBackground())
        .sheet(isPresented: $showPIN) {
            PINGate { app.go(.alex) }
        }
    }
}

private struct FeatureTile: View {
    var title: String
    var subtitle: String
    var symbol: String
    var fill: Color
    var depth: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(.white))
                    Spacer()
                }
                Spacer(minLength: 8)
                Text(title).font(.xa(30, .heavy)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(subtitle).font(.xa(17, .bold)).foregroundStyle(Palette.ink.opacity(0.78))
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .chunky(fill, depth: depth, radius: 28)
        }
        .buttonStyle(Squish())
    }
}

/// The full-width Dolmetscher tile: icon on the left, title and subtitle beside it.
private struct WideTile: View {
    var title: String
    var subtitle: String
    var symbol: String
    var fill: Color
    var depth: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.xa(30, .heavy)).foregroundStyle(Palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(subtitle).font(.xa(17, .bold)).foregroundStyle(Palette.ink.opacity(0.78))
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .chunky(fill, depth: depth, radius: 28)
        }
        .buttonStyle(Squish())
    }
}

private struct RideBar: View {
    var contact: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "car.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(.white))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Fahrt").font(.xa(26, .heavy)).foregroundStyle(Palette.ink)
                    Text("\(contact) bestellt ein Auto").font(.xa(16, .bold)).foregroundStyle(Palette.lilacInk)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 20, weight: .heavy)).foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 72)
            .chunky(Palette.lilac, depth: Palette.lilacDeep, radius: 26)
        }
        .buttonStyle(Squish())
        .accessibilityElement(children: .combine)
    }
}
