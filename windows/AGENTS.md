# YYReader Windows 分支协作规范

本文件适用于 `windows/` 及其全部子目录，专用于 `windows/bootstrap` 分支。用户当前请求优先于本文件；本文件中的 Windows 规则覆盖仓库根目录 `AGENTS.md` 中面向 macOS、SwiftUI、XcodeGen 和 DMG 的规则。若子目录以后出现更具体的 `AGENTS.md`，以更具体的文件为准。

## 项目目标

YYReader Windows 是原生 Windows 小说阅读器。用户输入章节网页 URL 后，应用下载、解析并统一为 `Book` / `Chapter` 数据模型，通过 WinUI 3 原生界面显示书架、目录和正文。

首要原则：

- 正文阅读器使用 WinUI 3 原生 `ScrollViewer`、`ItemsRepeater` 和文本控件，不使用 WebView2 渲染正文。
- WebView2 只用于 Cloudflare、JavaScript 验证和取得验证后的最终 HTML。
- 不自动解决 CAPTCHA，不绕过登录、付费墙或网站访问控制。
- 启迪小说（`qidiy.com`）使用专用适配器；其他站点走通用解析，失败时返回可理解的错误。
- Windows 与 macOS 可以共享传输协议和 fixture，但 Windows SQLite 数据库及 UI 实现保持独立。

## 技术基线

- Windows x64
- .NET 8
- C#，`LangVersion=latest`、Nullable 和 Implicit Usings 开启
- WinUI 3 / Windows App SDK
- Windows SDK 10.0.26100，最低目标 Windows 10 1809（10.0.17763.0）
- AngleSharp 1.7.1
- Microsoft.Data.Sqlite 8.0.21
- WebView2 Runtime，仅作为验证 fallback
- MSTest
- 未打包 WinExe，`RuntimeIdentifier=win-x64`

依赖版本和构建属性以各 `.csproj` 及 `Directory.Build.props` 为准。不要手工编辑 `bin/`、`obj/`、生成的 XBF/PRI 或 publish 目录中的文件。

## 常用命令

从仓库根目录执行。

首次还原：

```powershell
dotnet restore windows\YYReader.Windows\YYReader.Windows.csproj
```

日常 Debug 构建：

```powershell
dotnet build windows\YYReader.Windows\YYReader.Windows.csproj --configuration Debug --runtime win-x64
```

运行完整 Windows 测试：

```powershell
dotnet test windows\YYReader.Windows.Tests\YYReader.Windows.Tests.csproj --configuration Debug
```

依赖未变化时可使用更快的校验命令：

```powershell
dotnet build windows\YYReader.Windows\YYReader.Windows.csproj --no-restore --verbosity minimal
dotnet test windows\YYReader.Windows.Tests\YYReader.Windows.Tests.csproj --no-restore --verbosity minimal
```

启动 Debug 客户端：

```powershell
Start-Process .\windows\YYReader.Windows\bin\Debug\net8.0-windows10.0.26100.0\win-x64\YYReader.Windows.exe
```

用户要求运行或手动验收时，应先完成 Debug 构建，再启动上述实际产物；不要只告诉用户产物路径。避免重复启动多个实例，启动前可先检查 `Get-Process YYReader.Windows -ErrorAction SilentlyContinue`。

只有用户明确要求发布、制作安装包或验证发布流程时才执行：

```powershell
.\windows\scripts\package-release.ps1
```

该脚本要求 Inno Setup 6，输出 `dist/windows/YYReader-Setup-x64-<version>.exe`。普通功能开发和修复不得额外生成 Release 安装包。`bin/`、`obj/`、`.codex/` 临时 SDK、publish 目录和 `dist/` 产物不得提交 Git。

## 目录与职责

- `YYReader.Windows.Core/Models`：书籍、章节、阅读偏好、滚动和 anchor 等平台无关模型。
- `YYReader.Windows.Core/Parsing`：站点适配器、通用解析、URL 规范化和解析结果。
- `YYReader.Windows.Core/Services`：HTML 加载协议、导入协调、限速和离线下载。
- `YYReader.Windows.Core/Persistence`：SQLite 仓储和数据合并。
- `YYReader.Windows.Core/Reading`：连续阅读 session、缓存和章末状态机。
- `YYReader.Windows.Core/Sync`、`Transfer`：文件夹同步和跨平台书架交换。
- `YYReader.Windows/Views`：WinUI XAML 页面与窄范围 code-behind。
- `YYReader.Windows/Services`：Windows UI 编排、WebView2 验证、偏好和同步服务。
- `YYReader.Windows.Tests`：MSTest 回归测试和精简 fixture。
- `installer`：Inno Setup 配置和语言资源。
- `scripts`：Windows 构建产物清理和发布脚本。

核心解析、持久化、阅读状态机应放在 `YYReader.Windows.Core`，不要把可测试的业务规则埋进 XAML code-behind。WinUI 控件交互保留在 App 项目中；确需测试 App 服务时，可按现有模式将单个生产源文件 link 到测试项目，避免让测试程序集依赖完整 WinUI App。

## C# 与异步规则

- UI 控件、ObservableCollection 和 `LibraryStore` 界面状态只在 UI 线程修改。
- 后台完成后更新 UI 时使用现有 `DispatcherQueue` 或 `SynchronizationContext` 模式。
- 异步 API 接受并传播 `CancellationToken`；取消属于正常控制流，不显示普通失败提示。
- 不使用 fire-and-forget 隐藏前台操作异常；只有 View 事件或明确的机会性预取可使用 `_ = ...`，并由目标方法内部处理异常和状态。
- 同一资源的刷新、预取和同步遵守现有 single-flight、gate 和 cooldown 约束，不制造并发重复请求。
- 不用空 `catch` 吞掉非取消异常；用户触发的失败应映射为明确状态或消息。
- 保持 Nullable 警告可读，避免不必要的 null-forgiving 和无依据的线程安全假设。

## 网页加载与解析

- 静态 HTML 优先使用 `HttpHtmlLoader`；仅在检测到验证需要时进入 `WebView2HtmlLoader` fallback。
- 检查 HTTP 状态、最终重定向 URL、编码、Cloudflare challenge、429 和取消。
- 同域请求必须经过 `HostRateLimiter`，429 尊重 `Retry-After`，不得紧密或并发重试。
- WebView2 验证后同步必要 Cookie 和真实 User-Agent 给静态请求。
- 同一次操作不得循环弹出验证窗口；验证失败或取消后停止并给出明确结果。
- 不记录 Cookie、challenge token、完整 HTML 或用户隐私数据。
- 所有站点实现统一适配器协议；UI 和 `LibraryStore` 不写站点 CSS selector 或域名分支。
- 章节分页和目录分页必须有 visited 集合及明确上限，只跟随同源解析链接。
- URL 去重保留正文、阅读进度和缓存时间；目录顺序以网站页面及 DOM 顺序为准，不按标题章节号重新排序。
- fixture 使用自造、精简正文，不提交完整版权章节，也不让自动测试依赖实时第三方网站。

## 数据与阅读规则

- 有目录书籍以规范目录 URL 确定身份；无目录书籍使用稳定的 `SourceBookUrl`；章节按规范章节 URL 去重。
- 目录 merge 必须保留已有章节正文、缓存和阅读进度，不重复 attach 同一章节。
- 删除书籍级联清理章节和离线内容；切换章节、书籍或关闭应用前持久化阅读进度。
- 下一章预取是机会性操作，失败不得破坏当前章节。
- 普通书架切换和连续阅读章末探测都不得自动刷新整本目录；完整目录只由用户明确刷新。

连续阅读章末状态必须区分：

```text
LoadingNext -> CheckingLatest -> Attached | ConfirmedLatest | Failed
```

- `Neighbor == null` 或本地 `book.Chapters` 到尾部只表示本地目录末尾，不能直接显示“已到最新章节”。
- 到达 session 尾章且本地无 next 时，统一重新加载当前尾章，通过专用或通用适配器解析 `nextURL`；不得扫描完整目录。
- 启迪和通用站点使用同一 Store 流程；站点差异只由适配器处理。通用适配器应支持导航文字和 `rel=next`。
- 只有当前尾章远端加载、解析成功且确实没有 `nextURL`，才能进入 `ConfirmedLatest`。
- 刷新失败进入可重试 `Failed`，不得伪装成最新章节。
- 用户手动完整目录刷新保持 single-flight 且可取消；自动章末检查不得调用该流程。
- 一次 near-end visit 最多自动启动一次 probe。布局触发的 `ViewChanged`、尾章 URL 因 append 改变或状态文字变化不得重复启动。
- 只有真正离开 rearm 区域后再次进入，或用户点击重试，才允许新一轮。
- continuation 的 Loading、Checking、Latest 和 Failed 状态切换必须保持布局高度稳定，使用固定尺寸及 `Opacity` / `IsHitTestVisible`，不得通过反复 `Collapsed/Visible` 改变 `ScrollableHeight`。
- append 下一章时保持当前可视 anchor，不为显示状态修改或恢复 `VerticalOffset`，不得引入滚动跳动。

## WinUI 与可访问性

- 保持现有书架、目录和阅读区信息架构，不因局部修复重构整个 Reader。
- 正文使用稳定项目和段落身份；影响 `ItemsRepeater` 的增删必须考虑 virtualization、anchor 和布局触发的 `ViewChanged`。
- 状态区、进度环和按钮应预留稳定尺寸，动态文本不得挤压或遮挡正文。
- 按钮保留可读文字或明确 accessibility label，支持键盘、缩放和高对比度。
- 优先使用 WinUI 原生控件和现有主题 palette，不引入 Web 前端或自绘窗口框架。

## 测试与验收

修改后先运行风险相称的定向测试，交付前运行完整 Windows 测试及 App Debug 构建。涉及解析、SQLite、同步或阅读状态机时必须增加回归测试。

至少保持覆盖：

- 启迪和通用解析、分页、噪声清理、相对 URL、循环和正文缺失。
- HTTP challenge、429、取消和验证 fallback 的边界行为。
- SQLite 去重、目录 merge、缓存、阅读进度和删除级联。
- 连续阅读增量尾章探测、latest/failure 语义、near-end rearm、稳定布局和 append 去重；测试必须断言自动探测不请求目录页。
- 文件夹同步恢复保护、离线下载和 BookshelfTransfer 兼容性。

默认禁止使用 Computer Use 做日常 UI 验证。优先使用单元测试、构建日志、静态检查和可测试状态机。需要判断真实网站、滚动抖动、闪烁、anchor 或窗口视觉效果时，启动 Debug App 后交给用户手动验证，并给出简短的复现路径和预期结果。只有用户在当前请求中明确授权，才可使用 Computer Use。

## Git 与交付

- 保留用户已有改动，不覆盖或回滚不相关文件。
- 提交前检查 `git status --short`、`git diff --check`、敏感信息和生成产物。
- 不提交数据库、Cookie、抓取 HTML、`bin/`、`obj/`、临时 SDK、publish 目录或安装包。
- 不执行 `git reset --hard`、强制推送等破坏性操作，除非用户明确要求。
- 未经用户明确要求，不提交、不推送、不创建 PR，也不修改版本号或制作安装包。
- 发布时同步检查 `.csproj` 版本、README、安装脚本与 About 页显示，并确认 self-contained x64 安装包不包含未使用的 AI/ML、ONNX Runtime 或 DirectML 组件。

## 完成标准

- 相关定向测试通过。
- `dotnet test windows\YYReader.Windows.Tests\YYReader.Windows.Tests.csproj` 全部通过。
- `dotnet build windows\YYReader.Windows\YYReader.Windows.csproj --configuration Debug --runtime win-x64` 成功。
- `git diff --check` 无错误，工作区没有误加入生成产物或敏感数据。
- 用户要求运行时，已启动 Debug 客户端并明确给出手动验收步骤。
- 主观 UI 或真实网站行为若未自动验证，必须明确标记为待用户手动验收，不能声称已经实机确认。
