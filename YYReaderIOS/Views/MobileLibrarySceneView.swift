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
            let library = LibraryStore(
                modelContext: modelContext,
                coordinator: services.importCoordinator,
                folderSync: services.folderSync
            )
            library.restoreSelection(bookID: UUID(uuidString: bookID), chapterID: UUID(uuidString: chapterID))
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                do {
                    let sample = ProcessInfo.processInfo.arguments.contains("--ui-testing-pagination")
                        ? MobileSampleContent.paginationText : MobileSampleContent.text
                    let draft = try LocalTextImportService.prepareImport(data: Data(sample.utf8), fileName: "山间来信")
                    try library.importLocalText(draft, title: "山间来信", author: "预览作者")
                    library.selectBook(nil)
                } catch {
                    library.presentedError = PresentedError(message: error.localizedDescription)
                }
            }
            #endif
            store = library
            services.folderSync.attach(to: library)
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
