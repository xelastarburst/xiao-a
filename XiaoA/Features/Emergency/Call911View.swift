import SwiftUI

/// Teaches the one word that matters ("Mandarin") before placing the call.
struct Call911View: View {
    var practice: Bool

    @EnvironmentObject private var store: ConfigStore
    @StateObject private var speaker = Speaker.shared
    @State private var practiceNote = false

    private var script: String {
        let address = store.config.homeAddressEN.isEmpty ? "" : " My home address is \(store.config.homeAddressEN)."
        return "Hello. I don't speak English. I speak Mandarin. Please get a Mandarin interpreter.\(address)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("接通后，先说这个词：").font(.xa(20, .heavy)).foregroundStyle(Palette.ink2)
                    Text("Mandarin")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.red)
                    Text("读作“曼-德-林”，意思是普通话").font(.xa(20, .bold))
                    Text("对方会找中文翻译来帮你").font(.xa(19, .bold)).foregroundStyle(Palette.tealInk)
                    SoftButton(title: "先听一遍怎么说", systemImage: "speaker.wave.2.fill",
                               fill: Palette.sky, border: nil) {
                        speaker.speakEnglish("Mandarin. Mandarin, please.", slow: true)
                    }
                    .padding(.top, 10)
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("也可以放给对方听：").font(.xa(20, .heavy)).foregroundStyle(Color(hex: 0x33455C))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(script).font(.xa(20, .heavy))
                        Text("我不会说英语，我说普通话，请找普通话翻译。" + (store.config.homeAddressZH.isEmpty ? "" : "我家地址是 \(store.config.homeAddressZH)。"))
                            .font(.xa(17, .semibold)).foregroundStyle(Palette.ink2)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18).fill(.white))
                    BigButton(title: speaker.isSpeaking ? "正在播放…" : "播放英文", systemImage: "play.fill",
                              fill: Palette.teal, depth: Palette.tealDeep, height: 56, fontSize: 20) {
                        speaker.speakEnglish(script)
                    }
                }
                .card(Palette.skyWash)

                BigButton(title: "现在拨打 911", systemImage: "phone.fill",
                          fill: Palette.red, depth: Palette.redDeep, height: 88, fontSize: 30) {
                    practiceNote = EmergencyActions.call911(practice: practice)
                }
                .padding(.top, 4)

                Text("提示：如果打电话时放不出声音，就直接说“Mandarin”。")
                    .font(.xa(17, .semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            TopBar(title: "打 911", showEmergency: false)
                .padding(.bottom, 8)
                .background(Palette.redWash)
        }
        .background(ScreenBackground(color: Palette.redWash))
        .alert("练习", isPresented: $practiceNote) {
            Button("知道了") {}
        } message: {
            Text("这里会拨打 911。iPhone 会再问一次，确认后才打出去。")
        }
        .onDisappear { speaker.stop() }
    }
}
