import SwiftUI

struct ReaderChapterHeader: View {
    let chapter: Chapter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(chapter.title)
                .font(.largeTitle)
                .bold()
                .textSelection(.enabled)

            if let book = chapter.book {
                Text("\(book.title) · \(book.author)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Divider()
                .padding(.vertical)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(-1)
    }
}
