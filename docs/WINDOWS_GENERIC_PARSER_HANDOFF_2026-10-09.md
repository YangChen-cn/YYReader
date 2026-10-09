# Windows 通用解析器交接：目录范围、正文容器和章节边界

本轮修改在 Mac / iOS 共用的 Swift 解析与加载代码中完成。Windows C# 实现尚未修改；下面列出需要移植的规则和可直接复用的自造样例。只记录正常返回 HTML、实际完成解析检查的站点。

## 实测 URL 与结果

观察日期：2026-10-09。章节数量是本次页面的解析结果，不是永久保证；自动测试不依赖这些线上页面。

| 站点 / 入口 | 检查页面 | 结果 |
| --- | --- | --- |
| [书斋阁：斗破苍穹目录](https://www.shuzhaige.com/doupocangqiong/) | [首章](https://www.shuzhaige.com/doupocangqiong/102764.html)、[下一章](https://www.shuzhaige.com/doupocangqiong/102765.html) | 1645 条有效目录记录，首条是第1章；两页正文及下一章链接均可提取。旧版首条错误地变成“第1646章 五帝破空（大结局）”。 |
| [天涯书库：斗破苍穹目录](https://tianyashuku.net/wangluo/1615/) | [第一条章节](https://tianyashuku.net/wangluo/1615/119149.html)、[第二条章节](https://tianyashuku.net/wangluo/1615/119150.html) | 1432 条有效目录记录；`m-article-text` 正文可提取。网站第二条当前标题是“第三章 客人”，按网站 DOM 顺序保留，不凭章号补齐或重排。 |
| [全本小说网：全职高手目录](https://www.quanben.io/n/quanzhigaoshou/list.html) | [第1章](https://www.quanben.io/n/quanzhigaoshou/1.html)、[第2章](https://www.quanben.io/n/quanzhigaoshou/2.html) | 静态目录只有46条预览，网页点击“展开完整列表”后实测可提取1713条章节。导航把下一章写作“下一页”，不能一直当章节分页合并。 |
| [云书斋：斗破苍穹章节](https://www.yunshuzhai.com/book/3568/91.html) | [相邻章节](https://www.yunshuzhai.com/book/3568/92.html) | 正文与上下章链接可提取；优先选择 `#novel-content`，避免把外层 `main` 的书名、作者和导航当作正文。本轮检查章节入口，不宣称完整目录已验证。 |

这些 URL 用于开发者手动复核。仓库中不保存其版权正文、抓取 HTML、Cookie 或网页验证数据。

## 1. 目录必须按节点范围筛选，再按 URL 去重

Swift 入口：`YYReader/Parsing/GenericNovelAdapter.swift` 的 `chapterSeeds`。

旧规则先从目录容器收集 URL 集合，再扫描整个文档：只要 URL 在集合里，就接受该链接。这会让目录外“最新更新”的同 URL 链接抢先入列，导致末章被排到首位。

新规则：

1. 找到包含至少两个有效章节的目录容器。
2. 收集这些容器中实际的 anchor 节点身份，Swift 使用 `ObjectIdentifier`。
3. 按文档 DOM 顺序扫描 anchors，只允许目录范围内的节点。
4. 最后按 URL 去重并生成全局位置。不能仅按标题章号排序，必须保留多卷重新编号。

Windows 对应：`windows/YYReader.Windows.Core/Parsing/GenericNovelAdapter.cs` 的两个 `ChapterSeeds` 方法。把 `ISet<string> allowed` 改为 DOM 节点身份集合，例如 `HashSet<IElement>(ReferenceEqualityComparer.Instance)`；URL 去重仍独立保留。不要先克隆节点再做身份比较。

## 2. 选择窄正文容器

在 `DedicatedContentSelectors` 中补充：

```text
[class*=article-text]
[class*=article-body]
.article-content
#novel-content
.novel-content
```

维持现有顺序：明确正文容器 → `article/main` → 密度候选。阈值和长目录保护保持不变。此处不增加域名分支，也不把 selector 放进 UI。

## 3. 章节首尾按钮指向目录时返回 null

通用导航有时让第一章的“上一章”或末章的“下一章”指向目录。先解析 `catalogURL`，再比较前后章 URL 的 canonical 值；与目录相同的链接必须置空。比较时去掉 fragment，因此 `./` 和 `./#list` 应当视为同一个目录。

不要删掉真实相邻章节；不要把“没有下一章”和“请求下一章失败”混为一谈。

## 4. 验证“下一页”确实属于同一章

Swift 入口：`NovelImportCoordinator.loadChapterContent`，结果合并位于 `NovelProcessingWorker.aggregateChapterPages`。

抓取并解析下一页后，如果首章和新页都能提取阿拉伯数字章节号，且章号不同：

- 不添加新页的正文。
- 不继续请求它的后续分页。
- 用新页最终 URL 作为本章的 `nextChapterURL`。
- 保留本章原有标题、正文与上一章链接。

同章分页继续执行原有去重、visited 集合和20页上限。当前边界核对使用既有的阿拉伯数字章号提取；没有明确章号时，不根据任意 URL 数字猜测章节身份。

Windows 对应：`windows/YYReader.Windows.Core/Services/NovelImportCoordinator.cs` 的章节分页循环。在 `AppendWithoutBoundaryDuplicate` 之前检查，保存 `nextChapterOverride`；返回时优先采用它。不要把新页赋为 `finalPage` 后再返回，否则会丢失原章的关系。

## 5. 静态目录预览需要展开时，走有限 DOM fallback

Swift 新增 `NovelParsingError.catalogNeedsExpansion` 和 `YYReader/Parsing/CatalogExpansionScripts.swift`。

解析器发现明确的 JavaScript 目录展开控件时，不把预览目录报告为完整。识别文本限于：

```text
展开完整列表
展开完整目录
展开全部章节
加载全部章节
```

检测时忽略空白和外层 `[] / 【】`。只识别 `javascript:` 链接或显式 `type=button` 的按钮。

协调器使用已有的 rendered-DOM fallback。浏览器在读取最终 HTML 前执行一次有限展开：

- 页面至少已有两个形似章节标题的链接。
- 只点击以上明确的目录控件；不点击登录、支付、submit 或验证控件。
- 点击后每200毫秒检查 DOM 中章节链接数量，最多等待8秒。这是本地 DOM 检查，不是重复发起网络请求。
- 数量增大后标记已展开，取得最终 DOM；仍无法展开时保留明确错误，不能把46条预览当全书。
- 保留原有整个导航超时和取消机制。异步操作返回后要核对 request ID，已取消的旧操作不得完成新请求。

Windows 对应：

- `Core/Parsing/NovelParsingException.cs` 增加同等错误种类。
- `Core/Services/NovelImportCoordinator.cs` 在静态目录识别阶段捕获该错误，直接走 DOM fallback，避免先误试作章节再重复载入目录。
- `YYReader.Windows/Services/WebView2HtmlLoader.cs` 在 `ReadHtmlAsync` 前展开并等待完成。按当前 WebView2 接口处理异步脚本结果，不要直接照搬 Swift `callAsyncJavaScript` 的 await 方式。
- 验证完成后的正文仍交给原生阅读器，不使用 WebView2 显示正文。

## 共享样例与验收

样例目录：[`shared/generic-parser/cases`](../shared/generic-parser/cases)。全部正文是自造短段落，`expected.json` 给出输入 URL 和预期结果：

| 样例 | 必须通过的检查 |
| --- | --- |
| `latest-update-outside-catalog.html` | 最新更新的同 URL 链接不得抢占首条；顺序为1、2、3 |
| `article-text-body.html` | 两段正文；阅读控件不混入；上一章为 null |
| `novel-content-body.html` | 只提取窄正文；外层作者标签不混入 |
| `last-chapter-catalog-link.html` | 指向目录 fragment 的下一章为 null |
| `ajax-catalog-preview.html` | 静态预览返回需要展开错误 |
| `next-page-first.html` + `next-page-second.html` | 第二章不合并进第一章；请求到第二章就停止，并返回第二章 URL |

Swift 单测实际读取这些共享文件。Windows 可在测试 `.csproj` 中 link/copy 到输出目录，逐项移植断言；另补上同章真正分页、取消和展开等待超时的回归。

Swift 参考测试：`GenericCatalogBoundaryTests`、`NovelImportCoordinatorTests` 和 `CatalogExpansionScriptTests`。后者用自造 HTML 在 WebKit 中验证展开控件能得到完整 DOM，以及登录/submit 控件不会被点击。

当前验证：Mac 完整测试159项通过，iOS 模拟器逻辑测试127项通过，3项 iOS UI 用例分别通过（阅读设置与返回书架、翻页切换与跨章、错误恢复）。Mac Debug 已通过规定脚本构建运行，iOS 设备版重新签名用 IPA 已构建。Windows 未构建或运行测试。

Windows 完成后运行：

```powershell
dotnet test windows\YYReader.Windows.Tests\YYReader.Windows.Tests.csproj --configuration Debug
dotnet build windows\YYReader.Windows\YYReader.Windows.csproj --configuration Debug --runtime win-x64
```

本交接不要求修改版本号、制作安装包、提交或推送。
