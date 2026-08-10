import SwiftUI

struct ChapterListView: View {
    @Bindable var store: LibraryStore
    let selectionScrollIntent: ReaderScrollIntent?
    let isCatalogVisible: Bool
    let activateChapter: (UUID) -> Void
    @State private var searchText = ""

    var body: some View {
        let chapters = searchText.isEmpty
            ? store.sortedChapters
            : store.sortedChapters.filter { $0.title.localizedStandardContains(searchText) }

        VStack(spacing: 0) {
            TextField("搜索章节", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("搜索章节")
                .padding(.horizontal, 8)
                .padding(.vertical, 7)

            ScrollViewReader { proxy in
                List(selection: chapterSelection) {
                    ForEach(chapters) { chapter in
                        ChapterListRow(chapter: chapter)
                            .id(chapter.id)
                            .tag(chapter.id)
                            .onTapGesture(count: 2) {
                                activateChapter(chapter.id)
                            }
                            .accessibilityAction(named: "打开章节") {
                                activateChapter(chapter.id)
                            }
                        }
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
                .onAppear {
                    centerSelectedChapter(using: proxy, in: chapters)
                }
                .onChange(of: isCatalogVisible) { _, isVisible in
                    guard isVisible else { return }
                    centerSelectedChapter(using: proxy, in: chapters)
                }
                .onChange(of: store.selectedChapterID) { _, _ in
                    centerSelectedChapter(using: proxy, in: chapters)
                }
                .onChange(of: searchText) { _, _ in
                    centerSelectedChapter(using: proxy, in: chapters)
                }
            }
        }
        .navigationTitle(store.selectedBook?.title ?? "目录")
        .onKeyPress(.return) {
            guard let chapterID = store.selectedChapterID else { return .ignored }
            activateChapter(chapterID)
            return .handled
        }
    }

    private var chapterSelection: Binding<UUID?> {
        Binding(
            get: { store.selectedChapterID },
            set: { newValue in
                guard newValue != store.selectedChapterID else { return }
                store.selectChapter(newValue, scrollIntent: selectionScrollIntent)
            }
        )
    }

    private func centerSelectedChapter(using proxy: ScrollViewProxy, in chapters: [Chapter]) {
        guard isCatalogVisible,
              let chapterID = store.selectedChapterID,
              chapters.contains(where: { $0.id == chapterID }) else {
            return
        }
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(chapterID, anchor: .center)
        }
    }
}
