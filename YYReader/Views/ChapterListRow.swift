import SwiftUI

struct ChapterListRow: View {
    let chapter: Chapter

    var body: some View {
        HStack(spacing: 8) {
            Text(chapter.title)
                .lineLimit(2)

            Spacer(minLength: 6)

            if chapter.isCached {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("已缓存")
            }
        }
        .padding(.vertical, 3)
    }
}
