import SwiftUI

struct MobileReaderView: View {
    let store: LibraryStore
    let showLibrary: () -> Void
    let showCatalog: () -> Void
    @AppStorage(ReaderPreferenceKeys.presentationMode) private var mode = ReaderPresentationMode.normal.rawValue
    @AppStorage(ReaderPreferenceKeys.pageTurnMode) private var pageTurnMode = ReaderPageTurnMode.verticalScroll.rawValue
    @State private var showingSettings = false
    @State private var controlsVisible = false
    @State private var chapterLoadTask: Task<Void, Never>?

    private var usesPages: Bool {
        pageTurnMode == ReaderPageTurnMode.horizontalPages.rawValue && (mode == ReaderPresentationMode.normal.rawValue || store.selectedChapter?.isManga == true)
    }

    var body: some View {
        GeometryReader { geometry in
            ReaderView(store: store, keyboardNavigationEnabled: false, showsPagingControls: controlsVisible,
                       loadsChapterAutomatically: false)
                .simultaneousGesture(SpatialTapGesture().onEnded { value in
                    guard usesPages, value.location.x > geometry.size.width * 0.3,
                          value.location.x < geometry.size.width * 0.7 else { return }
                    controlsVisible.toggle()
                })
                .accessibilityAction(named: "显示阅读选项") { controlsVisible = true }
        }
            .navigationTitle(store.selectedChapter?.title ?? "阅读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(usesPages && !controlsVisible ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("书架", systemImage: "books.vertical", action: showLibrary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu("阅读选项", systemImage: "ellipsis.circle") {
                        Section("阅读") {
                            Button("目录", systemImage: "list.bullet", action: showCatalog)
                            Button("阅读设置", systemImage: "textformat.size") { showingSettings = true }
                        }
                        Section("加载与更新") {
                            Button("重试加载", systemImage: "arrow.clockwise") {
                                Task { await store.ensureSelectedChapterLoaded() }
                            }
                            .disabled(store.isLoading)
                            Button("刷新目录", systemImage: "arrow.clockwise", action: store.startRefreshSelectedCatalog)
                                .disabled(!store.canRefreshSelectedCatalog || store.isLoading)
                        }
                        Section("离线阅读") {
                            Button("缓存当前章", systemImage: "arrow.down.circle", action: store.downloadCurrentChapter)
                                .disabled(!store.canDownloadCurrentChapter)
                            Button("缓存后续章节", systemImage: "arrow.down.to.line", action: store.downloadFollowingChapters)
                                .disabled(!store.canDownloadCurrentChapter)
                            Button("缓存全书", systemImage: "books.vertical", action: store.downloadEntireBook)
                                .disabled(!store.canDownloadEntireBook)
                            Button("清除正文缓存", systemImage: "trash", role: .destructive, action: store.deleteOfflineCache)
                                .disabled(!store.canDeleteOfflineCache)
                        }
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
            .sheet(isPresented: $showingSettings, onDismiss: { controlsVisible = false }) { MobileSettingsView() }
            .onChange(of: pageTurnMode) { _, _ in
                controlsVisible = false
                loadCurrentChapter()
            }
            .onChange(of: store.selectedChapterID) { _, _ in loadCurrentChapter() }
            .onChange(of: store.offlineDownloads.completedCount) { _, _ in
                if let chapter = store.selectedChapter, chapter.isAvailableOffline,
                   !store.readerSession.entries.contains(where: { $0.id == chapter.id }) {
                    loadCurrentChapter()
                }
            }
            .onAppear {
                store.beginReaderPresentation()
                loadCurrentChapter()
            }
            .onDisappear {
                chapterLoadTask?.cancel()
                store.flushPendingProgress()
                store.endReaderPresentation()
            }
    }

    private func loadCurrentChapter() {
        chapterLoadTask?.cancel()
        let chapterID = store.selectedChapterID
        if usesPages { store.configureContinuousReading(false) }
        // Keep foreground loading outside the conditional spinner and page
        // views, whose lifetimes change when navigation chrome is hidden.
        chapterLoadTask = Task {
            await store.ensureSelectedChapterLoaded()
            guard !Task.isCancelled, store.selectedChapterID == chapterID else { return }
            // Continuous scrolling commits the visible chapter while the reader
            // window keeps the previous one attached; rebuilding the session here
            // would drop that content and leave the viewport in the middle of the
            // chapter the reader just scrolled into.
            store.prepareContinuousReadingIfNeeded()
        }
    }
}
