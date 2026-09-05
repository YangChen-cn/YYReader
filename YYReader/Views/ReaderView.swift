import SwiftUI

struct ReaderView: View {
    @Bindable var store: LibraryStore
    let keyboardNavigationEnabled: Bool
    @AppStorage(ReaderPreferenceKeys.theme) private var themeName = ReaderTheme.system.rawValue
    @AppStorage(ReaderPreferenceKeys.presentationMode) private var presentationModeName = ReaderPresentationMode.normal.rawValue

    var body: some View {
        let theme = ReaderTheme(rawValue: themeName) ?? .system
        let isAcademic = presentationModeName == ReaderPresentationMode.academicPaper.rawValue

        ZStack {
            (isAcademic ? Color(white: 0.88) : theme.background)
                .ignoresSafeArea()

            Group {
                if let chapter = store.selectedChapter, chapter.isCached {
                    ReaderContentView(
                        store: store,
                        keyboardNavigationEnabled: keyboardNavigationEnabled
                    )
                } else if store.selectedBook?.isLocalText == true {
                    ContentUnavailableView(
                        "缺少本地正文",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("请在此设备重新导入同一 TXT 文件。书架同步不会传输小说正文。")
                    )
                } else if store.selectedChapter != nil {
                    ProgressView("正在准备章节…")
                        .task(id: store.selectedChapterID) {
                            await store.ensureSelectedChapterLoaded()
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
        .overlay(alignment: .bottom) {
            if store.selectedChapter != nil {
                ReaderReadingProgressFooter(
                    text: isAcademic ? store.academicFooterText : store.readerProgressText,
                    foreground: isAcademic ? Color(white: 0.30) : theme.accent
                )
            }
        }
    }
}
