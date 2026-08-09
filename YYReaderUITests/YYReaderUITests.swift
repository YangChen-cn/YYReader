import XCTest

final class YYReaderUITests: XCTestCase {
    @MainActor
    func testEmptyLibraryAndAddURLSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        if !app.windows.firstMatch.waitForExistence(timeout: 5) {
            app.typeKey("n", modifierFlags: .command)
        }

        XCTAssertTrue(app.staticTexts["书架为空"].waitForExistence(timeout: 5))
        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["添加小说网页"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["小说章节网址"].exists)
    }
}
