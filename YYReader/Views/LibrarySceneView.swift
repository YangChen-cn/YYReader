import SwiftData
import SwiftUI

struct LibrarySceneView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("selection.bookID") private var storedBookID = ""
    @SceneStorage("selection.chapterID") private var storedChapterID = ""
    @AppStorage(ReaderPreferenceKeys.lastReadingBookID) private var persistedBookID = ""
    @AppStorage(ReaderPreferenceKeys.lastReadingChapterID) private var persistedChapterID = ""
    @State private var store: LibraryStore?

    var body: some View {
        Group {
            if let store {
                LibraryRootView(store: store)
                    .onChange(of: store.selectedBookID) { _, newValue in
                        storedBookID = newValue?.uuidString ?? ""
                        persistedBookID = storedBookID
                    }
                    .onChange(of: store.selectedChapterID) { _, newValue in
                        storedChapterID = newValue?.uuidString ?? ""
                        persistedChapterID = storedChapterID
                    }
            } else {
                ProgressView("正在打开书架…")
            }
        }
        .task(initializeStore)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                services.folderSync.appBecameActive()
            } else {
                store?.flushPendingProgress()
            }
        }
        .onDisappear {
            store?.flushPendingProgress()
        }
        .sheet(item: verificationRequestBinding) { request in
            WebVerificationSheet(request: request, store: services.verificationStore)
        }
    }

    private var verificationRequestBinding: Binding<VerificationRequest?> {
        @Bindable var verificationStore = services.verificationStore
        return $verificationStore.request
    }

    private func initializeStore() async {
        guard store == nil else { return }
        let newStore = LibraryStore(
            modelContext: modelContext,
            coordinator: services.importCoordinator,
            folderSync: services.folderSync
        )
        services.folderSync.attach(to: newStore)
        let selection = ReaderSelectionRestoration.selection(
            persistedBookID: persistedBookID,
            persistedChapterID: persistedChapterID,
            sceneBookID: storedBookID,
            sceneChapterID: storedChapterID
        )
        newStore.restoreSelection(bookID: selection.bookID, chapterID: selection.chapterID)
        storedBookID = newStore.selectedBookID?.uuidString ?? ""
        storedChapterID = newStore.selectedChapterID?.uuidString ?? ""
        persistedBookID = storedBookID
        persistedChapterID = storedChapterID
        store = newStore
    }
}
