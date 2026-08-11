# SyncSnapshot v2

`SyncSnapshot v2` 是 YYReader macOS 与 Windows 客户端通过用户自选共享文件夹交换书架元数据和阅读位置的本地 JSON 格式。它不绑定任何云服务，也不包含正文缓存、Cookie、登录状态或 WebView 数据。macOS 仍可读取 v1，v2 新增可选的 `currentChapterIndex`。

共享目录固定为：

```text
YYReaderSync/
├── mac.json
└── windows.json
```

macOS 只写 `mac.json`、读取 `windows.json`；Windows 只写 `windows.json`、读取 `mac.json`。两端均使用临时文件和原子替换写入自己的文件。

书籍通过 canonical `sourceURL` 合并。`updatedAt` 较新的记录提供标题与作者。阅读位置先比较 `currentChapterIndex`，只允许更后的章节覆盖更前的章节；同一章再比较 `paragraphIndex` 和 `progress`，只允许位置向前。`lastReadAt` 仅作记录，不参与阅读位置决策。`deletedAt` 不早于最新 `updatedAt` 时表示删除 tombstone。

监听器只在 `windows.json` 的文件签名变化后触发读取和合并；低频轮询仅作为丢失文件系统事件时的兜底。合并结果未变时不重写 `mac.json`。
本地书架或阅读进度变化只导出 `mac.json`，不将导出结果反向应用到正在阅读的 SwiftUI 滚动会话。启动、回到前台、手动同步或检测到 `windows.json` 文件签名变化时才将合并结果落库；落库也必须保留当前屏幕上的章节和 Reader session。
