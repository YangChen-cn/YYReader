import SwiftUI

struct BookSidebarView: View {
    @Bindable var store: LibraryStore
    @Environment(AppServices.self) private var services
    @State private var showingUpdateDetails = false

    var body: some View {
        @Bindable var sync = services.folderSync
        List(selection: $store.selectedBookID) {
            ForEach(store.books) { book in
                BookSidebarRow(book: book)
                    .tag(book.id)
                    .contextMenu {
                                    if book.isLocalText {
                                        Button("上传正文到同步文件夹", systemImage: "icloud.and.arrow.up") {
                                            services.folderSync.uploadText(book)
                                        }
                                        .disabled(services.folderSync.isUploadingText || services.folderSync.isSyncing)
                                    }
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("书架")
        .alert("正文同步", isPresented: $sync.showingTextTransferMessage) {
            Button("好", role: .cancel) { }
        } message: {
            Text(sync.textTransferMessage ?? "")
        }
        .onChange(of: store.selectedBookID) { oldValue, newValue in
            Task { @MainActor in
                await Task.yield()
                guard store.selectedBookID == newValue else { return }
                store.reconcileBookSelection(newValue, previousID: oldValue)
            }
        }
        .overlay {
            if store.books.isEmpty {
                ContentUnavailableView(
                    "书架为空",
                    systemImage: "books.vertical",
                    description: Text("添加小说网页，或从“更多”导入本地 TXT。")
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let release = services.updates.release {
                VStack(alignment: .leading, spacing: 10) {
                    Text("发现新版本").font(.headline)
                    Button {
                        services.updates.revealBanner()
                        showingUpdateDetails = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("下载更新")
                            Spacer(minLength: 4)
                            Text(verbatim: release.version).monospacedDigit()
                        }
                        .font(.callout)
                        .frame(maxWidth: .infinity, minHeight: 20)
                    }
                    .buttonStyle(.borderedProminent)
                    .help("展开更新说明与下载")
                    .popover(isPresented: $showingUpdateDetails, arrowEdge: .leading) {
                        AppUpdateCard(updates: services.updates, canDismiss: true)
                            .frame(width: 400)
                            .padding(12)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
            }
        }
        .onChange(of: services.updates.showsBanner) { _, visible in
            if !visible { showingUpdateDetails = false }
        }
    }
}
