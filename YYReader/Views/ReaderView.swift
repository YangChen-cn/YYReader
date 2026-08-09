import SwiftUI

struct ReaderView: View {
    @Bindable var store: LibraryStore

    var body: some View {
        Group {
            if let chapter = store.selectedChapter, chapter.isCached {
                ReaderContentView(chapter: chapter, store: store)
            } else if store.selectedChapter != nil {
                ProgressView("正在准备章节…")
                    .task(id: store.selectedChapterID) {
                        await store.ensureSelectedChapterLoaded()
                    }
            } else {
                ContentUnavailableView(
                    "开始阅读",
                    systemImage: "text.book.closed",
                    description: Text("从书架和目录中选择一个章节。")
                )
            }
        }
    }
}
