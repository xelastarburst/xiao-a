import SwiftUI
import UIKit

struct Place: Codable, Identifiable, Hashable {
    var id = UUID()
    var nameDE: String
    var addressEN: String
    var icon: String = "mappin.and.ellipse"

    static let iconChoices: [(symbol: String, label: String)] = [
        ("house.fill", "Home"),
        ("cart.fill", "Store"),
        ("leaf.fill", "Park"),
        ("cross.case.fill", "Clinic"),
        ("fork.knife", "Restaurant"),
        ("building.columns.fill", "Building"),
        ("person.2.fill", "Friend"),
        ("mappin.and.ellipse", "Other")
    ]
}

struct MedicalInfo: Codable, Hashable {
    var insurer = ""
    var policyNumber = ""
    var memberID = ""
    var insurerPhone = ""
    var conditionsEN = ""
    var conditionsDE = ""
    var medicationsEN = ""
    var medicationsDE = ""
    var allergiesEN = ""
    var allergiesDE = ""
    var doctorName = ""
    var doctorPhone = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        insurer = c.value(.insurer, "")
        policyNumber = c.value(.policyNumber, "")
        memberID = c.value(.memberID, "")
        insurerPhone = c.value(.insurerPhone, "")
        conditionsEN = c.value(.conditionsEN, "")
        conditionsDE = c.value(.conditionsDE, "")
        medicationsEN = c.value(.medicationsEN, "")
        medicationsDE = c.value(.medicationsDE, "")
        allergiesEN = c.value(.allergiesEN, "")
        allergiesDE = c.value(.allergiesDE, "")
        doctorName = c.value(.doctorName, "")
        doctorPhone = c.value(.doctorPhone, "")
    }
}

/// Everything her family sets up (Einstellungen). She never sees this directly.
struct AppConfig: Codable {
    /// What the app calls her, e.g. "Frau Weber" or "Oma Inge" (empty: no name in greetings).
    var herName = ""
    var herNameEN = ""
    var herPhone = ""
    /// The family member she calls and texts for help and rides.
    var contactName = ""
    var contactPhone = ""
    var homeAddressEN = ""
    var homeAddressDE = ""
    var places: [Place] = []
    var medical = MedicalInfo()
    var askContext = ""
    var pin = ""

    init() {}

    // Tolerant decoding so adding a field later never wipes the setup.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        herName = c.value(.herName, "")
        herNameEN = c.value(.herNameEN, "")
        herPhone = c.value(.herPhone, "")
        contactName = c.value(.contactName, "")
        contactPhone = c.value(.contactPhone, "")
        homeAddressEN = c.value(.homeAddressEN, "")
        homeAddressDE = c.value(.homeAddressDE, "")
        places = c.value(.places, [])
        medical = c.value(.medical, MedicalInfo())
        askContext = c.value(.askContext, "")
        pin = c.value(.pin, "")
    }

    /// Her contact as shown to her: the name, or "Ihre Familie" until one is set.
    var contactLabel: String {
        let name = contactName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Ihre Familie" : name
    }
}

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

enum CardSide: String { case front, back }

@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: AppConfig {
        didSet { save() }
    }

    private static var folder: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Helferlein", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private static var fileURL: URL { folder.appendingPathComponent("config.json") }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        } else {
            #if DEBUG && targetEnvironment(simulator)
            config = AppConfig.simulatorSample      // sample details for testing in the simulator
            #else
            config = AppConfig()
            #endif
        }
    }

    var isSetUp: Bool { !config.contactPhone.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Places she can ride to: home first, then the saved places.
    var ridePlaces: [Place] {
        var list: [Place] = []
        if !config.homeAddressEN.isEmpty {
            list.append(Place(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                              nameDE: "Zuhause", addressEN: config.homeAddressEN, icon: "house.fill"))
        }
        return list + config.places
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        // Medical and contact details stay on this phone, encrypted while it's locked.
        try? data.write(to: Self.fileURL, options: [.atomic, .completeFileProtection])
    }

    // MARK: Insurance card photos

    private func cardURL(_ side: CardSide) -> URL {
        Self.folder.appendingPathComponent("card-\(side.rawValue).jpg")
    }

    func saveCard(_ data: Data, side: CardSide) {
        let image = UIImage(data: data)
        let jpeg = image?.jpegData(compressionQuality: 0.85) ?? data
        try? jpeg.write(to: cardURL(side), options: [.atomic, .completeFileProtection])
        objectWillChange.send()
    }

    func removeCard(_ side: CardSide) {
        try? FileManager.default.removeItem(at: cardURL(side))
        objectWillChange.send()
    }

    func cardImage(_ side: CardSide) -> UIImage? {
        guard let data = try? Data(contentsOf: cardURL(side)) else {
            return Demo.isOn ? Demo.cardImage(side) : nil
        }
        return UIImage(data: data)
    }
}
