import SwiftUI

struct LibraryRootView: View {
    @Bindable var store: LibraryStore
    @State private var showingAddURL = false
    @State private var showingAppearance = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationSplitView {
            BookSidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } content: {
            ChapterListView(store: store)
                .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 380)
        } detail: {
            ReaderView(store: store)
                .inspector(isPresented: $showingAppearance) {
                    AppearanceInspectorView()
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
                }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("添加网页", systemImage: "plus", action: showAddURL)
                    .disabled(store.isLoading)
                Button("刷新目录", systemImage: "arrow.clockwise", action: refreshCatalog)
                    .disabled(store.selectedBook == nil || store.isLoading)
                Button("删除小说", systemImage: "trash", action: confirmDelete)
                    .disabled(store.selectedBook == nil)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("上一章", systemImage: "chevron.left", action: store.goToPreviousChapter)
                    .disabled(store.selectedChapter == nil)
                Button("下一章", systemImage: "chevron.right", action: store.goToNextChapter)
                    .disabled(store.selectedChapter == nil)
                Button("阅读外观", systemImage: "textformat.size", action: toggleAppearance)
            }
        }
        .overlay {
            if store.isLoading {
                if store.canCancelLoading {
                    LoadingOverlay(message: store.loadingMessage) {
                        store.cancelLoading()
                    }
                } else {
                    LoadingOverlay(message: store.loadingMessage, onCancel: nil)
                }
            }
        }
        .sheet(isPresented: $showingAddURL) {
            AddURLSheet(onSubmit: store.startImportURL)
        }
        .alert(item: $store.presentedError) { error in
            Alert(title: Text("操作失败"), message: Text(error.message), dismissButton: .default(Text("好")))
        }
        .confirmationDialog("确定删除这本小说及其离线缓存吗？", isPresented: $confirmingDelete) {
            Button("删除", role: .destructive, action: store.deleteSelectedBook)
        }
        .focusedSceneValue(\.readerCommandActions, ReaderCommandActions(
            addURL: showAddURL,
            refreshCatalog: refreshCatalog,
            previousChapter: store.goToPreviousChapter,
            nextChapter: store.goToNextChapter,
            toggleAppearance: toggleAppearance
        ))
    }

    private func showAddURL() { showingAddURL = true }
    private func confirmDelete() { confirmingDelete = true }
    private func toggleAppearance() { showingAppearance.toggle() }
    private func refreshCatalog() { Task { await store.refreshSelectedCatalog() } }
}
