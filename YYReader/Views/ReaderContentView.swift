import SwiftUI

struct ReaderContentView: View {
    let store: LibraryStore

    @AppStorage(ReaderPreferenceKeys.fontFamily) private var fontFamily = ReaderFontFamily.serif.rawValue
    @AppStorage(ReaderPreferenceKeys.fontSize) private var fontSize = 20.0
    @AppStorage(ReaderPreferenceKeys.lineSpacing) private var lineSpacing = 8.0
    @AppStorage(ReaderPreferenceKeys.paragraphSpacing) private var paragraphSpacing = 12.0
    @AppStorage(ReaderPreferenceKeys.contentWidth) private var contentWidth = ReaderViewportLayout.defaultPreferredWidth
    @AppStorage(ReaderPreferenceKeys.theme) private var themeName = ReaderTheme.system.rawValue
    @AppStorage(ReaderPreferenceKeys.paragraphIndent) private var paragraphIndent = true
    @AppStorage(ReaderPreferenceKeys.focusMode) private var focusMode = false
    @State private var scrollPosition: ReaderScrollTarget?
    @State private var hasAppliedInitialScroll = false
    @FocusState private var isReaderFocused: Bool

    var body: some View {
        let family = ReaderFontFamily(rawValue: fontFamily) ?? .serif
        let theme = ReaderTheme(rawValue: themeName) ?? .system
        let entries = store.readerSession.entries

        GeometryReader { geometry in
            let effectiveWidth = ReaderViewportLayout.effectiveContentWidth(
                preferredWidth: contentWidth,
                viewportWidth: geometry.size.width
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: paragraphSpacing) {
                    ForEach(entries) { entry in
                        ReaderChapterHeader(
                            chapter: entry.chapter,
                            target: .chapterHeader(entry.chapter.id)
                        )

                        ForEach(entry.paragraphs.indices, id: \.self) { index in
                            ReaderParagraphView(
                                paragraph: entry.paragraphs[index],
                                fontFamily: family,
                                fontSize: fontSize,
                                lineSpacing: lineSpacing,
                                usesFirstLineIndent: paragraphIndent,
                                focusOpacity: paragraphOpacity(
                                    chapterID: entry.chapter.id,
                                    paragraphIndex: index,
                                    focusMode: focusMode
                                )
                            )
                            .id(ReaderScrollTarget.paragraph(chapterID: entry.chapter.id, index: index))
                        }
                    }

                    if let lastEntry = entries.last {
                        ReaderContinuationBoundary(
                            status: store.continuationStatus(after: lastEntry.chapter.id),
                            prefetch: { store.prefetchContinuousChapter(after: lastEntry.chapter.id) },
                            retry: { store.retryContinuousChapter(after: lastEntry.chapter.id) }
                        )
                        .id(ReaderScrollTarget.chapterFooter(lastEntry.chapter.id))
                    }

                    ReaderChapterFooter(
                        snapshot: store.chapterNavigationSnapshot,
                        previousChapter: store.goToPreviousChapter,
                        nextChapter: store.goToNextChapter
                    )
                }
                .scrollTargetLayout()
                .frame(width: effectiveWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $scrollPosition, anchor: .top)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .textSelection(.enabled)
            .focusable()
            .focused($isReaderFocused)
            .onKeyPress(.upArrow) {
                moveScrollPosition(by: -1, entries: entries)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveScrollPosition(by: 1, entries: entries)
                return .handled
            }
        }
        .background(theme.background)
        .foregroundStyle(theme.foreground)
        .task(id: store.selectedChapterID) {
            await prepareContinuousReading()
        }
        .task(id: store.readerScrollRequest?.id) {
            await applyPendingScrollRequest()
        }
        .onChange(of: scrollPosition) { _, target in
            handleScrollTarget(target)
        }
    }

    @MainActor
    private func prepareContinuousReading() async {
        store.prepareContinuousReading()
        isReaderFocused = true
        await applyPendingScrollRequest()
    }

    @MainActor
    private func applyPendingScrollRequest() async {
        await Task.yield()
        guard let chapter = store.selectedChapter else { return }
        if let request = store.readerScrollRequest, request.chapterID == chapter.id {
            scrollPosition = .chapterHeader(chapter.id)
            hasAppliedInitialScroll = true
            store.consumeReaderScrollRequest(request.id)
        } else if !hasAppliedInitialScroll {
            scrollPosition = .paragraph(
                chapterID: chapter.id,
                index: min(max(chapter.topParagraphIndex, 0), max(chapter.paragraphs.count - 1, 0))
            )
            hasAppliedInitialScroll = true
        }
    }

    private func handleScrollTarget(_ target: ReaderScrollTarget?) {
        guard let target else { return }
        switch target {
        case let .chapterHeader(chapterID):
            store.updateVisibleReaderPosition(chapterID: chapterID, paragraphIndex: 0, total: 1)
        case let .paragraph(chapterID, index):
            guard let entry = store.readerSession.entries.first(where: { $0.chapter.id == chapterID }) else { return }
            store.updateVisibleReaderPosition(chapterID: chapterID, paragraphIndex: index, total: entry.paragraphs.count)
            if index >= max(entry.paragraphs.count - 3, 0) {
                store.prefetchContinuousChapter(after: chapterID)
            }
        case let .chapterFooter(chapterID):
            store.prefetchContinuousChapter(after: chapterID)
        }
    }

    private func moveScrollPosition(
        by offset: Int,
        entries: [ContinuousReaderSession.Entry]
    ) {
        let targets = entries.flatMap { entry in
            entry.paragraphs.indices.map { ReaderScrollTarget.paragraph(chapterID: entry.chapter.id, index: $0) }
        }
        guard !targets.isEmpty else { return }
        let currentIndex = scrollPosition.flatMap { targets.firstIndex(of: $0) }
            ?? targets.firstIndex(of: .paragraph(
                chapterID: store.selectedChapterID ?? entries[0].chapter.id,
                index: store.selectedChapter?.topParagraphIndex ?? 0
            ))
            ?? 0
        let targetIndex = min(max(currentIndex + offset, 0), targets.count - 1)
        scrollPosition = targets[targetIndex]
        hasAppliedInitialScroll = true
    }

    private func paragraphOpacity(chapterID: UUID, paragraphIndex: Int, focusMode: Bool) -> Double {
        guard focusMode, let focus = store.readerSession.focusedParagraph else { return 1 }
        guard focus.chapterID == chapterID else { return 0.52 }
        switch abs(focus.paragraphIndex - paragraphIndex) {
        case 0: return 1
        case 1: return 0.68
        default: return 0.52
        }
    }
}
