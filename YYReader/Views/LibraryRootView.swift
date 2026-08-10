import SwiftUI

struct LibraryRootView: View {
    @Bindable var store: LibraryStore
    @AppStorage(ReaderPreferenceKeys.theme) private var themeName = ReaderTheme.system.rawValue
    @State private var libraryColumnVisibility: NavigationSplitViewVisibility = .all
    @State private var readerColumnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var isReading = false
    @State private var showingAddURL = false
    @State private var showingAppearancePopover = false
    @State private var showingAppearanceInspector = false
    @State private var showingDownloadProgress = false
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if isReading {
                readerNavigation
            } else {
                libraryNavigation
            }
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            if isReading {
                ReaderToolbar(
                    showingAppearancePopover: $showingAppearancePopover,
                    showingDownloadProgress: $showingDownloadProgress,
                    canManageBook: store.selectedBook != nil,
                    canRefreshCatalog: store.canRefreshSelectedCatalog,
                    isLoading: store.isLoading,
                    returnToLibrary: showLibrary,
                    showAdvancedAppearance: showAdvancedAppearance,
                    addURL: showAddURL,
                    refreshCatalog: refreshCatalog,
                    downloadCurrentChapter: store.downloadCurrentChapter,
                    downloadFollowingChapters: store.downloadFollowingChapters,
                    downloadEntireBook: store.downloadEntireBook,
                    cancelDownload: store.cancelOfflineDownload,
                    deleteOfflineCache: store.deleteOfflineCache,
                    canDownloadEntireBook: store.canDownloadEntireBook,
                    isDownloading: store.offlineDownloads.isDownloading,
                    hasDownloadStatus: store.offlineDownloads.isDownloading || store.offlineDownloads.failureMessage != nil,
                    downloads: store.offlineDownloads,
                    deleteBook: confirmDelete
                )
            } else {
                LibraryToolbar(
                    canContinueReading: store.selectedChapter != nil,
                    isLoading: store.isLoading,
                    toggleBookSidebar: toggleBookSidebar,
                    addURL: showAddURL,
                    continueReading: continueReading
                )
            }
        }
        .overlay {
            if store.isLoading, store.canCancelLoading || !isReading {
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
        .onChange(of: store.offlineDownloads.isDownloading) { _, isDownloading in
            if !isDownloading {
                showingDownloadProgress = false
            }
        }
        .confirmationDialog("确定删除这本小说及其离线缓存吗？", isPresented: $confirmingDelete) {
            Button("删除", role: .destructive, action: deleteSelectedBook)
        }
        .onChange(of: store.books.isEmpty) { _, isEmpty in
            if isEmpty { showLibrary() }
        }
        .preferredColorScheme(isReading ? readerTheme.preferredColorScheme : nil)
        .focusedSceneValue(\.readerCommandActions, ReaderCommandActions(
            canAddURL: !store.isLoading,
            canRefreshCatalog: store.canRefreshSelectedCatalog && !store.isLoading,
            canNavigatePreviousChapter: isReading && store.chapterNavigationSnapshot.hasPrevious && !store.isLoading,
            canNavigateNextChapter: isReading && store.chapterNavigationSnapshot.hasNext && !store.isLoading,
            canToggleCatalog: isReading,
            canChangeAppearance: isReading,
            addURL: showAddURL,
            refreshCatalog: refreshCatalog,
            previousChapter: store.goToPreviousChapter,
            nextChapter: store.goToNextChapter,
            toggleCatalog: toggleCatalog,
            toggleAppearance: toggleAppearance
        ))
    }

    private func showAddURL() { showingAddURL = true }
    private func confirmDelete() { confirmingDelete = true }
    private var readerTheme: ReaderTheme { ReaderTheme(rawValue: themeName) ?? .system }

    private func continueReading() {
        store.requestReaderScroll(.restore)
        enterReader()
    }

    private func activateChapter(_ chapterID: UUID) {
        store.selectChapter(chapterID, scrollIntent: .chapterTop)
        enterReader()
    }

    private func enterReader() {
        guard store.selectedChapter != nil else { return }
        readerColumnVisibility = .detailOnly
        isReading = true
    }
    private func showLibrary() {
        store.flushPendingProgress()
        store.resetContinuousReaderWindow()
        libraryColumnVisibility = .all
        isReading = false
        showingAppearancePopover = false
        showingAppearanceInspector = false
        showingDownloadProgress = false
    }
    private func deleteSelectedBook() {
        let wasReading = isReading
        if store.deleteSelectedBook(), wasReading {
            showLibrary()
        }
    }
    private func toggleCatalog() {
        guard isReading else { return }
        readerColumnVisibility = readerColumnVisibility == .detailOnly ? .all : .detailOnly
    }
    private func toggleBookSidebar() {
        guard !isReading else { return }
        libraryColumnVisibility = libraryColumnVisibility == .all ? .doubleColumn : .all
    }
    private func toggleAppearance() {
        guard isReading else { return }
        if showingAppearanceInspector {
            showingAppearanceInspector = false
        } else {
            showingAppearancePopover.toggle()
        }
    }
    private func showAdvancedAppearance() {
        showingAppearancePopover = false
        showingAppearanceInspector = true
    }
    private func refreshCatalog() { store.startRefreshSelectedCatalog() }

    private var libraryNavigation: some View {
        NavigationSplitView(columnVisibility: $libraryColumnVisibility) {
            BookSidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } content: {
            ChapterListView(
                store: store,
                selectionScrollIntent: nil,
                isCatalogVisible: true,
                activateChapter: activateChapter
            )
                .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 380)
        } detail: {
            readerDetail
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var readerNavigation: some View {
        NavigationSplitView(columnVisibility: $readerColumnVisibility) {
            ChapterListView(
                store: store,
                selectionScrollIntent: .chapterTop,
                isCatalogVisible: readerColumnVisibility != .detailOnly,
                activateChapter: activateChapter
            )
                .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 380)
        } detail: {
            readerDetail
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var readerDetail: some View {
        ReaderView(store: store)
            .inspector(isPresented: $showingAppearanceInspector) {
                AppearanceInspectorView()
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
            }
    }
}
