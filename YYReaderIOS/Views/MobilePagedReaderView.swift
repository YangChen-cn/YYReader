import SwiftUI

struct MobilePagedReaderView: View {
    let store: LibraryStore
    let chapter: Chapter
    @AppStorage(ReaderPreferenceKeys.fontFamily) private var fontFamily = ReaderFontFamily.serif.rawValue
    @AppStorage(ReaderPreferenceKeys.fontSize) private var fontSize = 20.0
    @AppStorage(ReaderPreferenceKeys.lineSpacing) private var lineSpacing = ReaderLineSpacingPreset.comfortable.value
    @AppStorage(ReaderPreferenceKeys.paragraphSpacing) private var paragraphSpacing = 0.60
    @AppStorage(ReaderPreferenceKeys.contentWidth) private var contentWidth = ReaderViewportLayout.defaultPreferredWidthEM
    @AppStorage(ReaderPreferenceKeys.paragraphIndent) private var indent = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0
    @State private var paginator = MobileTextPaginator()
    @State private var pages: [MobileReadingPage] = []
    @State private var visiblePageID: Int?
    @State private var isPaginating = true
    @State private var anchorParagraph = 0
    @State private var anchorOffset = 0
    @State private var hasPrepared = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let font = MobileReadingFont.resolve(ReaderFontFamily(rawValue: fontFamily) ?? .serif,
                                                     size: fontSize * textScale)
                let layout = MobilePaginationLayout(
                    width: ReaderViewportLayout.effectiveContentWidth(preferredWidthEM: contentWidth,
                                                                      fontSize: fontSize * textScale,
                                                                      viewportWidth: geometry.size.width),
                    height: max(geometry.size.height - 24, 1), fontName: font.fontName,
                    fontSize: font.pointSize, lineHeight: font.lineHeight,
                    lineSpacing: lineSpacing * fontSize * textScale,
                    paragraphSpacing: paragraphSpacing * fontSize * textScale, usesFirstLineIndent: indent
                )
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        if store.chapterNavigationSnapshot.hasPrevious {
                            MobilePageChapterBoundary(title: "上一章", action: previousChapter)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .id(-1)
                        }
                        ForEach(pages) { page in
                            MobileReaderPageView(page: page, layout: layout, viewportSize: geometry.size)
                                .id(page.id)
                        }
                        if store.chapterNavigationSnapshot.hasNext {
                            MobilePageChapterBoundary(title: "下一章", action: nextChapter)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .id(pages.count)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $visiblePageID)
                .scrollIndicators(.hidden)
                .scrollDisabled(isPaginating)
                .accessibilityIdentifier("ios.pagedReader")
                .overlay {
                    if isPaginating {
                        ProgressView("正在分页…")
                            .accessibilityIdentifier("ios.paginating")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.background)
                    }
                }
                .task(id: MobilePaginationRequest(layout: layout, contentRevision: chapter.contentRevision)) {
                    await paginate(layout: layout)
                }
                .task(id: store.readerScrollRequest?.id) { applyScrollRequest() }
                .onScrollPhaseChange { _, phase in
                    if phase == .idle { settlePage() }
                }
            }

            HStack {
                Button(currentPage > 0 ? "上一页" : "上一章", systemImage: "chevron.left", action: turnBackward)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("ios.previousPage")
                    .disabled(isPaginating || (currentPage == 0 && !store.chapterNavigationSnapshot.hasPrevious))
                Spacer(minLength: 4)
                Text("第 \(currentPage + 1) / \(max(pages.count, 1)) 页")
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier("ios.pageCount")
                Spacer(minLength: 4)
                Button(currentPage < pages.count - 1 ? "下一页" : "下一章", systemImage: "chevron.right", action: turnForward)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("ios.nextPage")
                    .disabled(isPaginating || (currentPage >= pages.count - 1 && !store.chapterNavigationSnapshot.hasNext))
            }
            .font(.callout)
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
            .padding(.horizontal, 20)
            Text(store.readerProgressText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .onChange(of: visiblePageID) { _, _ in commitPage() }
        .onDisappear {
            commitPage()
            store.flushPendingProgress()
        }
    }

    private var currentPage: Int { min(max(visiblePageID ?? 0, 0), max(pages.count - 1, 0)) }

    private func paginate(layout: MobilePaginationLayout) async {
        let priorPage = pages.first { $0.id == visiblePageID }
        if let fragment = priorPage?.fragments.first {
            anchorParagraph = fragment.paragraphIndex
            anchorOffset = fragment.utf16Offset
        } else if !hasPrepared {
            anchorParagraph = chapter.topParagraphIndex
            anchorOffset = 0
        }
        isPaginating = true
        store.configureContinuousReading(false)
        let paragraphs = store.readerSession.paragraphs(for: chapter)
        do {
            let result = try await paginator.pages(paragraphs: paragraphs, layout: layout)
            try Task.checkCancellation()
            guard store.selectedChapterID == chapter.id else { return }
            pages = result
            visiblePageID = MobileReadingPage.pageID(containingParagraph: anchorParagraph, utf16Offset: anchorOffset, in: result)
            hasPrepared = true
            isPaginating = false
            applyScrollRequest()
        } catch is CancellationError {
            // Reflow/chapter changes cancel the old layout; the newer task owns the UI.
        } catch {
            isPaginating = false
            store.presentedError = PresentedError(message: "章节分页失败：\(error.localizedDescription)")
        }
    }

    private func applyScrollRequest() {
        guard !isPaginating, let request = store.readerScrollRequest, request.chapterID == chapter.id else { return }
        switch request.intent {
        case .chapterTop:
            visiblePageID = pages.first?.id
        case .chapterBottom:
            visiblePageID = pages.last?.id
        case .restore:
            visiblePageID = MobileReadingPage.pageID(containingParagraph: chapter.topParagraphIndex, in: pages)
        }
        store.consumeReaderScrollRequest(request.id)
    }

    private func commitPage() {
        guard !isPaginating, store.selectedChapterID == chapter.id,
              let page = pages.first(where: { $0.id == visiblePageID }),
              let fragment = page.fragments.first else { return }
        anchorParagraph = fragment.paragraphIndex
        anchorOffset = fragment.utf16Offset
        store.updateVisibleReaderPosition(chapterID: chapter.id, paragraphIndex: fragment.paragraphIndex,
                                          total: store.readerSession.paragraphs(for: chapter).count)
    }

    private func settlePage() {
        guard !isPaginating, !pages.isEmpty else { return }
        if visiblePageID == -1 { previousChapter() }
        else if visiblePageID == pages.count { nextChapter() }
        else { commitPage() }
    }

    private func turnBackward() {
        if currentPage > 0 { showPage(currentPage - 1) }
        else { previousChapter() }
    }

    private func turnForward() {
        if currentPage < pages.count - 1 { showPage(currentPage + 1) }
        else { nextChapter() }
    }

    private func showPage(_ id: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { visiblePageID = id }
    }

    private func previousChapter() {
        guard store.chapterNavigationSnapshot.hasPrevious else { return }
        commitPage()
        store.goToPreviousChapter()
        if store.selectedChapterID != chapter.id { store.requestReaderScroll(.chapterBottom) }
    }

    private func nextChapter() {
        guard store.chapterNavigationSnapshot.hasNext else { return }
        commitPage()
        store.goToNextChapter()
    }
}
