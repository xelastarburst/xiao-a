import Foundation
import Testing
@testable import XiaoA

@Suite("看一看 · Look")
@MainActor
struct LookTests {

    @Test("Claude's reply: what the photo is, and each numbered line, whatever the punctuation")
    func parsesReply() {
        let r = ClearRead.parse("""
        WHAT：药瓶标签
        1: 布洛芬
        2. 每次 1 片，每天 3 次
        3、
        4) 饭后服用
          5 ： 儿童勿近
        12345: too long a number
        Note: ignore me
        """)
        #expect(r.what == "药瓶标签")
        #expect(r.chinese[1] == "布洛芬")
        #expect(r.chinese[2] == "每次 1 片，每天 3 次")
        #expect(r.chinese[3] == "")                 // not real text: left as is on screen
        #expect(r.chinese[4] == "饭后服用")
        #expect(r.chinese[5] == "儿童勿近")
        #expect(r.chinese.count == 5)
    }

    @Test("Prices, doses and phone numbers survive exactly as written")
    func keepsNumbers() {
        let r = ClearRead.parse("1: 拿铁咖啡 $4.50\n2: 电话 (206) 555-0123\n3: 每 4-6 小时 1 粒")
        #expect(r.chinese[1] == "拿铁咖啡 $4.50")
        #expect(r.chinese[2] == "电话 (206) 555-0123")
        #expect(r.chinese[3] == "每 4-6 小时 1 粒")
    }

    @Test("An empty or chatty reply gives nothing, never a crash")
    func junkReply() {
        #expect(ClearRead.parse("").chinese.isEmpty)
        #expect(ClearRead.parse("Sorry, I can't read this photo.").chinese.isEmpty)
        #expect(ClearRead.parse("WHAT:").what == nil)
    }

    @Test("Claude's in-context line replaces the on-device one; an empty one doesn't")
    func prefersContext() {
        let engine = TranslationEngine()
        #expect(engine.translation(for: "EXIT") == nil)
        engine.cache["EXIT"] = "出口"
        #expect(engine.translation(for: "EXIT") == "出口")
        engine.contextual["EXIT"] = "安全出口"
        #expect(engine.translation(for: "EXIT") == "安全出口")
        engine.contextual["EXIT"] = ""
        #expect(engine.translation(for: "EXIT") == "出口")
    }

    @Test("All in context only when every visible line has Claude's translation")
    func allInContext() {
        let engine = TranslationEngine()
        #expect(!engine.allInContext)
        engine.noteVisible(["SALE", "50% OFF"])
        engine.contextual["SALE"] = "特价"
        #expect(!engine.allInContext)
        engine.contextual["50% OFF"] = "五折"
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

@Suite("问一问 · Ask")
@MainActor
struct AskTests {
    typealias Turn = AskModel.Turn

    @Test("The photo goes with her first question only; empty turns are dropped")
    func conversationForClaude() throws {
        let turns = [
            Turn(fromMom: true, text: "这是什么？"),
            Turn(fromMom: false, text: "这是药。"),
            Turn(fromMom: false, text: ""),
            Turn(fromMom: true, text: "一天吃几次？")
        ]
        let messages = AskModel.messages(turns: turns, imageBlock: ["type": "image", "source": "x"])
        #expect(messages.count == 3)
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "user"])
        let first = try #require(messages[0]["content"] as? [[String: Any]])
        #expect(first.count == 2)
        #expect(first[0]["type"] as? String == "image")
        #expect(first[1]["text"] as? String == "这是什么？")
        #expect(messages[1]["content"] as? String == "这是药。")
        let third = try #require(messages[2]["content"] as? [[String: Any]])
        #expect(third.count == 1)
        #expect(third[0]["type"] as? String == "text")
    }

    @Test("Without a photo, questions are plain text")
    func noPhoto() throws {
        let messages = AskModel.messages(turns: [Turn(fromMom: true, text: "你好")], imageBlock: nil)
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        #expect(content.count == 1)
        #expect(JSONSerialization.isValidJSONObject(messages))
    }

    @Test("Ground rules: Chinese, short, no made-up doses, scam warnings, the emergency button")
    func groundRules() {
        var config = AppConfig()
        config.alexName = "Bob"
        config.askContext = "她住在 Seattle"
        config.homeAddressEN = "1 Main St, Seattle"
        let prompt = AskModel.systemPrompt(config)
        #expect(prompt.contains("永远用简体中文回答"))
        #expect(prompt.contains("绝对不要编造剂量"))
        #expect(prompt.contains("诈骗"))
        #expect(prompt.contains("紧急"))
        #expect(prompt.contains("先问Bob"))
        #expect(prompt.contains("她住在 Seattle"))
        #expect(prompt.contains("1 Main St, Seattle"))
    }

    @Test("Privacy: her medical card is never part of what is sent to Claude")
    func medicalStaysOnPhone() {
        var config = AppConfig()
        config.medical.insurer = "SECRET-INSURER"
        config.medical.policyNumber = "SECRET-POLICY"
        config.medical.memberID = "SECRET-MEMBER"
        config.medical.conditionsEN = "SECRET-CONDITION"
        config.medical.conditionsZH = "秘密病情"
        config.medical.medicationsEN = "SECRET-MEDICATION"
        config.medical.allergiesEN = "SECRET-ALLERGY"
        config.medical.doctorName = "SECRET-DOCTOR"
        let prompt = AskModel.systemPrompt(config)
        #expect(!prompt.contains("SECRET"))
        #expect(!prompt.contains("秘密"))
    }

    @Test("Answers point back to her question")
    func questionBeforeAnswer() {
        let model = AskModel()
        #expect(model.latestAnswer == nil)
        #expect(model.question(before: Turn(fromMom: false, text: "x")) == nil)
    }
}
