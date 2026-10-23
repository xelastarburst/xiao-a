import SwiftUI

struct MedicalCardView: View {
    @EnvironmentObject private var store: ConfigStore
    @State private var staffView = false
    @State private var zoomed: UIImage?

    private var medical: MedicalInfo { store.config.medical }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                BigToggle(left: "Für mich", right: "Für Ärzte & Helfer", isRight: $staffView)
                    .padding(.vertical, 4)

                cards

                if staffView { staffCard } else { herCard }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            TopBar(title: "Notfallausweis").padding(.bottom, 8).background(Palette.cream)
        }
        .background(ScreenBackground())
        .fullScreenCover(item: Binding(get: { zoomed.map(IdentifiedImage.init) }, set: { zoomed = $0?.image })) { item in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                Image(uiImage: item.image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                IconButton(systemImage: "xmark", label: "Schließen", fill: .white) { zoomed = nil }
                    .padding(20)
            }
        }
    }

    @ViewBuilder private var cards: some View {
        let front = store.cardImage(.front)
        let back = store.cardImage(.back)
        if front != nil || back != nil {
            HStack(spacing: 10) {
                ForEach([front, back].compactMap { $0 }, id: \.self) { image in
                    Button { zoomed = image } label: {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(Squish())
                }
            }
        } else if !staffView {
            Text("Noch kein Foto der Versicherungskarte. Bitte lassen Sie \(store.config.contactLabel) es in den Einstellungen aufnehmen.")
                .font(.xa(18, .semibold)).foregroundStyle(Palette.ink2)
                .card()
        }
    }

    private var herCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            InfoRow(label: "Versicherung", value: medical.insurer)
            InfoRow(label: "Policennummer", value: medical.policyNumber)
            InfoRow(label: "Mitgliedsnummer", value: medical.memberID)
            if !medical.insurerPhone.isEmpty {
                PhoneRow(label: "Telefon Versicherung", number: medical.insurerPhone)
            }
            InfoRow(label: "Erkrankungen", value: medical.conditionsDE.isEmpty ? medical.conditionsEN : medical.conditionsDE)
            InfoRow(label: "Medikamente", value: medical.medicationsDE.isEmpty ? medical.medicationsEN : medical.medicationsDE)
            InfoRow(label: "Allergien", value: medical.allergiesDE.isEmpty ? medical.allergiesEN : medical.allergiesDE)
            if !medical.doctorName.isEmpty { InfoRow(label: "Arzt", value: medical.doctorName) }
            if !medical.doctorPhone.isEmpty { PhoneRow(label: "Telefon Arzt", number: medical.doctorPhone) }
            if !store.config.contactPhone.isEmpty {
                PhoneRow(label: "Notfallkontakt: \(store.config.contactLabel)", number: store.config.contactPhone)
            }
        }
        .card()
    }

    private var staffCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Patient speaks German only. Please use a German phone interpreter.")
                .font(.xa(20, .heavy)).foregroundStyle(Palette.red)
            if !store.config.herNameEN.isEmpty { InfoRow(label: "Name", value: store.config.herNameEN) }
            InfoRow(label: "Insurance", value: medical.insurer)
            InfoRow(label: "Policy #", value: medical.policyNumber)
            InfoRow(label: "Member ID", value: medical.memberID)
            InfoRow(label: "Insurer phone", value: medical.insurerPhone)
            InfoRow(label: "Conditions", value: medical.conditionsEN)
            InfoRow(label: "Medications", value: medical.medicationsEN)
            InfoRow(label: "Allergies", value: medical.allergiesEN.isEmpty ? "None known" : medical.allergiesEN)
            if !medical.doctorName.isEmpty {
                InfoRow(label: "Doctor", value: [medical.doctorName, medical.doctorPhone].filter { !$0.isEmpty }.joined(separator: " · "))
            }
            InfoRow(label: "Emergency contact", value: "\(store.config.contactName.isEmpty ? "Family" : store.config.contactName) (family) \(store.config.contactPhone)")
            InfoRow(label: "Home address", value: store.config.homeAddressEN)
        }
        .card()
    }
}

private struct IdentifiedImage: Identifiable {
    let image: UIImage
    var id: ObjectIdentifier { ObjectIdentifier(image) }
}

private struct InfoRow: View {
    var label: String
    var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.xa(16, .heavy)).foregroundStyle(Palette.ink2)
            Text(value.isEmpty ? "—" : value).font(.xa(22, .bold)).foregroundStyle(Palette.ink)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PhoneRow: View {
    var label: String
    var number: String
    var body: some View {
        HStack {
            InfoRow(label: label, value: number)
            IconButton(systemImage: "phone.fill", label: "Anrufen", fill: Palette.mint, foreground: Palette.teal, size: 52) {
                Phone.call(number)
            }
        }
    }
}
