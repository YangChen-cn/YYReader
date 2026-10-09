import XCTest

final class MobileReaderUITests: XCTestCase {
    @MainActor
    func testPageModesSwipeReflowAndChapterBoundary() {
        let app = launchLibrary(extraArguments: ["--ui-testing-pagination"])
        let book = app.staticTexts["山间来信"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.tap()
        let chapter = app.buttons.containing(.staticText, identifier: "第1章 清晨").firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 10))
        chapter.tap()
        openSettings(app)
        app.buttons["左右翻页"].tap()
        app.buttons["完成"].tap()
        let pager = app.scrollViews["ios.pagedReader"]
        XCTAssertTrue(pager.waitForExistence(timeout: 10))
        let count = app.staticTexts["ios.pageCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label MATCHES %@", "第 1 / ([2-9]|[1-9][0-9]+) 页"), evaluatedWith: count)
        waitForExpectations(timeout: 10)
        let firstPage = count.label
        pager.swipeLeft()
        waitForLabelChange(count, from: firstPage)
        pager.swipeRight()
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        let restored = NSPredicate(format: "label == %@", firstPage)
        expectation(for: restored, evaluatedWith: count)
        waitForExpectations(timeout: 5)
        app.buttons["ios.nextPage"].tap()
        waitForLabelChange(count, from: firstPage)
        openSettings(app)
        app.sliders["字号"].adjust(toNormalizedSliderPosition: 0.8)
        app.buttons["完成"].tap()
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        openSettings(app)
        app.buttons["上下滚动"].tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(pager.waitForNonExistence(timeout: 5))

        // A short second chapter has a single page: the first swipe right crosses
        // the chapter boundary and must leave the reader usable on chapter one.
        app.buttons["ios.readerMenu"].tap()
        app.buttons["目录"].tap()
        app.buttons.containing(.staticText, identifier: "第2章 石桥").firstMatch.tap()
        openSettings(app)
        app.buttons["左右翻页"].tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.swipeRight()
        XCTAssertTrue(app.navigationBars["第1章 清晨"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["ios.paginating"].waitForNonExistence(timeout: 10))
        let lastPageCount = count.label.split { !$0.isNumber }.compactMap { Int($0) }
        XCTAssertEqual(lastPageCount.count, 2)
        XCTAssertEqual(lastPageCount.first, lastPageCount.last)
    }

    @MainActor
    func testOfflineBookNavigatesToReaderAndSettings() {
        let app = launchLibrary()
        let book = app.staticTexts["山间来信"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.tap()
        let chapter = app.buttons.containing(.staticText, identifier: "第1章 清晨").firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        chapter.tap()
        let readerMenu = app.buttons["ios.readerMenu"]
        XCTAssertTrue(readerMenu.waitForExistence(timeout: 5))
        readerMenu.tap()
        app.buttons["阅读设置"].tap()
        let continuous = app.switches["连续阅读"]
        XCTAssertTrue(continuous.waitForExistence(timeout: 5))
        continuous.tap()
        app.buttons["完成"].tap()
        app.buttons["书架"].tap()
        XCTAssertTrue(app.buttons["ios.addMenu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["山间来信"].firstMatch.exists)
    }

    @MainActor
    func testUnsupportedURLShowsRecoverableError() {
        let app = launchLibrary()
        let menu = app.buttons["ios.addMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        app.buttons["添加网页"].tap()
        let input = app.textFields["chapterURL"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("unsupported://example.invalid/chapter")
        app.buttons["添加"].tap()
        let error = app.alerts["操作失败"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        error.buttons["好"].tap()
        XCTAssertTrue(app.staticTexts["山间来信"].firstMatch.exists)
    }

    @MainActor
    private func launchLibrary(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        let menu = app.buttons["ios.readerMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["阅读设置"].tap()
        XCTAssertTrue(app.segmentedControls["ios.pageTurnMode"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func waitForLabelChange(_ element: XCUIElement, from label: String) {
        expectation(for: NSPredicate(format: "label != %@", label), evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }
}
