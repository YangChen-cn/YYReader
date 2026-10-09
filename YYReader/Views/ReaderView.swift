import SwiftUI

struct ReaderView: View {
    @Bindable var store: LibraryStore
    let keyboardNavigationEnabled: Bool
    var showsPagingControls = true
    var loadsChapterAutomatically = true
    var togglePagingControls: () -> Void = {}
    @AppStorage(ReaderPreferenceKeys.theme) private var themeName = ReaderTheme.system.rawValue
    @AppStorage(ReaderPreferenceKeys.presentationMode) private var presentationModeName = ReaderPresentationMode.normal.rawValue
    @AppStorage(ReaderPreferenceKeys.pageTurnMode) private var pageTurnMode = ReaderPageTurnMode.verticalScroll.rawValue

    var body: some View {
        let theme = ReaderTheme(rawValue: themeName) ?? .system
        let isAcademic = presentationModeName == ReaderPresentationMode.academicPaper.rawValue
        #if os(iOS)
        // A load completing also replaces the prepared session. Observe that
        // transition even when SwiftData's body fault has not notified this view.
        let chapter = store.readerSession.entries.first { $0.id == store.selectedChapterID }?.chapter
            ?? store.selectedChapter
        #else
        let chapter = store.selectedChapter
        #endif

        ZStack {
            (isAcademic ? Color(white: 0.88) : theme.background)
                .ignoresSafeArea()

            Group {
                if let chapter, chapter.isCached {
                    if chapter.isManga {
                        MangaReaderView(store: store, chapter: chapter, showsControls: showsPagingControls,
                                        keyboardNavigationEnabled: keyboardNavigationEnabled, toggleControls: togglePagingControls)
                            .id(chapter.id)
                    } else {
                    #if os(iOS)
                    if pageTurnMode == ReaderPageTurnMode.horizontalPages.rawValue && !isAcademic {
                        MobilePagedReaderView(store: store, chapter: chapter, showsControls: showsPagingControls, toggleControls: togglePagingControls)
                            .id(chapter.id)
                    } else {
                        ReaderContentView(store: store, keyboardNavigationEnabled: keyboardNavigationEnabled)
                    }
                    #else
                    ReaderContentView(
                        store: store,
                        keyboardNavigationEnabled: keyboardNavigationEnabled
                    )
                    #endif
                    }
                } else if store.selectedBook?.isLocalText == true {
                    ContentUnavailableView(
                        "缺少本地正文",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("请在此设备重新导入同一 TXT 文件。书架同步不会传输小说正文。")
                    )
                } else if let failure = store.selectedChapterLoadFailure {
                    ContentUnavailableView {
                        Label("章节加载失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(failure)
                    } actions: {
                        Button("重试") { retrySelectedChapter() }
                            .accessibilityIdentifier("reader.retryChapter")
                    }
                    .accessibilityIdentifier("reader.chapterLoadFailed")
                } else if store.selectedChapter != nil {
                    ProgressView("正在准备章节…")
                        .accessibilityIdentifier("reader.preparingChapter")
                        .task(id: store.selectedChapterID) {
                            if loadsChapterAutomatically { await store.ensureSelectedChapterLoaded() }
                        }
                } else {
                    ContentUnavailableView(
                        "开始阅读",
                        systemImage: "text.book.closed",
                        description: Text("从书架中打开一本小说，或选择一个章节。")
                    )
                }
            }
            .foregroundStyle(isAcademic ? Color(white: 0.12) : theme.foreground)
        }
        .onDisappear {
            if store.selectedChapter?.isManga == true { store.endReaderPresentation() }
        }
        .overlay(alignment: .bottom) {
            if store.selectedChapter != nil && store.selectedChapter?.isManga != true && showsProgressOverlay {
                ReaderReadingProgressFooter(
                    text: isAcademic ? store.academicFooterText : store.readerProgressText,
                    foreground: isAcademic ? Color(white: 0.30) : theme.accent
                )
            }
        }
    }

    private func retrySelectedChapter() {
        // iOS loads chapters from MobileReaderView, so the retry drives the load
        // itself instead of relying on the spinner branch's task.
        Task { await store.ensureSelectedChapterLoaded() }
    }

    private var showsProgressOverlay: Bool {
        #if os(iOS)
        pageTurnMode != ReaderPageTurnMode.horizontalPages.rawValue
            || presentationModeName == ReaderPresentationMode.academicPaper.rawValue
        #else
        true
        #endif
    }
}
