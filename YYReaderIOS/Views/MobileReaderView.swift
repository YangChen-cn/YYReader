import SwiftUI

struct MobileReaderView: View {
    let store: LibraryStore
    let showLibrary: () -> Void
    let showCatalog: () -> Void
    @AppStorage(ReaderPreferenceKeys.theme) private var themeName = ReaderTheme.system.rawValue
    @AppStorage(ReaderPreferenceKeys.presentationMode) private var mode = ReaderPresentationMode.normal.rawValue
    @State private var showingSettings = false

    var body: some View {
        ReaderView(store: store, keyboardNavigationEnabled: false)
            .navigationTitle(store.selectedChapter?.title ?? "阅读")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(mode == ReaderPresentationMode.academicPaper.rawValue
                                  ? .light : ReaderTheme(rawValue: themeName)?.preferredColorScheme)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("书架", systemImage: "books.vertical", action: showLibrary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu("阅读选项", systemImage: "ellipsis.circle") {
                        Button("目录", systemImage: "list.bullet", action: showCatalog)
                        Button("阅读设置", systemImage: "textformat.size") { showingSettings = true }
                        Button("重试加载", systemImage: "arrow.clockwise") {
                            Task { await store.ensureSelectedChapterLoaded() }
                        }
                        .disabled(store.isLoading)
                        Button("刷新目录", systemImage: "arrow.clockwise", action: store.startRefreshSelectedCatalog)
                            .disabled(!store.canRefreshSelectedCatalog || store.isLoading)
                        Button("缓存当前章", systemImage: "arrow.down.circle", action: store.downloadCurrentChapter)
                            .disabled(!store.canDownloadCurrentChapter)
                        Button("缓存后续章节", systemImage: "arrow.down.to.line", action: store.downloadFollowingChapters)
                            .disabled(!store.canDownloadCurrentChapter)
                        Button("缓存全书", systemImage: "books.vertical", action: store.downloadEntireBook)
                            .disabled(!store.canDownloadEntireBook)
                        Button("清除正文缓存", systemImage: "trash", role: .destructive, action: store.deleteOfflineCache)
                            .disabled(!store.canDeleteOfflineCache)
                    }
                    .accessibilityIdentifier("ios.readerMenu")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if store.offlineDownloads.isDownloading || store.offlineDownloads.failureMessage != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.offlineDownloads.failureMessage ?? store.offlineDownloads.progressMessage)
                            .font(.caption)
                        if store.offlineDownloads.isDownloading {
                            Button("取消下载", action: store.cancelOfflineDownload)
                        } else {
                            Button("关闭状态", action: store.offlineDownloads.dismissFailure)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
                }
            }
            .sheet(isPresented: $showingSettings) { MobileSettingsView() }
            .onAppear { store.beginReaderPresentation() }
            .onDisappear {
                store.flushPendingProgress()
                store.endReaderPresentation()
            }
    }
}
