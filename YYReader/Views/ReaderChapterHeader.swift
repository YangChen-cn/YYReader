import SwiftUI

struct ReaderChapterHeader: View {
    let chapter: Chapter
    let accent: Color
    let target: ReaderScrollTarget

    var body: some View {
        VStack(spacing: 12) {
            Text("❦")
                .font(.system(size: 15))
                .foregroundStyle(accent)
                .accessibilityHidden(true)

            Text(chapter.title)
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 92)
        .padding(.bottom, 36)
        .id(target)
    }
}
