import SwiftUI

struct ReaderContentView: View {
    let chapter: Chapter
    let store: LibraryStore

    @AppStorage(ReaderPreferenceKeys.fontFamily) private var fontFamily = ReaderFontFamily.serif.rawValue
    @AppStorage(ReaderPreferenceKeys.fontSize) private var fontSize = 20.0
    @AppStorage(ReaderPreferenceKeys.lineSpacing) private var lineSpacing = 9.0
    @AppStorage(ReaderPreferenceKeys.paragraphSpacing) private var paragraphSpacing = 18.0
    @AppStorage(ReaderPreferenceKeys.contentWidth) private var contentWidth = 720.0
    @AppStorage(ReaderPreferenceKeys.horizontalPadding) private var horizontalPadding = 36.0
    @AppStorage(ReaderPreferenceKeys.theme) private var themeName = ReaderTheme.system.rawValue
    @State private var scrollPosition: Int?

    var body: some View {
        let paragraphs = chapter.paragraphs
        let family = ReaderFontFamily(rawValue: fontFamily) ?? .serif
        let theme = ReaderTheme(rawValue: themeName) ?? .system

        ScrollView {
            LazyVStack(alignment: .leading, spacing: paragraphSpacing) {
                ReaderChapterHeader(chapter: chapter)

                ForEach(paragraphs.indices, id: \.self) { index in
                    Text(paragraphs[index])
                        .font(family.font(size: fontSize))
                        .lineSpacing(lineSpacing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(index)
                }

                ReaderChapterFooter(store: store)
            }
            .scrollTargetLayout()
            .frame(maxWidth: contentWidth, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 44)
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
        .navigationTitle(chapter.title)
    }
}
