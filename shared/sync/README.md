# SyncSnapshot v1

`SyncSnapshot v1` 是 YYReader macOS 与 Windows 客户端通过用户自选共享文件夹交换书架元数据和阅读位置的本地 JSON 格式。它不绑定任何云服务，也不包含正文缓存、Cookie、登录状态或 WebView 数据。

共享目录固定为：

```text
YYReaderSync/
├── mac.json
└── windows.json
```

macOS 只写 `mac.json`、读取 `windows.json`；Windows 只写 `windows.json`、读取 `mac.json`。两端均使用临时文件和原子替换写入自己的文件。

书籍通过 canonical `sourceURL` 合并。`updatedAt` 较新的记录提供标题与作者，`lastReadAt` 较新的记录提供当前章节和阅读位置，`deletedAt` 不早于最新 `updatedAt` 时表示删除 tombstone。更新晚于 tombstone 可以显式恢复书籍。
