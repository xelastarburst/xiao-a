import SwiftUI

enum CarColor: String, CaseIterable, Identifiable {
    case white, black, silver, gray, blue, red, green, other
    var id: String { rawValue }
    var en: String { rawValue.capitalized }
    var de: String {
        switch self {
        case .white: return "Weiß"
        case .black: return "Schwarz"
        case .silver: return "Silber"
        case .gray: return "Grau"
        case .blue: return "Blau"
        case .red: return "Rot"
        case .green: return "Grün"
        case .other: return ""
        }
    }
}

/// After booking an Uber for her, her family fills this in and it becomes a German text to her.
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

    /// The German text she gets: car, plate, driver, minutes, and the plate check. Empty fields are left out.
    static func message(color: CarColor, model: String, plate: String, driver: String, minutes: Int) -> String {
        var lines = ["[Helferlein] Ihr Auto ist bestellt!"]
        if !color.de.isEmpty { lines.append("Farbe: \(color.de)") }
        if !model.isEmpty { lines.append("Auto: \(model)") }
        lines.append("Kennzeichen: \(plate.uppercased())")
        if !driver.isEmpty { lines.append("Fahrer: \(driver)") }
        lines.append("Ankunft in etwa \(minutes) Minuten")
        lines.append("Vor dem Einsteigen unbedingt das Kennzeichen prüfen! Nur einsteigen, wenn es stimmt.")
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
            Section("She will get") {
                Text(message).font(.body)
            }
            Section {
                Button("Text her") {
                    app.text(store.config.herPhone, body: message)
                }
                .disabled(plate.isEmpty || store.config.herPhone.isEmpty)
            } footer: {
                if store.config.herPhone.isEmpty {
                    Text("Add her phone number at the top of Settings first.")
                } else {
                    Text("Tip: in Uber, choose “Ride for someone else” and pick her so the driver can call her too.")
                }
            }
        }
        .navigationTitle("Tell her about her car")
    }
}
