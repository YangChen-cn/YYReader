import SwiftUI

struct ReaderChapterHeader: View {
    let chapter: Chapter
    let accent: Color
    let target: ReaderScrollTarget
    let style: ReaderChapterHeaderStyle
    let usesOrnament: Bool
    let separator: Color
    @ScaledMetric(relativeTo: .title) private var titleSize = 28.0

    var body: some View {
        VStack(spacing: 12) {
            if usesOrnament {
                Text("❦")
                    .font(.system(size: 15))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
            } else {
                Capsule()
                    .fill(separator)
                    .frame(width: 44, height: 1)
                    .accessibilityHidden(true)
            }

            Text(chapter.title)
                .font(.system(size: titleSize, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, style.topPadding)
        .padding(.bottom, style.bottomPadding)
        .id(target)
    }
}
