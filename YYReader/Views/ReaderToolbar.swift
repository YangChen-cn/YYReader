import SwiftUI

struct ReaderToolbar: ToolbarContent {
    @Binding var showingAppearancePopover: Bool
    @Binding var showingDownloadProgress: Bool
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
    let hasDownloadStatus: Bool
    let downloads: OfflineDownloadManager
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

            if hasDownloadStatus {
                Button("下载进度", systemImage: isDownloading ? "arrow.down.circle" : "exclamationmark.triangle") {
                    showingDownloadProgress.toggle()
                }
                .help("显示或隐藏下载进度")
                .popover(isPresented: $showingDownloadProgress, arrowEdge: .top) {
                    OfflineDownloadStatusPopover(
                        downloads: downloads,
                        cancel: cancelDownload,
                        dismiss: { showingDownloadProgress = false },
                        dismissFailure: downloads.dismissFailure
                    )
                }
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
                        Button("显示下载进度") {
                            showingDownloadProgress = true
                        }
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
