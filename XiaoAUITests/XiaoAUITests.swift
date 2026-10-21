import XCTest

/// Opens every screen Mom uses, in the simulator demo, with no API keys (nothing is ever sent).
/// Never taps anything that would call, text or dial 911.
final class XiaoAUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Backup for permission questions that appear while tapping.
        addUIInterruptionMonitor(withDescription: "iOS permission question") { alert in
            let deny = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Don' OR label CONTAINS '不允许'")).firstMatch
            if deny.exists { deny.tap(); return true }
            return false
        }
        app = XCUIApplication()
        app.launchArguments = ["-noKeys"]
        app.launch()
        dismissSystemAlerts()
        XCTAssertTrue(button("紧急").waitForExistence(timeout: 15), "home screen didn't appear")
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: Helpers

    /// The first button whose label contains `text` (tiles combine title and subtitle).
    private func button(_ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Taps the visible button containing `text` (screens underneath in the navigation stack may
    /// still be in the accessibility tree).
    private func tapVisible(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let query = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text))
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 5), "no \(text) button", file: file, line: line)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let visible = query.allElementsBoundByIndex.last(where: { $0.isHittable }) {
                visible.tap()
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("\(text) never became tappable", file: file, line: line)
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    private func anyText(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Notification / location / microphone questions from iOS: answer "Don't Allow".
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 2) else { return }
            let deny = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Don' OR label CONTAINS '不允许'")).firstMatch
            if deny.exists { deny.tap() } else { alert.buttons.element(boundBy: 0).tap() }
        }
    }

    private func open(_ tile: String, expect title: String, file: StaticString = #filePath, line: UInt = #line) {
        tapVisible(tile, file: file, line: line)
        dismissSystemAlerts()
        XCTAssertTrue(button("返回").waitForExistence(timeout: 8), "\(tile) didn't open", file: file, line: line)
        XCTAssertTrue(anyText(title).waitForExistence(timeout: 5), "\(tile) shows no \(title)", file: file, line: line)
    }

    /// 返回 until the home screen is back (no 返回 left anywhere).
    private func goBack(file: StaticString = #filePath, line: UInt = #line) {
        tapVisible("返回", file: file, line: line)
        XCTAssertTrue(waitUntilGone(button("返回")), "didn't get back home", file: file, line: line)
        XCTAssertTrue(button("翻译官").isHittable, "home screen isn't showing", file: file, line: line)
    }

    // MARK: Tests

    func testHomeShowsEveryFeature() {
        for name in ["看一看", "问一问", "翻译官", "学英语", "叫车", "紧急"] {
            XCTAssertTrue(anyText(name).exists, "\(name) missing from the home screen")
        }
    }

    func testLook() {
        open("看一看", expect: "看一看")
        goBack()
    }

    func testAsk() {
        open("问一问", expect: "问一问")
        goBack()
    }

    func testInterpreter() {
        open("翻译官", expect: "翻译官")
        goBack()
    }

    func testLearn() {
        open("学英语", expect: "学英语")
        goBack()
    }

    func testRide() {
        open("叫车", expect: "叫车")
        goBack()
    }

    /// Opens the emergency screen and its practice mode only. Nothing is dialled or texted.
    func testEmergencyPracticeOnly() {
        open("紧急", expect: "练习一下")
        tapVisible("练习一下")
        XCTAssertTrue(anyText("练习模式").waitForExistence(timeout: 5), "practice mode didn't open")
        tapVisible("返回")
        XCTAssertTrue(waitUntilGone(anyText("练习模式")), "didn't leave practice mode")
        goBack()
    }

    func testEveryScreenTwiceInARow() {
        for tile in ["看一看", "问一问", "翻译官", "学英语", "叫车"] {
            open(tile, expect: tile)
            goBack()
        }
        for tile in ["学英语", "翻译官"] {
            open(tile, expect: tile)
            goBack()
        }
    }
}
