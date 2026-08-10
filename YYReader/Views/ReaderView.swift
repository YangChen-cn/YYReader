import SwiftUI

struct ReaderView: View {
    @Bindable var store: LibraryStore
    @AppStorage(ReaderPreferenceKeys.theme) private var themeName = ReaderTheme.system.rawValue

    var body: some View {
        let theme = ReaderTheme(rawValue: themeName) ?? .system

        ZStack {
            theme.background
                .ignoresSafeArea()

            Group {
                if let chapter = store.selectedChapter, chapter.isCached {
                    ReaderContentView(store: store)
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
            .foregroundStyle(theme.foreground)
        }
        .overlay(alignment: .bottom) {
            if store.selectedChapter != nil {
                ReaderReadingProgressFooter(
                    text: store.readerProgressText,
                    foreground: theme.tertiaryForeground
                )
            }
        }
    }
}
