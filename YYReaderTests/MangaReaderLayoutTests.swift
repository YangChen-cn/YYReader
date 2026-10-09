#if os(macOS)
import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import YYReader

@MainActor
private final class MangaLayoutWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

@MainActor
struct MangaReaderLayoutTests {
    @Test func keyboardResizeAndModeChangesKeepRawPageAndBoundedRendering() async throws {
        let defaults = UserDefaults.standard
        let keys = [ReaderPreferenceKeys.mangaPageTurnMode, ReaderPreferenceKeys.mangaPageLayout,
                    ReaderPreferenceKeys.mangaFirstPageAlone, ReaderPreferenceKeys.prefetchNext]
        let original = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, original) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(ReaderPageTurnMode.horizontalPages.rawValue, forKey: keys[0])
        defaults.set(MangaPageLayout.Mode.automatic.rawValue, forKey: keys[1])
        defaults.set(true, forKey: keys[2]); defaults.set(false, forKey: keys[3])
        let directory = URL.temporaryDirectory.appending(path: "MangaLayout-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let book = try MangaPreviewFixture.seed(in: container.mainContext, directory: directory)
        let chapter = try #require(book.chapters.first(where: { $0.sortIndex == 1 }))
        chapter.topParagraphIndex = 2; chapter.readingProgress = 2.0 / 6
        let store = LibraryStore(modelContext: container.mainContext, coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:])))
        store.selectBook(book.id)
        let cache = MangaImageCache(directory: directory)
        let window = MangaLayoutWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                                       styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MangaReaderView(store: store, chapter: chapter, imageCache: cache))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        #expect(chapter.topParagraphIndex == 2)
        #expect(await cache.cachedThumbnailCount == 2)
        #expect(window.firstResponder is ReaderKeyboardEventView)
        window.sendEvent(try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124)))
        try await Task.sleep(for: .milliseconds(100))
        #expect(chapter.topParagraphIndex == 3) // A whole spread forward.
        window.setContentSize(NSSize(width: 650, height: 850))
        try await Task.sleep(for: .milliseconds(100))
        #expect(chapter.topParagraphIndex == 3)
        #expect(chapter.readingProgress == 3.0 / 6)
        defaults.set(MangaPageLayout.Mode.double.rawValue, forKey: keys[1])
        try await Task.sleep(for: .milliseconds(100))
        #expect(chapter.topParagraphIndex == 3)
        // A late callback from the old chapter must not change current selection.
        store.goToNextChapter()
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.selectedChapter?.sortIndex == 2)
    }
}
#endif
