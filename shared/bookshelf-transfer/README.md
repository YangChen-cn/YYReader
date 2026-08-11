# BookshelfTransfer v1

`BookshelfTransfer` 是 YYReader macOS 与 Windows 客户端之间交换书架和阅读位置的本地 JSON 格式。它不是云同步协议，也不包含 Cookie、登录状态、完整章节正文或服务器信息。

## 顶层字段

- `format`：必填，固定为 `yyreader-bookshelf`。
- `version`：必填，当前为整数 `1`。
- `exportedAt`：必填，ISO 8601 日期时间。
- `books`：必填，小说数组，可以为空。

## 小说字段

- `sourceURL`：必填。书籍级 canonical source URL；有目录时通常是目录 URL，无目录时是稳定的书籍身份 URL。不要填当前章节 URL 作为书籍身份。
- `title`：必填，书名。
- `author`：必填，作者；未知时可以使用空字符串或“未知作者”。
- `currentChapterURL`：可选，当前章节的 canonical URL。
- `paragraphIndex`：可选，当前章节顶部段落索引，非负整数。
- `progress`：可选，当前章节阅读比例，范围 `0..1`。

客户端必须忽略未知的可选字段，以便 v2 在不破坏 v1 导入器的情况下增加字段。无法识别的顶层 `format` 或 `version` 应拒绝整个文件；单本小说字段无效时，应报告该项失败并继续处理其他项。

## canonicalization 与去重

书架去重使用 `sourceURL` 的 canonical 值，比较 scheme/host 大小写、默认端口和 fragment 时视为相同。启迪小说章节分页后缀 `/book/<book>/<chapter>/<page>.html` 只 canonicalize 为 `/book/<book>/<chapter>.html`。不得把不同章节、不同书籍或不同目录页面仅按标题合并。

目录条目按网站 DOM 出现顺序保留全局位置；不能只按标题中的章节号排序，因为番外和新卷可能重新从“第 1 章”开始编号。

## 阅读位置恢复

恢复优先级是 `currentChapterURL + paragraphIndex`。如果章节已加载但 `paragraphIndex` 超出正文段落范围，客户端使用 `progress` 按比例估算；两者都缺失时从章节开头开始。保存阅读位置时应同时保存章节 URL、段落索引、比例和最近阅读时间。

`.yyreader` 文件只是 JSON 文件扩展名。Windows 导入器也应接受剪贴板文本和普通 `.json` 文件，并在导入前显示新书/已存在数量。
