import XCTest

final class TreehouseUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor
    func testDemoChatReplyNotesAndFiles() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["channel-general"].waitForExistence(timeout: 15))
        capture("01-channels")
        app.buttons["channel-general"].tap()
        XCTAssertTrue(app.textFields["messageInput"].waitForExistence(timeout: 5))
        capture("02-chat")
        app.buttons["thread-1"].tap()
        let reply = app.textFields["messageInput"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        reply.tap(); reply.typeText("A reply from iPhone")
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.staticTexts["A reply from iPhone"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let input = app.textFields["messageInput"]
        input.tap(); input.typeText("Hello from the iPhone simulator")
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.staticTexts["Hello from the iPhone simulator"].waitForExistence(timeout: 5))
        app.swipeDown()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Notes"].tap()
        XCTAssertTrue(app.buttons["note-1"].waitForExistence(timeout: 5))
        capture("03-notes")
        app.buttons["note-1"].tap()
        XCTAssertTrue(app.staticTexts["A shared little space"].waitForExistence(timeout: 5))
        capture("04-page")
        app.navigationBars.buttons["Edit"].tap()
        let editor = app.textViews["noteBody"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap(); editor.typeText("\nA new little idea.")
        app.buttons["saveNote"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "A new little idea.")).firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Files"].tap()
        XCTAssertTrue(app.buttons["file-1"].waitForExistence(timeout: 5))
        capture("05-files")
        app.buttons["file-2"].tap()
        XCTAssertTrue(app.buttons["Share or save file"].waitForExistence(timeout: 5))
        capture("06-file-preview")
    }
    @MainActor
    func testSignOutReturnsToWelcome() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["Leave demo"].waitForExistence(timeout: 10))
        app.buttons["Leave demo"].tap()
        XCTAssertTrue(app.secureTextFields["personalKey"].waitForExistence(timeout: 5))
        capture("00-welcome")
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
