import XCTest

final class MobileReaderUITests: XCTestCase {
    @MainActor
    func testRelaunchStartsOnBookshelfAndKeepsBookChapter() {
        continueAfterFailure = false
        let app = launchLibrary(extraArguments: ["--ui-testing-relaunch"])
        XCTAssertTrue(app.buttons["ios.addMenu"].waitForExistence(timeout: 10))
        app.staticTexts["山间来信"].firstMatch.tap()
        let chapter = app.buttons["ios.chapter.2"]
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        chapter.tap()
        XCTAssertTrue(app.buttons["ios.readerMenu"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["ios.addMenu"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["ios.continueReading"].exists)
        app.staticTexts["山间来信"].firstMatch.tap()
        let current = app.buttons["ios.continueReading"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertTrue(current.staticTexts["第2章 石桥"].exists)
    }

    @MainActor
    func testSystemDarkAndPaperThemeStayConsistentAcrossNavigation() {
        continueAfterFailure = false
        // The single test simulator is configured to system Dark by the test command.
        for (arguments, expected) in [([String](), "dark"), (["--ui-testing-theme-sepia"], "light")] {
            let app = launchLibrary(extraArguments: arguments)
            let scene = app.descendants(matching: .any)["ios.libraryScene"]
            XCTAssertTrue(app.buttons["ios.addMenu"].waitForExistence(timeout: 10))
            expectation(for: NSPredicate(format: "value == %@", expected), evaluatedWith: scene)
            waitForExpectations(timeout: 5)
            app.staticTexts["山间来信"].firstMatch.tap()
            XCTAssertTrue(app.buttons["ios.continueReading"].waitForExistence(timeout: 5))
            XCTAssertEqual(scene.value as? String, expected)
            app.buttons["ios.chapter.1"].tap()
            XCTAssertTrue(app.buttons["ios.readerMenu"].waitForExistence(timeout: 5))
            XCTAssertEqual(scene.value as? String, expected)
            app.buttons["书架"].tap()
            XCTAssertTrue(app.buttons["ios.addMenu"].waitForExistence(timeout: 5))
            XCTAssertEqual(scene.value as? String, expected)
            app.terminate()
        }
    }

    @MainActor
    func testEmptyBookshelfHasUsefulActions() {
        let app = launchLibrary(extraArguments: ["--ui-testing-empty"])
        let empty = app.descendants(matching: .any)["ios.emptyBookshelf"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["导入 TXT"].exists)
        XCTAssertTrue(app.buttons["导入已有书架"].exists)
        app.buttons["添加小说网址"].tap()
        XCTAssertTrue(app.textFields["chapterURL"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
    }

    @MainActor
    func testPageModesSwipeReflowAndChapterBoundary() {
        continueAfterFailure = false
        let app = launchLibrary(extraArguments: ["--ui-testing-pagination"])
        let book = app.staticTexts["山间来信"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["预览作者"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["可离线阅读"].firstMatch.exists)
        book.tap()
        let chapter = app.buttons.containing(.staticText, identifier: "第1章 清晨").firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 10))
        chapter.tap()
        openSettings(app)
        app.buttons["左右翻页"].tap()
        app.buttons["完成"].tap()
        let pager = app.scrollViews["ios.pagedReader"]
        XCTAssertTrue(pager.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["ios.readerMenu"].exists)
        XCTAssertFalse(app.buttons["ios.nextPage"].exists)
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let count = app.staticTexts["ios.pageCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["ios.paginating"].waitForNonExistence(timeout: 10), app.debugDescription)
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
        expectation(for: NSPredicate(format: "value BEGINSWITH %@", "第1章 清晨"), evaluatedWith: pager)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.descendants(matching: .any)["ios.paginating"].waitForNonExistence(timeout: 10))
        let position = (pager.value as? String ?? "").split { !$0.isNumber }.compactMap { Int($0) }.suffix(2)
        XCTAssertEqual(position.count, 2)
        XCTAssertEqual(position.first, position.last)
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(count.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLargeCatalogPagesOnlyCachedCurrentChapter() {
        continueAfterFailure = false
        let app = launchLibrary(extraArguments: ["--ui-testing-large-catalog"])
        let book = app.staticTexts["山间来信"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.tap()
        let current = app.buttons["ios.continueReading"]
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        current.tap()
        openSettings(app)
        app.buttons["左右翻页"].tap()
        app.buttons["完成"].tap()
        let pager = app.scrollViews["ios.pagedReader"]
        XCTAssertTrue(pager.waitForExistence(timeout: 10))
        let loading = app.descendants(matching: .any)["ios.paginating"]
        XCTAssertTrue(loading.waitForNonExistence(timeout: 5))
        for _ in 0..<3 {
            pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(loading.waitForNonExistence(timeout: 5))
            XCTAssertTrue((pager.value as? String)?.hasPrefix("第1章 清晨") == true)
        }
        openSettings(app)
        app.buttons["上下滚动"].tap()
        app.buttons["完成"].tap()
        openSettings(app)
        app.buttons["左右翻页"].tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        XCTAssertTrue(loading.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testPagedReaderLoadsUncachedAndDiskCachedChaptersWithoutChangingMode() {
        continueAfterFailure = false
        let app = launchLibrary(extraArguments: ["--ui-testing-uncached"])
        let book = app.staticTexts["山间来信"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.tap()
        let next = app.buttons["ios.chapter.2"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        let pager = app.scrollViews["ios.pagedReader"]
        XCTAssertTrue(pager.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["reader.preparingChapter"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["ios.paginating"].waitForNonExistence(timeout: 5))
        XCTAssertTrue((pager.value as? String)?.hasPrefix("第2章 石桥") == true)
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["ios.readerMenu"].tap()
        app.buttons["目录"].tap()
        let offline = app.buttons["ios.chapter.3"]
        XCTAssertTrue(offline.waitForExistence(timeout: 5))
        offline.tap()
        XCTAssertTrue(pager.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["reader.preparingChapter"].waitForNonExistence(timeout: 5))
        XCTAssertTrue((pager.value as? String)?.hasPrefix("第3章 书店") == true)
        XCTAssertTrue(app.staticTexts["ios.page.paragraph.0"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ios.page.paragraph.0"].firstMatch.label.contains("磁盘缓存正文"))
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
        if !menu.waitForExistence(timeout: 3) {
            app.scrollViews["ios.pagedReader"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
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
