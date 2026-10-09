import SwiftUI

struct MobilePagedReaderView: View {
    let store: LibraryStore
    let chapter: Chapter
    var showsControls = true
    var toggleControls: () -> Void = {}
    @AppStorage(ReaderPreferenceKeys.fontFamily) private var fontFamily = ReaderFontFamily.serif.rawValue
    @AppStorage(ReaderPreferenceKeys.fontSize) private var fontSize = 20.0
    @AppStorage(ReaderPreferenceKeys.lineSpacing) private var lineSpacing = ReaderLineSpacingPreset.comfortable.value
    @AppStorage(ReaderPreferenceKeys.paragraphSpacing) private var paragraphSpacing = 0.60
    @AppStorage(ReaderPreferenceKeys.contentWidth) private var contentWidth = ReaderViewportLayout.defaultPreferredWidthEM
    @AppStorage(ReaderPreferenceKeys.paragraphIndent) private var indent = true
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0
    @State private var pagination = MobilePaginationStore()
    @State private var visiblePageID: Int?
    @State private var anchorParagraph = 0
    @State private var anchorOffset = 0
    @State private var hasPrepared = false
    @State private var userIsPaging = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let font = MobileReadingFont.resolve(ReaderFontFamily(rawValue: fontFamily) ?? .serif,
                                                     size: fontSize * textScale)
                let layout = MobilePaginationLayout(
                    width: ReaderViewportLayout.effectiveContentWidth(preferredWidthEM: contentWidth,
                                                                      fontSize: fontSize * textScale,
                                                                      viewportWidth: geometry.size.width).rounded(.down),
                    height: max((geometry.size.height * displayScale).rounded(.down) / displayScale - 24, 1), fontName: font.fontName,
                    fontSize: font.pointSize, lineHeight: font.lineHeight,
                    lineSpacing: lineSpacing * fontSize * textScale,
                    paragraphSpacing: paragraphSpacing * fontSize * textScale, usesFirstLineIndent: indent
                )
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        if !pagination.pages.isEmpty && store.chapterNavigationSnapshot.hasPrevious {
                            MobilePageChapterBoundary(title: "上一章", action: previousChapter)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .id(-1)
                        }
                        ForEach(pagination.pages) { page in
                            MobileReaderPageView(page: page, layout: layout, viewportSize: geometry.size)
                                .id(page.id)
                        }
                        if !pagination.pages.isEmpty && store.chapterNavigationSnapshot.hasNext {
                            MobilePageChapterBoundary(title: "下一章", action: nextChapter)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .id(Int.max)
                        }
                    }
                    .scrollTargetLayout()
                }
                .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                    guard !pagination.isPaginating else { return }
                    switch MangaPageLayout.tap(at: tap.location.x, width: geometry.size.width) {
                    case .backward: turnBackward()
                    case .forward: turnForward()
                    case .controls: toggleControls()
                    }
                })
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $visiblePageID)
                .scrollIndicators(.hidden)
                .scrollDisabled(pagination.isPaginating)
                .accessibilityIdentifier("ios.pagedReader")
                .accessibilityValue(Text("\(chapter.title) · \(currentPage + 1)/\(max(pagination.pages.count, 1))"))
                .overlay {
                    if pagination.isPaginating {
                        ProgressView("正在分页…")
                            .accessibilityIdentifier("ios.paginating")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.background)
                    }
                }
                .onChange(of: MobilePaginationRequest(chapterID: chapter.id, layout: layout, contentRevision: chapter.contentRevision), initial: true) { _, request in
                    startPagination(request: request)
                }
                .task(id: store.readerScrollRequest?.id) { applyScrollRequest() }
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting { userIsPaging = true }
                    if phase == .idle, userIsPaging {
                        userIsPaging = false
                        settlePage()
                    }
                }
            }

            if showsControls {
                HStack {
                    Button(currentPage > 0 ? "上一页" : "上一章", systemImage: "chevron.left", action: turnBackward)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("ios.previousPage")
                        .disabled(pagination.isPaginating || (currentPage == 0 && !store.chapterNavigationSnapshot.hasPrevious))
                    Spacer(minLength: 4)
                    Text("第 \(currentPage + 1) / \(max(pagination.pages.count, 1)) 页")
                        .font(.caption.monospacedDigit())
                        .accessibilityIdentifier("ios.pageCount")
                    Spacer(minLength: 4)
                    Button(currentPage < pagination.pages.count - 1 ? "下一页" : "下一章", systemImage: "chevron.right", action: turnForward)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("ios.nextPage")
                        .disabled(pagination.isPaginating || (currentPage >= pagination.pages.count - 1 && !store.chapterNavigationSnapshot.hasNext))
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
        }
        .onChange(of: pagination.completedRequest) { _, request in
            guard request?.chapterID == chapter.id else { return }
            visiblePageID = MobileReadingPage.pageID(containingParagraph: anchorParagraph, utf16Offset: anchorOffset, in: pagination.pages)
            hasPrepared = true
            applyScrollRequest()
        }
        .onChange(of: pagination.errorMessage) { _, message in
            if let message { store.presentedError = PresentedError(message: message) }
        }
        .onChange(of: visiblePageID) { _, _ in commitPage() }
        .onDisappear {
            commitPage()
            pagination.cancel()
            store.flushPendingProgress()
        }
    }

    private var currentPage: Int { min(max(visiblePageID ?? 0, 0), max(pagination.pages.count - 1, 0)) }

    private func startPagination(request: MobilePaginationRequest) {
        let priorPage = pagination.pages.first { $0.id == visiblePageID }
        if let fragment = priorPage?.fragments.first {
            anchorParagraph = fragment.paragraphIndex
            anchorOffset = fragment.utf16Offset
        } else if !hasPrepared {
            anchorParagraph = chapter.topParagraphIndex
            anchorOffset = chapter.topUTF16Offset
        }
        // Viewport changes must not be mistaken for a swipe across a chapter boundary.
        userIsPaging = false
        store.configureContinuousReading(false)
        pagination.start(request: request, paragraphs: store.readerSession.paragraphs(for: chapter))
    }

    private func applyScrollRequest() {
        guard !pagination.isPaginating, !pagination.pages.isEmpty,
              let request = store.readerScrollRequest, request.chapterID == chapter.id else { return }
        switch request.intent {
        case .chapterTop:
            visiblePageID = pagination.pages.first?.id
        case .chapterBottom:
            visiblePageID = pagination.pages.last?.id
        case .restore:
            visiblePageID = MobileReadingPage.pageID(
                containingParagraph: chapter.topParagraphIndex,
                utf16Offset: chapter.topUTF16Offset,
                in: pagination.pages
            )
        }
        store.consumeReaderScrollRequest(request.id)
    }

    private func commitPage() {
        guard !pagination.isPaginating, store.selectedChapterID == chapter.id,
              let page = pagination.pages.first(where: { $0.id == visiblePageID }),
              let fragment = page.fragments.first else { return }
        anchorParagraph = fragment.paragraphIndex
        anchorOffset = fragment.utf16Offset
        store.updateVisibleReaderPosition(chapterID: chapter.id, paragraphIndex: fragment.paragraphIndex,
                                          utf16Offset: fragment.utf16Offset,
                                          total: store.readerSession.paragraphs(for: chapter).count)
    }

    private func settlePage() {
        guard !pagination.isPaginating, !pagination.pages.isEmpty else { return }
        if visiblePageID == -1 { previousChapter() }
        else if visiblePageID == Int.max { nextChapter() }
        else { commitPage() }
    }

    private func turnBackward() {
        if currentPage > 0 { showPage(currentPage - 1) }
        else { previousChapter() }
    }

    private func turnForward() {
        if currentPage < pagination.pages.count - 1 { showPage(currentPage + 1) }
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
