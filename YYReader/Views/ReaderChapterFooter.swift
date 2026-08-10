import SwiftUI

struct ReaderChapterFooter: View {
    let snapshot: ReaderChapterNavigationSnapshot
    let accent: Color
    let separator: Color
    let foreground: Color
    let secondaryForeground: Color
    let previousChapter: () -> Void
    let nextChapter: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(separator.opacity(0.8))
                    .frame(height: 1)
                Text("❖")
                    .font(.caption)
                    .foregroundStyle(accent)
                Rectangle()
                    .fill(separator.opacity(0.8))
                    .frame(height: 1)
            }
            .frame(maxWidth: 180)
            .accessibilityHidden(true)

            HStack {
                Text(snapshot.positionText)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(secondaryForeground)

            HStack {
                ReaderChapterNavigationButton(
                    title: "上一章",
                    systemImage: "arrow.left",
                    isEnabled: snapshot.hasPrevious,
                    foreground: foreground,
                    secondaryForeground: secondaryForeground,
                    action: previousChapter
                )

                Spacer()

                ReaderChapterNavigationButton(
                    title: "下一章",
                    systemImage: "arrow.right",
                    imageOnTrailingEdge: true,
                    isEnabled: snapshot.hasNext,
                    foreground: foreground,
                    secondaryForeground: secondaryForeground,
                    action: nextChapter
                )
            }
        }
        .padding(.top, 76)
        .padding(.bottom, 88)
    }

}

private struct ReaderChapterNavigationButton: View {
    let title: String
    let systemImage: String
    var imageOnTrailingEdge = false
    let isEnabled: Bool
    let foreground: Color
    let secondaryForeground: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if !imageOnTrailingEdge {
                    Image(systemName: systemImage)
                }
                Text(title)
                if imageOnTrailingEdge {
                    Image(systemName: systemImage)
                }
            }
            .foregroundStyle(isHovered && isEnabled ? foreground : secondaryForeground)
            .contentShape(.rect)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { isHovered = $0 }
    }
}
