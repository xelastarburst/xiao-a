import Foundation
import Testing
@testable import XiaoA

@Suite("Lesen · Look")
@MainActor
struct LookTests {

    @Test("Claude's reply: what the photo is, and each numbered line, whatever the punctuation")
    func parsesReply() {
        let r = ClearRead.parse("""
        WHAT：Etikett einer Medikamentenflasche
        1: Ibuprofen
        2. 1 Tablette, 3-mal täglich
        3、
        4) Nach dem Essen einnehmen
          5 ： Für Kinder unzugänglich aufbewahren
        12345: too long a number
        Note: ignore me
        """)
        #expect(r.what == "Etikett einer Medikamentenflasche")
        #expect(r.translated[1] == "Ibuprofen")
        #expect(r.translated[2] == "1 Tablette, 3-mal täglich")
        #expect(r.translated[3] == "")                 // not real text: left as is on screen
        #expect(r.translated[4] == "Nach dem Essen einnehmen")
        #expect(r.translated[5] == "Für Kinder unzugänglich aufbewahren")
        #expect(r.translated.count == 5)
    }

    @Test("Prices, doses and phone numbers survive exactly as written")
    func keepsNumbers() {
        let r = ClearRead.parse("1: Milchkaffee $4.50\n2: Telefon: (206) 555-0123\n3: alle 4–6 Stunden 1 Kapsel")
        #expect(r.translated[1] == "Milchkaffee $4.50")
        #expect(r.translated[2] == "Telefon: (206) 555-0123")
        #expect(r.translated[3] == "alle 4–6 Stunden 1 Kapsel")
    }

    @Test("An empty or chatty reply gives nothing, never a crash")
    func junkReply() {
        #expect(ClearRead.parse("").translated.isEmpty)
        #expect(ClearRead.parse("Sorry, I can't read this photo.").translated.isEmpty)
        #expect(ClearRead.parse("WHAT:").what == nil)
    }

    @Test("Claude's in-context line replaces the on-device one; an empty one doesn't")
    func prefersContext() {
        let engine = TranslationEngine()
        #expect(engine.translation(for: "EXIT") == nil)
        engine.cache["EXIT"] = "Ausgang"
        #expect(engine.translation(for: "EXIT") == "Ausgang")
        engine.contextual["EXIT"] = "Notausgang"
        #expect(engine.translation(for: "EXIT") == "Notausgang")
        engine.contextual["EXIT"] = ""
        #expect(engine.translation(for: "EXIT") == "Ausgang")
    }

    @Test("All in context only when every visible line has Claude's translation")
    func allInContext() {
        let engine = TranslationEngine()
        #expect(!engine.allInContext)
        engine.noteVisible(["SALE", "50% OFF"])
        engine.contextual["SALE"] = "Angebot"
        #expect(!engine.allInContext)
        engine.contextual["50% OFF"] = "50 % Rabatt"
        #expect(engine.allInContext)
    }

    @Test("Claude is asked only when the camera has rested on new text, at most every 1.5 s")
    func refineTiming() {
        #expect(TranslationEngine.shouldRefine(missing: 2, sinceNewText: 1.0, sinceLastRefine: 5))
        #expect(!TranslationEngine.shouldRefine(missing: 0, sinceNewText: 1.0, sinceLastRefine: 5))   // all done
        #expect(!TranslationEngine.shouldRefine(missing: 2, sinceNewText: 0.3, sinceLastRefine: 5))   // still moving
        #expect(!TranslationEngine.shouldRefine(missing: 2, sinceNewText: 1.0, sinceLastRefine: 1.0)) // just asked
    }
}

@Suite("Fragen · Ask")
@MainActor
struct AskTests {
    typealias Turn = AskModel.Turn

    @Test("The photo goes with her first question only; empty turns are dropped")
    func conversationForClaude() throws {
        let turns = [
            Turn(fromHer: true, text: "Was ist das?"),
            Turn(fromHer: false, text: "Das ist ein Medikament."),
            Turn(fromHer: false, text: ""),
            Turn(fromHer: true, text: "Wie oft am Tag?")
        ]
        let messages = AskModel.messages(turns: turns, imageBlock: ["type": "image", "source": "x"])
        #expect(messages.count == 3)
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "user"])
        let first = try #require(messages[0]["content"] as? [[String: Any]])
        #expect(first.count == 2)
        #expect(first[0]["type"] as? String == "image")
        #expect(first[1]["text"] as? String == "Was ist das?")
        #expect(messages[1]["content"] as? String == "Das ist ein Medikament.")
        let third = try #require(messages[2]["content"] as? [[String: Any]])
        #expect(third.count == 1)
        #expect(third[0]["type"] as? String == "text")
    }

    @Test("Without a photo, questions are plain text")
    func noPhoto() throws {
        let messages = AskModel.messages(turns: [Turn(fromHer: true, text: "Hallo")], imageBlock: nil)
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        #expect(content.count == 1)
        #expect(JSONSerialization.isValidJSONObject(messages))
    }

    @Test("Ground rules: German with Sie, short, no made-up doses, scam warnings, the Notfall button")
    func groundRules() {
        var config = AppConfig()
        config.herName = "Frau Weber"
        config.contactName = "Sabine"
        config.askContext = "Sie wohnt in Seattle"
        config.homeAddressEN = "1 Main St, Seattle"
        let prompt = AskModel.systemPrompt(config)
        #expect(prompt.contains("Antworte immer auf Deutsch"))
        #expect(prompt.contains("„Sie“"))
        #expect(prompt.contains("Erfinde niemals Dosierung"))
        #expect(prompt.contains("Betrug"))
        #expect(prompt.contains("„Notfall“"))
        #expect(prompt.contains("zuerst Sabine fragen"))
        #expect(prompt.contains("(Frau Weber)"))
        #expect(prompt.contains("Sie wohnt in Seattle"))
        #expect(prompt.contains("1 Main St, Seattle"))
    }

    @Test("Before setup, the family is simply 'Ihre Familie'")
    func noContactYet() {
        let prompt = AskModel.systemPrompt(AppConfig())
        #expect(prompt.contains("zuerst Ihre Familie fragen"))
        #expect(!prompt.contains("Ansprechperson"))
        #expect(!prompt.contains("()"))
    }

    @Test("Privacy: her medical card is never part of what is sent to Claude")
    func medicalStaysOnPhone() {
        var config = AppConfig()
        config.medical.insurer = "SECRET-INSURER"
        config.medical.policyNumber = "SECRET-POLICY"
        config.medical.memberID = "SECRET-MEMBER"
        config.medical.conditionsEN = "SECRET-CONDITION"
        config.medical.conditionsDE = "GEHEIMER-BEFUND"
        config.medical.medicationsEN = "SECRET-MEDICATION"
        config.medical.allergiesEN = "SECRET-ALLERGY"
        config.medical.doctorName = "SECRET-DOCTOR"
        let prompt = AskModel.systemPrompt(config)
        #expect(!prompt.contains("SECRET"))
        #expect(!prompt.contains("GEHEIM"))
    }

    @Test("Answers point back to her question")
    func questionBeforeAnswer() {
        let model = AskModel()
        #expect(model.latestAnswer == nil)
        #expect(model.question(before: Turn(fromHer: false, text: "x")) == nil)
    }
}
