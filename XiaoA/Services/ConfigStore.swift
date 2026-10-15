import SwiftUI
import UIKit

struct Place: Codable, Identifiable, Hashable {
    var id = UUID()
    var nameZH: String
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
    var conditionsZH = ""
    var medicationsEN = ""
    var medicationsZH = ""
    var allergiesEN = ""
    var allergiesZH = ""
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
        conditionsZH = c.value(.conditionsZH, "")
        medicationsEN = c.value(.medicationsEN, "")
        medicationsZH = c.value(.medicationsZH, "")
        allergiesEN = c.value(.allergiesEN, "")
        allergiesZH = c.value(.allergiesZH, "")
        doctorName = c.value(.doctorName, "")
        doctorPhone = c.value(.doctorPhone, "")
    }
}

/// Everything Alex sets up. Mom never sees this directly.
struct AppConfig: Codable {
    var momNameZH = "妈妈"
    var momNameEN = ""
    var momPhone = ""
    var alexName = "Alex"
    var alexPhone = ""
    var homeAddressEN = ""
    var homeAddressZH = ""
    var places: [Place] = []
    var medical = MedicalInfo()
    var askContext = ""
    var reminderHour = 10
    var reminderMinute = 0
    var remindersOn = true
    var strictPronunciation = false
    var newPhrasesPerDay = 4
    var pin = ""

    init() {}

    // Tolerant decoding so adding a field later never wipes Alex's setup.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        momNameZH = c.value(.momNameZH, "妈妈")
        momNameEN = c.value(.momNameEN, "")
        momPhone = c.value(.momPhone, "")
        alexName = c.value(.alexName, "Alex")
        alexPhone = c.value(.alexPhone, "")
        homeAddressEN = c.value(.homeAddressEN, "")
        homeAddressZH = c.value(.homeAddressZH, "")
        places = c.value(.places, [])
        medical = c.value(.medical, MedicalInfo())
        askContext = c.value(.askContext, "")
        reminderHour = c.value(.reminderHour, 10)
        reminderMinute = c.value(.reminderMinute, 0)
        remindersOn = c.value(.remindersOn, true)
        strictPronunciation = c.value(.strictPronunciation, false)
        newPhrasesPerDay = c.value(.newPhrasesPerDay, 4)
        pin = c.value(.pin, "")
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
            .appendingPathComponent("XiaoA", isDirectory: true)
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

    var isSetUp: Bool { !config.alexPhone.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Places Mom can ride to: home first, then Alex's saved places.
    var ridePlaces: [Place] {
        var list: [Place] = []
        if !config.homeAddressEN.isEmpty {
            list.append(Place(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                              nameZH: "家", addressEN: config.homeAddressEN, icon: "house.fill"))
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
