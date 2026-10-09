import SwiftUI
import UniformTypeIdentifiers

struct MobileLibraryView: View {
    @Bindable var store: LibraryStore
    @Environment(AppServices.self) private var services
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var navigationID = UUID()
    @State private var isReading = false
    @State private var showingURL = false
    @State private var pendingURL: String?
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
            .id(navigationID)
            .overlay {
                if textImport.isWorking {
                    LoadingOverlay(message: "正在读取 TXT…", onCancel: textImport.cancel)
                } else if store.isLoading, store.canCancelLoading {
                    LoadingOverlay(message: store.loadingMessage, onCancel: store.cancelLoading)
                }
            }
            .sheet(isPresented: $showingURL, onDismiss: submitPendingURL) {
                AddURLSheet { pendingURL = $0 }
            }
            .sheet(isPresented: $showingSettings) { MobileSettingsView() }
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
            .onChange(of: store.selectedBookID) { _, _ in
                isReading = false
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

    private var navigation: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            List(selection: bookSelection) {
                if !store.books.isEmpty {
                    Text("\(store.books.count) 本藏书 · 轻点打开，长按管理")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(store.books) { book in
                    NavigationLink(value: book.id) {
                        MobileBookCardView(book: book)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 8))
                    .contextMenu {
                        Button("编辑信息", systemImage: "pencil") {
                            store.selectBook(book.id)
                            showingMetadata = true
                        }
                        Button("删除", systemImage: "trash", role: .destructive) {
                            store.selectBook(book.id)
                            confirmingDelete = true
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .overlay {
                if store.books.isEmpty {
                    MobileEmptyBookshelfView(addWeb: { showingURL = true }, importText: { chooseFile(text: true) },
                                            importBookshelf: { chooseFile(text: false) })
                }
            }
            .navigationTitle("书架")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
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
        } content: {
            MobileChapterListView(store: store, openChapter: openChapter)
        } detail: {
            if isReading {
                MobileReaderView(store: store, showLibrary: showLibrary, showCatalog: showCatalog)
            } else {
                ContentUnavailableView {
                    Label("开始阅读", systemImage: "text.book.closed")
                } description: {
                    Text("选择小说和章节，或继续上次阅读。")
                } actions: {
                    if let id = store.selectedChapterID {
                        Button("继续阅读") {
                            store.requestReaderScroll(.restore)
                            openChapter(id)
                        }
                    }
                }
            }
        }
    }

    private var bookSelection: Binding<UUID?> {
        Binding(get: { store.selectedBookID }, set: { store.selectBook($0) })
    }

    private var verificationBinding: Binding<VerificationRequest?> {
        @Bindable var verification = services.verificationStore
        return $verification.request
    }

    private func openChapter(_ id: UUID) {
        guard store.selectedChapterID == id else { return }
        store.beginReaderPresentation()
        isReading = true
        compactColumn = .detail
        columns = .detailOnly
    }

    private func showLibrary() {
        guard store.flushPendingProgress() else { return }
        if sizeClass == .compact { store.selectBook(nil) }
        isReading = false
        store.resetContinuousReaderWindow()
        store.endReaderPresentation()
        compactColumn = .sidebar
        columns = .all
        // Recreate the compact navigation host when returning to its root.
        // Otherwise an active detail stack can leave iPhone on the catalog
        // despite preferredCompactColumn being reset to sidebar.
        if sizeClass == .compact { navigationID = UUID() }
    }

    private func showCatalog() {
        guard store.flushPendingProgress() else { return }
        columns = .all
        compactColumn = .content
        if sizeClass == .compact {
            isReading = false
            store.resetContinuousReaderWindow()
            store.endReaderPresentation()
            navigationID = UUID()
        }
    }

    private func chooseFile(text: Bool) {
        importingText = text
        showingFile = true
    }

    private func submitPendingURL() {
        guard let pendingURL else { return }
        self.pendingURL = nil
        store.startImportURL(pendingURL)
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
