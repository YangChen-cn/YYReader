# SyncSnapshot v2

`SyncSnapshot v2` 是 YYReader macOS、iOS 与 Windows 客户端通过用户自选共享文件夹交换书架元数据和阅读位置的本地 JSON 格式。它不绑定任何云服务，也不包含正文缓存、Cookie、登录状态或 WebView 数据。Swift 客户端仍可读取 v1，v2 支持可选的 `currentChapterIndex` 与 `capabilities`。

共享目录固定为：

```text
YYReaderSync/
├── mac.json
├── ios.json
└── windows.json
```

macOS 只写 `mac.json`、读取 `windows.json` 和 `ios.json`；iOS 只写 `ios.json`、读取 `mac.json` 和 `windows.json`。Windows 当前只写 `windows.json`、读取 `mac.json`；iOS 与 Windows 可经新版 Mac 中转，或手动传输书架。三端均使用临时文件和原子替换写入自己的文件。

书籍通过 canonical `sourceURL` 合并。`updatedAt` 较新的记录提供标题与作者。阅读位置先比较 `currentChapterIndex`，只允许更后的章节覆盖更前的章节；同一章再比较 `paragraphIndex` 和 `progress`，只允许位置向前。`lastReadAt` 仅作记录，不参与阅读位置决策。`deletedAt` 不早于最新 `updatedAt` 时表示删除 tombstone。

监听器只在对端快照的文件签名变化后触发读取和合并；低频轮询仅作为丢失文件系统事件时的兜底。合并结果未变时不重写 `mac.json`。
本地书架或阅读进度变化走独立 `publishLocal()` 路径：只构建本机快照并导出自己的文件，不读取或解析对端快照，也不将导出结果反向应用到正在阅读的 SwiftUI 会话。启动、回到前台、手动同步或检测到对端文件签名变化时才执行完整合并。对端 signature 仅在读取、合并和落库全部成功后确认；失败时 watcher 和轮询必须可再次触发。当前阅读书的远端 tombstone 延迟到退出 Reader 后再刷新界面。

支持本地 TXT 的客户端声明 `local-txt-v1`。只有成功读到所有已存在的对端快照均声明同一能力后，才将本地 TXT 元数据、进度和 tombstone 写入自己的快照；正文始终只保存在导入设备。书籍身份严格为 `yyreader-local://txt/<64位 SHA-256>`，章节身份为其后的 `/chapter/<六位序号>`。
