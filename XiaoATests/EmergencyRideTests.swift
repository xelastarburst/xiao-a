import Foundation
import Testing
@testable import XiaoA

/// Nothing here can dial or text: every test swaps the phone's "open URL" for a recorder.
@Suite("Notfall · Emergency and Fahrt · Ride", .serialized)
@MainActor
struct EmergencyRideTests {

    final class Dialer {
        var opened: [URL] = []
    }

    /// Runs `body` with dialling and texting recorded instead of done.
    func recording(_ body: (Dialer) throws -> Void) rethrows {
        let dialer = Dialer()
        let real = Phone.open
        Phone.open = { dialer.opened.append($0) }
        defer { Phone.open = real }
        try body(dialer)
    }

    @Test("Phone numbers keep only digits and +")
    func digits() {
        #expect(Phone.digits("(206) 555-0123") == "2065550123")
        #expect(Phone.digits("+1 206.555.0123 ext") == "+12065550123")
        #expect(Phone.digits("") == "")
    }

    @Test("Practice mode never dials her contact; it explains instead")
    func practiceCallContact() {
        recording { dialer in
            var config = AppConfig()
            config.contactName = "Sabine"
            config.contactPhone = "206-555-0123"
            let note = EmergencyActions.callContact(practice: true, config: config)
            #expect(note == "Hier würde Helferlein Sabine direkt anrufen.")
            #expect(EmergencyActions.callContact(practice: true, config: AppConfig()) == "Hier würde Helferlein Ihre Familie direkt anrufen.")
            #expect(dialer.opened.isEmpty)
        }
    }

    @Test("For real, “… anrufen” dials her contact's number")
    func realCallContact() {
        recording { dialer in
            var config = AppConfig()
            config.contactPhone = "(206) 555-0123"
            #expect(EmergencyActions.callContact(practice: false, config: config) == nil)
            #expect(dialer.opened.map(\.absoluteString) == ["tel://2065550123"])
        }
    }

    @Test("Practice mode never dials 911")
    func practice911() {
        recording { dialer in
            #expect(EmergencyActions.call911(practice: true))
            #expect(dialer.opened.isEmpty)
        }
    }

    @Test("For real, “Jetzt 911 anrufen” dials exactly 911 (recorded here, not dialled)")
    func real911() {
        recording { dialer in
            #expect(!EmergencyActions.call911(practice: false))
            #expect(dialer.opened.map(\.absoluteString) == ["tel://911"])
        }
    }

    @Test("No number saved: nothing is dialled")
    func noNumber() {
        recording { dialer in
            Phone.call("")
            Phone.call("ask Sabine")
            #expect(dialer.opened.isEmpty)
        }
    }

    @Test("The help text to her family: who, where, a map link; or asks them to call if there's no location")
    func helpText() {
        let found = EmergencyActions.message(help: true, contactName: "Sabine", address: "1 Main St",
                                             mapsLink: "https://maps.apple.com/?ll=47.6,-122.3")
        #expect(found == "[Helferlein] Sabine, ich brauche Hilfe!\nAdresse: 1 Main St\nhttps://maps.apple.com/?ll=47.6,-122.3")
        let noName = EmergencyActions.message(help: true, contactName: "", address: nil, mapsLink: "https://m")
        #expect(noName.hasPrefix("[Helferlein] Ich brauche Hilfe!"))
        let here = EmergencyActions.message(help: false, contactName: "Sabine", address: nil, mapsLink: "https://m")
        #expect(here == "[Helferlein] Ich bin gerade hier:\nhttps://m")
        let lost = EmergencyActions.message(help: true, contactName: "Sabine", address: "ignored", mapsLink: nil)
        #expect(lost.hasSuffix("(Standort nicht gefunden – bitte ruf mich an)"))
        #expect(!lost.contains("ignored"))
    }

    @Test("Text fallback: the whole message arrives, even with & or # in it")
    func smsFallback() throws {
        try recording { dialer in
            Phone.openSMS(to: "(206) 555-0123", body: "Ich bin bei Smith & Co #2, Tür 1+1=2? Grüße")
            let url = try #require(dialer.opened.first)
            #expect(url.absoluteString.hasPrefix("sms:2065550123&body="))
            let body = try #require(url.absoluteString.components(separatedBy: "&body=").last?.removingPercentEncoding)
            #expect(body == "Ich bin bei Smith & Co #2, Tür 1+1=2? Grüße")
        }
    }

    // MARK: Ride

    @Test("Ride text: car, plate in capitals, driver, minutes, and the check-the-plate warning")
    func rideText() {
        let text = RideDetailsComposer.message(color: .white, model: "Toyota Camry", plate: "abc123",
                                               driver: "Mike", minutes: 5)
        #expect(text == """
        [Helferlein] Ihr Auto ist bestellt!
        Farbe: Weiß
        Auto: Toyota Camry
        Kennzeichen: ABC123
        Fahrer: Mike
        Ankunft in etwa 5 Minuten
        Vor dem Einsteigen unbedingt das Kennzeichen prüfen! Nur einsteigen, wenn es stimmt.
        """)
    }

    @Test("Ride text leaves out what the family didn't fill in, never the plate or the warning")
    func rideTextMinimal() {
        let text = RideDetailsComposer.message(color: .other, model: "", plate: "7xyz", driver: "", minutes: 3)
        #expect(!text.contains("Farbe:"))
        #expect(!text.contains("Auto:"))
        #expect(!text.contains("Fahrer"))
        #expect(text.contains("Kennzeichen: 7XYZ"))
        #expect(text.contains("das Kennzeichen prüfen"))
        #expect(CarColor.allCases.filter { $0 != .other }.allSatisfy { !$0.de.isEmpty })
    }

    @Test("A ride request tells the family where she is going, in German, with an Uber link")
    func rideRequest() {
        var config = AppConfig()
        config.herName = "Frau Weber"
        let place = Place(nameDE: "Supermarkt", addressEN: "100 Main St, San Jose", icon: "cart.fill")
        let text = RideView.requestMessage(place: place, location: nil, address: nil, config: config)
        #expect(text.hasPrefix("[Helferlein] Fahrtwunsch für Frau Weber: Supermarkt"))
        #expect(text.contains("Ziel: 100 Main St, San Jose"))
        #expect(text.contains("Standort unbekannt"))
        #expect(text.contains("https://m.uber.com/ul/?"))
    }

    // MARK: Settings lock

    @Test("Settings open only with exactly the right PIN")
    func pin() {
        #expect(PINGate.unlocks(entry: "2580", pin: "2580"))
        #expect(!PINGate.unlocks(entry: "2581", pin: "2580"))
        #expect(!PINGate.unlocks(entry: "258", pin: "2580"))
        #expect(!PINGate.unlocks(entry: " 2580", pin: "2580"))
    }
}
