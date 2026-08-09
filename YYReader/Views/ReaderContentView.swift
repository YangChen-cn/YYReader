import SwiftUI

struct ReaderContentView: View {
    let chapter: Chapter
    let store: LibraryStore

    @AppStorage(ReaderPreferenceKeys.fontFamily) private var fontFamily = ReaderFontFamily.serif.rawValue
    @AppStorage(ReaderPreferenceKeys.fontSize) private var fontSize = 20.0
    @AppStorage(ReaderPreferenceKeys.lineSpacing) private var lineSpacing = 8.0
    @AppStorage(ReaderPreferenceKeys.paragraphSpacing) private var paragraphSpacing = 12.0
    @AppStorage(ReaderPreferenceKeys.contentWidth) private var contentWidth = 680.0
    @AppStorage(ReaderPreferenceKeys.theme) private var themeName = ReaderTheme.system.rawValue
    @AppStorage(ReaderPreferenceKeys.paragraphIndent) private var paragraphIndent = true
    @State private var scrollPosition: Int?

    var body: some View {
        let paragraphs = chapter.paragraphs
        let family = ReaderFontFamily(rawValue: fontFamily) ?? .serif
        let theme = ReaderTheme(rawValue: themeName) ?? .system

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

                ReaderChapterFooter(chapter: chapter, store: store)
            }
            .scrollTargetLayout()
            .frame(maxWidth: min(max(contentWidth, 560), 800), alignment: .leading)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition(id: $scrollPosition, anchor: .top)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .background(theme.background)
        .foregroundStyle(theme.foreground)
        .textSelection(.enabled)
        .task(id: chapter.id) {
            scrollPosition = min(chapter.topParagraphIndex, max(paragraphs.count - 1, 0))
        }
        .onChange(of: scrollPosition) { _, newValue in
            guard let newValue else { return }
            store.updateProgress(paragraphIndex: newValue, total: paragraphs.count)
        }
    }
}
