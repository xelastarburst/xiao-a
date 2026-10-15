import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var learning: LearningStore
    @State private var showPIN = false

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return "早上好"
        case 11..<13: return "中午好"
        case 13..<18: return "下午好"
        default: return "晚上好"
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 8) {
                Mascot(size: 92)
                    .onLongPressGesture(minimumDuration: 2) {
                        Haptics.success()
                        showPIN = true
                    }
                    .accessibilityHint("Alex: long-press for settings")
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(greeting)，\(store.config.momNameZH)！")
                        .font(.xa(28, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(store.isSetUp ? "今天想做什么？" : "请让 \(store.config.alexName) 先帮你设置一下")
                        .font(.xa(20, .medium)).foregroundStyle(Palette.ink2)
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
                    FeatureTile(title: "看一看", subtitle: "拍英文看中文", symbol: "camera.viewfinder",
                                fill: Palette.peach, depth: Palette.peachDeep) { app.go(.look) }
                    FeatureTile(title: "问一问", subtitle: "不懂就问我", symbol: "questionmark.bubble",
                                fill: Palette.sky, depth: Palette.skyDeep) { app.ask(about: nil) }
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 12) {
                    FeatureTile(title: "翻译官", subtitle: "帮你和人说话", symbol: "bubble.left.and.bubble.right",
                                fill: Palette.sage, depth: Palette.sageDeep) { app.go(.interpreter) }
                    FeatureTile(title: "学英语", subtitle: "每天 30 分钟", symbol: "book",
                                fill: Palette.butter, depth: Palette.butterDeep,
                                badge: learning.streak > 0 ? "\(learning.streak)天" : nil) { app.go(.learn) }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            // A slim bar, not a fifth big tile: rides are occasional, the four tiles are daily.
            RideBar { app.go(.ride) }

            Button { app.go(.emergency(practice: false)) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill").font(.system(size: 28, weight: .bold))
                    Text("紧急").font(.xa(30, .heavy)).tracking(2)
                    Text("一按就找人帮忙").font(.xa(20, .medium))
                }
                .foregroundStyle(.white)
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
    var badge: String? = nil
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
                Text(subtitle).font(.xa(19, .medium)).foregroundStyle(Palette.ink.opacity(0.75))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .chunky(fill, depth: depth, radius: 28)
            .overlay(alignment: .topTrailing) {
                if let badge {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").foregroundStyle(Palette.gold)
                        Text(badge).foregroundStyle(Palette.ink)
                    }
                    .font(.xa(17, .heavy))
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(Capsule().fill(.white))
                    .overlay(Capsule().strokeBorder(Palette.gold, lineWidth: 2))
                    .fixedSize()
                    .offset(x: 4, y: -10)
                    .accessibilityLabel("已经连续学了\(badge)")
                }
            }
        }
        .buttonStyle(Squish())
    }
}

private struct RideBar: View {
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
                    Text("叫车").font(.xa(27, .heavy)).foregroundStyle(Palette.ink)
                    Text("小A 帮你叫车").font(.xa(18, .medium)).foregroundStyle(Palette.lilacInk)
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
