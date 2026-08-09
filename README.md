# YYReader

YYReader 是一个原生 macOS 小说阅读器。输入章节网页 URL 后，它会解析书籍信息、完整目录、章节正文和前后章节，并将网站拆分的章节分页合并后用 SwiftUI 渲染。

## 环境与运行

- macOS 15+
- Xcode 26+（Swift 6.3）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
./script/build_and_run.sh run
```

脚本会从 `project.yml` 重新生成 `YYReader.xcodeproj`、构建并启动应用。运行完整测试：

```bash
xcodebuild test -project YYReader.xcodeproj -scheme YYReader -destination 'platform=macOS' -derivedDataPath DerivedData
```

生成仅支持 Apple 芯片、临时签名的可传输版本：

```bash
./script/package_release.sh
```

产物位于 `dist/YYReader.app` 和 `dist/YYReader-release.zip`。

## 实现边界

正文始终由 `ScrollView`、`LazyVStack` 和 `Text` 原生渲染。`WKWebView` 仅在静态请求遇到 Cloudflare/JavaScript 验证时临时显示；应用不会自动解决 CAPTCHA、绕过登录或付费墙。同次导入中每个域名最多触发一次人工验证，验证等待 90 秒后自动停止，也可随时点击“停止导入”。
