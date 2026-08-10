# YYReader 仓库协作规范

本文件适用于仓库根目录及其全部子目录。用户当前请求优先于本文件；若子目录以后出现更具体的 `AGENTS.md`，则该文件只覆盖对应子目录。

## 项目目标

YYReader 是一个原生 macOS 小说阅读器：用户输入章节网页 URL，应用下载和解析网页，将不同站点的内容转换为统一的 `Book` / `Chapter` 数据模型，并用 SwiftUI 原生界面显示正文。

首要原则：

- 正文阅读器必须使用 SwiftUI `ScrollView`、`LazyVStack` 和 `Text`，不得使用 `WKWebView` 渲染正文。
- `WKWebView` 只允许用于 Cloudflare、JavaScript 验证及获取验证后的最终 HTML。
- 不自动解决 CAPTCHA，不绕过登录、付费墙或网站访问控制。
- 启迪小说（`qidiy.com`）是专用适配站点；其他站点走通用解析，失败时必须返回可理解的错误。

## 技术基线

- macOS 15+
- Swift 6 语言模式与严格并发检查
- SwiftUI
- SwiftData
- SwiftSoup 2.13.5（精确版本）
- XcodeGen 维护工程配置
- App Sandbox 仅开放出站网络权限
- 仅构建 Apple 芯片 `arm64`，除非用户明确要求 Universal 或 Intel 版本

`project.yml` 是工程配置的唯一来源。不要直接修改 `YYReader.xcodeproj/project.pbxproj`；修改 `project.yml` 后运行 `xcodegen generate`，并提交重新生成的 `.xcodeproj`。

## 常用命令

生成工程：

```bash
xcodegen generate
```

构建并运行 Debug：

```bash
./script/build_and_run.sh run
```

日常开发、人工验收和需要交付给用户运行的 Debug App 必须使用上述脚本。不要把直接调用
`xcodebuild build` 生成的 `DerivedData/Build/Products/*/YYReader.app` 当作可运行交付；
该命令仅可用于自动化构建校验。脚本会更新 `dist/YYReader.app`，完成便携化、签名和校验后，
再从临时副本启动它。

运行完整测试：

```bash
xcodebuild test \
  -project YYReader.xcodeproj \
  -scheme YYReader \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData
```

生成 arm64 Release：

```bash
./script/package_release.sh
```

Release 产物位于 `dist/YYReader-<version>-arm64.dmg` ，不生成 ZIP。`DerivedData/` 与 `dist/` 不提交 Git。

## 目录与职责

- `YYReader/App`：App、Scene、菜单命令和应用入口。
- `YYReader/Models`：SwiftData 模型与界面值类型。
- `YYReader/Views`：SwiftUI 视图；主要视图保持单一职责。
- `YYReader/Stores`：`@MainActor @Observable` 界面状态和用户操作编排。
- `YYReader/Services`：网络加载、限速、验证、导入协调和缓存服务。
- `YYReader/Parsing`：站点适配器、解析协议和统一解析结果。
- `YYReader/Persistence`：持久化辅助代码（新增持久化设施放在此处）。
- `YYReader/Support`：依赖装配、偏好键和跨模块辅助类型。
- `YYReader/Resources`：Asset Catalog、字符串目录和其他应用资源。
- `YYReaderTests`：解析、服务、SwiftData 和回归测试。
- `YYReaderUITests`：关键原生 UI 流程测试。
- `script`：可重复执行的构建、运行和打包脚本。

主要类型原则上每个文件一个，避免把网络、解析、持久化和视图状态混在同一类型中。

## Swift 与并发规则

- 所有 UI 状态、SwiftData `ModelContext` 使用和界面 Store 必须隔离在 `@MainActor`。
- 网络限速、可变缓存和后台队列使用 actor 或其他明确隔离方式。
- 不使用 `Task.detached` 绕过 actor 隔离。
- 新增异步操作必须传播取消；取消是正常控制流，不应向用户显示失败弹窗。
- 不用 `try?` 静默吞掉前台用户操作错误；只有预取等明确的机会性任务可以忽略失败，并写注释说明。
- 避免不必要的 `@unchecked Sendable`；确需使用时说明被保护的不变量。
- 优先使用现代 SwiftUI 和 Foundation API，部署目标允许时不保留旧系统兼容分支。

## 网页加载和验证规则

- 静态 HTML 优先通过 `URLSessionHTMLLoader` 下载。
- 检查 HTTP 状态、最终重定向 URL、字符编码、Cloudflare challenge、429 和取消。
- 同一域名请求必须串行并限速。
- 429 必须尊重 `Retry-After`，不得紧密重试或并发重试。
- WebKit 验证完成后，同步 Cookie 和真实 User-Agent 给后续静态请求。
- 同一次导入中，同一域名最多展示一次人工验证；验证仍被拒绝时停止并显示明确错误，不得循环弹窗。
- 验证面板必须能取消、失败重试，并有有限等待时间。
- 不记录 Cookie、challenge token、完整 HTML 或用户隐私数据到日志。

## 解析规则

- 所有站点实现统一的 `NovelSourceAdapter`，不得在 UI 中写 CSS selector 或站点判断。
- 专用适配器优先于 `GenericNovelAdapter`。
- 只跟随解析得到的同源分页链接。
- 章节分页使用 visited 集合防循环，最多 20 页。
- 目录分页使用 visited 集合防循环，最多 200 页。
- 合并分页时去除边界重复段落、页码提示、脚本调用、广告和“本章未完”等噪声。
- 章节 URL 规范化必须只移除分页后缀，不得把不同章节错误合并。
- 目录条目按网站目录的页面与 DOM 出现顺序生成全局位置；不得仅按标题中的章节号排序，因为番外或新卷可能从“第1章”重新编号。URL 去重时保留已有正文、进度和缓存时间。
- 通用解析优先使用 JSON-LD、OpenGraph、语义标签和 `rel=prev/next`，再使用正文密度和中文标点评分。
- 解析失败必须区分不支持 URL、正文缺失、目录缺失、分页循环和请求失败。

## 数据与缓存规则

- `Book` 保存书名、作者、来源、目录 URL、更新时间、当前章节和章节关系。
- `Chapter` 保存规范 URL、标题、序号、纯文本正文、前后章节、缓存时间和阅读进度。
- 有目录书籍以规范目录 URL 去重；无目录书籍以稳定的书籍级 `sourceBookURL` 去重，不能使用当前章节 URL 作为书籍身份。章节仍以规范章节 URL 去重。
- 删除书籍必须级联删除章节和离线正文。
- 阅读进度至少保存顶部段落索引和阅读比例；切换章节、关闭窗口或退出时持久化。
- 首次阅读后缓存正文；下一章预取是机会性任务，失败不得影响当前阅读。
- 切换书架书籍只读取本地缓存目录，不得因为缓存过期而自动刷新全目录。目录更新只能由导入流程或用户明确执行“刷新目录”触发；多页目录必须可取消。
- 不在首版实现整本正文批量下载。

## SwiftUI 与可访问性规则

- 主窗口保持三栏 `NavigationSplitView`：书架、目录、阅读区。
- 空状态使用原生 `ContentUnavailableView`。
- 阅读正文使用稳定段落 ID，支持文字选择和滚动位置恢复。
- 按钮保留可读文字标签或明确的 accessibility label，不仅依赖图标。
- 支持键盘焦点、VoiceOver、增大字体、提高对比度和减少动态效果。
- 使用原生工具栏、菜单、Settings 场景和 Inspector；仅在 SwiftUI 无法完成时使用窄边界 AppKit bridge。
- 不引入自绘窗口框架或 Web 前端组件模拟 macOS 界面。

## UI 验证与 Computer Use

- 默认禁止使用 Computer Use 做日常 UI 验证、点击、输入或截图检查。
- 优先使用单元测试、XCUITest、构建日志、静态检查和 accessibility identifier 验证可自动确认的行为。
- 需要主观判断布局、动画、图标、Dock 或真实网站交互时，优先请用户在自己的 Mac 上手动验证，并给出简短、明确的验收步骤。
- 只有用户在当前请求中明确要求使用 Computer Use，或手动验证客观上无法完成且用户先同意时，才可使用该能力。
- 不得因为“方便”或“更快”自行启用 Computer Use。

## 图标与资源

- `YYReader/Resources/Assets.xcassets` 必须存在于 App Target 的 Resources Build Phase。
- App Icon 集名固定为 `AppIcon`，构建设置保持 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`。
- Release 验收时确认 App 包含 `Contents/Resources/AppIcon.icns` 和 `Assets.car`，并检查 `CFBundleIconName`。
- 修改字符串时优先更新字符串目录，为未来本地化保留结构。

## 测试要求

修改相关代码后运行风险相称的测试；交付前运行完整测试。

至少覆盖：

- 启迪小说双页章节合并、噪声清理、上下章和多页目录。
- 示例元数据：全职法师、乱、第1章 世界大变和下一章。
- 通用解析的 JSON-LD、语义正文、非标准容器和导航文本。
- 相对 URL、重复分页、循环分页、正文缺失、乱码、403 challenge、429 与取消。
- SwiftData 去重、目录更新、缓存、进度恢复和删除级联。
- 添加 URL、错误重试、目录搜索、章节切换、主题和离线恢复等 UI 流程。

Fixture 必须精简且使用自造段落，不提交完整版权章节内容。测试不得依赖实时第三方网站，因为 Cloudflare、限流和站点结构会变化。

## Git 与交付规则

- 保留用户已有改动，不覆盖或回滚不相关文件。
- 提交前检查 `git status`、`git diff --check`、敏感信息和构建产物。
- 不提交 `DerivedData/`、`dist/`、用户 Xcode 状态、Cookie、网页抓取内容或临时文件。
- 提交 `project.yml` 和重新生成的 `YYReader.xcodeproj`，保证仓库可直接打开。
- 默认不执行破坏性 Git 命令，不使用 `git reset --hard` 或强制推送。
- GitHub 发布前确认仓库可见性；未经用户明确要求不创建公开仓库。
- Release 必须为 arm64、ad-hoc 签名，且通过 `codesign --verify --strict` 和 ZIP 完整性检查。

## 完成标准

只有同时满足以下条件才视为完成：

- XcodeGen 可重新生成工程。
- Debug 和 Release 均能构建。
- 相关测试全部通过。
- Release 二进制仅包含要求的架构。
- App Sandbox 权限正确。
- App 图标和资源已进入 App 包。
- 用户可随时停止导入，Cloudflare 和限流不会造成无限循环。
- README、脚本和实际工程行为保持一致。
- 需要主观 UI 判断的部分已经明确交给用户手动验收。
