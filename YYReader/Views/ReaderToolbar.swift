import SwiftUI

struct ReaderToolbar: ToolbarContent {
    @Binding var showingAppearancePopover: Bool
    let canManageBook: Bool
    let isLoading: Bool
    let returnToLibrary: () -> Void
    let showAdvancedAppearance: () -> Void
    let addURL: () -> Void
    let refreshCatalog: () -> Void
    let deleteBook: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("返回书架", systemImage: "chevron.left", action: returnToLibrary)
                .help("返回书架")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button("阅读外观", systemImage: "textformat.size") {
                showingAppearancePopover.toggle()
            }
            .help("阅读外观")
            .popover(isPresented: $showingAppearancePopover, arrowEdge: .top) {
                ReaderAppearancePopover(showAdvancedSettings: showAdvancedAppearance)
            }

            Menu("更多", systemImage: "ellipsis") {
                Button("刷新目录", systemImage: "arrow.clockwise", action: refreshCatalog)
                    .disabled(!canManageBook || isLoading)
                Button("添加网页…", systemImage: "plus", action: addURL)
                    .disabled(isLoading)

                Divider()

                Button(role: .destructive, action: deleteBook) {
                    Label("删除小说…", systemImage: "trash")
                }
                    .disabled(!canManageBook)
            }
            .help("更多书籍操作")
        }
    }
}
