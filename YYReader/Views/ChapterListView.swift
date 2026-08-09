import SwiftUI

struct ChapterListView: View {
    @Bindable var store: LibraryStore
    let selectionScrollIntent: ReaderScrollIntent?
    let activateChapter: (UUID) -> Void
    @State private var searchText = ""

    var body: some View {
        let chapters = searchText.isEmpty
            ? store.sortedChapters
            : store.sortedChapters.filter { $0.title.localizedStandardContains(searchText) }

        List(selection: $store.selectedChapterID) {
            ForEach(chapters) { chapter in
                ChapterListRow(chapter: chapter)
                    .tag(chapter.id)
                    .onTapGesture(count: 2) {
                        activateChapter(chapter.id)
                    }
                    .accessibilityAction(named: "打开章节") {
                        activateChapter(chapter.id)
                    }
            }
        }
        .navigationTitle(store.selectedBook?.title ?? "目录")
        .searchable(text: $searchText, prompt: "搜索章节")
        .onChange(of: store.selectedChapterID) { oldValue, newValue in
            Task { @MainActor in
                await Task.yield()
                guard store.selectedChapterID == newValue else { return }
                store.reconcileChapterSelection(
                    newValue,
                    previousID: oldValue,
                    scrollIntent: selectionScrollIntent
                )
            }
        }
        .onKeyPress(.return) {
            guard let chapterID = store.selectedChapterID else { return .ignored }
            activateChapter(chapterID)
            return .handled
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
