import SwiftUI

struct MobileReaderView: View {
    let store: LibraryStore
    let showLibrary: () -> Void
    let showCatalog: () -> Void
    var isCatalogPresented = false
    @BookReaderPresentation private var mode
    @AppStorage(ReaderPreferenceKeys.pageTurnMode) private var pageTurnMode = ReaderPageTurnMode.verticalScroll.rawValue
    @AppStorage(ReaderPreferenceKeys.mangaPageTurnMode) private var mangaPageTurnMode = ReaderPageTurnMode.mangaDefault.rawValue
    @AppStorage(ReaderPreferenceKeys.mangaTabletAutoLandscape) private var autoLandscape = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @State private var viewportSize = CGSize.zero
    @State private var showingAppearance = false
    @State private var showingMore = false
    @State private var controlsVisible = false
    @State private var isScrubbing = false
    @State private var isMangaScrubbing = false
    @State private var sliderIndex = 0.0
    @State private var scrubChapterID: UUID?
    @State private var controlActivity = UUID()
    @State private var chapterLoadTask: Task<Void, Never>?

    private struct AutoHideState: Equatable {
        let enabled: Bool
        let activity: UUID
    }

    private var automaticMangaLandscape: Bool {
        store.selectedChapter?.isManga == true && MangaPageLayout.usesTabletLandscapeSpreads(
            enabled: autoLandscape, isTablet: UIDevice.current.userInterfaceIdiom == .pad, viewport: viewportSize)
    }

    private var usesPages: Bool {
        if store.selectedChapter?.isManga == true {
            return automaticMangaLandscape || mangaPageTurnMode == ReaderPageTurnMode.horizontalPages.rawValue
        }
        return pageTurnMode == ReaderPageTurnMode.horizontalPages.rawValue && mode == ReaderPresentationMode.normal.rawValue
    }

    private var paragraphCount: Int {
        guard let chapter = store.selectedChapter, !chapter.isManga else { return 0 }
        return store.readerSession.paragraphs(for: chapter).count
    }

    private var hideState: AutoHideState {
        AutoHideState(enabled: controlsVisible && !showingAppearance && !showingMore && !isCatalogPresented
                      && !isScrubbing && !isMangaScrubbing && !voiceOverEnabled && !switchControlEnabled,
                      activity: controlActivity)
    }

    var body: some View {
        GeometryReader { geometry in
            ReaderView(store: store, keyboardNavigationEnabled: false, showsPagingControls: false,
                       mangaControlsVisible: controlsVisible,
                       onMangaScrubbingChanged: { editing in isMangaScrubbing = editing; noteActivity() },
                       loadsChapterAutomatically: false, togglePagingControls: toggleControls,
                       automaticMangaLandscape: automaticMangaLandscape)
                .accessibilityAction(named: "显示阅读选项") { showControls() }
                .accessibilityAction(named: "隐藏阅读选项") { controlsVisible = false }
                .simultaneousGesture(TapGesture(count: 2).exclusively(before: SpatialTapGesture())
                    .onEnded { value in
                        guard !usesPages, case let .second(tap) = value,
                              MangaPageLayout.tap(at: tap.location.x, width: geometry.size.width) == .controls else { return }
                        toggleControls()
                    }, including: usesPages ? .none : .all)
                // The system edge recognizer only claims an actual edge swipe;
                // taps and double-taps remain available to the page underneath.
                .gesture(ReaderEdgeBackGesture(action: showLibrary))
                .overlay(alignment: .top) {
                    if controlsVisible { topControls.transition(.opacity) }
                }
                .overlay(alignment: .bottom) {
                    if controlsVisible { bottomControls.transition(.opacity) }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: controlsVisible)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }
        // Keep this hidden for the entire reader lifetime: toggling a navigation
        // bar changes the viewport and can repaginate or shift the scroll position.
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAppearance) {
            MobileReadingAppearanceView(readingManga: store.selectedChapter?.isManga == true,
                                        automaticLandscapeActive: automaticMangaLandscape)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("阅读选项", isPresented: $showingMore, titleVisibility: .visible) {
            Button("重试加载") { Task { await store.ensureSelectedChapterLoaded() } }
                .disabled(store.isLoading)
            Button("刷新目录", action: store.startRefreshSelectedCatalog)
                .disabled(!store.canRefreshSelectedCatalog || store.isLoading)
            Button("缓存当前章", action: store.downloadCurrentChapter).disabled(!store.canDownloadCurrentChapter)
            Button("缓存后续章节", action: store.downloadFollowingChapters).disabled(!store.canDownloadCurrentChapter)
            Button("缓存全书", action: store.downloadEntireBook).disabled(!store.canDownloadEntireBook)
            Button("清除正文缓存", role: .destructive, action: store.deleteOfflineCache).disabled(!store.canDeleteOfflineCache)
            Button("取消", role: .cancel) { }
        }
        .task(id: hideState) {
            guard hideState.enabled else { return }
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            guard !Task.isCancelled, hideState.enabled else { return }
            controlsVisible = false
        }
        .onChange(of: usesPages) { _, _ in readingModeChanged() }
        .onChange(of: store.selectedChapterID) { _, _ in
            isScrubbing = false
            isMangaScrubbing = false
            scrubChapterID = nil
            syncSlider()
            noteActivity()
            loadCurrentChapter()
        }
        .onChange(of: store.selectedChapter?.topParagraphIndex, initial: true) { _, _ in
            if !isScrubbing { syncSlider() }
        }
        .onChange(of: paragraphCount) { _, _ in
            if !isScrubbing { syncSlider() }
        }
        .onChange(of: store.offlineDownloads.completedCount) { _, _ in
            if let chapter = store.selectedChapter, chapter.isAvailableOffline,
               !store.readerSession.entries.contains(where: { $0.id == chapter.id }) {
                loadCurrentChapter()
            }
        }
        .onAppear {
            store.beginReaderPresentation()
            loadCurrentChapter()
        }
        .onDisappear {
            chapterLoadTask?.cancel()
            store.flushPendingProgress()
            store.endReaderPresentation()
        }
    }

    private var topControls: some View {
        HStack(spacing: 8) {
            Button("返回书架", systemImage: "chevron.left", action: showLibrary)
                .labelStyle(.iconOnly)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.selectedBook?.title ?? "阅读").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(store.selectedChapter?.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("目录", systemImage: "list.bullet") { noteActivity(); showCatalog() }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("ios.readerCatalog")
            Button("阅读设置", systemImage: "textformat.size") { noteActivity(); showingAppearance = true }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("ios.readerAppearance")
            Button("更多", systemImage: "ellipsis.circle") { noteActivity(); showingMore = true }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("ios.readerMenu")
        }
        .buttonStyle(ReaderControlButtonStyle())
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private var bottomControls: some View {
        VStack(spacing: 2) {
            if store.selectedChapter?.isManga != true {
                HStack(spacing: 10) {
                    Text("\(progressPercentage)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 38, alignment: .trailing)
                        .accessibilityHidden(true)
                    Slider(value: $sliderIndex, in: 0...Double(max(paragraphCount - 1, 1)), step: 1,
                           onEditingChanged: scrubProgress) { Text("阅读进度") }
                        .disabled(paragraphCount < 2)
                        .accessibilityValue(Text("\(progressPercentage)%"))
                        .accessibilityIdentifier("ios.readerProgressSlider")
                }
                .padding(.horizontal, 10)
            }
            ViewThatFits(in: .horizontal) {
                chapterNavigation(showLabels: true)
                chapterNavigation(showLabels: false)
            }
            .padding(.horizontal, 10)
            if store.offlineDownloads.isDownloading || store.offlineDownloads.failureMessage != nil {
                HStack {
                    Text(store.offlineDownloads.failureMessage ?? store.offlineDownloads.progressMessage)
                        .font(.caption).lineLimit(2)
                    Spacer()
                    if store.offlineDownloads.isDownloading {
                        Button("取消下载", action: store.cancelOfflineDownload)
                    } else {
                        Button("关闭状态", action: store.offlineDownloads.dismissFailure)
                    }
                }
                .font(.caption)
                .padding(.horizontal, 10)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private var progressPercentage: Int {
        let progress = isScrubbing && paragraphCount > 1
            ? sliderIndex / Double(paragraphCount - 1)
            : (store.selectedChapter?.readingProgress ?? 0)
        return Int((min(max(progress, 0), 1) * 100).rounded())
    }

    private func chapterNavigation(showLabels: Bool) -> some View {
        HStack(spacing: 4) {
            Button {
                noteActivity()
                store.goToPreviousChapter()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").accessibilityHidden(true)
                    if showLabels { Text("上一章") }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("上一章")
            .disabled(!store.chapterNavigationSnapshot.hasPrevious)

            Spacer(minLength: 4)
            Text(store.chapterNavigationSnapshot.positionText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: showLabels, vertical: false)
            Spacer(minLength: 4)

            Button {
                noteActivity()
                store.goToNextChapter()
            } label: {
                HStack(spacing: 4) {
                    if showLabels { Text("下一章") }
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("下一章")
            .disabled(!store.chapterNavigationSnapshot.hasNext)
        }
        .font(.callout)
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
    }

    private func scrubProgress(_ editing: Bool) {
        noteActivity()
        if editing {
            isScrubbing = true
            scrubChapterID = store.selectedChapterID
            return
        }
        defer { isScrubbing = false; scrubChapterID = nil }
        guard let chapter = store.selectedChapter, chapter.id == scrubChapterID, paragraphCount > 0 else {
            syncSlider()
            return
        }
        let index = min(max(Int(sliderIndex.rounded()), 0), paragraphCount - 1)
        store.updateVisibleReaderPosition(chapterID: chapter.id, paragraphIndex: index, total: paragraphCount)
        store.requestReaderScroll(.restore)
    }

    private func syncSlider() {
        sliderIndex = Double(min(max(store.selectedChapter?.topParagraphIndex ?? 0, 0), max(paragraphCount - 1, 1)))
    }
    private func noteActivity() { controlActivity = UUID() }
    private func showControls() { noteActivity(); controlsVisible = true }
    private func toggleControls() { noteActivity(); controlsVisible.toggle() }

    private func readingModeChanged() {
        controlsVisible = false
        loadCurrentChapter()
    }

    private func loadCurrentChapter() {
        chapterLoadTask?.cancel()
        let chapterID = store.selectedChapterID
        if usesPages { store.configureContinuousReading(false) }
        chapterLoadTask = Task {
            await store.ensureSelectedChapterLoaded()
            guard !Task.isCancelled, store.selectedChapterID == chapterID else { return }
            store.prepareContinuousReadingIfNeeded()
        }
    }
}

private struct ReaderControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

/// A system edge pan leaves ordinary page taps and manga double-tap zoom intact.
private struct ReaderEdgeBackGesture: UIGestureRecognizerRepresentable {
    let action: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIScreenEdgePanGestureRecognizer {
        let recognizer = UIScreenEdgePanGestureRecognizer()
        recognizer.edges = .left
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIScreenEdgePanGestureRecognizer, context: Context) {
        guard recognizer.state == .ended else { return }
        let translation = recognizer.translation(in: recognizer.view)
        guard translation.x > 60, translation.x > abs(translation.y) * 1.5 else { return }
        action()
    }
}
