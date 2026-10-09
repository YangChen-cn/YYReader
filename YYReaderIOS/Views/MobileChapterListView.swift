import SwiftUI

struct MobileChapterListView: View {
    let store: LibraryStore
    let openChapter: (UUID) -> Void
    @State private var search = ""

    private var chapters: [Chapter] {
        search.isEmpty ? store.sortedChapters : store.sortedChapters.filter { $0.title.localizedStandardContains(search) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if store.selectedChapter != nil {
                    Button("继续阅读", systemImage: "book") {
                        store.requestReaderScroll(.restore)
                        if let id = store.selectedChapterID { openChapter(id) }
                    }
                    .accessibilityIdentifier("ios.continueReading")
                }
                ForEach(chapters) { chapter in
                    Button {
                        store.selectChapter(chapter.id, scrollIntent: .chapterTop)
                        openChapter(chapter.id)
                    } label: {
                        ChapterListRow(chapter: chapter)
                            .foregroundStyle(chapter.id == store.selectedChapterID ? Color.accentColor : Color.primary)
                    }
                    .id(chapter.id)
                }
            }
            .task(id: store.selectedBookID) {
                await Task.yield()
                if let id = store.selectedChapterID { proxy.scrollTo(id, anchor: .center) }
            }
            .overlay {
                if store.selectedBook == nil {
                    ContentUnavailableView("请选择小说", systemImage: "book")
                } else if chapters.isEmpty {
                    if search.isEmpty {
                        ContentUnavailableView("没有识别到章节", systemImage: "list.bullet")
                    } else {
                        ContentUnavailableView.search
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "搜索章节")
        .navigationTitle(store.selectedBook?.title ?? "目录")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("刷新目录", systemImage: "arrow.clockwise", action: store.startRefreshSelectedCatalog)
                    .disabled(!store.canRefreshSelectedCatalog || store.isLoading)
            }
        }
    }
}
