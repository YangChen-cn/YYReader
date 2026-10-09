import SwiftData
import SwiftUI

struct MobileLibrarySceneView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppServices.self) private var services
    @AppStorage(ReaderPreferenceKeys.lastReadingBookID) private var bookID = ""
    @AppStorage(ReaderPreferenceKeys.lastReadingChapterID) private var chapterID = ""
    @State private var store: LibraryStore?

    var body: some View {
        Group {
            if let store {
                MobileLibraryView(store: store)
                    .onChange(of: store.selectedBookID) { _, id in bookID = id?.uuidString ?? "" }
                    .onChange(of: store.selectedChapterID) { _, id in chapterID = id?.uuidString ?? "" }
            } else {
                ProgressView("正在打开书架…")
            }
        }
        .task {
            guard store == nil else { return }
            #if DEBUG
            let uncachedTest = ProcessInfo.processInfo.arguments.contains("--ui-testing")
                && ProcessInfo.processInfo.arguments.contains("--ui-testing-uncached")
            let coordinator = uncachedTest ? NovelImportCoordinator(loader: MobileUncachedTestLoader()) : services.importCoordinator
            #else
            let coordinator = services.importCoordinator
            #endif
            let library = LibraryStore(
                modelContext: modelContext,
                coordinator: coordinator,
                folderSync: services.folderSync
            )
            library.restoreSelection(bookID: UUID(uuidString: bookID), chapterID: UUID(uuidString: chapterID))
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
               !ProcessInfo.processInfo.arguments.contains("--ui-testing-empty") {
                do {
                    let largeCatalog = ProcessInfo.processInfo.arguments.contains("--ui-testing-large-catalog")
                    let sample = largeCatalog || ProcessInfo.processInfo.arguments.contains("--ui-testing-pagination")
                        ? MobileSampleContent.paginationText : MobileSampleContent.text
                    let draft = try LocalTextImportService.prepareImport(data: Data(sample.utf8), fileName: "山间来信")
                    let book = try library.importLocalText(draft, title: "山间来信", author: "预览作者")
                    if uncachedTest {
                        book.catalogURL = "https://example.invalid/late/"
                        for chapter in book.chapters {
                            chapter.sourceURL = "\(book.catalogURL)\(chapter.sortIndex).html"
                            if chapter.sortIndex != 1 {
                                chapter.replaceBodyText(nil)
                                chapter.cachedAt = chapter.sortIndex == 3 ? .now : nil
                            }
                        }
                        try modelContext.save()
                        if let offline = book.chapters.first(where: { $0.sortIndex == 3 }) {
                            let result = ChapterLoadResult(title: offline.title, bookTitle: nil, author: nil,
                                catalogURL: nil, chapterURL: URL(string: offline.sourceURL)!, bodyText: "磁盘缓存正文：这章已下载，打开时直接从本机读取。",
                                previousChapterURL: nil, nextChapterURL: nil)
                            try await OfflineChapterPersistence(modelContainer: modelContext.container)
                                .persist(result, chapterID: offline.id, cachedAt: .now)
                        }
                    }
                    if largeCatalog {
                        for chapter in book.chapters where chapter.sortIndex != 1 {
                            chapter.replaceBodyText(nil)
                            chapter.cachedAt = nil
                        }
                        let additional = (3...5000).map { index in
                            Chapter(sourceURL: "\(draft.sourceBookURL)/chapter/\(index)", title: "第\(index)章 目录占位", sortIndex: index)
                        }
                        for chapter in additional { modelContext.insert(chapter) }
                        book.chapters += additional
                        try modelContext.save()
                    }
                    library.selectBook(nil)
                } catch {
                    library.presentedError = PresentedError(message: error.localizedDescription)
                }
            }
            #endif
            store = library
            services.folderSync.attach(to: library)
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--preview-url"), arguments.indices.contains(index + 1) {
                library.startImportURL(arguments[index + 1])
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                services.folderSync.appBecameActive()
            } else {
                store?.flushPendingProgress()
            }
        }
        .onDisappear { store?.flushPendingProgress() }
    }
}
