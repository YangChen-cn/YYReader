# YYReader

YYReader 是一款以正文为中心的原生 macOS 小说阅读器。粘贴小说章节网页 URL 后，应用会识别书籍、作者、章节正文、前后章节与目录，并将网站拆分的章节分页合并为完整内容，再使用 SwiftUI 原生界面呈现。

## 功能

- 原生 SwiftUI 阅读界面，正文可选择，不使用 WebView 渲染。
- 书架、可搜索目录与沉浸式阅读模式。
- 自动合并章节分页，支持上一章和下一章。
- 阅读进度、章节缓存与离线重开。
- 字体、字号、行距、正文宽度、段首缩进和明暗主题设置。
- 为 `qidiy.com` 提供专用解析；其他小说网站使用通用解析器。
- 遇到 Cloudflare 或 JavaScript 验证时，复用每个网站的持久 WebKit 会话。

## 安装 v1.0.0

YYReader 1.0.0 支持 Apple 芯片和 Intel Mac，要求 macOS 15 或更高版本。

1. 从 [GitHub Releases](https://github.com/YangChen-cn/YYReader/releases/latest) 下载对应架构的 DMG：Apple 芯片选择 `YYReader-1.0.0-arm64.dmg`，Intel Mac 选择 `YYReader-1.0.0-x86_64.dmg`。
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

生成 ad-hoc 签名的 arm64 和 Intel x86_64 Release DMG：

```bash
./script/package_release.sh
```

产物位于：

- `dist/YYReader-1.0.0-arm64.dmg`
- `dist/YYReader-1.0.0-x86_64.dmg`

构建脚本会分别编译两个架构，移除调试记录和绝对 RPATH，并检查挂载后的 DMG 内不包含开发机 `/Users/...` 路径。发布产物只包含 DMG，不生成 ZIP。

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
