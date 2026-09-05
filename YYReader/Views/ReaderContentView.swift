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
    @AppStorage(ReaderPreferenceKeys.presentationMode) private var presentationModeName = ReaderPresentationMode.normal.rawValue
    @AppStorage(ReaderPreferenceKeys.academicColumnMode) private var academicColumnModeName = AcademicColumnMode.double.rawValue
    @State private var scrollPosition = ScrollPosition(idType: ReaderScrollTarget.self)
    @State private var scrollState = ReaderScrollState()
    @State private var hasAppliedInitialScroll = false
    @State private var academicPlanCache = AcademicPaperPlanCache()
    @State private var isRestoringPresentation = false
    @State private var activeReadingAnchor: (chapterID: UUID, paragraphIndex: Int)?

    var body: some View {
        let family = ReaderFontFamily(rawValue: fontFamily) ?? .serif
        let theme = ReaderTheme(rawValue: themeName) ?? .system
        let entries = store.readerSession.entries
        let firstEntryID = entries.first?.id
        let lastEntryID = entries.last?.id
        let presentationMode = ReaderPresentationMode(rawValue: presentationModeName) ?? .normal

        GeometryReader { geometry in
            let effectiveWidth = ReaderViewportLayout.effectiveContentWidth(
                preferredWidthEM: contentWidth,
                fontSize: fontSize,
                viewportWidth: geometry.size.width
            )
            let usesDoubleColumns = presentationMode == .academicPaper
                && (AcademicColumnMode(rawValue: academicColumnModeName) ?? .double) == .double
                && geometry.size.width >= 760
            let displayedWidth = presentationMode == .academicPaper
                ? min(max(geometry.size.width - 56, 520), 1080)
                : effectiveWidth

            ScrollView {
                LazyVStack(alignment: .leading, spacing: paragraphSpacing * fontSize) {
                    ForEach(entries) { entry in
                        let paragraphs = entry.paragraphs
                        if paragraphs.isEmpty {
                            if presentationMode == .academicPaper {
                                AcademicPaperLoadingCard(
                                    title: entry.chapter.title,
                                    showsPaperFrontMatter: entry.id == firstEntryID
                                )
                                .id(ReaderScrollTarget.chapterHeader(entry.chapter.id))
                                .task(id: entry.chapter.id) {
                                    await store.materializeChapterBody(entry.chapter)
                                }
                            } else {
                                VStack(spacing: 12) {
                                    ReaderChapterHeader(
                                        chapter: entry.chapter,
                                        accent: theme.accent,
                                        target: .chapterHeader(entry.chapter.id),
                                        style: entry.id == firstEntryID ? .prominent : .compact,
                                        usesOrnament: theme.usesBookishChapterOrnament,
                                        separator: theme.separator
                                    )
                                    ProgressView("正在加载正文…")
                                        .padding(.vertical, 20)
                                        .task(id: entry.chapter.id) {
                                            await store.materializeChapterBody(entry.chapter)
                                        }
                                }
                                .id(ReaderScrollTarget.chapterHeader(entry.chapter.id))
                            }
                        } else if presentationMode == .academicPaper {
                            let bookIdentity = store.selectedBook?.sourceBookURL
                                ?? entry.chapter.book?.sourceBookURL
                                ?? ""
                            let plan = academicPlanCache.plan(
                                bookIdentity: bookIdentity,
                                chapter: entry.chapter,
                                position: store.chapterIndexByID[entry.chapter.id] ?? 0,
                                paragraphs: paragraphs
                            )
                            AcademicPaperChapterView(
                                plan: plan,
                                chapterID: entry.chapter.id,
                                showsPaperFrontMatter: entry.id == firstEntryID,
                                usesDoubleColumns: usesDoubleColumns,
                                fontSize: fontSize,
                                lineSpacing: lineSpacing
                            )
                            .padding(.horizontal, 38)
                            .padding(.top, entry.id == firstEntryID ? 32 : 22)
                            .padding(.bottom, 26)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.07), radius: 7, x: 0, y: 2.5)
                            )
                            .padding(.vertical, 10)
                        } else {
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
                .frame(width: displayedWidth, alignment: .leading)
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
                updateActiveReadingAnchor(from: targets)
                if continuousReading {
                    checkContinuousAttachment(for: targets)
                }
            }
            .onScrollPhaseChange { oldPhase, newPhase, context in
                handleScrollPhaseChange(oldPhase: oldPhase, newPhase: newPhase, context: context)
            }
            .contentMargins(.vertical, 0, for: .scrollContent)
            .textSelection(.enabled)
            .background {
                if keyboardNavigationEnabled {
                    ReaderKeyboardEventBridge { command in
                        handleKeyboardCommand(
                            command,
                            fallbackViewportHeight: geometry.size.height
                        )
                    }
                }
            }
        }
        .background(presentationMode == .academicPaper ? Color(white: 0.88) : theme.background)
        .foregroundStyle(presentationMode == .academicPaper ? Color(white: 0.12) : theme.foreground)
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
        .task(id: presentationModeName + "|" + academicColumnModeName) {
            await restoreAfterPresentationChange()
        }
        .onChange(of: store.selectedChapterID) { oldID, newID in
            if oldID != newID && !continuousReading {
                scrollPosition = ScrollPosition(idType: ReaderScrollTarget.self, y: 0)
            }
        }
        .onDisappear {
            cancelDeferredKeyboardCommit()
        }
    }

    @MainActor
    private func restoreAfterPresentationChange() async {
        guard hasAppliedInitialScroll else { return }
        let anchor = resolveActiveReadingAnchor()
        guard let anchorChapter = store.chapterByID[anchor.chapterID] ?? store.selectedChapter else { return }

        isRestoringPresentation = true
        store.beginReaderScrollTransaction()
        defer {
            releaseProgrammaticScrollPosition()
            store.endReaderScrollTransaction(topVisibleChapterID: anchor.chapterID)
            isRestoringPresentation = false
        }

        await store.materializeChapterBody(anchorChapter)

        for entry in store.readerSession.entries {
            if entry.chapter.id == anchorChapter.id { break }
            if entry.paragraphs.isEmpty {
                await store.materializeChapterBody(entry.chapter)
            }
        }

        await Task.yield()
        do {
            try await Task.sleep(for: .milliseconds(30))
        } catch is CancellationError {
            return
        } catch {
            return
        }

        let target = resolvedScrollTarget(for: anchorChapter, desiredParagraphIndex: anchor.paragraphIndex)
        scrollPosition.scrollTo(id: target, anchor: .top)

        do {
            try await Task.sleep(for: .milliseconds(60))
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    private func resolveActiveReadingAnchor() -> (chapterID: UUID, paragraphIndex: Int) {
        if let current = activeReadingAnchor {
            return current
        }
        if let top = scrollState.topVisibleTarget {
            switch top {
            case let .paragraph(chapterID, index):
                return (chapterID: chapterID, paragraphIndex: index)
            case let .chapterHeader(chapterID):
                return (chapterID: chapterID, paragraphIndex: 0)
            case let .chapterFooter(chapterID):
                let count = store.readerSession.entries.first(where: { $0.chapter.id == chapterID })?.paragraphs.count ?? 1
                return (chapterID: chapterID, paragraphIndex: max(count - 1, 0))
            }
        }
        if let currentChapterID = store.readerSession.visibleChapterID ?? store.selectedChapterID,
           let chapter = store.chapterByID[currentChapterID] {
            return (chapterID: chapter.id, paragraphIndex: chapter.topParagraphIndex)
        }
        if let selected = store.selectedChapter {
            return (chapterID: selected.id, paragraphIndex: selected.topParagraphIndex)
        }
        return (chapterID: UUID(), paragraphIndex: 0)
    }

    private func resolvedScrollTarget(for chapter: Chapter, desiredParagraphIndex: Int) -> ReaderScrollTarget {
        let paragraphs = store.readerSession.paragraphs(for: chapter)
        if !paragraphs.isEmpty {
            let clampedIndex = min(max(desiredParagraphIndex, 0), paragraphs.count - 1)
            return .paragraph(chapterID: chapter.id, index: clampedIndex)
        }
        return .chapterHeader(chapter.id)
    }

    private func updateActiveReadingAnchor(from targets: [ReaderScrollTarget]) {
        guard !isRestoringPresentation else { return }
        guard let target = scrollState.topVisibleTarget else { return }
        switch target {
        case let .paragraph(chapterID, index):
            activeReadingAnchor = (chapterID: chapterID, paragraphIndex: index)
        case let .chapterHeader(chapterID):
            activeReadingAnchor = (chapterID: chapterID, paragraphIndex: 0)
        case let .chapterFooter(chapterID):
            let count = store.readerSession.entries.first(where: { $0.chapter.id == chapterID })?.paragraphs.count ?? 1
            activeReadingAnchor = (chapterID: chapterID, paragraphIndex: max(count - 1, 0))
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
                scrollPosition = ScrollPosition(idType: ReaderScrollTarget.self, y: 0)
                scrollPosition.scrollTo(id: ReaderScrollTarget.chapterHeader(chapter.id), anchor: .top)
                activeReadingAnchor = (chapterID: chapter.id, paragraphIndex: 0)
            case .restore:
                let target = restoredParagraphTarget(for: chapter)
                scrollPosition.scrollTo(id: target, anchor: .top)
                activeReadingAnchor = (chapterID: chapter.id, paragraphIndex: chapter.topParagraphIndex)
            }
            hasAppliedInitialScroll = true
            store.consumeReaderScrollRequest(request.id)
        } else if !hasAppliedInitialScroll {
            let target = restoredParagraphTarget(for: chapter)
            scrollPosition.scrollTo(id: target, anchor: .top)
            activeReadingAnchor = (chapterID: chapter.id, paragraphIndex: chapter.topParagraphIndex)
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
        guard !isRestoringPresentation else { return }
        switch target {
        case let .chapterHeader(chapterID):
            activeReadingAnchor = (chapterID: chapterID, paragraphIndex: 0)
            store.updateVisibleReaderPosition(chapterID: chapterID, paragraphIndex: 0, total: 1)
        case let .paragraph(chapterID, index):
            activeReadingAnchor = (chapterID: chapterID, paragraphIndex: index)
            guard let entry = store.readerSession.entries.first(where: { $0.chapter.id == chapterID }) else { return }
            let paragraphCount = entry.paragraphs.count
            store.updateVisibleReaderPosition(chapterID: chapterID, paragraphIndex: index, total: paragraphCount)
            if continuousReading, index >= max(paragraphCount - 3, 0) {
                store.prepareContinuousChapterAttachment(after: chapterID)
            }
        case let .chapterFooter(chapterID):
            let count = store.readerSession.entries.first(where: { $0.chapter.id == chapterID })?.paragraphs.count ?? 1
            activeReadingAnchor = (chapterID: chapterID, paragraphIndex: max(count - 1, 0))
            if continuousReading {
                store.prepareContinuousChapterAttachment(after: chapterID)
            }
        }
    }

    private func checkContinuousAttachment(for targets: [ReaderScrollTarget]) {
        for target in targets {
            switch target {
            case let .paragraph(chapterID, index):
                guard let entry = store.readerSession.entries.first(where: { $0.chapter.id == chapterID }) else { continue }
                if index >= max(entry.paragraphs.count - 4, 0) {
                    store.prepareContinuousChapterAttachment(after: chapterID)
                }
            case let .chapterFooter(chapterID):
                store.prepareContinuousChapterAttachment(after: chapterID)
            case .chapterHeader:
                break
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
        guard !isRestoringPresentation else { return }
        guard let target = scrollState.consumeVisibleTargetForCommit() else { return }
        commitVisibleTarget(target)
    }

    private func handleKeyboardCommand(
        _ command: ReaderKeyboardCommand,
        fallbackViewportHeight: Double
    ) {
        switch command {
        case .moveUp:
            moveVertically(distance: -ReaderPageScroll.smallStep)
        case .moveDown:
            moveVertically(distance: ReaderPageScroll.smallStep)
        case .pageBackward:
            moveByPage(direction: -1, fallbackViewportHeight: fallbackViewportHeight)
        case .pageForward:
            moveByPage(direction: 1, fallbackViewportHeight: fallbackViewportHeight)
        }
    }

    private func moveVertically(distance: Double) {
        scroll(to: scrollState.destinationY(distance: distance))
    }

    private func moveByPage(direction: Double, fallbackViewportHeight: Double) {
        scroll(
            to: scrollState.pageDestinationY(
                direction: direction,
                fallbackViewportHeight: fallbackViewportHeight
            )
        )
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
