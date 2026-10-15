import SwiftUI

struct MedicalCardView: View {
    @EnvironmentObject private var store: ConfigStore
    @State private var staffView = false
    @State private var zoomed: UIImage?

    private var medical: MedicalInfo { store.config.medical }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                BigToggle(left: "我看", right: "给医护人员看", isRight: $staffView)
                    .padding(.vertical, 4)

                cards

                if staffView { staffCard } else { momCard }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            TopBar(title: "我的医疗卡").padding(.bottom, 8).background(Palette.cream)
        }
        .background(ScreenBackground())
        .fullScreenCover(item: Binding(get: { zoomed.map(IdentifiedImage.init) }, set: { zoomed = $0?.image })) { item in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                Image(uiImage: item.image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                IconButton(systemImage: "xmark", label: "关闭", fill: .white) { zoomed = nil }
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
            Text("还没有保险卡照片。请让 \(store.config.alexName) 在设置里拍一下。")
                .font(.xa(18, .semibold)).foregroundStyle(Palette.ink2)
                .card()
        }
    }

    private var momCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            InfoRow(label: "保险公司", value: medical.insurer)
            InfoRow(label: "保单号", value: medical.policyNumber)
            InfoRow(label: "会员号", value: medical.memberID)
            if !medical.insurerPhone.isEmpty {
                PhoneRow(label: "保险公司电话", number: medical.insurerPhone)
            }
            InfoRow(label: "我的病", value: medical.conditionsZH.isEmpty ? medical.conditionsEN : medical.conditionsZH)
            InfoRow(label: "我吃的药", value: medical.medicationsZH.isEmpty ? medical.medicationsEN : medical.medicationsZH)
            InfoRow(label: "过敏", value: medical.allergiesZH.isEmpty ? medical.allergiesEN : medical.allergiesZH)
            if !medical.doctorName.isEmpty { InfoRow(label: "医生", value: medical.doctorName) }
            if !medical.doctorPhone.isEmpty { PhoneRow(label: "医生电话", number: medical.doctorPhone) }
            if !store.config.alexPhone.isEmpty {
                PhoneRow(label: "紧急联系人 \(store.config.alexName)", number: store.config.alexPhone)
            }
        }
        .card()
    }

    private var staffCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Patient speaks Mandarin Chinese only. Please use a phone interpreter.")
                .font(.xa(20, .heavy)).foregroundStyle(Palette.red)
            if !store.config.momNameEN.isEmpty { InfoRow(label: "Name", value: store.config.momNameEN) }
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
            InfoRow(label: "Emergency contact", value: "\(store.config.alexName) (son) \(store.config.alexPhone)")
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
            IconButton(systemImage: "phone.fill", label: "打电话", fill: Palette.mint, foreground: Palette.teal, size: 52) {
                Phone.call(number)
            }
        }
    }
}
