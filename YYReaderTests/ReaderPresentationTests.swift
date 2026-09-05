import AppKit
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import YYReader

struct ReaderPresentationTests {
    @Test
    func academicModeShortcutRoundTripsAndRejectsInvalidKeys() throws {
        let shortcut = try #require(ReaderKeyboardShortcut(
            key: "K",
            usesControl: true,
            usesOption: false,
            usesShift: true,
            usesCommand: true
        ))

        #expect(shortcut.storageValue == "k|control,shift,command")
        #expect(shortcut.displayName == "⌃⇧⌘K")
        #expect(ReaderKeyboardShortcut(storageValue: shortcut.storageValue) == shortcut)
        #expect(ReaderKeyboardShortcut(key: "ab", usesControl: true, usesOption: true, usesShift: false, usesCommand: false) == nil)
        #expect(ReaderKeyboardShortcut(key: "\n", usesControl: true, usesOption: true, usesShift: false, usesCommand: false) == nil)
    }

    @Test
    func paragraphFormatterAddsTwoCharacterIndentOnlyWhenNeeded() {
        #expect(
            ReaderParagraphFormatter.format("第一段正文。", usesFirstLineIndent: true)
                == "　　第一段正文。"
        )
        #expect(
            ReaderParagraphFormatter.format("　　已经缩进。", usesFirstLineIndent: true)
                == "　　已经缩进。"
        )
        #expect(
            ReaderParagraphFormatter.format("  已经留白。", usesFirstLineIndent: true)
                == "  已经留白。"
        )
        #expect(ReaderParagraphFormatter.format("", usesFirstLineIndent: true).isEmpty)
        #expect(
            ReaderParagraphFormatter.format("关闭缩进。", usesFirstLineIndent: false)
                == "关闭缩进。"
        )
    }

    @Test
    func readerPresetsUseBoundedNovelReadingValues() {
        #expect(ReaderLineSpacingPreset.compact.value == 0.30)
        #expect(ReaderLineSpacingPreset.comfortable.value == 0.40)
        #expect(ReaderLineSpacingPreset.spacious.value == 0.50)
        #expect(ReaderLineSpacingPreset.closest(to: 0.42) == .comfortable)

        #expect(ReaderContentWidthPreset.narrow.value == 38)
        #expect(ReaderContentWidthPreset.medium.value == 48)
        #expect(ReaderContentWidthPreset.wide.value == 58)
        #expect(ReaderContentWidthPreset.closest(to: 50) == .medium)
    }

    @Test
    func readerWidthUsesViewportWithoutGrowingPastPreference() {
        #expect(ReaderViewportLayout.minimumPreferredWidthEM == 20)
        #expect(ReaderViewportLayout.maximumPreferredWidthEM == 80)
        #expect(
            ReaderViewportLayout.effectiveContentWidth(
                preferredWidthEM: 38,
                fontSize: 20,
                viewportWidth: 1_500
            ) == 760
        )
        #expect(
            ReaderViewportLayout.effectiveContentWidth(
                preferredWidthEM: 38,
                fontSize: 28,
                viewportWidth: 800
            ) == 720
        )
        #expect(
            ReaderViewportLayout.effectiveContentWidth(
                preferredWidthEM: 80,
                fontSize: 36,
                viewportWidth: 2_000
            ) == 1_896
        )
    }

    @Test
    func migratesOnlyKnownReaderDefaultsOnce() throws {
        let suiteName = "ReaderPreferenceMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(680.0, forKey: ReaderPreferenceKeys.contentWidth)
        defaults.set(9.0, forKey: ReaderPreferenceKeys.lineSpacing)
        defaults.set(18.0, forKey: ReaderPreferenceKeys.paragraphSpacing)

        ReaderPreferenceMigration.migrateIfNeeded(defaults: defaults)

        #expect(defaults.double(forKey: ReaderPreferenceKeys.contentWidth) == 48)
        #expect(defaults.double(forKey: ReaderPreferenceKeys.lineSpacing) == 0.40)
        #expect(defaults.double(forKey: ReaderPreferenceKeys.paragraphSpacing) == 0.60)

        defaults.set(940.0, forKey: ReaderPreferenceKeys.contentWidth)
        ReaderPreferenceMigration.migrateIfNeeded(defaults: defaults)
        #expect(defaults.double(forKey: ReaderPreferenceKeys.contentWidth) == 940)
    }

    @Test
    func legacyIvoryThemeMigratesToRose() throws {
        let suiteName = "ReaderThemeMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("ivory", forKey: ReaderPreferenceKeys.theme)
        ReaderPreferenceMigration.migrateIfNeeded(defaults: defaults)

        #expect(defaults.string(forKey: ReaderPreferenceKeys.theme) == ReaderTheme.rose.rawValue)
        #expect(ReaderTheme.rose.title == "绯霞")
    }

    @Test
    func customReaderPreferencesArePreservedAndClamped() throws {
        let suiteName = "ReaderPreferenceCustomTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(940.0, forKey: ReaderPreferenceKeys.contentWidth)
        defaults.set(7.0, forKey: ReaderPreferenceKeys.lineSpacing)
        defaults.set(50.0, forKey: ReaderPreferenceKeys.paragraphSpacing)
        ReaderPreferenceMigration.migrateIfNeeded(defaults: defaults)

        #expect(defaults.double(forKey: ReaderPreferenceKeys.contentWidth) == 47)
        #expect(defaults.double(forKey: ReaderPreferenceKeys.lineSpacing) == 0.35)
        #expect(defaults.double(forKey: ReaderPreferenceKeys.paragraphSpacing) == 0.90)
        #expect(ReaderTheme.dark.preferredColorScheme == .dark)
        #expect(ReaderTheme.sepia.preferredColorScheme == .light)
        #expect(ReaderTheme.system.preferredColorScheme == nil)
    }

    @Test
    func readerThemesProvideReadableCompletePalettes() throws {
        #expect(ReaderTheme.allCases.count == 8)

        for theme in ReaderTheme.allCases {
            let background = try #require(NSColor(theme.background).usingColorSpace(.sRGB))
            let accent = try #require(NSColor(theme.accent).usingColorSpace(.sRGB))
            let foreground = try #require(NSColor(theme.foreground).usingColorSpace(.sRGB))
            let secondary = try #require(NSColor(theme.secondaryForeground).usingColorSpace(.sRGB))
            let tertiary = try #require(NSColor(theme.tertiaryForeground).usingColorSpace(.sRGB))
            let separator = try #require(NSColor(theme.separator).usingColorSpace(.sRGB))

            #expect(background.alphaComponent > 0)
            #expect(accent.alphaComponent > 0)
            #expect(foreground.alphaComponent > 0)
            #expect(secondary.alphaComponent > 0)
            #expect(tertiary.alphaComponent > 0)
            #expect(separator.alphaComponent > 0)
            #expect(contrastRatio(foreground, background) >= 4.5)
            #expect(contrastRatio(accent, background) >= 3.0)
        }
    }

    @Test
    func legacyThemeRawValuesRemainCompatible() {
        #expect(ReaderTheme(rawValue: "system") == .system)
        #expect(ReaderTheme(rawValue: "light") == .light)
        #expect(ReaderTheme(rawValue: "sepia") == .sepia)
        #expect(ReaderTheme(rawValue: "dark") == .dark)
        #expect(ReaderTheme(rawValue: "unknown") == nil)
    }

    @Test
    func smallArrowMovementCanRepeatAndClampsToContent() {
        let firstDown = ReaderPageScroll.destinationY(
            currentY: 100,
            viewportHeight: 800,
            contentHeight: 3_000,
            distance: ReaderPageScroll.smallStep
        )
        let secondDown = ReaderPageScroll.destinationY(
            currentY: firstDown,
            viewportHeight: 800,
            contentHeight: 3_000,
            distance: ReaderPageScroll.smallStep
        )

        #expect(firstDown == 212)
        #expect(secondDown == 324)
        #expect(
            ReaderPageScroll.destinationY(
                currentY: 40,
                viewportHeight: 800,
                contentHeight: 3_000,
                distance: -ReaderPageScroll.smallStep
            ) == 0
        )
    }

    @Test
    func pageMovementUsesViewportHeightAndKeepsTwelvePercentOverlap() {
        #expect(ReaderPageScroll.pageFraction == 0.88)
        #expect(abs(ReaderPageScroll.pageOverlap - 0.12) < 0.000_001)
        #expect(ReaderPageScroll.pageDistance(viewportHeight: 800) == 704)
        #expect(ReaderPageScroll.pageDistance(viewportHeight: 1_000) == 880)
    }

    @Test
    func leftAndRightPageMovementCanRepeatWithoutParagraphCounts() {
        let firstPage = ReaderPageScroll.pageDestinationY(
            currentY: 0,
            viewportHeight: 800,
            contentHeight: 5_000,
            direction: 1
        )
        let secondPage = ReaderPageScroll.pageDestinationY(
            currentY: firstPage,
            viewportHeight: 800,
            contentHeight: 5_000,
            direction: 1
        )
        let previousPage = ReaderPageScroll.pageDestinationY(
            currentY: secondPage,
            viewportHeight: 800,
            contentHeight: 5_000,
            direction: -1
        )

        #expect(firstPage == 704)
        #expect(secondPage == 1_408)
        #expect(previousPage == firstPage)
    }

    @Test
    func pageMovementClampsAtDocumentEdges() {
        #expect(
            ReaderPageScroll.pageDestinationY(
                currentY: 1_800,
                viewportHeight: 800,
                contentHeight: 2_000,
                direction: 1
            ) == 1_200
        )
    }

    @Test @MainActor
    func pageMovementUsesViewportFallbackBeforeScrollGeometryIsReady() {
        let state = ReaderScrollState()
        state.update(
            metrics: ReaderScrollMetrics(
                contentOffsetY: 1_000,
                viewportHeight: 0,
                contentHeight: 5_000
            )
        )

        #expect(
            state.pageDestinationY(direction: 1, fallbackViewportHeight: 800) == 1_704
        )
    }

    @Test
    func readerKeyboardCommandsResolveArrowsWithoutStealingModifiedShortcuts() {
        #expect(ReaderKeyboardCommand.resolve(keyCode: 126, modifierFlags: []) == .moveUp)
        #expect(ReaderKeyboardCommand.resolve(keyCode: 125, modifierFlags: []) == .moveDown)
        #expect(ReaderKeyboardCommand.resolve(keyCode: 123, modifierFlags: []) == .pageBackward)
        #expect(ReaderKeyboardCommand.resolve(keyCode: 124, modifierFlags: [.shift]) == .pageForward)
        #expect(ReaderKeyboardCommand.resolve(keyCode: 124, modifierFlags: [.command]) == nil)
        #expect(ReaderKeyboardCommand.resolve(keyCode: 124, modifierFlags: [.option]) == nil)
        #expect(ReaderKeyboardCommand.resolve(keyCode: 36, modifierFlags: []) == nil)
    }

    @Test @MainActor
    func readerKeyboardRoutingDefersToEditingListsAndDirectionalControls() {
        let editableTextView = NSTextView()
        editableTextView.isEditable = true
        let readOnlyTextView = NSTextView()
        readOnlyTextView.isEditable = false

        #expect(ReaderKeyboardRouting.shouldDeferToFocusedControl(editableTextView))
        #expect(!ReaderKeyboardRouting.shouldDeferToFocusedControl(readOnlyTextView))
        #expect(ReaderKeyboardRouting.shouldDeferToFocusedControl(NSTableView()))
        #expect(ReaderKeyboardRouting.shouldDeferToFocusedControl(NSSlider()))
        #expect(!ReaderKeyboardRouting.shouldDeferToFocusedControl(NSView()))
    }

    @Test @MainActor
    func readerKeyboardRoutingIgnoresHiddenOrDetachedStaleControls() {
        let window = NSWindow()
        let container = NSView()
        let table = NSTableView()
        window.contentView = container
        container.addSubview(table)

        #expect(ReaderKeyboardRouting.shouldDeferToFocusedControl(table, in: window))

        table.isHidden = true
        #expect(!ReaderKeyboardRouting.shouldDeferToFocusedControl(table, in: window))

        table.removeFromSuperview()
        #expect(!ReaderKeyboardRouting.shouldDeferToFocusedControl(table, in: window))
    }

    @Test @MainActor
    func scrollingPhasesOnlyCommitLatestVisibleTargetAfterIdle() {
        let chapterID = UUID()
        let state = ReaderScrollState()
        let first = ReaderScrollTarget.paragraph(chapterID: chapterID, index: 1)
        let second = ReaderScrollTarget.paragraph(chapterID: chapterID, index: 2)
        let final = ReaderScrollTarget.paragraph(chapterID: chapterID, index: 3)

        state.update(phase: .interacting)
        state.update(visibleTargets: [first])
        #expect(state.consumeVisibleTargetForCommit() == nil)

        state.update(visibleTargets: [second])
        state.update(phase: .decelerating)
        state.update(visibleTargets: [final])
        #expect(state.consumeVisibleTargetForCommit() == nil)

        state.update(phase: .idle)
        #expect(state.consumeVisibleTargetForCommit() == final)
        #expect(state.consumeVisibleTargetForCommit() == nil)
    }

    @Test @MainActor
    func visibleTargetsAreExplicitlyOrderedByChapterAndParagraph() {
        let firstChapterID = UUID()
        let secondChapterID = UUID()
        let state = ReaderScrollState()

        state.update(
            visibleTargets: [
                .paragraph(chapterID: secondChapterID, index: 0),
                .paragraph(chapterID: firstChapterID, index: 8),
                .paragraph(chapterID: firstChapterID, index: 3)
            ],
            chapterIndexByID: [firstChapterID: 10, secondChapterID: 11]
        )

        #expect(state.topVisibleTarget == .paragraph(chapterID: firstChapterID, index: 3))
    }

    @Test
    func restoredScrollTargetUsesSavedParagraphAndClampsToContent() {
        let chapterID = UUID()
        #expect(
            ReaderScrollTarget.restoredParagraph(chapterID: chapterID, savedIndex: 12, paragraphCount: 40)
                == .paragraph(chapterID: chapterID, index: 12)
        )
        #expect(
            ReaderScrollTarget.restoredParagraph(chapterID: chapterID, savedIndex: 99, paragraphCount: 40)
                == .paragraph(chapterID: chapterID, index: 39)
        )
    }

    @Test @MainActor
    func repeatedKeyboardCommandsCommitOnlyTheLatestVisibleRevisionAfterDebounce() async throws {
        let chapterID = UUID()
        let state = ReaderScrollState()
        let initial = ReaderScrollTarget.paragraph(chapterID: chapterID, index: 1)
        let passedDuringRepeat = ReaderScrollTarget.paragraph(chapterID: chapterID, index: 7)
        let final = ReaderScrollTarget.paragraph(chapterID: chapterID, index: 12)
        var debounceCallbacks = 0

        state.update(visibleTargets: [initial])
        state.requestDeferredCommit()
        state.scheduleDeferredCommit(after: .milliseconds(200)) {
            debounceCallbacks += 1
        }
        state.update(visibleTargets: [passedDuringRepeat])

        try await Task.sleep(for: .milliseconds(10))
        state.requestDeferredCommit()
        state.scheduleDeferredCommit(after: .milliseconds(200)) {
            debounceCallbacks += 1
        }
        state.update(visibleTargets: [final])

        #expect(!state.canFinishDeferredCommit)
        try await Task.sleep(for: .milliseconds(250))
        #expect(debounceCallbacks == 1)
        #expect(state.canFinishDeferredCommit)
        #expect(state.finishDeferredCommit() == final)
        #expect(!state.hasPendingDeferredCommit)
        #expect(state.finishDeferredCommit() == nil)
    }

    @Test @MainActor
    func deferredKeyboardCommitRequiresAVisibleTargetsRevision() {
        let chapterID = UUID()
        let state = ReaderScrollState()
        let target = ReaderScrollTarget.paragraph(chapterID: chapterID, index: 4)

        state.update(visibleTargets: [target])
        state.requestDeferredCommit()
        state.markDeferredCommitDelayElapsed()

        #expect(state.canFinishDeferredCommit)
        #expect(state.finishDeferredCommit() == nil)
        #expect(!state.hasPendingDeferredCommit)
    }

    @Test @MainActor
    func idleScrollCommitUpdatesAndPersistsLatestReadingPosition() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        let book = Book(
            title: "滚动提交测试",
            author: "测试作者",
            sourceHost: "example.com",
            catalogURL: "https://example.com/book/scroll/"
        )
        let chapter = Chapter(
            sourceURL: "https://example.com/book/scroll/1.html",
            title: "第1章",
            sortIndex: 1,
            bodyText: "第一段\n第二段\n第三段\n第四段",
            cachedAt: .now,
            book: book
        )
        book.chapters = [chapter]
        book.currentChapterID = chapter.id
        context.insert(book)
        context.insert(chapter)
        try context.save()

        let store = LibraryStore(
            modelContext: context,
            coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:]))
        )
        store.restoreSelection(bookID: book.id, chapterID: chapter.id)
        #expect(store.readerScrollRequest?.intent == .restore)
        let state = ReaderScrollState()

        state.update(phase: .interacting)
        state.update(visibleTargets: [.paragraph(chapterID: chapter.id, index: 1)])
        state.update(visibleTargets: [.paragraph(chapterID: chapter.id, index: 2)])
        #expect(state.consumeVisibleTargetForCommit() == nil)
        #expect(!context.hasChanges)

        state.update(phase: .idle)
        let target = try #require(state.consumeVisibleTargetForCommit())
        guard case let .paragraph(chapterID, index) = target else {
            Issue.record("idle 应提交当前可见段落")
            return
        }
        store.updateVisibleReaderPosition(chapterID: chapterID, paragraphIndex: index, total: 4)

        #expect(chapter.topParagraphIndex == 2)
        #expect(abs(chapter.readingProgress - (2.0 / 3.0)) < 0.000_001)
        #expect(chapter.lastReadAt != nil)
        #expect(context.hasChanges)
        #expect(store.flushPendingProgress())
        #expect(!context.hasChanges)
    }

    @Test @MainActor
    func repeatedCommandsAccumulateFromLastCommandedOffset() {
        let state = ReaderScrollState()
        state.update(metrics: ReaderScrollMetrics(contentOffsetY: 100, viewportHeight: 800, contentHeight: 5_000))

        #expect(state.pageDestinationY(direction: 1) == 804)
        #expect(state.pageDestinationY(direction: 1) == 1_508)
        #expect(state.destinationY(distance: ReaderPageScroll.smallStep) == 1_620)
    }

    @Test @MainActor
    func pixelCommandReplacesTheOldViewIdentityAndReleasesAfterScrolling() {
        let chapterID = UUID()
        var position = ScrollPosition(id: ReaderScrollTarget.chapterHeader(chapterID), anchor: .top)
        #expect(position.viewID(type: ReaderScrollTarget.self) == .chapterHeader(chapterID))

        position = ScrollPosition(idType: ReaderScrollTarget.self, y: 640)
        #expect(position.viewID(type: ReaderScrollTarget.self) == nil)

        position.isPositionedByUser = true
        #expect(position.isPositionedByUser)
        #expect(position.point == nil)
    }

    @Test @MainActor
    func continuousReaderParagraphCacheInvalidatesUpdatedContent() {
        let book = Book(
            title: "长时间连续阅读",
            author: "测试作者",
            sourceHost: "example.com",
            catalogURL: "https://example.com/book/long-session/"
        )
        let chapter = Chapter(
            sourceURL: "https://example.com/book/long-session/1.html",
            title: "第1章",
            sortIndex: 0,
            bodyText: "第一段\n\n第二段",
            cachedAt: .now,
            book: book
        )
        let session = ContinuousReaderSession()
        session.reset(around: chapter)
        #expect(session.entries.first?.paragraphs == ["第一段", "第二段"])

        chapter.replaceBodyText("更新后的第一段\n\n更新后的第二段")
        #expect(session.entries.first?.paragraphs == ["更新后的第一段", "更新后的第二段"])
    }

    @Test @MainActor
    func continuousReaderParagraphCacheEvictsLeastRecentlyUsedChapters() {
        let session = ContinuousReaderSession(paragraphCacheCapacity: 5)
        let chapters = (0..<8).map { index in
            Chapter(
                sourceURL: "https://example.com/cache/\(index)",
                title: "第\(index)章",
                sortIndex: index,
                bodyText: "正文 \(index)",
                cachedAt: .now
            )
        }

        for chapter in chapters {
            _ = session.paragraphs(for: chapter)
        }

        #expect(session.cachedParagraphChapterCount == 5)
    }

    @Test
    func persistentReaderSelectionTakesPriorityOverSceneRestoration() {
        let persistedBookID = UUID()
        let persistedChapterID = UUID()
        let sceneBookID = UUID()
        let sceneChapterID = UUID()

        let selection = ReaderSelectionRestoration.selection(
            persistedBookID: persistedBookID.uuidString,
            persistedChapterID: persistedChapterID.uuidString,
            sceneBookID: sceneBookID.uuidString,
            sceneChapterID: sceneChapterID.uuidString
        )

        #expect(selection.bookID == persistedBookID)
        #expect(selection.chapterID == persistedChapterID)
    }

    @Test
    func sceneSelectionRemainsFallbackWhenNoPersistentReadingSelectionExists() {
        let sceneBookID = UUID()
        let sceneChapterID = UUID()

        let selection = ReaderSelectionRestoration.selection(
            persistedBookID: "",
            persistedChapterID: "",
            sceneBookID: sceneBookID.uuidString,
            sceneChapterID: sceneChapterID.uuidString
        )

        #expect(selection.bookID == sceneBookID)
        #expect(selection.chapterID == sceneChapterID)
    }

    @Test
    func visibilityGateCommitsOnlyOneAdjacentChapterPerScrollTransaction() {
        let chapters = (0..<4).map { _ in UUID() }
        var gate = ContinuousReaderVisibilityGate()

        gate.beginTransaction()
        let indexes = Dictionary(uniqueKeysWithValues: chapters.enumerated().map { ($0.element, $0.offset) })
        #expect(gate.accepts(candidateID: chapters[1], currentID: chapters[0], chapterIndexByID: indexes))
        gate.recordCommit()
        #expect(!gate.accepts(candidateID: chapters[2], currentID: chapters[1], chapterIndexByID: indexes))

        gate.beginTransaction()
        #expect(gate.accepts(candidateID: chapters[2], currentID: chapters[1], chapterIndexByID: indexes))
    }

    @Test @MainActor
    func continuousReadingPreservesAllChaptersAndParagraphsInAcademicModeEvenWithMissingBookRelationship() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext

        let book = Book(
            title: "连续阅读论文模式测试",
            author: "测试作者",
            sourceHost: "example.com",
            catalogURL: "https://example.com/book/academic-continuous/"
        )
        context.insert(book)

        let chapterA = Chapter(
            sourceURL: "https://example.com/book/academic-continuous/1.html",
            title: "第1章 开启",
            sortIndex: 0,
            bodyText: "第一章第一段内容。\n\n第一章第二段内容。\n\n第一章第三段内容。",
            cachedAt: .now,
            book: nil
        )
        let chapterB = Chapter(
            sourceURL: "https://example.com/book/academic-continuous/2.html",
            title: "第2章 进展",
            sortIndex: 1,
            bodyText: "第二章第一段内容。\n\n第二章第二段内容。",
            cachedAt: .now,
            book: nil
        )
        let chapterC = Chapter(
            sourceURL: "https://example.com/book/academic-continuous/3.html",
            title: "第3章 结论",
            sortIndex: 2,
            bodyText: "第三章第一段内容。\n\n第三章第二段内容。\n\n第三章第三段内容。\n\n第三章第四段内容。",
            cachedAt: .now,
            book: book
        )

        context.insert(chapterA)
        context.insert(chapterB)
        context.insert(chapterC)

        book.chapters = [chapterA, chapterB, chapterC]
        // Explicitly simulate broken inverse relationship on A and B
        chapterA.book = nil
        chapterB.book = nil
        #expect(chapterA.book == nil)
        #expect(chapterB.book == nil)
        #expect(chapterC.book != nil)

        // Set up ContinuousReaderSession and attach A, B, C
        let session = ContinuousReaderSession()
        session.reset(around: chapterA)
        session.attachNext(chapterB)
        session.attachNext(chapterC)

        // Attempting duplicate attach must not duplicate entries
        session.attachNext(chapterB)
        session.attachNext(chapterC)

        #expect(session.entries.count == 3)
        #expect(session.entries.map(\.chapter.id) == [chapterA.id, chapterB.id, chapterC.id])

        // Normal mode paragraphs
        let normalParagraphsA = session.entries[0].paragraphs
        let normalParagraphsB = session.entries[1].paragraphs
        let normalParagraphsC = session.entries[2].paragraphs
        #expect(normalParagraphsA.count == 3)
        #expect(normalParagraphsB.count == 2)
        #expect(normalParagraphsC.count == 4)

        // Normal mode paragraph anchors
        let normalTargetsA = normalParagraphsA.indices.map {
            ReaderScrollTarget.paragraph(chapterID: chapterA.id, index: $0)
        }
        let normalTargetsB = normalParagraphsB.indices.map {
            ReaderScrollTarget.paragraph(chapterID: chapterB.id, index: $0)
        }
        let normalTargetsC = normalParagraphsC.indices.map {
            ReaderScrollTarget.paragraph(chapterID: chapterC.id, index: $0)
        }

        // Academic paper presentation:
        // Even when chapter.book == nil, plan is successfully generated using bookIdentity
        let planCache = AcademicPaperPlanCache()
        let bookIdentity = book.sourceBookURL
        let chapterIndexByID: [UUID: Int] = [chapterA.id: 0, chapterB.id: 1, chapterC.id: 2]

        let planA = planCache.plan(
            bookIdentity: bookIdentity,
            chapter: session.entries[0].chapter,
            position: chapterIndexByID[chapterA.id] ?? 0,
            paragraphs: normalParagraphsA
        )
        let planB = planCache.plan(
            bookIdentity: bookIdentity,
            chapter: session.entries[1].chapter,
            position: chapterIndexByID[chapterB.id] ?? 0,
            paragraphs: normalParagraphsB
        )
        let planC = planCache.plan(
            bookIdentity: bookIdentity,
            chapter: session.entries[2].chapter,
            position: chapterIndexByID[chapterC.id] ?? 0,
            paragraphs: normalParagraphsC
        )

        // All 3 chapters have full text and all enter academic presentation
        #expect(planA.paragraphs.count == normalParagraphsA.count)
        #expect(planB.paragraphs.count == normalParagraphsB.count)
        #expect(planC.paragraphs.count == normalParagraphsC.count)

        #expect(planA.paragraphs.map(\.text) == normalParagraphsA)
        #expect(planB.paragraphs.map(\.text) == normalParagraphsB)
        #expect(planC.paragraphs.map(\.text) == normalParagraphsC)

        // Academic paragraph anchors match normal targets 1:1
        let academicTargetsA = planA.paragraphs.map {
            ReaderScrollTarget.paragraph(chapterID: chapterA.id, index: $0.index)
        }
        let academicTargetsB = planB.paragraphs.map {
            ReaderScrollTarget.paragraph(chapterID: chapterB.id, index: $0.index)
        }
        let academicTargetsC = planC.paragraphs.map {
            ReaderScrollTarget.paragraph(chapterID: chapterC.id, index: $0.index)
        }

        #expect(academicTargetsA == normalTargetsA)
        #expect(academicTargetsB == normalTargetsB)
        #expect(academicTargetsC == normalTargetsC)

        // Normal -> Academic -> Normal: session paragraphs are identical
        #expect(session.entries[0].paragraphs == normalParagraphsA)
        #expect(session.entries[1].paragraphs == normalParagraphsB)
        #expect(session.entries[2].paragraphs == normalParagraphsC)
        #expect(session.entries.count == 3)

        // Verify data relationship self-healing for chapters belonging to book with chapter.book == nil
        let chaptersToRepair = [chapterA, chapterB, chapterC]
        for chapter in chaptersToRepair where chapter.book == nil {
            chapter.book = book
        }
        #expect(chapterA.book === book)
        #expect(chapterB.book === book)
        #expect(chapterC.book === book)
    }

    @Test @MainActor
    func materializesChapterBodyWhenAttachedCachedChapterHasZeroParagraphs() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext

        let chapterURL = try #require(URL(string: "https://example.com/book/materialize/1.html"))
        let p1 = "这是用于测试正文恢复与重新构建的完整段落之一，确保达到通用解析器的六十字符长度门槛。"
        let p2 = "这是第二段测试正文内容，同样包含足够多的汉字字符以保证解析器正确提取全部有效段落文本。"
        let html = "<html><head><title>第1章</title></head><body><div id=\"content\"><p>\(p1)</p><p>\(p2)</p></div></body></html>"
        let loader = MockHTMLLoader(documents: [
            chapterURL: html
        ])

        let book = Book(
            title: "正文恢复测试",
            author: "测试作者",
            sourceHost: "example.com",
            catalogURL: "https://example.com/book/materialize/"
        )
        context.insert(book)

        let chapter = Chapter(
            sourceURL: chapterURL.absoluteString,
            title: "第1章",
            sortIndex: 0,
            bodyText: "",
            book: book
        )
        context.insert(chapter)
        book.chapters = [chapter]

        let store = LibraryStore(
            modelContext: context,
            coordinator: NovelImportCoordinator(loader: loader)
        )
        store.selectBook(book.id)

        #expect(chapter.paragraphs.isEmpty)
        #expect(!chapter.isCached)

        await store.materializeChapterBody(chapter)

        #expect(chapter.isCached)
        #expect(chapter.paragraphs.count == 2)
        #expect(chapter.paragraphs == [p1, p2])

        store.readerSession.reset(around: chapter)
        #expect(store.readerSession.entries.first?.paragraphs == [p1, p2])
    }

    @Test
    @MainActor
    func chapterParagraphCacheDoesNotCacheEmptyParagraphsPermanently() {
        let cache = ChapterParagraphCache(capacity: 4)
        let chapter = Chapter(
            sourceURL: "https://example.com/chapter2",
            title: "第二章",
            sortIndex: 2,
            bodyText: nil,
            cachedAt: .now
        )

        let initial = cache.paragraphs(for: chapter)
        #expect(initial.isEmpty)

        chapter.replaceBodyText("新加载正文段落")
        let updated = cache.paragraphs(for: chapter)
        #expect(updated == ["新加载正文段落"])
    }

    private func contrastRatio(_ first: NSColor, _ second: NSColor) -> Double {
        let lighter = max(relativeLuminance(first), relativeLuminance(second))
        let darker = min(relativeLuminance(first), relativeLuminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: NSColor) -> Double {
        func linearized(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearized(color.redComponent)
            + 0.7152 * linearized(color.greenComponent)
            + 0.0722 * linearized(color.blueComponent)
    }

}
