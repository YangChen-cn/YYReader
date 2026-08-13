import SwiftUI

struct LibraryToolbar: ToolbarContent {
    let canContinueReading: Bool
    let canDeleteBook: Bool
    let isLoading: Bool
    let toggleBookSidebar: () -> Void
    let addURL: () -> Void
    let continueReading: () -> Void
    let deleteBook: () -> Void
    let importBookshelf: () -> Void
    let importBookshelfFromClipboard: () -> Void
    let copyBookshelfExport: () -> Void
    let exportBookshelf: () -> Void

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

            Button("删除小说", systemImage: "trash", role: .destructive, action: deleteBook)
                .disabled(!canDeleteBook || isLoading)
                .help("删除当前选中的小说")

            Menu("更多", systemImage: "ellipsis") {
                Button("导入书架…", systemImage: "square.and.arrow.down", action: importBookshelf)
                Button(
                    "从剪贴板导入",
                    systemImage: "clipboard",
                    action: importBookshelfFromClipboard
                )

                Divider()

                Button("复制书架导出 JSON", systemImage: "doc.on.doc", action: copyBookshelfExport)
                Button("导出为 .yyreader 文件…", systemImage: "square.and.arrow.up", action: exportBookshelf)
            }
            .disabled(isLoading)
            .help("导入或导出书架")
        }
    }
}
