import SwiftUI
import CoreLocation

/// Fahrt (text-message flow): she picks a place, Helferlein texts her family her location and
/// destination with a pre-filled Uber link. They book the ride and text her the car details in German.
struct RideView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var store: ConfigStore

    @State private var chosen: Place?
    @State private var stage: Stage = .choose
    @State private var problem: String?

    enum Stage { case choose, confirm, locating, waiting }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Fahrt").padding(.bottom, 8)
            switch stage {
            case .choose: chooser
            case .confirm, .locating: confirm
            case .waiting: waiting
            }
        }
        .background(ScreenBackground())
    }

    // MARK: 1. Where to?

    private var chooser: some View {
        ScrollView {
            VStack(spacing: 12) {
                MascotSays(text: "Wohin möchten Sie?", detail: "Tippen Sie auf einen Ort. \(store.config.contactLabel) bekommt dann eine Nachricht.", mascotSize: 68)
                if store.ridePlaces.isEmpty {
                    Text("Noch keine Orte eingerichtet. Bitte lassen Sie \(store.config.contactLabel) in den Einstellungen Orte eintragen (lange auf das Helferlein drücken).")
                        .font(.xa(20, .bold)).foregroundStyle(Palette.ink2).card()
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(store.ridePlaces) { place in
                        Button {
                            chosen = place
                            stage = .confirm
                        } label: {
                            VStack(spacing: 10) {
                                Image(systemName: place.icon)
                                    .font(.system(size: 32, weight: .semibold))
                                    .frame(width: 68, height: 68)
                                    .background(Circle().fill(.white))
                                Text(place.nameDE).font(.xa(26, .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 150)
                            .chunky(Palette.lilac, depth: Palette.lilacDeep, radius: 26)
                        }
                        .buttonStyle(Squish())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: 2. Confirm

    @ViewBuilder private var confirm: some View {
        if let place = chosen {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: place.icon).font(.system(size: 30, weight: .semibold))
                            .frame(width: 64, height: 64).background(Circle().fill(Palette.lilac))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ziel: \(place.nameDE)").font(.xa(30, .heavy)).lineLimit(2).minimumScaleFactor(0.7)
                            Text(place.addressEN).font(.xa(17, .semibold)).foregroundStyle(Palette.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("Ich schicke Ihren Standort und das Ziel an \(store.config.contactLabel). \(store.config.contactLabel) bestellt dann das Auto.")
                        .font(.xa(20, .semibold)).foregroundStyle(Palette.ink)
                }
                .card()

                if let problem { WarningNote(text: problem) }
                Spacer(minLength: 0)

                BigButton(title: stage == .locating ? "Ich suche Ihren Standort …" : "Auto bestellen lassen",
                          systemImage: stage == .locating ? "location.circle" : "paperplane.fill") {
                    request(place)
                }
                .disabled(stage == .locating || store.config.contactPhone.isEmpty)
                SoftButton(title: "Anderer Ort", systemImage: "arrow.uturn.left", height: 64, fontSize: 22) {
                    stage = .choose
                    problem = nil
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    // MARK: 3. Waiting for her family

    private var waiting: some View {
        ScrollView {
            VStack(spacing: 12) {
                MascotSays(text: "\(store.config.contactLabel) weiß Bescheid!",
                           detail: "Wenn das Auto bestellt ist, bekommen Sie eine SMS mit Farbe und Kennzeichen.", mascotSize: 68)

                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle").font(.system(size: 28, weight: .bold))
                    Text("Vor dem Einsteigen das Kennzeichen prüfen! Nur einsteigen, wenn es stimmt.").font(.xa(21, .heavy))
                }
                .foregroundStyle(Palette.warnInk)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22).fill(Palette.butter))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Etwas auf Englisch?").font(.xa(20, .heavy))
                    Text("Halten Sie „Lesen“ darauf, dann übersetze ich es.").font(.xa(19, .semibold)).foregroundStyle(Palette.ink2)
                    SoftButton(title: "Lesen", systemImage: "camera.viewfinder", fill: Palette.peach, border: nil) {
                        app.go(.look)
                    }
                }
                .card()

                if let chosen {
                    BigButton(title: "Adresse für den Fahrer", systemImage: "doc.text.magnifyingglass",
                              fill: Palette.sky, depth: Palette.skyDeep, foreground: Palette.ink, height: 68, fontSize: 24) {
                        app.go(.addressCard(chosen))
                    }
                }
                BigButton(title: "\(store.config.contactLabel) anrufen", systemImage: "phone.fill",
                          fill: Palette.teal, depth: Palette.tealDeep, height: 68, fontSize: 24) {
                    Phone.call(store.config.contactPhone)
                }
                SoftButton(title: "Startseite", systemImage: "house.fill", height: 60) { app.home() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: Actions

    private func request(_ place: Place) {
        stage = .locating
        problem = nil
        Task {
            let location = await LocationService.shared.current()
            var address: String?
            if let location { address = await LocationService.shared.address(for: location) }
            let body = Self.requestMessage(place: place, location: location, address: address, config: store.config)
            stage = .confirm
            if location == nil {
                problem = "Ich finde Ihren Standort nicht. In der SMS bitte ich \(store.config.contactLabel), Sie anzurufen."
            }
            app.text(store.config.contactPhone, body: body) { sent in
                if sent { stage = .waiting }
            }
        }
    }

    static func requestMessage(place: Place, location: CLLocation?, address: String?, config: AppConfig) -> String {
        let who = config.herName.isEmpty ? "" : " für \(config.herName)"
        var lines = ["[Helferlein] Fahrtwunsch\(who): \(place.nameDE)",
                     "Ziel: \(place.addressEN)"]
        if let location {
            lines.append("Abholung: \(address ?? "siehe Karte")")
            lines.append("Karte: \(LocationService.mapsLink(location))")
        } else {
            lines.append("Abholung: Standort unbekannt – bitte anrufen.")
        }
        if let uber = uberLink(place: place, location: location) {
            lines.append("In Uber öffnen: \(uber)")
        }
        let rider = config.herNameEN.isEmpty ? "sie" : config.herNameEN
        lines.append("Als Fahrt für \(rider) buchen, dann die Autodaten in Helferlein › Settings › Send car details schicken.")
        return lines.joined(separator: "\n")
    }

    /// Uber universal link with pickup and drop-off filled in. Brackets are percent-encoded
    /// so Messages keeps the whole link tappable.
    static func uberLink(place: Place, location: CLLocation?) -> String? {
        func enc(_ s: String) -> String {
            s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        }
        var parts = ["action=setPickup"]
        if let c = location?.coordinate {
            parts.append("pickup%5Blatitude%5D=\(c.latitude)")
            parts.append("pickup%5Blongitude%5D=\(c.longitude)")
            parts.append("pickup%5Bnickname%5D=Pickup")
        } else {
            parts.append("pickup=my_location")
        }
        parts.append("dropoff%5Bformatted_address%5D=\(enc(place.addressEN))")
        parts.append("dropoff%5Bnickname%5D=\(enc(place.nameDE))")
        return "https://m.uber.com/ul/?" + parts.joined(separator: "&")
    }
}
