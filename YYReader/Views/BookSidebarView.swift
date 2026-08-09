import SwiftUI

struct BookSidebarView: View {
    @Bindable var store: LibraryStore

    var body: some View {
        List(selection: $store.selectedBookID) {
            ForEach(store.books) { book in
                BookSidebarRow(book: book)
                    .tag(book.id)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("书架")
        .onChange(of: store.selectedBookID) { _, newValue in
            store.selectBook(newValue)
        }
        .overlay {
            if store.books.isEmpty {
                ContentUnavailableView(
                    "书架为空",
                    systemImage: "books.vertical",
                    description: Text("点击工具栏的加号，粘贴小说章节 URL。")
                )
            }
        }
    }
}
