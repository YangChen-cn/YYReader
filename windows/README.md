# YYReader Windows

这是 YYReader 的原生 Windows 客户端，使用 C#、.NET 8、WinUI 3 和 Windows App SDK。macOS 工程保持在仓库原位置，不依赖 Windows 端的 SQLite 数据库结构。

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

脚本会运行 Release 测试并生成包含 .NET 8 和 Windows App Runtime 的完整自包含 Setup.exe。Windows App SDK 只引用 YYReader 实际使用的 WinUI、Foundation、InteractiveExperiences 和 Runtime 组件，不携带未使用的 AI/ML、ONNX Runtime 或 DirectML。

输出位于：

```text
dist/windows/YYReader-Setup-x64-1.2.0.exe
```

`Setup.exe` 无需目标电脑预装 .NET 或 Windows App Runtime，也不会在安装或启动时联网下载运行库。

清理仓库内可重新生成的 `bin`、`obj`、临时 SDK 和旧 publish 目录，同时保留最终安装包：

```powershell
.\windows\scripts\clean-local.ps1
```

需要临时指定其他版本号时：

```powershell
.\windows\scripts\package-release.ps1 -Version 1.2.0
```

安装程序和应用都使用 `YYReader.Windows/Assets/AppIcon.ico`。安装向导使用仓库内固定的 Inno Setup 官方源码仓库 `ChineseSimplified.isl` 简体中文语言文件，更新来源为 <https://github.com/jrsoftware/issrc/blob/main/Files/Languages/ChineseSimplified.isl>。

公开分发前建议使用受信任的代码签名证书签署安装程序；未签名版本仍可安装，但 Windows SmartScreen 可能显示“未知发布者”。

## 目录

- `YYReader.Windows.Core`：模型、解析、SQLite、阅读位置、缓存和书架交换协议。
- `YYReader.Windows`：WinUI 3 书架、原生阅读器和 WebView2 验证 fallback。
- `YYReader.Windows.Tests`：核心行为等价测试与精简 HTML fixture 测试。
- `../shared/bookshelf-transfer`：Mac 与 Windows 共用的 BookshelfTransfer v1 schema、示例和说明。
