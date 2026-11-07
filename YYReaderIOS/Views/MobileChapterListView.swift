import SwiftUI

struct MobileChapterListView: View {
    let store: LibraryStore
    let openChapter: (UUID) -> Void
    @State private var showingReverseConfirmation = false
    @State private var search = ""
    @State private var locateRequest = UUID()

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
                            // Re-selecting the open chapter would rebuild the reader
                            // window and reset its saved position to the chapter top.
                            // Resume from the reading position instead.
                            if chapter.id == store.selectedChapterID {
                                store.requestReaderScroll(.restore)
                            } else {
                                store.selectChapter(chapter.id, scrollIntent: .chapterTop)
                            }
                            openChapter(chapter.id)
                        } label: {
                            HStack(spacing: 12) {
                                if chapter.id == store.selectedChapterID {
                                    Image(systemName: "book.pages.fill")
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityHidden(true)
                                }
                                Text(chapter.title)
                                    .font(.body.weight(chapter.id == store.selectedChapterID ? .medium : .regular))
                                    .foregroundStyle(chapter.id == store.selectedChapterID ? Color.accentColor : Color.primary)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if chapter.isAvailableOffline {
                                    Image(systemName: "checkmark.circle")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .accessibilityLabel("已缓存")
                                }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .listRowBackground(chapter.id == store.selectedChapterID
                        ? Color.accentColor.opacity(0.07) : Color(.secondarySystemGroupedBackground))
                    .accessibilityAddTraits(chapter.id == store.selectedChapterID ? .isSelected : [])
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
            .onChange(of: locateRequest) { _, _ in
                if let id = store.selectedChapterID { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: store.selectedChapterID) { _, id in
                if search.isEmpty, let id { proxy.scrollTo(id, anchor: .center) }
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if store.selectedBook == nil {
                    ContentUnavailableView("请选择书籍", systemImage: "book")
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
        .confirmationDialog("反转目录？", isPresented: $showingReverseConfirmation, titleVisibility: .visible) {
            Button("确认反转", action: store.reverseSelectedCatalog)
            Button("取消", role: .cancel) {}
        } message: {
            Text("目录顺序将反转，并跳到新的第一章。仅适用于导入目录顺序颠倒的情况；手动顺序会保留，刷新目录后仍然生效。")
        }
        .onChange(of: store.selectedBookID) { _, _ in showingReverseConfirmation = false }
        .navigationTitle(store.selectedBook?.title ?? "目录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("定位当前章节", systemImage: "location") {
                    search = ""
                    // Allow the unfiltered list to lay out before locating it.
                    Task { @MainActor in
                        await Task.yield()
                        locateRequest = UUID()
                    }
                }
                .disabled(store.selectedChapterID == nil)
                Menu("目录选项", systemImage: "ellipsis.circle") {
                    if store.selectedBook?.sourceKind == .web {
                        Button("刷新目录", systemImage: "arrow.clockwise", action: store.startRefreshSelectedCatalog)
                            .disabled(!store.canRefreshSelectedCatalog || store.isLoading)
                    }
                    Button("反转目录", systemImage: "arrow.up.arrow.down") { showingReverseConfirmation = true }
                        .disabled(store.sortedChapters.count < 2 || store.isLoading)
                }
            }
        }
    }
}
