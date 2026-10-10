import SwiftUI

struct MangaReaderView: View {
    let store: LibraryStore
    let chapter: Chapter
    let keyboardNavigationEnabled: Bool
    var showsControls = true
    let imageCache: MangaImageCache
    var toggleControls: () -> Void = {}
    @AppStorage(ReaderPreferenceKeys.mangaPageTurnMode) private var pageTurnMode = ReaderPageTurnMode.mangaDefault.rawValue
    @AppStorage(ReaderPreferenceKeys.prefetchNext) private var prefetch = true
    @AppStorage(ReaderPreferenceKeys.mangaPageLayout) private var layoutName = MangaPageLayout.Mode.automatic.rawValue
    @AppStorage(ReaderPreferenceKeys.mangaFirstPageAlone) private var firstPageAlone = true
    @AppStorage(ReaderPreferenceKeys.mangaDarkBackground) private var darkBackground = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var pageIndex: Int
    @State private var sliderValue: Double
    @State private var isScrubbing = false
    @State private var restoringScroll = true
    @State private var ratios: [String: Double] = [:]
    @State private var cachedRatiosReady = false
    @State private var loadedPages = Set<Int>()
    @State private var canvasSize = CGSize.zero
    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    @State private var scrollState = ReaderScrollState()
    private var urls: [URL] { chapter.imageSourceURLs.compactMap(URL.init(string:)) }
    private var usesPages: Bool { pageTurnMode == ReaderPageTurnMode.horizontalPages.rawValue }
    private var desktop: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    init(store: LibraryStore, chapter: Chapter, showsControls: Bool = true,
         keyboardNavigationEnabled: Bool = true, imageCache: MangaImageCache = .shared, toggleControls: @escaping () -> Void = {}) {
        self.store = store
        self.chapter = chapter
        self.showsControls = showsControls
        self.keyboardNavigationEnabled = keyboardNavigationEnabled
        self.toggleControls = toggleControls
        self.imageCache = imageCache
        let index = Self.resolvedPageIndex(request: store.readerScrollRequest, chapter: chapter,
                                          total: chapter.imageSourceURLs.count)
            ?? min(max(chapter.topParagraphIndex, 0), max(chapter.imageSourceURLs.count - 1, 0))
        _pageIndex = State(initialValue: index)
        _sliderValue = State(initialValue: Double(index + 1))
    }

    var body: some View {
        if let referer = chapterURL {
            reader(referer: referer)
        } else {
            invalidChapterAddress
        }
    }

    /// A persisted chapter address that no longer parses cannot serve as a referer.
    /// Report it with a way out instead of substituting an unrelated site.
    private var invalidChapterAddress: some View {
        ContentUnavailableView {
            Label("章节地址无效", systemImage: "exclamationmark.triangle")
        } description: {
            Text("无法确定这本漫画的章节地址，图片请求缺少合法的来源地址。请刷新目录后重试。")
        } actions: {
            Button("刷新目录", action: store.startRefreshSelectedCatalog)
                .disabled(!store.canRefreshSelectedCatalog || store.isLoading)
            Button("重试加载") { Task { await store.ensureSelectedChapterLoaded() } }
                .disabled(store.isLoading)
        }
        .accessibilityIdentifier("manga.invalidChapterAddress")
    }

    @ViewBuilder
    private func reader(referer: URL) -> some View {
        let pages = urls
        let aspectRatios = pages.map { ratios[$0.absoluteString] }
        let layout = MangaPageLayout(aspectRatios: aspectRatios,
            mode: desktop ? (MangaPageLayout.Mode(rawValue: layoutName) ?? .automatic) : .single,
            firstPageAlone: firstPageAlone, viewport: canvasSize)
        let group = layout.group(containing: pageIndex)
        VStack(spacing: 0) {
            // Measure the space actually left by the native controls. Images
            // must fit this region rather than a manually estimated bar height.
            GeometryReader { geometry in
                if usesPages {
                    #if os(iOS)
                    MobileMangaPager(pages: pages, referer: referer, pageIndex: pageIndex,
                        size: geometry.size, imageCache: imageCache,
                        hasPrevious: store.chapterNavigationSnapshot.hasPrevious,
                        hasNext: store.chapterNavigationSnapshot.hasNext,
                        turn: { turn($0, layout: layout) }, toggleControls: toggleControls,
                        didLoad: { index, ratio in imageLoaded(index: index, ratio: ratio, pages: pages) })
                    #else
                    if cachedRatiosReady {
                        pagedCanvas(pages: pages, layout: layout, group: group, size: geometry.size, referer: referer)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    #endif
                } else {
                    scrollingCanvas(pages: pages, aspectRatios: aspectRatios, size: geometry.size, referer: referer)
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
            if showsControls {
                pagingControls(layout: layout, group: group, total: pages.count)
            }
        }
        .task(id: prefetchKey(group: group)) {
            await prefetchImages(after: usesPages ? max(group.upperBound - 1, pageIndex) : pageIndex, pages: pages, referer: referer)
        }
        .background(desktop && darkBackground ? Color(white: 0.10) : Color.clear)
        .environment(\.colorScheme, desktop && darkBackground ? .dark : colorScheme)
        .task(id: chapter.contentRevision) {
            await refreshRatios(pages)
            if !Task.isCancelled { cachedRatiosReady = true }
        }
        .task(id: store.readerScrollRequest?.id) {
            guard usesPages else { return }
            if let index = requestedPageIndex(total: pages.count) { seek(to: index) }
            consumePendingScrollRequest()
        }
        .onChange(of: usesPages) { _, _ in
            // Layout changes never alter pageIndex, which is an original image index.
            restoringScroll = true
        }
        .onChange(of: pageIndex) { _, index in
            if !isScrubbing { sliderValue = Double(index + 1) }
            savePosition(total: pages.count)
        }
        .onDisappear { _ = store.flushPendingProgress() }
        .accessibilityElement(children: .contain)
    }

    private func pagedCanvas(pages: [URL], layout: MangaPageLayout, group: Range<Int>, size: CGSize, referer: URL) -> some View {
        let pageRatios = group.map { ratios[pages[$0].absoluteString] ?? 0.7 }
        let gap = group.count == 2 ? 16.0 : 0.0
        let height = MangaPageLayout.fittedHeight(ratios: pageRatios,
            viewport: CGSize(width: max(1, size.width - 16), height: max(1, size.height - 8)), gap: gap)
        return HStack(spacing: 0) {
            ForEach(Array(group), id: \.self) { index in
                if index > group.lowerBound {
                    Rectangle().fill(Color.primary.opacity(0.18))
                        .frame(width: 1, height: height)
                        .frame(width: gap)
                        .accessibilityHidden(true)
                }
                MangaPageImage(url: pages[index], referer: referer, pageNumber: index + 1,
                               imageCache: imageCache) { ratio in
                    imageLoaded(index: index, ratio: ratio, pages: pages)
                }
                .frame(width: height * pageRatios[index - group.lowerBound], height: height)
                .id(pages[index])
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .modifier(MangaPageTurnGesture(width: size.width, backward: { turn(-1, layout: layout) },
                                      forward: { turn(1, layout: layout) }, controls: toggleControls))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("manga.canvas")
        .accessibilityValue(pageLabel(group: group, total: pages.count))
        .accessibilityAction(named: "上一页") { turn(-1, layout: layout) }
        .accessibilityAction(named: "下一页") { turn(1, layout: layout) }
        .background {
            #if os(macOS)
            if keyboardNavigationEnabled {
                ReaderKeyboardEventBridge { command in
                    switch command {
                    case .moveUp, .pageBackward: turn(-1, layout: layout)
                    case .moveDown, .pageForward: turn(1, layout: layout)
                    }
                }
                .allowsHitTesting(false)
            }
            #endif
        }
    }

    private func scrollingCanvas(pages: [URL], aspectRatios: [Double?], size: CGSize, referer: URL) -> some View {
        let width = MangaPageLayout.scrollWidth(viewportWidth: size.width, desktop: desktop)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { index in
                    MangaPageImage(url: pages[index], referer: referer, pageNumber: index + 1,
                                   imageCache: imageCache) { ratio in
                        imageLoaded(index: index, ratio: ratio, pages: pages)
                    }
                    .frame(width: width, height: width / (ratios[pages[index].absoluteString] ?? 0.7))
                    .padding(.bottom, MangaPageLayout.gap(after: index, ratios: aspectRatios))
                    .id(index)
                }
                HStack {
                    Button("上一话", systemImage: "chevron.left") { changeChapter(backward: true) }
                        .disabled(!store.chapterNavigationSnapshot.hasPrevious)
                    Spacer()
                    Button("下一话", systemImage: "chevron.right") { changeChapter(backward: false) }
                        .disabled(!store.chapterNavigationSnapshot.hasNext)
                }.padding(12)
            }
            .scrollTargetLayout()
            .frame(width: width)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: ReaderScrollMetrics.self) { ReaderScrollMetrics(geometry: $0) }
        action: { _, metrics in scrollState.update(metrics: metrics) }
        .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.2) { indices in
            guard !restoringScroll, !isScrubbing, let index = indices.min() else { return }
            pageIndex = index
        }
        .onScrollPhaseChange { _, phase in
            // Release a programmatic anchor only when the user starts scrolling.
            // It keeps the selected image pinned while placeholder heights settle.
            if phase == .interacting || phase == .tracking { restoringScroll = false }
        }
        .task {
            await Task.yield()
            scrollPosition.scrollTo(id: pageIndex, anchor: .top)
            restoringScroll = true
            consumePendingScrollRequest()
        }
        .onChange(of: store.readerScrollRequest?.id) { _, _ in
            if let index = requestedPageIndex(total: pages.count) { seek(to: index) }
            consumePendingScrollRequest()
        }
        .background {
            #if os(macOS)
            if keyboardNavigationEnabled {
                ReaderKeyboardEventBridge { command in
                    restoringScroll = false
                    let y: Double
                    switch command {
                    case .moveUp: y = scrollState.destinationY(distance: -ReaderPageScroll.smallStep)
                    case .moveDown: y = scrollState.destinationY(distance: ReaderPageScroll.smallStep)
                    case .pageBackward: y = scrollState.pageDestinationY(direction: -1, fallbackViewportHeight: size.height)
                    case .pageForward: y = scrollState.pageDestinationY(direction: 1, fallbackViewportHeight: size.height)
                    }
                    scrollPosition = ScrollPosition(idType: Int.self, y: y)
                }
                .allowsHitTesting(false)
            }
            #endif
        }
    }

    private func pagingControls(layout: MangaPageLayout, group: Range<Int>, total: Int) -> some View {
        HStack(spacing: 8) {
            if usesPages {
                Button("上一页", systemImage: "chevron.left") { turn(-1, layout: layout) }
                    .labelStyle(.iconOnly).frame(minWidth: 32, minHeight: 44)
                    .disabled(group.lowerBound == 0 && !store.chapterNavigationSnapshot.hasPrevious)
                    .accessibilityIdentifier("manga.previousPage")
            }
            Text(isScrubbing ? "\(Int(sliderValue)) / \(total)" : pageLabel(group: usesPages ? group : pageIndex..<pageIndex + 1, total: total))
                .font(.caption.monospacedDigit()).frame(minWidth: 72)
                .accessibilityIdentifier("manga.pageCount")
            Slider(value: $sliderValue, in: 1...Double(max(2, total)), step: 1, onEditingChanged: { editing in
                isScrubbing = editing
                if !editing { seek(to: Int(sliderValue.rounded()) - 1) }
            }) { Text("跳到图片") }
            .disabled(total <= 1)
            .accessibilityIdentifier("manga.pageSlider")
            .frame(maxWidth: desktop ? 240 : .infinity)
            if usesPages {
                Button("下一页", systemImage: "chevron.right") { turn(1, layout: layout) }
                    .labelStyle(.iconOnly).frame(minWidth: 32, minHeight: 44)
                    .disabled(group.upperBound == total && !store.chapterNavigationSnapshot.hasNext)
                    .accessibilityIdentifier("manga.nextPage")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }

    private func pageLabel(group: Range<Int>, total: Int) -> String {
        guard !group.isEmpty else { return "0 / \(total)" }
        return group.count == 1 ? "\(group.lowerBound + 1) / \(total)" : "\(group.lowerBound + 1)–\(group.upperBound) / \(total)"
    }

    private func turn(_ direction: Int, layout: MangaPageLayout) {
        guard !isScrubbing, store.selectedChapterID == chapter.id else { return }
        if let next = layout.adjacentIndex(from: pageIndex, direction: direction) { seek(to: next) }
        else { changeChapter(backward: direction < 0) }
    }

    private func changeChapter(backward: Bool) {
        guard backward ? store.chapterNavigationSnapshot.hasPrevious : store.chapterNavigationSnapshot.hasNext else { return }
        savePosition(total: urls.count)
        if backward { store.goToPreviousChapter() } else { store.goToNextChapter() }
        if store.selectedChapterID != chapter.id { store.requestReaderScroll(backward ? .chapterBottom : .chapterTop) }
    }

    private func seek(to index: Int) {
        pageIndex = min(max(index, 0), max(urls.count - 1, 0))
        sliderValue = Double(pageIndex + 1)
        if !usesPages {
            restoringScroll = true
            scrollPosition.scrollTo(id: pageIndex, anchor: .top)
        }
        savePosition(total: urls.count)
    }

    /// Referer for every image request. Only the chapter's own address qualifies:
    /// borrowing another site's address would silently send the images of this
    /// chapter with a foreign referer, so an unusable address reports a
    /// recoverable error instead.
    private var chapterURL: URL? {
        guard let url = URL(string: chapter.sourceURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
    private func requestedPageIndex(total: Int) -> Int? {
        Self.resolvedPageIndex(request: store.readerScrollRequest, chapter: chapter, total: total)
    }
    private static func resolvedPageIndex(request: ReaderScrollRequest?, chapter: Chapter, total: Int) -> Int? {
        guard let request, request.chapterID == chapter.id else { return nil }
        switch request.intent {
        case .chapterTop: return 0
        case .chapterBottom: return max(total - 1, 0)
        case .restore: return min(max(chapter.topParagraphIndex, 0), max(total - 1, 0))
        }
    }
    private func consumePendingScrollRequest() {
        guard let request = store.readerScrollRequest, request.chapterID == chapter.id else { return }
        store.consumeReaderScrollRequest(request.id)
    }
    private func savePosition(total: Int) {
        guard store.selectedChapterID == chapter.id else { return }
        store.updateProgress(chapterID: chapter.id, paragraphIndex: pageIndex, total: total)
    }
    private func imageLoaded(index: Int, ratio: Double, pages: [URL]) {
        guard store.selectedChapterID == chapter.id, pages.indices.contains(index) else { return }
        ratios[pages[index].absoluteString] = ratio
        loadedPages.insert(index)
        Task {
            if chapter.imagesCachedAt == nil, await imageCache.containsAll(pages) {
                store.markChapterImagesCached(chapter)
            }
        }
    }
    private func refreshRatios(_ pages: [URL]) async {
        let known = await imageCache.cachedAspectRatios(for: pages)
        guard !Task.isCancelled, store.selectedChapterID == chapter.id else { return }
        ratios.merge(known) { _, new in new }
    }
    private func prefetchKey(group: Range<Int>) -> String {
        let ready = usesPages ? group.allSatisfy { loadedPages.contains($0) } : loadedPages.contains(pageIndex)
        return "\(prefetch)-\(ready)-\(usesPages ? group.upperBound - 1 : pageIndex)"
    }
    private func prefetchImages(after index: Int, pages: [URL], referer: URL) async {
        guard prefetch, loadedPages.contains(index) else { return }
        do {
            let images = try await store.mangaPrefetchImages(after: chapter, pageIndex: index)
            for url in images {
                try Task.checkCancellation()
                guard prefetch else { return }
                _ = try await imageCache.original(at: url, referer: referer)
            }
            await refreshRatios(pages)
            if !Task.isCancelled, chapter.imagesCachedAt == nil, await imageCache.containsAll(pages) {
                store.markChapterImagesCached(chapter)
            }
        } catch { /* Prefetch is opportunistic; a failure never replaces the visible page. */ }
    }
}
