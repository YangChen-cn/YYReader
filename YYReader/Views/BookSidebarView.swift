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
        .onChange(of: store.selectedBookID) { oldValue, newValue in
            Task { @MainActor in
                await Task.yield()
                guard store.selectedBookID == newValue else { return }
                store.reconcileBookSelection(newValue, previousID: oldValue)
            }
        }
        .overlay {
            if store.books.isEmpty {
                ContentUnavailableView(
                    "书架为空",
                    systemImage: "books.vertical",
                    description: Text("添加小说网页，或从“更多”导入本地 TXT。")
                )
            }
        }
    }
}
