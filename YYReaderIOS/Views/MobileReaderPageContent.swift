import SwiftUI

struct MobileReaderPageContent: View {
    let page: MobileReadingPage
    let layout: MobilePaginationLayout

    var body: some View {
        LazyVStack(alignment: .leading, spacing: layout.paragraphSpacing) {
            ForEach(page.fragments) { fragment in
                Text(fragment.text)
                    .font(.custom(layout.fontName, fixedSize: layout.fontSize))
                    .lineSpacing(layout.lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("ios.page.paragraph.\(fragment.paragraphIndex)")
            }
        }
        .frame(width: max(layout.width - 2, 1), alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .textSelection(.enabled)
    }
}
