import SwiftUI
import UniformTypeIdentifiers

struct MobileLibraryView: View {
    @Bindable var store: LibraryStore
    @Environment(AppServices.self) private var services
    private enum Destination: Hashable { case reader }
    @State private var path: [Destination] = []
    @State private var showingCatalog = false
    @State private var readingBookID: UUID?
    @State private var showingURL = false
    @State private var pendingURL: String?
    @State private var pendingContentType = BookContentType.auto
    @State private var showingSettings = false
    @State private var showingFile = false
    @State private var importingText = true
    @State private var showingExport = false
    @State private var exportDocument: BookshelfFileDocument?
    @State private var confirmingDelete = false
    @State private var showingMetadata = false
    @State private var transfer = BookshelfTransferController()
    @State private var textImport = LocalTextImportController()
    @State private var activeNotice: BookshelfTransferNotice?

    var body: some View {
        navigation
            .overlay {
                if textImport.isWorking {
                    LoadingOverlay(message: "正在读取 TXT…", onCancel: textImport.cancel)
                } else if store.isLoading, store.canCancelLoading {
                    LoadingOverlay(message: store.loadingMessage, onCancel: store.cancelLoading)
                }
            }
            .sheet(isPresented: $showingURL, onDismiss: submitPendingURL) {
                AddURLSheet { url, type in pendingURL = url; pendingContentType = type }
            }
            .sheet(isPresented: $showingSettings) { MobileSettingsView() }
            .sheet(isPresented: $showingCatalog) {
                NavigationStack {
                    MobileChapterListView(store: store, openChapter: openChapter)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { showingCatalog = false }
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $transfer.pendingImport) { pending in
                BookshelfTransferPreviewSheet(pendingImport: pending) {
                    transfer.confirmPendingImport(for: store)
                }
            }
            .sheet(item: $textImport.pendingDraft) { draft in
                LocalTextImportSheet(draft: draft, confirm: { title, author in
                    do {
                        try store.importLocalText(draft, title: title, author: author)
                        textImport.pendingDraft = nil
                    } catch {
                        textImport.errorMessage = error.localizedDescription
                    }
                }, cancel: { textImport.pendingDraft = nil })
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showingMetadata) {
                if let book = store.selectedBook {
                    BookMetadataEditorSheet(book: book, confirm: { title, author in
                        store.updateSelectedBookMetadata(title: title, author: author)
                        showingMetadata = false
                    }, cancel: { showingMetadata = false })
                }
            }
            .sheet(item: verificationBinding) { request in
                WebVerificationSheet(request: request, store: services.verificationStore)
            }
            .fileImporter(isPresented: $showingFile, allowedContentTypes: importingText
                          ? [.plainText] : [BookshelfFileDocument.contentType, .json]) { result in
                switch result {
                case .success(let url): importFile(url)
                case .failure(let error): store.presentedError = PresentedError(message: error.localizedDescription)
                }
            }
            .fileExporter(isPresented: $showingExport, document: exportDocument,
                          contentType: BookshelfFileDocument.contentType,
                          defaultFilename: "YYReader-Bookshelf") { result in
                if case .failure(let error) = result {
                    store.presentedError = PresentedError(message: error.localizedDescription)
                }
            }
            .alert(item: $activeNotice) { notice in
                Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("好")))
            }
            .onChange(of: store.presentedError?.id, initial: true) { _, _ in
                guard let error = store.presentedError else { return }
                activeNotice = BookshelfTransferNotice(title: "操作失败", message: error.message)
                store.presentedError = nil
            }
            .onChange(of: transfer.notice?.id, initial: true) { _, _ in
                guard let notice = transfer.notice else { return }
                activeNotice = notice
                transfer.notice = nil
            }
            .onChange(of: textImport.errorMessage, initial: true) { _, message in
                guard let message else { return }
                activeNotice = BookshelfTransferNotice(title: "导入 TXT 失败", message: message)
                textImport.errorMessage = nil
            }
            .confirmationDialog("删除小说及其离线缓存？", isPresented: $confirmingDelete) {
                Button("删除", role: .destructive) {
                    if store.deleteSelectedBook() { showLibrary() }
                }
            }
            .onChange(of: store.selectedBookID) { _, id in
                // The bookshelf action already opened this book's reader or
                // catalog. Its deferred selection notification must not close it.
                if id == readingBookID { return }
                path.removeAll()
                showingCatalog = false
                readingBookID = nil
                store.endReaderPresentation()
            }
            .onOpenURL { url in
                if url.isFileURL {
                    importingText = url.pathExtension.lowercased() == "txt"
                    importFile(url)
                } else if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    store.startImportURL(url.absoluteString)
                }
            }
    }

    private var isReading: Bool { path.last == .reader }

    private var navigation: some View {
        NavigationStack(path: $path) {
            MobileBookshelfView(
                store: store,
                openBook: openBook,
                editBook: { id in store.selectBook(id); showingMetadata = true },
                deleteBook: { id in store.selectBook(id); confirmingDelete = true },
                addWeb: { showingURL = true },
                importText: { chooseFile(text: true) },
                importBookshelf: { chooseFile(text: false) }
            )
            .toolbar {
                if !isReading {
                    if services.updates.hasCollapsedUpdate {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("查看更新", systemImage: "app.badge", action: services.updates.revealBanner)
                                .labelStyle(.iconOnly)
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu("添加", systemImage: "plus") {
                            Section("添加小说") {
                                Button("添加网页", systemImage: "link") { showingURL = true }
                                Button("导入 TXT", systemImage: "doc.text") { chooseFile(text: true) }
                            }
                            Section("书架传输") {
                                Button("导入书架文件", systemImage: "square.and.arrow.down") { chooseFile(text: false) }
                                Button("从剪贴板导入书架", systemImage: "doc.on.clipboard") { transfer.importFromClipboard(for: store) }
                                Button("导出书架文件", systemImage: "square.and.arrow.up", action: exportBookshelf)
                                Button("复制书架 JSON", systemImage: "doc.on.doc") { transfer.copyExportJSON(from: store) }
                            }
                        }
                        .labelStyle(.titleAndIcon)
                        .disabled(store.isLoading || transfer.isWorking || textImport.isWorking)
                        .accessibilityIdentifier("ios.addMenu")
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("设置", systemImage: "gearshape") { showingSettings = true }
                            .accessibilityIdentifier("ios.settings")
                    }
                }
            }
            .navigationDestination(for: Destination.self) { _ in
                MobileReaderView(store: store, showLibrary: showLibrary, showCatalog: showCatalog)
                    .navigationBarBackButtonHidden(true)
            }
        }
    }

    private var verificationBinding: Binding<VerificationRequest?> {
        @Bindable var verification = services.verificationStore
        return $verification.request
    }

    private func openChapter(_ id: UUID) {
        guard store.selectedChapterID == id else { return }
        store.beginReaderPresentation()
        readingBookID = store.selectedBookID
        showingCatalog = false
        if !isReading { path = [.reader] }
    }

    private func openBook(_ id: UUID) {
        guard !(isReading && readingBookID == id) else { return }
        if store.selectedBookID != id { store.selectBook(id) }
        guard store.selectedBookID == id else { return }
        readingBookID = id
        guard let chapterID = store.selectedChapterID else {
            showingCatalog = true
            return
        }
        store.requestReaderScroll(.restore)
        openChapter(chapterID)
    }

    private func showLibrary() {
        guard store.flushPendingProgress() else { return }
        path.removeAll()
        showingCatalog = false
        readingBookID = nil
        store.resetContinuousReaderWindow()
        store.endReaderPresentation()
    }

    private func showCatalog() {
        guard store.flushPendingProgress() else { return }
        showingCatalog = true
    }

    private func chooseFile(text: Bool) {
        importingText = text
        showingFile = true
    }

    private func submitPendingURL() {
        guard let pendingURL else { return }
        self.pendingURL = nil
        store.startImportURL(pendingURL, contentType: pendingContentType)
    }

    private func importFile(_ url: URL) {
        if importingText { textImport.loadFile(url) }
        else { transfer.loadImport(from: url, for: store) }
    }

    private func exportBookshelf() {
        guard store.flushPendingProgress() else { return }
        exportDocument = BookshelfFileDocument(document: store.bookshelfTransferDocument())
        showingExport = true
    }
}
