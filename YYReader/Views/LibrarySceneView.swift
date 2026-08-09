import SwiftData
import SwiftUI

struct LibrarySceneView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("selection.bookID") private var storedBookID = ""
    @SceneStorage("selection.chapterID") private var storedChapterID = ""
    @State private var store: LibraryStore?

    var body: some View {
        Group {
            if let store {
                LibraryRootView(store: store)
                    .onChange(of: store.selectedBookID) { _, newValue in
                        storedBookID = newValue?.uuidString ?? ""
                    }
                    .onChange(of: store.selectedChapterID) { _, newValue in
                        storedChapterID = newValue?.uuidString ?? ""
                    }
            } else {
                ProgressView("正在打开书架…")
            }
        }
        .task(initializeStore)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
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
            coordinator: services.importCoordinator
        )
        newStore.restoreSelection(
            bookID: UUID(uuidString: storedBookID),
            chapterID: UUID(uuidString: storedChapterID)
        )
        store = newStore
    }
}
