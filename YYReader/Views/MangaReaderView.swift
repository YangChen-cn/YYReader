import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct MangaReaderView: View {
    let store: LibraryStore
    let chapter: Chapter
    let keyboardNavigationEnabled: Bool
    var showsControls = true
    @AppStorage(ReaderPreferenceKeys.pageTurnMode) private var pageTurnMode = ReaderPageTurnMode.verticalScroll.rawValue
    @AppStorage(ReaderPreferenceKeys.prefetchNext) private var prefetch = true
    @State private var pageIndex = 0
    @State private var restored = false
    @State private var visiblePages: [Int] = []
    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    @State private var scrollState = ReaderScrollState()
    private var urls: [URL] { chapter.imageSourceURLs.compactMap(URL.init(string:)) }
    private var usesPages: Bool { pageTurnMode == ReaderPageTurnMode.horizontalPages.rawValue }

    init(store: LibraryStore, chapter: Chapter, showsControls: Bool = true, keyboardNavigationEnabled: Bool = true) {
        self.store = store
        self.chapter = chapter
        self.showsControls = showsControls
        self.keyboardNavigationEnabled = keyboardNavigationEnabled
        let total = chapter.imageSourceURLs.count
        _pageIndex = State(initialValue: Self.resolvedPageIndex(
            request: store.readerScrollRequest,
            chapter: chapter,
            total: total
        ) ?? min(max(chapter.topParagraphIndex, 0), max(total - 1, 0)))
    }

    var body: some View {
        let pages = urls
        GeometryReader { geometry in
            VStack(spacing: 0) {
                #if os(macOS)
                HStack {
                    Text(chapter.title).lineLimit(1)
                    Spacer()
                    Picker("阅读方式", selection: $pageTurnMode) {
                        Text("上下滚动").tag(ReaderPageTurnMode.verticalScroll.rawValue)
                        Text("左右翻页").tag(ReaderPageTurnMode.horizontalPages.rawValue)
                    }.fixedSize()
                }.padding(12)
                #endif
                if usesPages {
                    if pages.indices.contains(pageIndex) {
                        MangaPageImage(url: pages[pageIndex], referer: chapterURL, pageNumber: pageIndex + 1,
                                       fitHeight: geometry.size.height - (showsControls ? 48 : 0)) {
                            await pageLoaded(at: pageIndex, pages: pages)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            turnPage(value.translation.width < 0 ? 1 : -1, total: pages.count)
                        })
                        .background {
                            #if os(macOS)
                            if keyboardNavigationEnabled {
                                ReaderKeyboardEventBridge { command in
                                    switch command {
                                    case .moveUp, .pageBackward: turnPage(-1, total: pages.count)
                                    case .moveDown, .pageForward: turnPage(1, total: pages.count)
                                    }
                                }
                            }
                            #endif
                        }
                    }
                    if showsControls { pagingControls(total: pages.count) }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(pages.indices, id: \.self) { index in
                                    MangaPageImage(url: pages[index], referer: chapterURL, pageNumber: index + 1) {
                                        await pageLoaded(at: index, pages: pages)
                                    }
                                    .id(index)
                                }
                                HStack {
                                    Button("上一话", systemImage: "chevron.left", action: store.goToPreviousChapter)
                                        .disabled(!store.chapterNavigationSnapshot.hasPrevious)
                                    Spacer()
                                    Button("下一话", systemImage: "chevron.right", action: store.goToNextChapter)
                                        .disabled(!store.chapterNavigationSnapshot.hasNext)
                                }.padding()
                            }
                            .scrollTargetLayout()
                            .frame(maxWidth: 900)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollPosition($scrollPosition)
                        .onScrollGeometryChange(for: ReaderScrollMetrics.self) { ReaderScrollMetrics(geometry: $0) }
                        action: { _, metrics in scrollState.update(metrics: metrics) }
                        .background {
                            #if os(macOS)
                            if keyboardNavigationEnabled {
                                ReaderKeyboardEventBridge { command in
                                    let destination: Double
                                    switch command {
                                    case .moveUp: destination = scrollState.destinationY(distance: -ReaderPageScroll.smallStep)
                                    case .moveDown: destination = scrollState.destinationY(distance: ReaderPageScroll.smallStep)
                                    case .pageBackward: destination = scrollState.pageDestinationY(direction: -1, fallbackViewportHeight: geometry.size.height)
                                    case .pageForward: destination = scrollState.pageDestinationY(direction: 1, fallbackViewportHeight: geometry.size.height)
                                    }
                                    scrollPosition = ScrollPosition(idType: Int.self, y: destination)
                                }
                            }
                            #endif
                        }
                        .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.2) { indices in
                            visiblePages = indices.sorted()
                            if restored, let index = visiblePages.first { pageIndex = index }
                        }
                        .onScrollPhaseChange { _, phase in
                            guard phase == .idle, restored, let index = visiblePages.first else { return }
                            pageIndex = index
                            savePosition(total: pages.count)
                        }
                        .task(id: usesPages) {
                            await Task.yield()
                            proxy.scrollTo(pageIndex, anchor: .top)
                            restored = true
                        }
                        .onChange(of: store.readerScrollRequest?.id) { _, _ in
                            // A request can arrive while this view is already on
                            // screen, e.g. "继续阅读" from the catalog on iPad.
                            guard let index = requestedPageIndex(total: pages.count) else { return }
                            pageIndex = index
                            proxy.scrollTo(index, anchor: .top)
                            restored = true
                            consumePendingScrollRequest()
                        }
                    }
                }
            }
        }
        .task(id: store.readerScrollRequest?.id) {
            // Paged mode shows a single page driven by pageIndex; the scrolling
            // branch moves its own ScrollView above.
            guard !usesPages, let index = requestedPageIndex(total: urls.count) else { return }
            pageIndex = index
            consumePendingScrollRequest()
        }
        .onChange(of: pageIndex) { _, _ in savePosition(total: pages.count) }
        .onDisappear { _ = store.flushPendingProgress() }
        .accessibilityIdentifier("reader.manga")
    }

    private var chapterURL: URL { URL(string: chapter.sourceURL) ?? URL(string: "https://www.guazimanhua.com/")! }

    private func pagingControls(total: Int) -> some View {
        HStack {
            Button("上一页", systemImage: "chevron.left") { turnPage(-1, total: total) }
                .disabled(pageIndex == 0 && !store.chapterNavigationSnapshot.hasPrevious)
            Spacer()
            Text("\(pageIndex + 1) / \(total)").font(.caption).monospacedDigit()
            Spacer()
            Button("下一页", systemImage: "chevron.right") { turnPage(1, total: total) }
                .disabled(pageIndex == total - 1 && !store.chapterNavigationSnapshot.hasNext)
        }.padding(12)
    }

    private func turnPage(_ delta: Int, total: Int) {
        let next = pageIndex + delta
        if next < 0 { store.goToPreviousChapter() }
        else if next >= total { store.goToNextChapter() }
        else { pageIndex = next }
    }

    private func requestedPageIndex(total: Int) -> Int? {
        Self.resolvedPageIndex(request: store.readerScrollRequest, chapter: chapter, total: total)
    }

    private static func resolvedPageIndex(
        request: ReaderScrollRequest?,
        chapter: Chapter,
        total: Int
    ) -> Int? {
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
        // A stale view must not write back after the reader moved to another
        // chapter: updateProgress also points the book at this chapter.
        guard store.selectedChapterID == chapter.id else { return }
        store.updateProgress(chapterID: chapter.id, paragraphIndex: pageIndex, total: total)
    }

    private func pageLoaded(at index: Int, pages: [URL]) async {
        await markOfflineIfComplete(pages)
        guard prefetch, !Task.isCancelled else { return }
        // Opportunistic prefetch is disk-only and may fail without affecting the visible image.
        do {
            let images = try await store.mangaPrefetchImages(after: chapter, pageIndex: index)
            for url in images {
                try Task.checkCancellation()
                guard prefetch else { return }
                _ = try await MangaImageCache.shared.original(at: url, referer: chapterURL)
            }
            await markOfflineIfComplete(pages)
        } catch { }
    }

    private func markOfflineIfComplete(_ pages: [URL]) async {
        guard chapter.imagesCachedAt == nil,
              await MangaImageCache.shared.containsAll(pages) else { return }
        // The store owns the flag so it can persist it (and report a failure)
        // even when no reading progress is pending.
        store.markChapterImagesCached(chapter)
    }
}

private struct MangaPageImage: View {
    let url: URL
    let referer: URL
    let pageNumber: Int
    var fitHeight: CGFloat? = nil
    let didLoad: () async -> Void
    @State private var image: Image?
    @State private var aspectRatio = 0.7
    @State private var errorMessage: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if let image {
                image.resizable().aspectRatio(aspectRatio, contentMode: .fit)
                    .accessibilityLabel("漫画第 \(pageNumber) 页")
            } else {
                VStack(spacing: 12) {
                    if let errorMessage {
                        Image(systemName: "photo.badge.exclamationmark")
                        Text(errorMessage).font(.caption).multilineTextAlignment(.center)
                        Button("重试加载") { retry += 1 }
                    } else { ProgressView("加载第 \(pageNumber) 页…") }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .frame(height: fitHeight ?? 500)
            }
        }
        .frame(maxHeight: fitHeight)
        .onDisappear { image = nil }
        .task(id: "\(url.absoluteString)#\(retry)") {
            image = nil
            errorMessage = nil
            do {
                let payload = try await MangaImageCache.shared.image(at: url, referer: referer)
                try Task.checkCancellation()
                #if os(iOS)
                guard let native = UIImage(data: payload.data) else { throw HTMLLoadError.invalidResponse }
                image = Image(uiImage: native)
                #else
                guard let native = NSImage(data: payload.data) else { throw HTMLLoadError.invalidResponse }
                image = Image(nsImage: native)
                #endif
                aspectRatio = payload.aspectRatio
                await didLoad()
            } catch is CancellationError {
                // Scrolling past a page cancels its work normally.
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
