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

## 目录

- `YYReader.Windows.Core`：模型、解析、SQLite、阅读位置、缓存和书架交换协议。
- `YYReader.Windows`：WinUI 3 书架、原生阅读器和 WebView2 验证 fallback。
- `YYReader.Windows.Tests`：核心行为等价测试与精简 HTML fixture 测试。
- `../shared/bookshelf-transfer`：Mac 与 Windows 共用的 BookshelfTransfer v1 schema、示例和说明。
