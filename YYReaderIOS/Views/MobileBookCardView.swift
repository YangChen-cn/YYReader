import SwiftUI

struct MobileBookCardView: View {
    let book: Book

    var body: some View {
        let chapter = book.chapters.first { $0.id == book.currentChapterID }
        let hasRead = chapter?.lastReadAt != nil
        let chapterProgress = min(max(chapter?.readingProgress ?? 0, 0), 1)

        HStack(alignment: .top, spacing: 14) {
            MobileBookCover(title: book.title)
            VStack(alignment: .leading, spacing: 7) {
                Text(book.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(book.author.isEmpty ? "未知作者" : book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Label(book.isLocalText ? "本地 TXT" : (book.isManga ? "漫画" : "网页小说"), systemImage: book.isLocalText ? "doc.text" : (book.isManga ? "photo.stack" : "globe"))
                    if chapter?.isAvailableOffline == true {
                        Label("可离线阅读", systemImage: "checkmark.circle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if hasRead, let chapter {
                    Text(chapter.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack {
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
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 16))
        .accessibilityHint("接续上次阅读位置")
    }
}
