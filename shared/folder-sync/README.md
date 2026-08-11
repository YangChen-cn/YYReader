# YYReader 文件夹同步

用户选择任意普通文件夹后，客户端在其中使用 `YYReaderSync/`：macOS 只写 `mac.json`，Windows 只写 `windows.json`，并读取对端文件。

SyncSnapshot v1 只包含书籍身份、元数据、阅读位置与删除 tombstone。它不包含正文、Cookie、WebView 数据或账号信息。

- `sourceURL` 经过 YYReader URL canonicalization 后标识同一本书。
- 阅读位置采用 `lastReadAt` 更新的一侧。
- 书名和作者采用 `updatedAt` 更新的一侧。
- `deletedAt` 不早于活动记录更新时间时，记录视为已删除；旧快照不能将其恢复。
- 未识别的可选字段必须忽略，以便 v1 客户端兼容未来扩展。
- 写入必须在同一目录先生成临时文件，再原子替换目标文件。
