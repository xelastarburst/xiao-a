import SwiftUI

enum CarColor: String, CaseIterable, Identifiable {
    case white, black, silver, gray, blue, red, green, other
    var id: String { rawValue }
    var en: String { rawValue.capitalized }
    var zh: String {
        switch self {
        case .white: return "白色"
        case .black: return "黑色"
        case .silver: return "银色"
        case .gray: return "灰色"
        case .blue: return "蓝色"
        case .red: return "红色"
        case .green: return "绿色"
        case .other: return ""
        }
    }
}

/// After booking Uber for Mom, Alex fills this in and it becomes a Chinese text to her.
struct RideDetailsComposer: View {
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var app: AppState

    @State private var color: CarColor = .white
    @State private var model = ""
    @State private var plate = ""
    @State private var driver = ""
    @State private var minutes = 3

    private var message: String {
        Self.message(color: color, model: model, plate: plate, driver: driver, minutes: minutes)
    }

    /// The Chinese text Mom gets: car, plate, driver, minutes, and the plate check. Empty fields are left out.
    static func message(color: CarColor, model: String, plate: String, driver: String, minutes: Int) -> String {
        var lines = ["【小A 叫车】车叫好啦！"]
        let car = [color.zh, model].filter { !$0.isEmpty }.joined(separator: " ")
        if !car.isEmpty { lines.append("车：\(car)") }
        lines.append("车牌：\(plate.uppercased())")
        if !driver.isEmpty { lines.append("司机：\(driver)") }
        lines.append("大约 \(minutes) 分钟到")
        lines.append("上车前，一定先对车牌！对上了再上车。")
        return lines.joined(separator: "\n")
    }

    var body: some View {
        Form {
            Section("Car") {
                Picker("Color", selection: $color) {
                    ForEach(CarColor.allCases) { c in Text(c.en).tag(c) }
                }
                TextField("Make and model (e.g. Toyota Camry)", text: $model)
                TextField("License plate", text: $plate)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            Section("Driver") {
                TextField("Driver's first name", text: $driver)
                Stepper("Arrives in \(minutes) min", value: $minutes, in: 1...30)
            }
            Section("Mom will get") {
                Text(message).font(.body)
            }
            Section {
                Button("Text Mom") {
                    app.text(store.config.momPhone, body: message)
                }
                .disabled(plate.isEmpty || store.config.momPhone.isEmpty)
            } footer: {
                if store.config.momPhone.isEmpty {
                    Text("Add Mom's phone number at the top of Alex mode first.")
                } else {
                    Text("Tip: in Uber, choose “Ride for someone else” and pick Mom so the driver can call her too.")
                }
            }
        }
        .navigationTitle("Tell Mom her car")
    }
}
