import SwiftUI

struct LibraryToolbar: ToolbarContent {
    let canContinueReading: Bool
    let isLoading: Bool
    let toggleBookSidebar: () -> Void
    let addURL: () -> Void
    let continueReading: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("显示或隐藏书架", systemImage: "sidebar.left", action: toggleBookSidebar)
                .help("显示或隐藏书架")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if canContinueReading {
                Button("继续阅读", systemImage: "book.pages", action: continueReading)
                    .help("打开当前章节")
            }
            Button("添加网页", systemImage: "plus", action: addURL)
                .disabled(isLoading)
                .help("添加小说网页")
        }
    }
}
