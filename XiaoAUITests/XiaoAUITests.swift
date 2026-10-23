import XCTest

/// Opens every screen she uses, in the simulator demo, with no API keys (nothing is ever sent).
/// Never taps anything that would call, text or dial 911.
final class XiaoAUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Backup for permission questions that appear while tapping.
        addUIInterruptionMonitor(withDescription: "iOS permission question") { alert in
            let deny = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Don' OR label BEGINSWITH 'Nicht' OR label CONTAINS '不允许'")).firstMatch
            if deny.exists { deny.tap(); return true }
            return false
        }
        app = XCUIApplication()
        app.launchArguments = ["-noKeys"]
        app.launch()
        dismissSystemAlerts()
        XCTAssertTrue(button("Notfall").waitForExistence(timeout: 15), "home screen didn't appear")
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
        let deadline = Date().addingTimeInterval(8)
        var scrolled = 0
        while Date() < deadline {
            if let visible = query.allElementsBoundByIndex.last(where: { $0.isHittable }) {
                visible.tap()
                return
            }
            // Longer German labels can push a button below the fold: scroll like she would.
            if scrolled < 3 {
                app.swipeUp()
                scrolled += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
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
            let deny = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Don' OR label BEGINSWITH 'Nicht' OR label CONTAINS '不允许'")).firstMatch
            if deny.exists { deny.tap() } else { alert.buttons.element(boundBy: 0).tap() }
        }
    }

    private func open(_ tile: String, expect title: String, file: StaticString = #filePath, line: UInt = #line) {
        tapVisible(tile, file: file, line: line)
        dismissSystemAlerts()
        XCTAssertTrue(button("Zurück").waitForExistence(timeout: 8), "\(tile) didn't open", file: file, line: line)
        XCTAssertTrue(anyText(title).waitForExistence(timeout: 5), "\(tile) shows no \(title)", file: file, line: line)
    }

    /// Zurück until the home screen is back (no Zurück left anywhere).
    private func goBack(file: StaticString = #filePath, line: UInt = #line) {
        tapVisible("Zurück", file: file, line: line)
        XCTAssertTrue(waitUntilGone(button("Zurück")), "didn't get back home", file: file, line: line)
        XCTAssertTrue(button("Dolmetscher").isHittable, "home screen isn't showing", file: file, line: line)
    }

    // MARK: Tests

    func testHomeShowsEveryFeature() {
        for name in ["Lesen", "Fragen", "Dolmetscher", "Fahrt", "Notfall"] {
            XCTAssertTrue(anyText(name).exists, "\(name) missing from the home screen")
        }
    }

    func testLook() {
        open("Lesen", expect: "Lesen")
        goBack()
    }

    func testAsk() {
        open("Fragen", expect: "Fragen")
        goBack()
    }

    func testInterpreter() {
        open("Dolmetscher", expect: "Gespräch")
        goBack()
    }

    func testRide() {
        open("Fahrt", expect: "Wohin möchten Sie?")
        goBack()
    }

    /// Opens the emergency screen and its practice mode only. Nothing is dialled or texted.
    func testEmergencyPracticeOnly() {
        open("Notfall", expect: "Einmal üben")
        tapVisible("Einmal üben")
        XCTAssertTrue(anyText("Übung:").waitForExistence(timeout: 5), "practice mode didn't open")
        tapVisible("Zurück")
        XCTAssertTrue(waitUntilGone(anyText("Übung:")), "didn't leave practice mode")
        goBack()
    }

    func testEveryScreenTwiceInARow() {
        for tile in ["Lesen", "Fragen", "Dolmetscher", "Fahrt"] {
            open(tile, expect: tile)
            goBack()
        }
        for tile in ["Dolmetscher", "Lesen"] {
            open(tile, expect: tile)
            goBack()
        }
    }
}
