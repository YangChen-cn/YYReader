import SwiftUI

struct ReaderReadingProgressFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .allowsHitTesting(false)
            .accessibilityLabel("阅读进度，\(text)")
    }
}
