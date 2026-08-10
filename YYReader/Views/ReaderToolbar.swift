import SwiftUI

struct ReaderToolbar: ToolbarContent {
    @Binding var showingAppearancePopover: Bool
    let canManageBook: Bool
    let canRefreshCatalog: Bool
    let isLoading: Bool
    let returnToLibrary: () -> Void
    let showAdvancedAppearance: () -> Void
    let addURL: () -> Void
    let refreshCatalog: () -> Void
    let downloadCurrentChapter: () -> Void
    let downloadFollowingChapters: () -> Void
    let downloadEntireBook: () -> Void
    let cancelDownload: () -> Void
    let deleteOfflineCache: () -> Void
    let canDownloadEntireBook: Bool
    let isDownloading: Bool
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
                    .disabled(!canRefreshCatalog || isLoading)
                Button("添加网页…", systemImage: "plus", action: addURL)
                    .disabled(isLoading)

                Menu("下载到本地…", systemImage: "arrow.down.circle") {
                    Button("下载当前章节", action: downloadCurrentChapter)
                        .disabled(isDownloading)
                    Button("下载后 20 章", action: downloadFollowingChapters)
                        .disabled(!canDownloadEntireBook || isDownloading)
                    Button("下载全部章节", action: downloadEntireBook)
                        .disabled(!canDownloadEntireBook || isDownloading)
                    if isDownloading {
                        Divider()
                        Button("取消下载", role: .cancel, action: cancelDownload)
                    }
                }
                .disabled(isLoading)

                Button("删除离线缓存", systemImage: "externaldrive.badge.xmark", action: deleteOfflineCache)
                    .disabled(!canManageBook || isDownloading)

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
