import SwiftUI

struct ReaderChapterFooter: View {
    let chapter: Chapter
    let store: LibraryStore

    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Text(chapterPositionText)
                Spacer()
                Text("本章阅读 \(progressPercent)%")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack {
                ReaderChapterNavigationButton(
                    title: "上一章",
                    systemImage: "arrow.left",
                    isEnabled: hasPreviousChapter,
                    action: store.goToPreviousChapter
                )

                Spacer()

                ReaderChapterNavigationButton(
                    title: "下一章",
                    systemImage: "arrow.right",
                    imageOnTrailingEdge: true,
                    isEnabled: hasNextChapter,
                    action: store.goToNextChapter
                )
            }
        }
        .padding(.top, 76)
        .padding(.bottom, 88)
    }

    private var selectedIndex: Int? {
        store.sortedChapters.firstIndex { $0.id == chapter.id }
    }

    private var chapterPositionText: String {
        guard let selectedIndex else { return "共 \(store.sortedChapters.count) 章" }
        return "第 \(selectedIndex + 1) / \(store.sortedChapters.count) 章"
    }

    private var progressPercent: Int {
        Int((min(max(chapter.readingProgress, 0), 1) * 100).rounded())
    }

    private var hasPreviousChapter: Bool {
        chapter.previousURL != nil || (selectedIndex ?? 0) > 0
    }

    private var hasNextChapter: Bool {
        if chapter.nextURL != nil { return true }
        guard let selectedIndex else { return false }
        return selectedIndex + 1 < store.sortedChapters.count
    }
}

private struct ReaderChapterNavigationButton: View {
    let title: String
    let systemImage: String
    var imageOnTrailingEdge = false
    let isEnabled: Bool
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
            .foregroundStyle(isHovered && isEnabled ? Color.primary : Color.secondary)
            .contentShape(.rect)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { isHovered = $0 }
    }
}
