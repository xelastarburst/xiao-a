import SwiftUI
import CoreLocation

/// 叫车 (v1, text-message flow): Mom picks a place, 小A texts Alex her location and destination
/// with a pre-filled Uber link. Alex books the ride and texts her the car details in Chinese.
struct RideView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var store: ConfigStore

    @State private var chosen: Place?
    @State private var stage: Stage = .choose
    @State private var problem: String?

    enum Stage { case choose, confirm, locating, waiting }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "叫车").padding(.bottom, 8)
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
                MascotSays(text: "想去哪里？", detail: "点一个地方，我告诉 \(store.config.alexName)", mascotSize: 68)
                if store.ridePlaces.isEmpty {
                    Text("还没有设置地方。请让 \(store.config.alexName) 长按小A，在设置里加上常去的地方。")
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
                                Text(place.nameZH).font(.xa(26, .heavy)).lineLimit(1).minimumScaleFactor(0.6)
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
                            Text("去：\(place.nameZH)").font(.xa(30, .heavy))
                            Text(place.addressEN).font(.xa(17, .semibold)).foregroundStyle(Palette.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("我会把你现在的位置和要去的地方发给 \(store.config.alexName)，他帮你叫车。")
                        .font(.xa(20, .semibold)).foregroundStyle(Palette.ink)
                }
                .card()

                if let problem { WarningNote(text: problem) }
                Spacer(minLength: 0)

                BigButton(title: stage == .locating ? "正在找你的位置…" : "请 \(store.config.alexName) 帮我叫车",
                          systemImage: stage == .locating ? "location.circle" : "paperplane.fill") {
                    request(place)
                }
                .disabled(stage == .locating || store.config.alexPhone.isEmpty)
                SoftButton(title: "换个地方", systemImage: "arrow.uturn.left", height: 64, fontSize: 22) {
                    stage = .choose
                    problem = nil
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    // MARK: 3. Waiting for Alex

    private var waiting: some View {
        ScrollView {
            VStack(spacing: 12) {
                MascotSays(text: "已经告诉 \(store.config.alexName) 了！",
                           detail: "叫好车后，他会发短信告诉你车的颜色和车牌", mascotSize: 68)

                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle").font(.system(size: 28, weight: .bold))
                    Text("上车前，先对车牌！对上了再上车。").font(.xa(22, .heavy))
                }
                .foregroundStyle(Palette.warnInk)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22).fill(Palette.butter))

                VStack(alignment: .leading, spacing: 8) {
                    Text("看不懂短信？").font(.xa(20, .heavy))
                    Text("用“看一看”对着短信拍一下，我帮你翻译。").font(.xa(19, .semibold)).foregroundStyle(Palette.ink2)
                    SoftButton(title: "看一看", systemImage: "camera.viewfinder", fill: Palette.peach, border: nil) {
                        app.go(.look)
                    }
                }
                .card()

                if let chosen {
                    BigButton(title: "给司机看地址", systemImage: "doc.text.magnifyingglass",
                              fill: Palette.sky, depth: Palette.skyDeep, foreground: Palette.ink, height: 68, fontSize: 24) {
                        app.go(.addressCard(chosen))
                    }
                }
                BigButton(title: "打给 \(store.config.alexName)", systemImage: "phone.fill",
                          fill: Palette.teal, depth: Palette.tealDeep, height: 68, fontSize: 24) {
                    Phone.call(store.config.alexPhone)
                }
                SoftButton(title: "回首页", systemImage: "house.fill", height: 60) { app.home() }
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
                problem = "找不到你的位置。短信里会请 \(store.config.alexName) 给你打电话。"
            }
            app.text(store.config.alexPhone, body: body) { sent in
                if sent { stage = .waiting }
            }
        }
    }

    static func requestMessage(place: Place, location: CLLocation?, address: String?, config: AppConfig) -> String {
        var lines = ["【小A 叫车】\(config.momNameZH)想去：\(place.nameZH)",
                     "Destination: \(place.addressEN)"]
        if let location {
            lines.append("Pickup: \(address ?? "see map")")
            lines.append("Map: \(LocationService.mapsLink(location))")
        } else {
            lines.append("Pickup: location unavailable — please call her.")
        }
        if let uber = uberLink(place: place, location: location) {
            lines.append("Open in Uber: \(uber)")
        }
        lines.append("Book it as a ride for \(config.momNameEN.isEmpty ? "Mom" : config.momNameEN), then send her the car in 小A › Alex mode › Send car details.")
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
            parts.append("pickup%5Bnickname%5D=Mom")
        } else {
            parts.append("pickup=my_location")
        }
        parts.append("dropoff%5Bformatted_address%5D=\(enc(place.addressEN))")
        parts.append("dropoff%5Bnickname%5D=\(enc(place.nameZH))")
        return "https://m.uber.com/ul/?" + parts.joined(separator: "&")
    }
}
