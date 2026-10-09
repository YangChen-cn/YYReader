import SwiftUI

struct LibraryRootView: View {
    @Bindable var store: LibraryStore
    @AppStorage(ReaderPreferenceKeys.theme) private var themeName = ReaderTheme.system.rawValue
    @AppStorage(ReaderPreferenceKeys.presentationMode) private var presentationModeName = ReaderPresentationMode.normal.rawValue
    @AppStorage(ReaderPreferenceKeys.mangaPageTurnMode) private var mangaPageTurnMode = ReaderPageTurnMode.mangaDefault.rawValue
    @State private var libraryColumnVisibility: NavigationSplitViewVisibility = .all
    @State private var readerColumnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var isReading = false
    @State private var showingAddURL = false
    @State private var pendingURL: String?
    @State private var pendingContentType = BookContentType.auto
    @State private var showingAppearancePopover = false
    @State private var showingAppearanceInspector = false
    @State private var showingDownloadProgress = false
    @State private var confirmingDelete = false
    @State private var bookshelfTransfer = BookshelfTransferController()
    @State private var localTextImport = LocalTextImportController()
    @State private var showingMetadataEditor = false

    var body: some View {
        Group {
            if isReading {
                readerNavigation
            } else {
                libraryNavigation
            }
        }
        .frame(minWidth: isReadingMangaVertically ? 600 : 900, minHeight: 600)
        .background { MangaWindowWidthBridge(enabled: isReadingMangaVertically).allowsHitTesting(false) }
        .onChange(of: store.selectedBookID) { _, id in
            if id == nil && isReading { showLibrary() }
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            if isReading {
                ReaderToolbar(
                    showingAppearancePopover: $showingAppearancePopover,
                    showingDownloadProgress: $showingDownloadProgress,
                    canManageBook: store.selectedBook != nil,
                    isAcademicMode: isAcademicMode,
                    isManga: store.selectedChapter?.isManga == true,
                    canRefreshCatalog: store.canRefreshSelectedCatalog,
                    canDownloadEntireBook: store.canDownloadEntireBook,
                    canDownloadCurrentChapter: store.canDownloadCurrentChapter,
                    canDeleteOfflineCache: store.canDeleteOfflineCache,
                    isLoading: store.isLoading || localTextImport.isWorking,
                    returnToLibrary: showLibrary,
                    showAdvancedAppearance: showAdvancedAppearance,
                    toggleAcademicMode: toggleAcademicMode,
                    addURL: showAddURL,
                    importLocalText: localTextImport.chooseFile,
                    editBookMetadata: { showingMetadataEditor = true },
                    refreshCatalog: refreshCatalog,
                    downloadCurrentChapter: store.downloadCurrentChapter,
                    downloadFollowingChapters: store.downloadFollowingChapters,
                    downloadEntireBook: store.downloadEntireBook,
                    cancelDownload: store.cancelOfflineDownload,
                    deleteOfflineCache: store.deleteOfflineCache,
                    isDownloading: store.offlineDownloads.isDownloading,
                    hasDownloadStatus: store.offlineDownloads.isDownloading || store.offlineDownloads.failureMessage != nil,
                    downloads: store.offlineDownloads,
                    deleteBook: confirmDelete
                )
            } else {
                LibraryToolbar(
                    showingDownloadProgress: $showingDownloadProgress,
                    canContinueReading: store.selectedChapter != nil,
                    canRefreshCatalog: store.canRefreshSelectedCatalog,
                    canDeleteBook: store.selectedBook != nil,
                    canDownloadEntireBook: store.canDownloadEntireBook,
                    canDownloadCurrentChapter: store.canDownloadCurrentChapter,
                    canDeleteOfflineCache: store.canDeleteOfflineCache,
                    isLoading: store.isLoading || bookshelfTransfer.isWorking || localTextImport.isWorking,
                    isDownloading: store.offlineDownloads.isDownloading,
                    hasDownloadStatus: store.offlineDownloads.isDownloading
                        || store.offlineDownloads.failureMessage != nil,
                    downloads: store.offlineDownloads,
                    toggleBookSidebar: toggleBookSidebar,
                    addURL: showAddURL,
                    importLocalText: localTextImport.chooseFile,
                    continueReading: continueReading,
                    refreshCatalog: refreshCatalog,
                    downloadCurrentChapter: store.downloadCurrentChapter,
                    downloadFollowingChapters: store.downloadFollowingChapters,
                    downloadEntireBook: store.downloadEntireBook,
                    cancelDownload: store.cancelOfflineDownload,
                    deleteOfflineCache: store.deleteOfflineCache,
                    deleteBook: confirmDelete,
                    importBookshelf: importBookshelf,
                    importBookshelfFromClipboard: importBookshelfFromClipboard,
                    copyBookshelfExport: copyBookshelfExport,
                    exportBookshelf: exportBookshelf,
                    editBookMetadata: { showingMetadataEditor = true }
                )
            }
        }
        .overlay {
            if localTextImport.isWorking {
                LoadingOverlay(message: "正在读取并识别 TXT…", onCancel: localTextImport.cancel)
            } else if store.isLoading, store.canCancelLoading || !isReading {
                if store.canCancelLoading {
                    LoadingOverlay(message: store.loadingMessage) {
                        store.cancelLoading()
                    }
                } else {
                    LoadingOverlay(message: store.loadingMessage, onCancel: nil)
                }
            }
        }
        .sheet(isPresented: $showingAddURL, onDismiss: submitPendingURL) {
            AddURLSheet { url, type in pendingURL = url; pendingContentType = type }
        }
        .sheet(item: $bookshelfTransfer.pendingImport) { pendingImport in
            BookshelfTransferPreviewSheet(
                pendingImport: pendingImport,
                confirmImport: confirmBookshelfImport
            )
        }
        .sheet(item: $localTextImport.pendingDraft) { draft in
            LocalTextImportSheet(
                draft: draft,
                confirm: { title, author in
                    confirmLocalTextImport(draft, title: title, author: author)
                },
                cancel: { localTextImport.pendingDraft = nil }
            )
        }
        .sheet(isPresented: $showingMetadataEditor) {
            if let book = store.selectedBook {
                BookMetadataEditorSheet(
                    book: book,
                    confirm: { title, author in
                        store.updateSelectedBookMetadata(title: title, author: author)
                        showingMetadataEditor = false
                    },
                    cancel: { showingMetadataEditor = false }
                )
            }
        }
        .alert(item: $store.presentedError) { error in
            Alert(title: Text("操作失败"), message: Text(error.message), dismissButton: .default(Text("好")))
        }
        .alert(item: $bookshelfTransfer.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("好"))
            )
        }
        .alert("导入 TXT 失败", isPresented: Binding(
            get: { localTextImport.errorMessage != nil },
            set: { if !$0 { localTextImport.errorMessage = nil } }
        )) {
            Button("好") { localTextImport.errorMessage = nil }
        } message: {
            Text(localTextImport.errorMessage ?? "未知错误")
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
        .preferredColorScheme(isReading ? (isAcademicMode ? .light : readerTheme.preferredColorScheme) : nil)
        .focusedSceneValue(\.readerCommandActions, ReaderCommandActions(
            canAddURL: !store.isLoading,
            canRefreshCatalog: store.canRefreshSelectedCatalog && !store.isLoading,
            canNavigatePreviousChapter: isReading && store.chapterNavigationSnapshot.hasPrevious && !store.isLoading,
            canNavigateNextChapter: isReading && store.chapterNavigationSnapshot.hasNext && !store.isLoading,
            canToggleCatalog: isReading,
            canChangeAppearance: isReading,
            canToggleAcademicMode: isReading,
            addURL: showAddURL,
            refreshCatalog: refreshCatalog,
            previousChapter: store.goToPreviousChapter,
            nextChapter: store.goToNextChapter,
            toggleCatalog: toggleCatalog,
            toggleAppearance: toggleAppearance,
            toggleAcademicMode: toggleAcademicMode
        ))
    }

    private var isReadingMangaVertically: Bool {
        isReading && store.selectedChapter?.isManga == true
            && mangaPageTurnMode == ReaderPageTurnMode.verticalScroll.rawValue
    }

    private func showAddURL() { showingAddURL = true }

    private func submitPendingURL() {
        guard let pendingURL else { return }
        self.pendingURL = nil
        store.startImportURL(pendingURL, contentType: pendingContentType)
    }
    private func confirmDelete() { confirmingDelete = true }
    private func importBookshelf() { bookshelfTransfer.chooseImportFile(for: store) }
    private func importBookshelfFromClipboard() { bookshelfTransfer.importFromClipboard(for: store) }
    private func confirmBookshelfImport() { bookshelfTransfer.confirmPendingImport(for: store) }
    private func copyBookshelfExport() { bookshelfTransfer.copyExportJSON(from: store) }
    private func exportBookshelf() { bookshelfTransfer.exportToFile(from: store) }
    private func confirmLocalTextImport(_ draft: LocalTextImportDraft, title: String, author: String) {
        do {
            try store.importLocalText(draft, title: title, author: author)
            localTextImport.pendingDraft = nil
        } catch {
            localTextImport.errorMessage = error.localizedDescription
        }
    }
    private var readerTheme: ReaderTheme { ReaderTheme(rawValue: themeName) ?? .system }
    private var isAcademicMode: Bool {
        presentationModeName == ReaderPresentationMode.academicPaper.rawValue
    }

    private func toggleAcademicMode() {
        presentationModeName = isAcademicMode
            ? ReaderPresentationMode.normal.rawValue
            : ReaderPresentationMode.academicPaper.rawValue
    }

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
        store.beginReaderPresentation()
        readerColumnVisibility = .detailOnly
        isReading = true
    }
    private func showLibrary() {
        store.flushPendingProgress()
        store.resetContinuousReaderWindow()
        libraryColumnVisibility = .all
        isReading = false
        store.endReaderPresentation()
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
        ReaderView(store: store, keyboardNavigationEnabled: isReading)
            .inspector(isPresented: $showingAppearanceInspector) {
                AppearanceInspectorView(dismiss: hideAdvancedAppearance)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
            }
    }

    private func hideAdvancedAppearance() {
        showingAppearanceInspector = false
    }
}
