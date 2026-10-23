import SwiftUI

/// Teaches the one word that matters ("German") before placing the call.
struct Call911View: View {
    var practice: Bool

    @EnvironmentObject private var store: ConfigStore
    @StateObject private var speaker = Speaker.shared
    @State private var practiceNote = false

    private var script: String {
        let address = store.config.homeAddressEN.isEmpty ? "" : " My home address is \(store.config.homeAddressEN)."
        return "Hello. I don't speak English. I speak German. Please get a German interpreter.\(address)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wenn jemand abnimmt, sagen Sie zuerst dieses Wort:").font(.xa(20, .heavy)).foregroundStyle(Palette.ink2)
                    Text("German")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.red)
                    Text("Gesprochen: „Dschör-men“ – so heißt „Deutsch“ auf Englisch.").font(.xa(20, .bold))
                    Text("Dann holt man einen deutschen Dolmetscher für Sie.").font(.xa(19, .bold)).foregroundStyle(Palette.tealInk)
                    SoftButton(title: "Erst anhören, wie man es sagt", systemImage: "speaker.wave.2.fill",
                               fill: Palette.sky, border: nil) {
                        speaker.speakEnglish("German. German, please.", slow: true)
                    }
                    .padding(.top, 10)
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Sie können auch das hier vorspielen:").font(.xa(20, .heavy)).foregroundStyle(Color(hex: 0x33455C))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(script).font(.xa(20, .heavy))
                        Text("Ich spreche kein Englisch. Ich spreche Deutsch. Bitte holen Sie einen deutschen Dolmetscher." + (store.config.homeAddressDE.isEmpty ? "" : " Meine Adresse ist \(store.config.homeAddressDE)."))
                            .font(.xa(17, .semibold)).foregroundStyle(Palette.ink2)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18).fill(.white))
                    BigButton(title: speaker.isSpeaking ? "Spielt ab …" : "Englisch abspielen", systemImage: "play.fill",
                              fill: Palette.teal, depth: Palette.tealDeep, height: 56, fontSize: 20) {
                        speaker.speakEnglish(script)
                    }
                }
                .card(Palette.skyWash)

                BigButton(title: "Jetzt 911 anrufen", systemImage: "phone.fill",
                          fill: Palette.red, depth: Palette.redDeep, height: 88, fontSize: 30) {
                    practiceNote = EmergencyActions.call911(practice: practice)
                }
                .padding(.top, 4)

                Text("Das iPhone fragt noch einmal, bevor es anruft. Wenn das Abspielen nicht klappt, sagen Sie einfach „German“.")
                    .font(.xa(17, .semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            TopBar(title: "911 anrufen", showEmergency: false)
                .padding(.bottom, 8)
                .background(Palette.redWash)
        }
        .background(ScreenBackground(color: Palette.redWash))
        .alert("Übung", isPresented: $practiceNote) {
            Button("Verstanden") {}
        } message: {
            Text("Hier würde 911 angerufen. Das iPhone fragt vorher noch einmal nach.")
        }
        .onDisappear { speaker.stop() }
    }
}
