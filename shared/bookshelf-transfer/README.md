# BookshelfTransfer v1

`BookshelfTransfer` 是 YYReader macOS 与 Windows 客户端之间手动交换书架和阅读位置的本地 JSON 格式。它不是云同步协议，也不包含 Cookie、登录状态、完整章节正文或服务器信息。

顶层字段为固定值 `format: yyreader-bookshelf`、整数 `version: 1`、ISO 8601 `exportedAt` 和 `books` 数组。每本小说包含 `sourceURL`、`title`、`author`，并可包含 `currentChapterURL`、`paragraphIndex` 和 `progress`。

书架去重使用 `sourceURL` 的 canonical 值。客户端必须忽略未知的可选字段；无法识别的顶层 `format` 或 `version` 应拒绝整个文件，单本小说字段无效时则报告该项并继续处理其他项。

恢复位置优先使用 `currentChapterURL + paragraphIndex`，`progress` 用作段落索引越界时的比例回退。`.yyreader` 只是 JSON 文件扩展名，客户端也接受普通 `.json` 文件和剪贴板 JSON。
