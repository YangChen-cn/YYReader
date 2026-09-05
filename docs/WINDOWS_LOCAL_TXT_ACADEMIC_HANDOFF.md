# Windows 端交接：本地 TXT 与论文伪装模式

本文记录 macOS 首发实现的跨端契约。Windows 后续实现应复用这些规则与测试向量；不要同步正文，也不要改变 SyncSnapshot 版本。

## 当前边界

- 本轮只实现了 `YYReader/` 下的 macOS 客户端；`windows/` 没有修改。
- 数据库不新增字段。书籍类型从已有 `sourceURL` 派生。
- 网页解析、连续阅读、离线正文与既有同步合并规则没有改写。
- SyncSnapshot 保持 v2，BookshelfTransfer 保持 v1。

## TXT 解码与清理

解码顺序固定：

1. 文件头为 `EF BB BF` 时去掉 BOM，严格 UTF-8。
2. 严格 UTF-8。
3. GB18030（兼容 GBK；Windows 可用 code page 54936，务必开启 invalid bytes exception）。
4. 仍失败则报告不支持的编码。

只允许 `.txt`。统一 `CRLF` / `CR` 为 `LF`，移除首尾 BOM 和空白，把三个及以上空行压缩为一个空段。不要改写正文文字、标点或全半角。

## 稳定身份（必须逐字节一致）

以原始文件字节计算：

```text
payload = UTF8("yyreader-txt-v1\0" + decimalByteCount + "\0") + originalBytes
stableID = lowercaseHex(SHA256(payload))
bookURL = "yyreader-local://txt/" + stableID
chapterURL = bookURL + "/chapter/" + oneBasedIndex.padLeft(6, "0")
```

路径、文件名、修改时间不参与 hash。相同字节换路径仍是同一本书，字节变化则是新书。不要保存或同步原文件路径。

身份 golden vector：原始字节为 UTF-8 `abc`（3 bytes）时，stableID 必须为 `6b1696d3895ebe8ca5de53c421913cae72d95dbf6150df64260081c60ea4793c`。

URL 校验必须严格：

```regex
^yyreader-local://txt/[0-9a-fA-F]{64}$
^yyreader-local://txt/[0-9a-fA-F]{64}/chapter/[0-9]{6}$
```

当前章节 URL 还必须以前述书籍 URL 加 `/chapter/` 开头。

## 章节切分

候选标题必须整行匹配、trim 后不超过 60 字，且不能以 `。！？!?；;` 结尾。数字部分为阿拉伯数字、全角数字或 `〇零一二三四五六七八九十百千万两`。

支持：

- `第 <数字> 章|回|节|卷`，可跟由空白、冒号、间隔点、顿号或横线分隔的标题。
- `序章`、`序言`、`楔子`、`引子`、`尾声`、`后记`、`番外`/`番外N`。
- `卷N`；`第一卷` 已由第一类覆盖。

可靠结构：至少两个候选；或唯一候选位于前 20 个非空行内，且其后至少有两个非空段落/行或 200 个非空白字符。不可靠时整本为单章“正文”。

首标题前至少两个非空段落/行或 200 字时建立“前言”；较短前置文字并入第一章正文。保留候选的文件顺序，不按章节数字排序。空正文候选不产生空章节。

每章正文最后走 Windows 现有 paragraph normalization。章节一开始就写入正文、`cachedAt`、前后 URL；Book `hasCatalog=true`。

## 重复导入、占位与本地能力

- 按 `bookURL` 复用 Book；按 `chapterURL` 复用 Chapter，必要时按一基 `sortIndex` 对齐同步占位章节。
- 重导入保留当前章节、段落索引和进度；超出新正文范围时钳制。
- 重新导入已删除本地书时清除对应 tombstone。
- 默认书名为不带扩展名的文件名，作者为“未知作者”；导入确认前和导入后都可编辑。
- 缺正文的同步占位书显示“请在此设备导入同一 TXT”，绝不能把自定义 URL 交给 HTTP/WebView2。
- 本地书禁止网页刷新目录、尾章 probe、网页验证、下载到本地和清除离线缓存。连续阅读使用已持久化的本地章节，末章显示“已到本书末尾”。

## SyncSnapshot v2 能力协商

快照可选顶层字段：

```json
"capabilities": ["local-txt-v1"]
```

读取旧快照时缺失等价于空数组；继续忽略未知能力。支持方始终声明 `local-txt-v1`，但只有成功读到对端也声明后，才把本地 TXT 活动记录与 tombstone 写入自己的快照。这防止旧客户端因未知 scheme 拒绝整个文件。

正文永不进入 SyncSnapshot 或 BookshelfTransfer。对端收到记录后创建 `hasCatalog=false` 占位书；导入同一 TXT 时依 stable identity 原地补全。同步已有 `currentChapterIndex` / paragraph forward-only 规则不变。

## 论文模式确定性协议

模式与单/双栏仅是本机偏好，不同步。正文、Book、Chapter 和 paragraph index 不变。窗口内容宽度小于 760 DIP 时，偏好双栏也临时显示单栏。

双栏阅读顺序不是逐段左右交替，也不是把整章永久切成两根长栏。以每两个补充块之间的正文作为一个版面内容块，前 `ceil(count / 2)` 段依原顺序放入左栏，剩余段落依原顺序放入右栏；阅读顺序为“完整左栏 → 完整右栏 → 横跨双栏的补充块 → 下一个版面内容块”。这样既符合论文栏序，也避免整章读到底后回到最顶部。补充块继续横跨双栏。

SHA-256 稳定取值：取 digest 前 8 字节，按 big-endian 解释为 `UInt64`，再 `% upperBound`。

```text
seed = canonicalBookIdentity + "|" + chapterIdentity
choice(type) = stableNumber(seed + "|" + type, candidateCount)
```

- 引用首次位置：`3 + hash(seed + "|citation-start") % 3`。
- 该位置引用数：`1 + hash(seed + "|citation-count|<index>") % 3`。
- 引用编号：`1 + hash(seed + "|citation|<index>|<ordinal>") % 18`，排序展示。
- 下一引用间隔：`3 + hash(seed + "|citation-gap|<index>") % 3`。
- 首个补充块：`10 + hash(seed + "|supplement-start") % 9`。
- 补充类型：`[equation, table, figure][hash(seed + "|supplement-kind|<index>") % 3]`。
- 下一补充块间隔：`10 + hash(seed + "|supplement-gap|<index>") % 9`。

章节映射为：0 → `1. Introduction`，1 → `2. Methodology`，2 → `3. Results and Discussion`，其后 N → `3.(N-2) Extended Analysis`。

论文标题、Abstract 和 Keywords 使用客户端内置固定数组，选择字符串必须与 macOS `AcademicPaperPlanner.swift` 完全一致，才能得到相同结果。引用/补充块没有阅读进度身份。切换模式前记录 chapter + paragraph anchor，布局后无动画恢复，并在恢复期间暂停进度提交。

macOS 默认用 `Ctrl+Option+P` 切换摸鱼模式，允许用户在阅读设置中录制新组合；至少要求两个 Ctrl/Option/Command 修饰键，避免覆盖普通输入和常见单修饰键命令。Windows 可按平台习惯设置默认键，但应同样提供可编辑偏好且不进入同步。

V1 补充块视觉基线：公式包含编号和变量说明；Table 使用四列、多行估计值、上下横线与 Note 脚注；Figure 使用带 X/Y 轴、图例、参考线和两个数据序列的原生折线图。不要退化为单行表格或无坐标轴的柱状图标。

论文 golden vector：book=`https://example.com/book/`、chapter=`https://example.com/book/3.html`、60 个段落、chapter position=2 时：标题为 `Contextual Dynamics in Long-Form Textual Corpora`；引用段落索引为 `[5,10,15,20,23,28,31,36,39,44,47,50,55,59]`；补充块为 `10 figure, 21 equation, 38 figure, 55 table`（索引从 0 开始）。

## Windows 建议落点

- Core：`LocalTextImportService`、严格解码、切章器、SHA-256 identity、`BookSourceKind`、`AcademicPaperPlanner`。
- Persistence：按现有 SQLite Book/Chapter upsert，不迁移 schema。
- Sync：v2 DTO 增加可选 `Capabilities`；codec 放行严格 local URL；publish/full sync 做能力门控。
- UI：添加小说面板增加 FileOpenPicker；Reader toolbar 增加论文模式；阅读设置增加单/双栏和可编辑快捷键；窄窗自动回落。
- Reader：继续使用 WinUI 原生 `ScrollViewer`/现有段落项，补充块无 anchor，复用 `ReaderAnchor` 恢复位置。

## 必测验收

- UTF-8、UTF-8 BOM、GBK/GB18030、空文件、坏编码、非 TXT。
- 全部标题形式、行内“第一章”不误切、前言、单标题可靠性、无标题回退、DOM/文件顺序。
- 同字节跨路径 identity 相同；正文持久化后删除原文件仍可阅读；清缓存不删除本地正文。
- 旧快照兼容、能力协商、占位书、同 TXT 再导入恢复进度、tombstone 复活、快照无正文。
- 本地书不会调用 HTTP loader、刷新目录、下载、验证或 tail probe。
- 论文 plan 重开完全一致、引用间隔 3–5、补充块间隔 10–18、原文数组逐项不变。
- 普通/论文/单栏/双栏切换保持 chapter 与 paragraph index；连续阅读追加后仍按原段落提交进度。

## Windows 实现回执（2026-09-05）

Windows 已根据 Mac `6ecc6db` 接入 TXT 导入、稳定身份、正文持久化、重导入保留进度与占位补全；网页刷新、下载和尾章探测对本地书禁用。SyncSnapshot v2 支持 `local-txt-v1` 协商，BookshelfTransfer v1 支持严格本地 URL，正文继续仅保存在各设备。

论文模式使用原生 WinUI 段落、单/双栏内容块、公式、四列表格和双序列折线图；默认快捷键 `Ctrl+Alt+P`，阅读设置可修改字母。复用 chapter/paragraph anchor，补充块不参与进度身份。

自动测试覆盖 TXT/Mac golden vector、编码与切章、SQLite 重导入及 tombstone、占位按 sortIndex 对齐、禁止本地书网络调用、同步能力门控、论文计划与单双栏段落映射。真实窗口布局、模式切换/缩窗的滚动 anchor 和双设备同步效果仍待用户手动验收。
