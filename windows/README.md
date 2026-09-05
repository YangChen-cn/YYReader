# YYReader Windows

这是 YYReader 的原生 Windows 客户端，使用 C#、.NET 8、WinUI 3 和 Windows App SDK。macOS 工程保持在仓库原位置，不依赖 Windows 端的 SQLite 数据库结构。

## 本地 TXT 与论文模式

已适配 Mac 提交 `6ecc6db` 的[交接协议](../docs/WINDOWS_LOCAL_TXT_ACADEMIC_HANDOFF.md)。

- “添加小说 → 导入本地 TXT…”支持 UTF-8、UTF-8 BOM 和 GB18030/GBK，预览章节数后可编辑书名、作者。导入后也可从书架右键“编辑书籍信息”。
- TXT 正文直接保存在 SQLite，删除原文件不影响阅读。相同原始字节重复导入会复用书籍并保留进度；清缓存不会删除本地正文。
- 文件夹同步保持 v2、书架传输保持 v1，均不携带正文。同步只有在读到 Mac 声明 `local-txt-v1` 后才发布 TXT 记录及其删除标记；另一台设备导入同一 TXT 可补全占位书。
- 阅读工具栏“论文”或默认 `Ctrl+Alt+P` 切换论文模式；阅读设置可修改快捷键字母和单/双栏偏好。宽度不足 760 DIP 时自动单栏。模式和快捷键仅保存在本机。
- 双栏以补充块为界，依次阅读完整左栏、完整右栏，再进入下一块；公式、四列表格和双序列折线图跨栏显示。原始正文和进度身份保持不变。

手动验收：导入 TXT 后切换章节、重开应用；在同一段切换普通/论文、单/双栏并缩窄窗口；连续阅读到末章应显示“已到本书末尾”。视觉布局、滚动 anchor 和真实双设备同步需要在设备上验证，自动测试不代替这部分验收。

## 开发环境

- Visual Studio Code 或其他编辑器
- .NET 8 SDK
- Windows SDK 10.0.26100.x
- WebView2 Runtime（系统通常已预装；验证 fallback 使用）

完整 Visual Studio 不是必需的；项目使用 .NET CLI 构建。

## 构建与测试

从仓库根目录执行：

```powershell
dotnet restore windows/YYReader.Windows/YYReader.Windows.csproj
dotnet build windows/YYReader.Windows/YYReader.Windows.csproj --configuration Debug --runtime win-x64
dotnet test windows/YYReader.Windows.Tests/YYReader.Windows.Tests.csproj --configuration Debug
```

构建输出位于：

```text
windows/YYReader.Windows/bin/Debug/net8.0-windows10.0.26100.0/win-x64/
```

直接运行 `YYReader.Windows.exe` 即可启动未打包 Debug 客户端。

## 正式安装包

正式分享使用 Inno Setup 6 生成当前用户安装程序。安装后会创建开始菜单入口，安装界面默认勾选桌面快捷方式，并在 Windows“已安装的应用”中提供卸载入口。

先安装 [Inno Setup 6](https://jrsoftware.org/isinfo.php)，然后从仓库根目录执行：

```powershell
.\windows\scripts\package-release.ps1
```

脚本会先删除 Windows 各项目之前生成的 Debug/Release `bin`、`obj` 及 `dist/windows` 中的旧应用包，再运行 Release 测试并生成包含 .NET 8 和 Windows App Runtime 的完整自包含 Setup.exe。结束时再次删除 `bin`、`obj` 和解包后的临时应用，只保留最终安装包。Windows App SDK 只引用 YYReader 实际使用的 WinUI、Foundation、InteractiveExperiences 和 Runtime 组件，不携带未使用的 AI/ML、ONNX Runtime 或 DirectML。

输出位于：

```text
dist/windows/YYReader-Setup-x64-1.2.3.exe
```

`Setup.exe` 无需目标电脑预装 .NET 或 Windows App Runtime，也不会在安装或启动时联网下载运行库。

清理仓库内可重新生成的 `bin`、`obj`、临时 SDK 和旧 publish 目录，同时保留最终安装包：

```powershell
.\windows\scripts\clean-local.ps1
```

需要临时指定其他版本号时：

```powershell
.\windows\scripts\package-release.ps1 -Version 1.2.3
```

安装程序和应用都使用 `YYReader.Windows/Assets/AppIcon.ico`。安装向导使用仓库内固定的 Inno Setup 官方源码仓库 `ChineseSimplified.isl` 简体中文语言文件，更新来源为 <https://github.com/jrsoftware/issrc/blob/main/Files/Languages/ChineseSimplified.isl>。

公开分发前建议使用受信任的代码签名证书签署安装程序；未签名版本仍可安装，但 Windows SmartScreen 可能显示“未知发布者”。

## 目录

- `YYReader.Windows.Core`：模型、解析、SQLite、阅读位置、缓存和书架交换协议。

> 通用网页解析器升级时应与 macOS 保持规则一致，站点回归矩阵和正文清理要求见 [双端通用解析器说明](../shared/generic-parser/README.md)。
- `YYReader.Windows`：WinUI 3 书架、原生阅读器和 WebView2 验证 fallback。
- `YYReader.Windows.Tests`：核心行为等价测试与精简 HTML fixture 测试。
- `../shared/bookshelf-transfer`：Mac 与 Windows 共用的 BookshelfTransfer v1 schema、示例和说明。
