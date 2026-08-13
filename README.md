# YYReader

YYReader 是一款以正文为中心的原生小说阅读器，现提供 macOS 与 Windows 客户端。粘贴小说章节网页 URL 后，应用会识别书籍、作者、章节正文、前后章节与目录，并将网站拆分的章节分页合并为完整内容，再使用平台原生界面呈现。

## 功能

- macOS 使用 SwiftUI，Windows 使用 WinUI 3；正文均由原生文本控件渲染，不使用 WebView 作为阅读器。
- 书架、可搜索目录与沉浸式阅读模式。
- 自动合并章节分页，支持上一章、下一章和可选的连续章节阅读。
- 阅读进度、章节缓存、主动下载与离线重开。
- 字体、字号、行距、正文宽度、段首缩进和明暗主题设置。
- 为 `qidiy.com` 提供专用解析；其他小说网站使用通用解析器。
- 遇到 Cloudflare 或 JavaScript 验证时，macOS 使用 WebKit、Windows 使用 WebView2 获取 rendered DOM，正文仍回到原生阅读器。

## 安装 Windows v1.2.1

Windows 版本支持 x64 Windows 10 1809 或更高版本，推荐 Windows 11。

1. 从 [YYReader Windows 1.2.1 Release](https://github.com/YangChen-cn/YYReader/releases/tag/v1.2.1) 下载 `YYReader-Setup-x64-1.2.1.exe`。
2. 运行中文安装向导；默认创建开始菜单入口，可选择创建桌面快捷方式。
3. 安装包已包含 .NET 8 与 Windows App Runtime，无需另外安装运行库。

安装程序目前没有商业代码签名，Windows SmartScreen 可能提示“未知发布者”。

## 安装 macOS v1.1.2

YYReader 1.1.2 支持 Apple 芯片 Mac，要求 macOS 15 或更高版本。

1. 从 [YYReader macOS 1.1.2 Release](https://github.com/YangChen-cn/YYReader/releases/tag/v1.1.2) 下载 `YYReader-1.1.2-arm64.dmg`。
2. 打开 DMG，将 `YYReader` 拖入 `Applications`。
3. 本版本使用 ad-hoc 签名且未经过 Apple 公证；首次启动时请在 Finder 中右键应用并选择“打开”，再确认启动。

应用不会自动解决 CAPTCHA，也不会绕过登录、付费墙或网站访问控制。第三方网站的结构和访问策略可能随时变化，通用解析无法保证支持所有站点。

## 使用

点击工具栏中的“添加网页”，粘贴任意章节 URL。当前章节成功解析后即可立即开始阅读，完整目录可随后按需加载或手动刷新。

- 单击书籍或章节：在书架模式中选择并预览。
- 双击章节、按 Return，或点击“继续阅读”：进入沉浸阅读。
- 阅读模式左侧系统按钮：显示或隐藏章节目录。
- 阅读模式返回箭头：退出沉浸阅读并回到书架。
- `⌘L`：添加网页。
- `⌘[` / `⌘]`：上一章 / 下一章。

Windows 客户端支持目录搜索、连续阅读、离线下载、书架导入导出，以及与 macOS 共用文件夹的 SyncSnapshot v2 同步。详细构建和使用说明见 [Windows README](windows/README.md)。

## 1.2.1 Windows 更新日志

- 文件夹同步改为完全非阻塞启动，并加入后台 I/O、恢复保护和看门狗；同步只合并元数据与阅读位置，不再自动刷新整本目录或打断当前阅读。
- 连续阅读在本地目录末尾通过当前尾章的下一章链接增量检查新章节，修复误报“已到最新章节”、检查失败后循环探测及通用站点无法继续的问题。
- 修复章末状态切换造成的滚动抖动；下一章可在滚动中完成网络加载，但只在滚动停止后 attach，并支持有上限的短章节连续补载。
- 修复释放聚合正文后阅读位置错误恢复到第 0 段；保持段落缓存和 `ItemsRepeater` 虚拟化，降低连续阅读的内存占用与布局开销。
- 目录关闭时不再因 append 章节重建完整列表；目录增加已缓存/已下载章节小点，HTTP 403 可进入 WebView2 验证 fallback。

## 1.2.0 Windows 更新日志

- 完成原生 WinUI 3 书架、目录、阅读器、连续章节、阅读位置恢复和 SQLite 本地存储。
- 支持 qidiy.com 与通用小说页面解析，并在必要时使用 WebView2 完成验证和 rendered DOM fallback。
- 新增完整目录刷新、章节预取、当前/后 20 章/整书离线下载，以及非阻塞错误重试。
- 新增 BookshelfTransfer 导入导出和 SyncSnapshot v2 文件夹同步；同步不会抢走正在阅读的章节或重建正文。
- 采用统一 Windows 11 标题栏、Mica 书架外壳、原生阅读主题、目录侧栏和即时 Aa 设置。
- 提供中文完整自包含安装程序，修复应用、安装程序和快捷方式图标，并移除未使用的 ONNX/DirectML 依赖。

## 1.1.2 更新日志

- 修复“继续阅读”恢复到章首的问题，改为恢复已保存的顶部段落；高级阅读设置新增“完成”按钮并支持 Escape 退出。
- 为章节正文加入 8 章容量的 LRU 缓存，避免主题、布局或阅读会话变化时反复拆分整章文本。
- 为大目录建立章节和位置索引，并按章节顺序选择可见目标，降低目录查询开销并稳定连续阅读定位。
- 正文宽度改为相对字号的 em 模型，提供 38/48/58em 三档和 20～80em 自定义滑块；行距与段距也随字号缩放。
- 收紧连续章节之间的视觉边界，并按主题使用分隔线或纸书装饰；抓取阶段完成段落清理，读取阶段只做轻量拆分。
- 构建脚本在 Debug 交付和 Release DMG 校验后清理中间 App，减少本地构建残留。

## 1.1.0 更新日志

- 新增可选连续阅读：进入章节后提前预取下一章，接近底部时平滑衔接，并保持稳定的阅读会话。
- 新增“下载到本地”：支持当前章节、后续 20 章或整本目录的低并发下载，可取消并在后台查看进度。
- 增强通用网站兼容性：支持直接导入目录页、无目录小说、多卷目录，以及静态解析失败后的安全 rendered DOM 回退。
- 改进阅读体验：支持方向键逐段滚动、轻量章节进度、目录跟随当前章节和上次阅读书籍恢复。
- 修复连续阅读中的跨章连跳、章节切换闪烁及章节边界轻微滚动跳动。

## 项目信息

- 作者：YangChen
- GitHub：[YangChen-cn/YYReader](https://github.com/YangChen-cn/YYReader)

## 从源码构建 macOS

开发环境：

- macOS 15+
- Xcode 26+（Swift 6）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

生成、构建并运行 arm64 Debug 版本：

```bash
./script/build_and_run.sh run
```

运行完整测试：

```bash
xcodegen generate
xcodebuild test \
  -project YYReader.xcodeproj \
  -scheme YYReader \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData
```

> 提示：UI 测试会合成键盘事件。若系统装有第三方输入法（如豆包输入法）且其为
> 激活输入源，macOS 会弹出「允许 testmanagerd 启用 …」授权框；由于 Debug 构建每次
> ad-hoc 重新签名，该授权无法被记住，每次运行都会弹出。跑测试前将输入源切换到
> ABC/英文即可避免。

生成 ad-hoc 签名的 arm64 Release DMG：

```bash
./script/package_release.sh
```

1.1.2 产物位于：

- `dist/YYReader-1.1.2-arm64.dmg`

构建脚本只编译 Apple 芯片 arm64 架构，移除调试记录和绝对 RPATH，并检查挂载后的 DMG 内不包含开发机 `/Users/...` 路径。发布产物只包含 DMG，不生成 ZIP。

Windows 版要求 .NET 8 SDK、Visual Studio 2022 的 C++/Windows 开发工具、Windows SDK、Windows App SDK 与 Inno Setup 6。构建、测试和生成完整安装包：

```powershell
dotnet test .\windows\YYReader.Windows.Tests\YYReader.Windows.Tests.csproj
.\windows\scripts\package-release.ps1
```

Windows 1.2.1 安装包位于 `dist/windows/YYReader-Setup-x64-1.2.1.exe`。

## 技术结构

- macOS：Swift 6、SwiftUI、SwiftData
- Windows：C#、.NET 8、WinUI 3、Windows App SDK、SQLite
- SwiftSoup 2.13.5
- XcodeGen 工程配置
- App Sandbox，仅开放出站网络

正文始终由 `ScrollView`、`LazyVStack` 和 `Text` 原生渲染。`WKWebView` 仅用于完成必要的网站验证并提取最终 HTML，解析层不依赖具体加载方式。

macOS 与 Windows 通用网页解析器的双端对齐规则见 [通用小说解析器说明](shared/generic-parser/README.md)。

## 隐私与内容

书架、缓存和阅读进度保存在本机。YYReader 不包含小说正文，也不提交抓取后的网页或 Cloudflare Cookie。请遵守目标网站的服务条款和内容版权要求。

## 许可证

当前仓库尚未声明开源许可证。源代码公开不等于自动授予复制、修改或再分发许可。
