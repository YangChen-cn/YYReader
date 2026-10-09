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
                    Button {
                        store.requestReaderScroll(.restore)
                        if let id = store.selectedChapterID { openChapter(id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "book.fill").font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("继续阅读").font(.headline)
                                Text(store.selectedChapter?.title ?? "")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.accentColor.opacity(0.08))
                    .accessibilityIdentifier("ios.continueReading")
                }
                Section("章节目录 · \(store.sortedChapters.count) 章") {
                    ForEach(chapters) { chapter in
                        Button {
                            store.selectChapter(chapter.id, scrollIntent: .chapterTop)
                            openChapter(chapter.id)
                        } label: {
                            ChapterListRow(chapter: chapter)
                                .foregroundStyle(chapter.id == store.selectedChapterID ? Color.accentColor : Color.primary)
                    }
                    .id(chapter.id)
                    .accessibilityIdentifier("ios.chapter.\(chapter.sortIndex)")
                    }
                }
            }
            .listStyle(.insetGrouped)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if store.selectedBook?.sourceKind == .web {
                    Button("刷新目录", systemImage: "arrow.clockwise", action: store.startRefreshSelectedCatalog)
                        .disabled(!store.canRefreshSelectedCatalog || store.isLoading)
                }
            }
        }
    }
}
