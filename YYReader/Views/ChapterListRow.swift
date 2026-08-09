import SwiftUI

struct ChapterListRow: View {
    let chapter: Chapter

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: chapter.isCached ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(chapter.isCached ? Color.green : Color.secondary)
                .accessibilityLabel(chapter.isCached ? "已缓存" : "未缓存")
            Text(chapter.title)
                .lineLimit(2)
        }
    }
}
