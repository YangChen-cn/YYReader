import SwiftUI

struct MobileBookCardView: View {
    let book: Book
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let chapter = book.chapters.first { $0.id == book.currentChapterID }
        let hasRead = chapter?.lastReadAt != nil
        let chapterProgress = min(max(chapter?.readingProgress ?? 0, 0), 1)

        HStack(alignment: .top, spacing: 14) {
            MobileBookCover(title: book.title)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                    Text(book.author.isEmpty ? "未知作者" : book.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        sourceLabel
                        if chapter?.isAvailableOffline == true { offlineLabel }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) {
                        sourceLabel
                        if chapter?.isAvailableOffline == true { offlineLabel }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if hasRead, let chapter {
                    Text(chapter.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    HStack(spacing: 8) {
                        ProgressView(value: chapterProgress)
                            .accessibilityLabel("本章阅读进度")
                        Text("\(Int(chapterProgress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Group {
                        if book.hasCatalog && book.catalogFetchedAt == nil && !book.isLocalText {
                            Text("目录待更新 · 尚未开始阅读")
                        } else {
                            Text("\(book.chapters.count) 章 · 尚未开始阅读")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(minHeight: 100)
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.04)))
        .accessibilityElement(children: .combine)
        .accessibilityHint("轻点打开，长按管理")
    }

    private var sourceLabel: some View {
        Label(book.isLocalText ? "本地 TXT" : (book.isManga ? "漫画" : "网页小说"),
              systemImage: book.isLocalText ? "doc.text" : (book.isManga ? "photo.stack" : "globe"))
    }

    private var offlineLabel: some View {
        Label("可离线阅读", systemImage: "checkmark.circle")
    }
}
