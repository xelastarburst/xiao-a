import Foundation
import Testing
@testable import XiaoA

@Suite("Keys and settings")
struct KeysTests {
    let openAI = "sk-proj-" + String(repeating: "a", count: 40)
    let claude = "sk-ant-api03-" + String(repeating: "b", count: 40)

    @Test("The built-in keys file is read, with stray spaces trimmed")
    func readsKeysFile() {
        let keys = APIKeys.parseBundled(#"{"openai": "  \#(openAI)\n", "anthropic": "\#(claude)"}"#)
        #expect(keys[.openAI] == openAI)
        #expect(keys[.anthropic] == claude)
    }

    @Test("Placeholders, half pastes, a missing key or a broken file give no key (never a crash)")
    func rejectsBadKeys() {
        #expect(APIKeys.parseBundled(#"{"openai": "PASTE KEY HERE", "anthropic": "short"}"#).isEmpty)
        #expect(APIKeys.parseBundled(#"{"openai": "sk-proj-aaaa bbbb cccc dddd eeee"}"#).isEmpty)
        #expect(APIKeys.parseBundled(#"{"anthropic": "\#(claude)"}"#) == [.anthropic: claude])
        #expect(APIKeys.parseBundled(#"{"openai": 12345678901234567890123}"#).isEmpty)
        #expect(APIKeys.parseBundled("").isEmpty)
        #expect(APIKeys.parseBundled("{ openai: nope").isEmpty)
        #expect(APIKeys.parseBundled("[]").isEmpty)
    }

    @Test("Test keys tries the phone's key and the built-in one, once each")
    func keyCandidates() {
        #expect(KeyCheck.candidates(saved: nil, builtIn: nil).isEmpty)
        #expect(KeyCheck.candidates(saved: "k1", builtIn: "k1").map { $0.1 } == ["k1"])
        #expect(KeyCheck.candidates(saved: nil, builtIn: "k2").map { $0.0 } == ["built into the app"])
        let both = KeyCheck.candidates(saved: "k1", builtIn: "k2")
        #expect(both.map { $0.0 } == ["saved on this iPhone", "built into the app"])
        #expect(both.map { $0.1 } == ["k1", "k2"])
    }

    @Test("Key test shows the service's own error message")
    func keyErrorMessages() {
        let openAIError = Data(#"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}"#.utf8)
        #expect(KeyCheck.message(from: openAIError) == "Incorrect API key provided")
        let claudeError = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        #expect(KeyCheck.message(from: claudeError) == "invalid x-api-key")
        #expect(KeyCheck.message(from: Data("Bad Gateway".utf8)) == "Bad Gateway")
        #expect(KeyCheck.message(from: Data(String(repeating: "x", count: 500).utf8)).count == 200)
    }

    @Test("A recording for OpenAI is a well-formed upload")
    func uploadBody() {
        let audio = Data("RIFF-fake-wav".utf8)
        let body = String(decoding: OpenAITranscribe.multipartBody(audio: audio, boundary: "B", language: "en"), as: UTF8.self)
        #expect(body.hasPrefix("--B\r\n"))
        #expect(body.contains("name=\"model\"\r\n\r\ngpt-4o-transcribe\r\n"))
        #expect(body.contains("name=\"language\"\r\n\r\nen\r\n"))
        #expect(body.contains("name=\"response_format\"\r\n\r\njson\r\n"))
        #expect(body.contains("filename=\"try.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFF-fake-wav\r\n"))
        #expect(body.hasSuffix("\r\n--B--\r\n"))
    }
}

@Suite("Her setup")
struct ConfigTests {

    @Test("A fresh setup has sensible defaults")
    func defaults() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        #expect(config.contactName == "")
        #expect(config.contactLabel == "Ihre Familie")
        #expect(config.herName == "")
        #expect(config.places.isEmpty)
    }

    @Test("An old or damaged field never wipes the rest of her setup")
    func tolerantDecoding() throws {
        let json = #"{"contactName":"Bob","contactPhone":"2065550123","herName":42,"fieldFromTheFuture":true,"medical":{"insurer":"Aetna","memberID":7}}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.contactName == "Bob")
        #expect(config.contactPhone == "2065550123")
        #expect(config.herName == "")
        #expect(config.contactLabel == "Bob")
        #expect(config.medical.insurer == "Aetna")
        #expect(config.medical.memberID == "")
    }

    @Test("Everything the family sets up is saved and read back unchanged")
    func roundTrip() throws {
        var config = AppConfig()
        config.herNameEN = "Lin"
        config.contactPhone = "+1 206 555 0123"
        config.homeAddressEN = "1 Main St"
        config.places = [Place(nameDE: "Supermarkt", addressEN: "2 Market St", icon: "cart.fill")]
        config.medical.allergiesDE = "Penicillin"
        config.herName = "Oma Inge"
        config.pin = "2580"
        let back = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(back.herNameEN == "Lin")
        #expect(back.contactPhone == "+1 206 555 0123")
        #expect(back.places == config.places)
        #expect(back.medical == config.medical)
        #expect(back.herName == "Oma Inge" && back.pin == "2580")
    }
}
