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
    @AppStorage(ReaderPreferenceKeys.continuousReading) private var continuousReading = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var topVisibleTarget: ReaderScrollTarget?
    @State private var keyboardTargets: [ReaderScrollTarget] = []
    @State private var hasAppliedInitialScroll = false
    @FocusState private var isReaderFocused: Bool

    var body: some View {
        let family = ReaderFontFamily(rawValue: fontFamily) ?? .serif
        let theme = ReaderTheme(rawValue: themeName) ?? .system
        let entries = store.readerSession.entries
        let lastEntryID = entries.last?.id

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
                                usesFirstLineIndent: paragraphIndent
                            )
                            .id(ReaderScrollTarget.paragraph(chapterID: entry.chapter.id, index: index))
                        }

                        if continuousReading {
                            ReaderContinuationBoundary(
                                status: entry.id == lastEntryID
                                    ? store.continuationStatus(after: entry.chapter.id)
                                    : .attached,
                                prepareAttachment: {
                                    store.prepareContinuousChapterAttachment(after: entry.chapter.id)
                                },
                                retry: { store.retryContinuousChapter(after: entry.chapter.id) }
                            )
                            .id(ReaderScrollTarget.chapterFooter(entry.chapter.id))
                        }
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
            .scrollPosition(id: $topVisibleTarget, anchor: .top)
            .onScrollPhaseChange { oldPhase, newPhase, _ in
                if newPhase.isScrolling, !oldPhase.isScrolling {
                    store.beginReaderScrollTransaction()
                } else if oldPhase.isScrolling, !newPhase.isScrolling {
                    store.endReaderScrollTransaction(topVisibleChapterID: topVisibleTarget?.chapterID)
                }
            }
            .contentMargins(.vertical, 0, for: .scrollContent)
            .textSelection(.enabled)
            .focusable()
            .focusEffectDisabled()
            .focused($isReaderFocused)
            .onKeyPress(.upArrow) {
                moveScrollPosition(by: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveScrollPosition(by: 1)
                return .handled
            }
        }
        .background(theme.background)
        .foregroundStyle(theme.foreground)
        .task {
            await prepareContinuousReading()
        }
        .task(id: continuousReading) {
            store.configureContinuousReading(continuousReading)
        }
        .task(id: entries.map(\.id)) {
            keyboardTargets = ReaderKeyboardScroll.paragraphTargets(
                entries: entries.map { (chapterID: $0.chapter.id, paragraphs: $0.paragraphs) }
            )
        }
        .task(id: store.readerScrollRequest?.id) {
            await applyPendingScrollRequest()
        }
        .onChange(of: topVisibleTarget) { _, target in
            handleScrollTarget(target)
        }
    }

    @MainActor
    private func prepareContinuousReading() async {
        store.configureContinuousReading(continuousReading)
        store.prepareContinuousReading()
        isReaderFocused = true
        await applyPendingScrollRequest()
    }

    @MainActor
    private func applyPendingScrollRequest() async {
        await Task.yield()
        guard let chapter = store.selectedChapter else { return }
        if let request = store.readerScrollRequest, request.chapterID == chapter.id {
            topVisibleTarget = .chapterHeader(chapter.id)
            hasAppliedInitialScroll = true
            store.consumeReaderScrollRequest(request.id)
        } else if !hasAppliedInitialScroll {
            topVisibleTarget = .paragraph(
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
            if continuousReading, index >= max(entry.paragraphs.count - 3, 0) {
                store.prepareContinuousChapterAttachment(after: chapterID)
            }
        case let .chapterFooter(chapterID):
            if continuousReading {
                store.prepareContinuousChapterAttachment(after: chapterID)
            }
        }
    }

    private func moveScrollPosition(by offset: Int) {
        guard let target = ReaderKeyboardScroll.nextTarget(
            visibleTarget: topVisibleTarget,
            selectedChapterID: store.selectedChapterID,
            fallbackParagraphIndex: store.selectedChapter?.topParagraphIndex ?? 0,
            targets: keyboardTargets,
            offset: offset
        ) else { return }
        if reduceMotion {
            topVisibleTarget = target
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                topVisibleTarget = target
            }
        }
    }

}

private extension ReaderScrollTarget {
    var chapterID: UUID {
        switch self {
        case let .chapterHeader(chapterID), let .chapterFooter(chapterID):
            return chapterID
        case let .paragraph(chapterID, _):
            return chapterID
        }
    }
}
