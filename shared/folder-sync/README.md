# YYReader 文件夹同步

用户选择任意普通文件夹后，客户端在其中使用 `YYReaderSync/`：macOS 只写 `mac.json`，Windows 只写 `windows.json`，并读取对端文件。

SyncSnapshot v2 只包含书籍身份、元数据、阅读位置与删除 tombstone。它不包含正文、Cookie、WebView 数据或账号信息。客户端继续读取 v1，但新写出的文件使用 v2；v2 新增可选的 `currentChapterIndex`。

- `sourceURL` 经过 YYReader URL canonicalization 后标识同一本书。
- 阅读位置先比较 `currentChapterIndex`，只允许更后的章节覆盖更前的章节；同一章再比较 `paragraphIndex` 和 `progress`，只允许位置向前。
- `lastReadAt` 仅作记录，不参与阅读位置决策。
- 书名和作者采用 `updatedAt` 更新的一侧。
- `deletedAt` 不早于活动记录更新时间时，记录视为已删除；旧快照不能将其恢复。
- 未识别的可选字段必须忽略，以便旧客户端兼容未来扩展。
- 写入必须在同一目录先生成临时文件，再原子替换目标文件。
- 自己的快照内容没有变化时不得重写文件，避免触发对端监听循环。
