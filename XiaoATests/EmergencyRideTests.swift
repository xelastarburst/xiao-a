import Foundation
import Testing
@testable import XiaoA

/// Nothing here can dial or text: every test swaps the phone's "open URL" for a recorder.
@Suite("紧急 · Emergency and 叫车 · Ride", .serialized)
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

    @Test("Practice mode never dials Alex; it explains instead")
    func practiceCallAlex() {
        recording { dialer in
            var config = AppConfig()
            config.alexName = "Bob"
            config.alexPhone = "206-555-0123"
            let note = EmergencyActions.callAlex(practice: true, config: config)
            #expect(note == "这里会直接打电话给 Bob。")
            #expect(dialer.opened.isEmpty)
        }
    }

    @Test("For real, 打电话给 Alex dials his number")
    func realCallAlex() {
        recording { dialer in
            var config = AppConfig()
            config.alexPhone = "(206) 555-0123"
            #expect(EmergencyActions.callAlex(practice: false, config: config) == nil)
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

    @Test("For real, 现在拨打 911 dials exactly 911 (recorded here, not dialled)")
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
            Phone.call("ask Alex")
            #expect(dialer.opened.isEmpty)
        }
    }

    @Test("The help text to Alex: who, where, a map link; or asks him to call if there's no location")
    func helpText() {
        let found = EmergencyActions.message(help: true, alexName: "Bob", address: "1 Main St",
                                             mapsLink: "https://maps.apple.com/?ll=47.6,-122.3")
        #expect(found == "【小A】Bob，我需要帮忙！\n地址：1 Main St\nhttps://maps.apple.com/?ll=47.6,-122.3")
        let here = EmergencyActions.message(help: false, alexName: "Bob", address: nil, mapsLink: "https://m")
        #expect(here == "【小A】我现在在这里：\nhttps://m")
        let lost = EmergencyActions.message(help: true, alexName: "Bob", address: "ignored", mapsLink: nil)
        #expect(lost.hasSuffix("（找不到位置，请给我打电话）"))
        #expect(!lost.contains("ignored"))
    }

    @Test("Text fallback: the whole message arrives, even with & or # in it")
    func smsFallback() throws {
        try recording { dialer in
            Phone.openSMS(to: "(206) 555-0123", body: "我在 Smith & Co #2 门口 1+1=2?")
            let url = try #require(dialer.opened.first)
            #expect(url.absoluteString.hasPrefix("sms:2065550123&body="))
            let body = try #require(url.absoluteString.components(separatedBy: "&body=").last?.removingPercentEncoding)
            #expect(body == "我在 Smith & Co #2 门口 1+1=2?")
        }
    }

    // MARK: Ride

    @Test("Ride text: car, plate in capitals, driver, minutes, and the check-the-plate warning")
    func rideText() {
        let text = RideDetailsComposer.message(color: .white, model: "Toyota Camry", plate: "abc123",
                                               driver: "Mike", minutes: 5)
        #expect(text == """
        【小A 叫车】车叫好啦！
        车：白色 Toyota Camry
        车牌：ABC123
        司机：Mike
        大约 5 分钟到
        上车前，一定先对车牌！对上了再上车。
        """)
    }

    @Test("Ride text leaves out what Alex didn't fill in, never the plate or the warning")
    func rideTextMinimal() {
        let text = RideDetailsComposer.message(color: .other, model: "", plate: "7xyz", driver: "", minutes: 3)
        #expect(!text.contains("车："))
        #expect(!text.contains("司机"))
        #expect(text.contains("车牌：7XYZ"))
        #expect(text.contains("一定先对车牌"))
        #expect(CarColor.allCases.filter { $0 != .other }.allSatisfy { !$0.zh.isEmpty })
    }

    // MARK: Alex mode lock

    @Test("Alex mode opens only with exactly the right PIN")
    func pin() {
        #expect(PINGate.unlocks(entry: "2580", pin: "2580"))
        #expect(!PINGate.unlocks(entry: "2581", pin: "2580"))
        #expect(!PINGate.unlocks(entry: "258", pin: "2580"))
        #expect(!PINGate.unlocks(entry: " 2580", pin: "2580"))
    }
}
