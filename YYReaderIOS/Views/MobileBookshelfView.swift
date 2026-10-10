import SwiftUI

/// A full-width home screen, not a sidebar. The actual window width determines
/// the grid, so rotation and iPad multitasking never hide the bookshelf.
struct MobileBookshelfView: View {
    let store: LibraryStore
    let openBook: (UUID) -> Void
    let editBook: (UUID) -> Void
    let deleteBook: (UUID) -> Void
    let addWeb: () -> Void
    let importText: () -> Void
    let importBookshelf: () -> Void
    @Environment(AppServices.self) private var services
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            let sidePadding: CGFloat = geometry.size.width >= 700 ? 32 : 16
            let availableWidth = min(geometry.size.width, 1200) - sidePadding * 2
            let count = dynamicTypeSize.isAccessibilitySize ? 1 : max(1, min(3, Int(availableWidth / 350)))
            ScrollView {
                VStack(spacing: 24) {
                    if services.updates.showsBanner {
                        AppUpdateCard(updates: services.updates, canDismiss: true)
                            .frame(maxWidth: 640)
                            .frame(maxWidth: .infinity)
                    }
                    if store.books.isEmpty {
                        MobileEmptyBookshelfView(addWeb: addWeb, importText: importText, importBookshelf: importBookshelf)
                            .frame(maxWidth: 600)
                            .frame(minHeight: max(360, geometry.size.height - (services.updates.showsBanner ? 400 : 48)))
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("\(store.books.count) 本藏书 · 轻点打开，长按管理")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 18, alignment: .top), count: count), spacing: 18) {
                            ForEach(store.books) { book in
                                Button { openBook(book.id) } label: {
                                    MobileBookCardView(book: book)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("编辑信息", systemImage: "pencil") { editBook(book.id) }
                                    Button("删除", systemImage: "trash", role: .destructive) { deleteBook(book.id) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, sidePadding)
                .padding(.vertical, 16)
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("书架")
        .navigationBarTitleDisplayMode(.large)
    }
}
