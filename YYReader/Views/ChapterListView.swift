import SwiftUI

struct ChapterListView: View {
    @Bindable var store: LibraryStore
    @State private var searchText = ""

    var body: some View {
        let chapters = searchText.isEmpty
            ? store.sortedChapters
            : store.sortedChapters.filter { $0.title.localizedStandardContains(searchText) }

        List(selection: $store.selectedChapterID) {
            ForEach(chapters) { chapter in
                ChapterListRow(chapter: chapter)
                    .tag(chapter.id)
            }
        }
        .navigationTitle(store.selectedBook?.title ?? "目录")
        .searchable(text: $searchText, prompt: "搜索章节")
        .onChange(of: store.selectedChapterID) { _, newValue in
            store.selectChapter(newValue)
        }
        .overlay {
            if store.selectedBook == nil {
                ContentUnavailableView("请选择小说", systemImage: "book")
            } else if chapters.isEmpty, !searchText.isEmpty {
                ContentUnavailableView.search
            } else if chapters.isEmpty {
                ContentUnavailableView("没有识别到章节", systemImage: "list.bullet")
            }
        }
    }
}
