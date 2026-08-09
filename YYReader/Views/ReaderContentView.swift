import SwiftUI

struct ReaderContentView: View {
    let chapter: Chapter
    let store: LibraryStore

    @AppStorage(ReaderPreferenceKeys.fontFamily) private var fontFamily = ReaderFontFamily.serif.rawValue
    @AppStorage(ReaderPreferenceKeys.fontSize) private var fontSize = 20.0
    @AppStorage(ReaderPreferenceKeys.lineSpacing) private var lineSpacing = 8.0
    @AppStorage(ReaderPreferenceKeys.paragraphSpacing) private var paragraphSpacing = 12.0
    @AppStorage(ReaderPreferenceKeys.contentWidth) private var contentWidth = ReaderViewportLayout.defaultPreferredWidth
    @AppStorage(ReaderPreferenceKeys.theme) private var themeName = ReaderTheme.system.rawValue
    @AppStorage(ReaderPreferenceKeys.paragraphIndent) private var paragraphIndent = true
    @State private var scrollPosition: Int?
    @State private var paragraphs: [String] = []
    @State private var hasPreparedContent = false
    @State private var hasAppliedInitialScroll = false

    var body: some View {
        let family = ReaderFontFamily(rawValue: fontFamily) ?? .serif
        let theme = ReaderTheme(rawValue: themeName) ?? .system

        GeometryReader { geometry in
            let effectiveWidth = ReaderViewportLayout.effectiveContentWidth(
                preferredWidth: contentWidth,
                viewportWidth: geometry.size.width
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: paragraphSpacing) {
                    ReaderChapterHeader(chapter: chapter)

                    ForEach(paragraphs.indices, id: \.self) { index in
                        ReaderParagraphView(
                            paragraph: paragraphs[index],
                            fontFamily: family,
                            fontSize: fontSize,
                            lineSpacing: lineSpacing,
                            usesFirstLineIndent: paragraphIndent
                        )
                        .id(index)
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
            .scrollPosition(id: $scrollPosition, anchor: .top)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .textSelection(.enabled)
        }
        .background(theme.background)
        .foregroundStyle(theme.foreground)
        .task(id: chapter.id) {
            await prepareChapterContent()
        }
        .task(id: store.readerScrollRequest?.id) {
            guard hasPreparedContent else { return }
            await applyPendingScrollRequest()
        }
        .onChange(of: scrollPosition) { _, newValue in
            guard let newValue, newValue >= 0, hasAppliedInitialScroll else { return }
            store.updateProgress(
                chapterID: chapter.id,
                paragraphIndex: newValue,
                total: paragraphs.count
            )
        }
    }

    @MainActor
    private func prepareChapterContent() async {
        hasPreparedContent = false
        hasAppliedInitialScroll = false
        scrollPosition = nil
        paragraphs = chapter.paragraphs
        hasPreparedContent = true
        await applyPendingScrollRequest()
    }

    @MainActor
    private func applyPendingScrollRequest() async {
        guard hasPreparedContent else { return }
        await Task.yield()

        if let request = store.readerScrollRequest, request.chapterID == chapter.id {
            scrollPosition = scrollTarget(for: request.intent)
            hasAppliedInitialScroll = true
            store.consumeReaderScrollRequest(request.id)
        } else if !hasAppliedInitialScroll {
            scrollPosition = scrollTarget(for: .restore)
            hasAppliedInitialScroll = true
        }
    }

    private func scrollTarget(for intent: ReaderScrollIntent) -> Int {
        switch intent {
        case .chapterTop:
            -1
        case .restore:
            min(max(chapter.topParagraphIndex, 0), max(paragraphs.count - 1, 0))
        }
    }
}
