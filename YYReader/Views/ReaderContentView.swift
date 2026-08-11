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
    @State private var scrollPosition = ScrollPosition(idType: ReaderScrollTarget.self)
    @State private var scrollState = ReaderScrollState()
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
                        let paragraphs = entry.paragraphs

                        ReaderChapterHeader(
                            chapter: entry.chapter,
                            accent: theme.accent,
                            target: .chapterHeader(entry.chapter.id)
                        )

                        ForEach(paragraphs.indices, id: \.self) { index in
                            ReaderParagraphView(
                                paragraph: paragraphs[index],
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
                                accent: theme.accent,
                                secondaryForeground: theme.secondaryForeground,
                                tertiaryForeground: theme.tertiaryForeground,
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
                        accent: theme.accent,
                        separator: theme.separator,
                        foreground: theme.foreground,
                        secondaryForeground: theme.secondaryForeground,
                        previousChapter: store.goToPreviousChapter,
                        nextChapter: store.goToNextChapter
                    )
                }
                .scrollTargetLayout()
                .frame(width: effectiveWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: ReaderScrollMetrics.self) { geometry in
                ReaderScrollMetrics(geometry: geometry)
            } action: { _, metrics in
                scrollState.update(metrics: metrics)
            }
            .onScrollTargetVisibilityChange(idType: ReaderScrollTarget.self, threshold: 0.01) { targets in
                scrollState.update(visibleTargets: targets)
            }
            .onScrollPhaseChange { oldPhase, newPhase, context in
                handleScrollPhaseChange(oldPhase: oldPhase, newPhase: newPhase, context: context)
            }
            .contentMargins(.vertical, 0, for: .scrollContent)
            .textSelection(.enabled)
            .focusable()
            .focusEffectDisabled()
            .focused($isReaderFocused)
            .onKeyPress(.upArrow, phases: [.down, .repeat]) { press in
                moveVertically(distance: -ReaderPageScroll.smallStep, isKeyRepeat: press.phase == .repeat)
                return .handled
            }
            .onKeyPress(.downArrow, phases: [.down, .repeat]) { press in
                moveVertically(distance: ReaderPageScroll.smallStep, isKeyRepeat: press.phase == .repeat)
                return .handled
            }
            .onKeyPress(.leftArrow, phases: [.down, .repeat]) { press in
                moveByPage(direction: -1, isKeyRepeat: press.phase == .repeat)
                return .handled
            }
            .onKeyPress(.rightArrow, phases: [.down, .repeat]) { press in
                moveByPage(direction: 1, isKeyRepeat: press.phase == .repeat)
                return .handled
            }
        }
        .background(theme.background)
        .foregroundStyle(theme.foreground)
        .tint(theme.accent)
        .task {
            await prepareContinuousReading()
        }
        .task(id: continuousReading) {
            store.configureContinuousReading(continuousReading)
        }
        .task(id: store.readerScrollRequest?.id) {
            await applyPendingScrollRequest()
        }
        .onDisappear {
            cancelDeferredKeyboardCommit()
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
            scrollPosition.scrollTo(id: ReaderScrollTarget.chapterHeader(chapter.id), anchor: .top)
            hasAppliedInitialScroll = true
            store.consumeReaderScrollRequest(request.id)
        } else if !hasAppliedInitialScroll {
            scrollPosition.scrollTo(
                id: ReaderScrollTarget.paragraph(
                    chapterID: chapter.id,
                    index: min(max(chapter.topParagraphIndex, 0), max(chapter.paragraphs.count - 1, 0))
                ),
                anchor: .top
            )
            hasAppliedInitialScroll = true
        }
    }

    private func commitVisibleTarget(_ target: ReaderScrollTarget) {
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

    private func handleScrollPhaseChange(
        oldPhase: ScrollPhase,
        newPhase: ScrollPhase,
        context: ScrollPhaseChangeContext
    ) {
        scrollState.update(metrics: ReaderScrollMetrics(geometry: context.geometry))
        scrollState.update(phase: newPhase)

        if newPhase == .tracking || newPhase == .interacting {
            releaseProgrammaticScrollPosition()
        }

        if newPhase.isScrolling,
           !oldPhase.isScrolling,
           scrollState.beginScrollTransactionIfNeeded() {
            store.beginReaderScrollTransaction()
        }

        if newPhase == .idle {
            releaseProgrammaticScrollPosition()
            if scrollState.hasPendingDeferredCommit {
                finishDeferredKeyboardCommitIfReady()
                return
            }
            commitVisiblePosition()
            finishScrollTransactionIfNeeded()
        }
    }

    private func commitVisiblePosition() {
        guard let target = scrollState.consumeVisibleTargetForCommit() else { return }
        commitVisibleTarget(target)
    }

    private func moveVertically(distance: Double, isKeyRepeat: Bool) {
        scroll(to: scrollState.destinationY(distance: distance), isKeyRepeat: isKeyRepeat)
    }

    private func moveByPage(direction: Double, isKeyRepeat: Bool) {
        scroll(to: scrollState.pageDestinationY(direction: direction), isKeyRepeat: isKeyRepeat)
    }

    private func scroll(to destinationY: Double, isKeyRepeat: Bool) {
        scrollState.requestDeferredCommit()
        if scrollState.beginScrollTransactionIfNeeded() {
            store.beginReaderScrollTransaction()
        }
        scrollState.scheduleDeferredCommit(after: .milliseconds(120)) {
            finishDeferredKeyboardCommitIfReady()
        }

        let destination = ScrollPosition(idType: ReaderScrollTarget.self, y: destinationY)
        if ReaderPageScroll.shouldAnimate(reduceMotion: reduceMotion, isKeyRepeat: isKeyRepeat) {
            withAnimation(.easeOut(duration: ReaderPageScroll.animationDuration)) {
                scrollPosition = destination
            }
        } else {
            scrollPosition = destination
        }
    }

    private func finishDeferredKeyboardCommitIfReady() {
        guard scrollState.canFinishDeferredCommit else { return }
        releaseProgrammaticScrollPosition()
        if let target = scrollState.finishDeferredCommit() {
            commitVisibleTarget(target)
        }
        finishScrollTransactionIfNeeded()
    }

    private func finishScrollTransactionIfNeeded() {
        guard scrollState.finishScrollTransactionIfNeeded() else { return }
        store.endReaderScrollTransaction(topVisibleChapterID: scrollState.topVisibleTarget?.chapterID)
    }

    private func cancelDeferredKeyboardCommit() {
        scrollState.cancelDeferredCommit()
        finishScrollTransactionIfNeeded()
    }

    private func releaseProgrammaticScrollPosition() {
        guard !scrollPosition.isPositionedByUser else { return }
        scrollPosition.isPositionedByUser = true
        scrollState.releaseProgrammaticPosition()
    }
}
