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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var topVisibleTarget: ReaderScrollTarget?
    @State private var viewportFrame = CGRect.zero
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

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: paragraphSpacing) {
                        ForEach(entries) { entry in
                            ReaderChapterHeader(
                                chapter: entry.chapter,
                                target: .chapterHeader(entry.chapter.id)
                            )

                            ForEach(entry.paragraphs.indices, id: \.self) { index in
                                let focus = ReaderParagraphFocus(chapterID: entry.chapter.id, paragraphIndex: index)
                                ReaderParagraphView(
                                    paragraph: entry.paragraphs[index],
                                    fontFamily: family,
                                    fontSize: fontSize,
                                    lineSpacing: lineSpacing,
                                    usesFirstLineIndent: paragraphIndent,
                                    focusOpacity: focusMode
                                        ? ReaderParagraphFocusStyle.opacity(
                                            chapterID: entry.chapter.id,
                                            paragraphIndex: index,
                                            focus: store.readerSession.focusedParagraph
                                        )
                                        : 1
                                )
                                .id(ReaderScrollTarget.paragraph(chapterID: entry.chapter.id, index: index))
                                .background {
                                    if focusMode {
                                        ReaderParagraphFocusReporter(focus: focus)
                                    }
                                }
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
                .scrollPosition(id: $topVisibleTarget, anchor: .top)
                .contentMargins(.vertical, 0, for: .scrollContent)
                .textSelection(.enabled)
                .focusable()
                .focused($isReaderFocused)
                .onKeyPress(.upArrow) {
                    moveScrollPosition(by: -1, entries: entries, proxy: scrollProxy)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveScrollPosition(by: 1, entries: entries, proxy: scrollProxy)
                    return .handled
                }
            }
            .onAppear { viewportFrame = geometry.frame(in: .global) }
            .onChange(of: geometry.size) { _, _ in viewportFrame = geometry.frame(in: .global) }
        }
        .background(theme.background)
        .foregroundStyle(theme.foreground)
        .task {
            await prepareContinuousReading()
        }
        .task(id: store.readerScrollRequest?.id) {
            await applyPendingScrollRequest()
        }
        .onChange(of: topVisibleTarget) { _, target in
            handleScrollTarget(target)
        }
        .onPreferenceChange(ReaderParagraphViewportFramePreferenceKey.self) { frames in
            updateFocusedParagraph(from: frames)
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
            if index >= max(entry.paragraphs.count - 3, 0) {
                store.prefetchContinuousChapter(after: chapterID)
            }
        case let .chapterFooter(chapterID):
            store.prefetchContinuousChapter(after: chapterID)
        }
    }

    private func moveScrollPosition(
        by offset: Int,
        entries: [ContinuousReaderSession.Entry],
        proxy: ScrollViewProxy
    ) {
        let targets = entries.flatMap { entry in
            entry.paragraphs.indices.map { ReaderScrollTarget.paragraph(chapterID: entry.chapter.id, index: $0) }
        }
        guard !targets.isEmpty else { return }
        let focusedTarget = store.readerSession.focusedParagraph.map {
            ReaderScrollTarget.paragraph(chapterID: $0.chapterID, index: $0.paragraphIndex)
        }
        let currentIndex = (focusMode ? focusedTarget : topVisibleTarget).flatMap { targets.firstIndex(of: $0) }
            ?? targets.firstIndex(of: .paragraph(
                chapterID: store.selectedChapterID ?? entries[0].chapter.id,
                index: store.selectedChapter?.topParagraphIndex ?? 0
            ))
            ?? 0
        let targetIndex = min(max(currentIndex + offset, 0), targets.count - 1)
        let target = targets[targetIndex]
        if let focus = target.paragraphFocus {
            store.updateReaderFocus(focus)
        }
        scroll(to: target, proxy: proxy, anchor: focusMode ? UnitPoint(x: 0.5, y: 0.42) : .top)
        hasAppliedInitialScroll = true
    }

    private func scroll(to target: ReaderScrollTarget, proxy: ScrollViewProxy, anchor: UnitPoint) {
        if reduceMotion {
            proxy.scrollTo(target, anchor: anchor)
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(target, anchor: anchor)
            }
        }
    }

    private func updateFocusedParagraph(from frames: [ReaderParagraphViewportFrame]) {
        guard focusMode, viewportFrame.height > 0 else { return }
        let readingLine = viewportFrame.minY + viewportFrame.height * 0.42
        guard let closest = frames
            .filter({ $0.frame.maxY >= viewportFrame.minY && $0.frame.minY <= viewportFrame.maxY })
            .min(by: { abs($0.frame.midY - readingLine) < abs($1.frame.midY - readingLine) }) else {
            return
        }
        guard store.readerSession.focusedParagraph != closest.focus else { return }
        store.updateReaderFocus(closest.focus)
    }
}

private extension ReaderScrollTarget {
    var paragraphFocus: ReaderParagraphFocus? {
        guard case let .paragraph(chapterID, index) = self else { return nil }
        return ReaderParagraphFocus(chapterID: chapterID, paragraphIndex: index)
    }
}
