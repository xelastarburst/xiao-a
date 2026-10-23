import SwiftUI

/// A big English card to hand to a driver or a stranger. `place == nil` means home.
struct AddressCardView: View {
    var place: Place?

    @EnvironmentObject private var store: ConfigStore
    @StateObject private var speaker = Speaker.shared

    private var nameDE: String { place?.nameDE ?? "Zuhause" }
    private var addressEN: String { place?.addressEN ?? store.config.homeAddressEN }
    private var isHome: Bool { place == nil || place?.icon == "house.fill" }

    var body: some View {
        VStack(spacing: 14) {
            Text(isHome ? "Bitte bringen Sie mich nach Hause" : "Bitte bringen Sie mich zu: \(nameDE)")
                .font(.xa(24, .heavy)).foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                Text("Please take me to this address:")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(addressEN.isEmpty ? "(No address yet — please ask my family)" : addressEN)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .textSelection(.enabled)
                if isHome && !store.config.homeAddressDE.isEmpty {
                    Text(store.config.homeAddressDE).font(.xa(20, .semibold)).foregroundStyle(Palette.ink2)
                }
                Divider()
                Text("I don't speak English, I speak German. If you need help, please call my family\(store.config.contactName.isEmpty ? "" : " (\(store.config.contactName))"): \(store.config.contactPhone)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Palette.ink)
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 26).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Palette.ink, lineWidth: 4))

            Spacer(minLength: 0)

            BigButton(title: "Auf Englisch vorlesen", systemImage: "speaker.wave.2.fill",
                      fill: Palette.teal, depth: Palette.tealDeep) {
                speaker.speakEnglish("Hello. Please take me to this address: \(addressEN). Thank you!")
            }
            if !store.config.contactPhone.isEmpty {
                SoftButton(title: "\(store.config.contactLabel) anrufen", systemImage: "phone.fill", height: 64, fontSize: 22) {
                    Phone.call(store.config.contactPhone)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .safeAreaInset(edge: .top) {
            TopBar(title: "Adresse zeigen").padding(.bottom, 8).background(Palette.cream)
        }
        .background(ScreenBackground())
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            speaker.stop()
        }
    }
}
