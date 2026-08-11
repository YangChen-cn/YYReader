# YYReader

YYReader 是一款以正文为中心的原生 macOS 小说阅读器。粘贴小说章节网页 URL 后，应用会识别书籍、作者、章节正文、前后章节与目录，并将网站拆分的章节分页合并为完整内容，再使用 SwiftUI 原生界面呈现。

## 功能

- 原生 SwiftUI 阅读界面，正文可选择，不使用 WebView 渲染。
- 书架、可搜索目录与沉浸式阅读模式。
- 自动合并章节分页，支持上一章、下一章和可选的连续章节阅读。
- 阅读进度、章节缓存、主动下载与离线重开。
- 字体、字号、行距、正文宽度、段首缩进和明暗主题设置。
- 为 `qidiy.com` 提供专用解析；其他小说网站使用通用解析器。
- 遇到 Cloudflare 或 JavaScript 验证时，复用每个网站的持久 WebKit 会话。

## 安装 v1.1.2

YYReader 1.1.2 支持 Apple 芯片 Mac，要求 macOS 15 或更高版本。

1. 从 [GitHub Releases](https://github.com/YangChen-cn/YYReader/releases/latest) 下载 `YYReader-1.1.2-arm64.dmg`。
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

- 作者：Yangchen
- GitHub：[YangChen-cn/YYReader](https://github.com/YangChen-cn/YYReader)

## 从源码构建

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

## 技术结构

- Swift 6 严格并发检查
- SwiftUI + SwiftData
- SwiftSoup 2.13.5
- XcodeGen 工程配置
- App Sandbox，仅开放出站网络

正文始终由 `ScrollView`、`LazyVStack` 和 `Text` 原生渲染。`WKWebView` 仅用于完成必要的网站验证并提取最终 HTML，解析层不依赖具体加载方式。

## 隐私与内容

书架、缓存和阅读进度保存在本机。YYReader 不包含小说正文，也不提交抓取后的网页或 Cloudflare Cookie。请遵守目标网站的服务条款和内容版权要求。

## 许可证

当前仓库尚未声明开源许可证。源代码公开不等于自动授予复制、修改或再分发许可。
