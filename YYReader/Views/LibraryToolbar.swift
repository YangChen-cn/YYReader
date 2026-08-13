import SwiftUI

struct LibraryToolbar: ToolbarContent {
    @Binding var showingDownloadProgress: Bool
    let canContinueReading: Bool
    let canRefreshCatalog: Bool
    let canDeleteBook: Bool
    let canDownloadEntireBook: Bool
    let isLoading: Bool
    let isDownloading: Bool
    let hasDownloadStatus: Bool
    let downloads: OfflineDownloadManager
    let toggleBookSidebar: () -> Void
    let addURL: () -> Void
    let continueReading: () -> Void
    let refreshCatalog: () -> Void
    let downloadCurrentChapter: () -> Void
    let downloadFollowingChapters: () -> Void
    let downloadEntireBook: () -> Void
    let cancelDownload: () -> Void
    let deleteOfflineCache: () -> Void
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

        if canContinueReading {
            ToolbarItem(placement: .primaryAction) {
                Button("继续阅读", systemImage: "book.pages", action: continueReading)
                    .help("打开当前章节")
            }

            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            ControlGroup {
                Menu("下载到本地", systemImage: "arrow.down.circle") {
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

                    Divider()
                    Button(
                        "删除离线缓存",
                        systemImage: "externaldrive.badge.xmark",
                        action: deleteOfflineCache
                    )
                    .disabled(isDownloading)
                }
                .disabled(!canContinueReading || isLoading)
                .help("下载当前小说到本地")

                Button("刷新目录", systemImage: "arrow.clockwise", action: refreshCatalog)
                    .disabled(!canRefreshCatalog || isLoading)
                    .help("获取当前小说的完整章节目录")

                if hasDownloadStatus {
                    Button(
                        "下载进度",
                        systemImage: isDownloading ? "arrow.down.circle" : "exclamationmark.triangle"
                    ) {
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
}
