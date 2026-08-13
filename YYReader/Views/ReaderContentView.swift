import SwiftUI

struct ReaderContentView: View {
    let store: LibraryStore
    let keyboardNavigationEnabled: Bool

    @AppStorage(ReaderPreferenceKeys.fontFamily) private var fontFamily = ReaderFontFamily.serif.rawValue
    @AppStorage(ReaderPreferenceKeys.fontSize) private var fontSize = 20.0
    @AppStorage(ReaderPreferenceKeys.lineSpacing) private var lineSpacing = ReaderLineSpacingPreset.comfortable.value
    @AppStorage(ReaderPreferenceKeys.paragraphSpacing) private var paragraphSpacing = 0.60
    @AppStorage(ReaderPreferenceKeys.contentWidth) private var contentWidth = ReaderViewportLayout.defaultPreferredWidthEM
    @AppStorage(ReaderPreferenceKeys.theme) private var themeName = ReaderTheme.system.rawValue
    @AppStorage(ReaderPreferenceKeys.paragraphIndent) private var paragraphIndent = true
    @AppStorage(ReaderPreferenceKeys.continuousReading) private var continuousReading = false
    @State private var scrollPosition = ScrollPosition(idType: ReaderScrollTarget.self)
    @State private var scrollState = ReaderScrollState()
    @State private var hasAppliedInitialScroll = false

    var body: some View {
        let family = ReaderFontFamily(rawValue: fontFamily) ?? .serif
        let theme = ReaderTheme(rawValue: themeName) ?? .system
        let entries = store.readerSession.entries
        let firstEntryID = entries.first?.id
        let lastEntryID = entries.last?.id

        GeometryReader { geometry in
            let effectiveWidth = ReaderViewportLayout.effectiveContentWidth(
                preferredWidthEM: contentWidth,
                fontSize: fontSize,
                viewportWidth: geometry.size.width
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: paragraphSpacing * fontSize) {
                    ForEach(entries) { entry in
                        let paragraphs = entry.paragraphs

                        ReaderChapterHeader(
                            chapter: entry.chapter,
                            accent: theme.accent,
                            target: .chapterHeader(entry.chapter.id),
                            style: entry.id == firstEntryID ? .prominent : .compact,
                            usesOrnament: theme.usesBookishChapterOrnament,
                            separator: theme.separator
                        )

                        ForEach(paragraphs.indices, id: \.self) { index in
                            ReaderParagraphView(
                                paragraph: paragraphs[index],
                                fontFamily: family,
                                fontSize: fontSize,
                                lineSpacing: lineSpacing * fontSize,
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
                                separator: theme.separator,
                                usesOrnament: theme.usesBookishChapterOrnament,
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
                scrollState.update(visibleTargets: targets, chapterIndexByID: store.chapterIndexByID)
            }
            .onScrollPhaseChange { oldPhase, newPhase, context in
                handleScrollPhaseChange(oldPhase: oldPhase, newPhase: newPhase, context: context)
            }
            .contentMargins(.vertical, 0, for: .scrollContent)
            .textSelection(.enabled)
            .background {
                if keyboardNavigationEnabled {
                    ReaderKeyboardEventBridge(handle: handleKeyboardCommand)
                }
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
        await applyPendingScrollRequest()
    }

    @MainActor
    private func applyPendingScrollRequest() async {
        await Task.yield()
        guard let chapter = store.selectedChapter else { return }
        if let request = store.readerScrollRequest, request.chapterID == chapter.id {
            switch request.intent {
            case .chapterTop:
                scrollPosition.scrollTo(id: ReaderScrollTarget.chapterHeader(chapter.id), anchor: .top)
            case .restore:
                scrollPosition.scrollTo(id: restoredParagraphTarget(for: chapter), anchor: .top)
            }
            hasAppliedInitialScroll = true
            store.consumeReaderScrollRequest(request.id)
        } else if !hasAppliedInitialScroll {
            scrollPosition.scrollTo(id: restoredParagraphTarget(for: chapter), anchor: .top)
            hasAppliedInitialScroll = true
        }
    }

    private func restoredParagraphTarget(for chapter: Chapter) -> ReaderScrollTarget {
        let paragraphCount = store.readerSession.paragraphs(for: chapter).count
        return .restoredParagraph(
            chapterID: chapter.id,
            savedIndex: chapter.topParagraphIndex,
            paragraphCount: paragraphCount
        )
    }

    private func commitVisibleTarget(_ target: ReaderScrollTarget) {
        switch target {
        case let .chapterHeader(chapterID):
            store.updateVisibleReaderPosition(chapterID: chapterID, paragraphIndex: 0, total: 1)
        case let .paragraph(chapterID, index):
            guard let entry = store.readerSession.entries.first(where: { $0.chapter.id == chapterID }) else { return }
            let paragraphCount = entry.paragraphs.count
            store.updateVisibleReaderPosition(chapterID: chapterID, paragraphIndex: index, total: paragraphCount)
            if continuousReading, index >= max(paragraphCount - 3, 0) {
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

    private func handleKeyboardCommand(_ command: ReaderKeyboardCommand) {
        switch command {
        case .moveUp:
            moveVertically(distance: -ReaderPageScroll.smallStep)
        case .moveDown:
            moveVertically(distance: ReaderPageScroll.smallStep)
        case .pageBackward:
            moveByPage(direction: -1)
        case .pageForward:
            moveByPage(direction: 1)
        }
    }

    private func moveVertically(distance: Double) {
        scroll(to: scrollState.destinationY(distance: distance))
    }

    private func moveByPage(direction: Double) {
        scroll(to: scrollState.pageDestinationY(direction: direction))
    }

    private func scroll(to destinationY: Double) {
        scrollState.requestDeferredCommit()
        if scrollState.beginScrollTransactionIfNeeded() {
            store.beginReaderScrollTransaction()
        }
        scrollState.scheduleDeferredCommit(after: .milliseconds(120)) {
            finishDeferredKeyboardCommitIfReady()
        }

        scrollPosition = ScrollPosition(idType: ReaderScrollTarget.self, y: destinationY)
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
