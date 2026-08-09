import SwiftUI

struct BookSidebarRow: View {
    let book: Book

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .lineLimit(1)
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "book.closed")
                .foregroundStyle(.secondary)
        }
    }
}
