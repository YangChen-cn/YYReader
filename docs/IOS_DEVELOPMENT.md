# iOS / iPadOS 开发与安装

最低系统为 iOS / iPadOS 18，使用 Swift 6 严格并发检查和 SwiftSoup 2.13.5。`project.yml` 管理两个 App target：Mac 的 `YYReader` 与手机端的 `YYReaderIOS`。iOS 的产品名仍为 YYReader，Bundle ID 为 `com.yyreader.ios`，不会覆盖 Mac App。

## 共用代码

iOS 直接编译 `YYReader/Models`、`Parsing`、`Services`、`Stores`、`Support` 和正文 SwiftUI 组件。网页解析、分页清理、限速、人工验证、SwiftData 去重、离线缓存、连续阅读和阅读位置算法各维护一份。

`YYReaderIOS` 包含移动端应用入口、书架/目录导航、阅读工具栏、设置、屏幕分页、FileDocument 和资源。Mac 的窗口、菜单、AppKit 文件面板和键盘事件 bridge 不进入 iOS target。WebKit 仅获取验证后的 HTML；正文仍由 `ScrollView`、`LazyVStack` 和 `Text` 显示。

## 翻页方式

阅读器右上角“阅读选项 → 阅读设置 → 翻页方式”可选择 **上下滚动** 或 **左右翻页**，默认上下滚动。设置会保留到下次打开。

- 上下滚动：保留原有连续阅读。开启“连续阅读”后可向下读到下一章。
- 左右翻页：左滑下一页，右滑上一页，默认隐藏顶部标题与底部工具栏，轻点正文中央显示阅读菜单、页数和翻页按钮，再点一次收起；越过章节末尾/开头时进入相邻章节。使用原有缓存、加载错误和重试流程。
- 两种方式共用段落进度，切换或重新打开时恢复到包含已保存段落的位置。左右模式的字号、字体、行距、段距、正文宽度、Dynamic Type 与屏幕尺寸变化会重新分页，并保留当前页的文字锚点。
- 连续阅读的开关值不会因选择左右翻页被清除。左右翻页使用常规排版；选择学术论文会切回上下滚动。

分页只处理当前章的正文，不遍历整本书，也不等待后续章节缓存；目录有几千章不增加当前章的分页工作量。跨章时使用已有缓存，未缓存的章节按原有加载流程获取；前台章节加载由手机端阅读器持有，独立于临时加载提示和分页视图。下载或读取磁盘缓存完成后刷新阅读 session，再显示正文；预取失败不会阻塞当前章分页。

分页在独立 actor 中用 Core Text 测量，主线程只传入正文值和排版参数。分页任务由独立状态持有，取消会清除加载状态，旧任务不能覆盖新结果；同一章、内容版本和布局复用已完成的结果，视口尺寸按像素取整，避免浮点抖动反复重排。SwiftUI 渲染正文，UIKit 仅用于获取与系统设计一致的字体度量。极窄窗口或超大辅助字体下，单页可纵向滚动以保证文字不被裁掉。分页不更改网页章节、URL 或正文缓存。

## 在 Xcode 调试 UI

1. 运行 `xcodegen generate`，打开根目录的 `YYReader.xcodeproj`。
2. 顶部 scheme 切换为 **YYReaderIOS**，右侧选择 iPhone 或 iPad 模拟器。不要选择 Mac 的 **YYReader** scheme。
3. 没有模拟器时，进入 **Xcode → Settings → Components**，下载安装 iOS 运行时；之后在 **Window → Devices and Simulators → Simulators** 添加设备。
4. 按 **⌘R** 构建和运行。可以在模拟器中使用鼠标点击、输入或滚动，并在 Xcode 设置断点、查看控制台或选择 **Debug → View Debugging → Capture View Hierarchy**。
5. Canvas：打开 `YYReaderIOS/Views/MobileLibraryPreview.swift`，选择 **Editor → Canvas**（⌥⌘↩），点 **Resume**。文件包含“书架”和“阅读器”两组预览，只使用自造文本与内存书架。Debug 启动传入 `--preview-library` 可在模拟器中使用同一内存示例书架，便于人工检查 iPad 横竖屏、阅读及目录；不读取真实书架，也不绑定同步。重新启动时不带参数即恢复真实书架。
6. 修改 SwiftUI 后重新运行或刷新 Canvas。可以切换 iPad、横屏、系统深色和增大字体检查适配。

命令行入口：

```bash
./script/build_ios.sh simulator
./script/build_ios.sh test
```

测试包含共享业务单元测试与屏幕分页测试，不包含界面自动化用例：界面行为一律人工验收。人工验收可使用 `--ui-testing` 的内存书架；分页场景另加 `--ui-testing-pagination` 使用自造长正文，`--ui-testing-large-catalog` 使用5000章目录且只缓存当前章，验证切换与工具栏不会卡在分页中。`--ui-testing-uncached` 则直接以左右翻页打开未缓存章（延迟模拟下载）和仅在磁盘缓存的章，验证正文就绪后不再停留在“正在准备章节”。Debug 可以传 `--preview-url <小说网址>` 预先导入实际书籍用于人工验收；该入口不进入 Release。真实网站、云文件提供商和主观视觉效果仍需手动验收。

多台模拟器时可通过 `YYREADER_SIMULATOR_ID=<UDID>` 指定设备。模拟器不需要 Apple 签名证书。

## 真机与 IPA

真机调试：连接设备，在 App target 的 **Signing & Capabilities → Team** 选择自己的 Apple ID 对应团队，按提示启用手机的开发者模式，然后选择设备并按 ⌘R。签名与描述文件必须允许目标设备运行。Apple 说明见 [向注册设备分发 App](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)。

供侧载工具重新签名的设备版 IPA：

```bash
./script/package_ios.sh unsigned
```

输出 `dist/iOS/YYReader-iOS-1.4.0-resign.ipa`，仅 arm64；上述日常构建命令默认 Debug，GitHub iOS 1.4.0 发布资产使用 Release。脚本检查图标、架构和 ZIP 完整性。**未签名 IPA 不能直接安装**；在侧载工具中使用自己的 Apple ID / 证书和描述文件签名后安装。普通 macOS ad-hoc 自签名不能代替 iOS 的设备签名。

本机具备 Apple 开发者签名资源时，也可导出 development IPA：

```bash
YYREADER_IOS_TEAM_ID=你的TeamID ./script/package_ios.sh signed
```

输出在 `dist/iOS/signed/`，脚本使用 Xcode 的 `debugging` 导出方式。Personal Team 的导出限制由 Xcode 决定，可改为直接从 Xcode 安装到自己的设备。日常开发默认 Debug；`./script/build_ios.sh release` 或 `./script/package_ios.sh unsigned Release` 生成发布用 arm64 Release IPA 和同名 `.sha256` 校验文件。两个配置均不构建 Mac Release 或 DMG。

### 使用 SideStore 在手机端安装与续签

YYReader 的 `resign.ipa` 可以交给 SideStore 重新签名。SideStore 的 [官方 FAQ](https://docs.sidestore.io/docs/faq) 说明普通 App 无需专门修改；续签由 SideStore 管理，YYReader 不需要内置签名服务。

1. 首次按 [SideStore 官方安装说明](https://docs.sidestore.io/docs/installation/install) 使用电脑安装并配置 SideStore，完成开发者信任、开发者模式、配对文件及 LocalDevVPN 设置。
2. 把 `YYReader-iOS-1.4.0-resign.ipa` 保存到 iPhone 的“文件”。在 SideStore 的 My Apps 页面导入该 IPA，使用自己的 Apple Account 签名安装。
3. SideStore 会尝试后台刷新已安装 App；免费账号签名通常为7天，仍需确保其后台刷新与 LocalDevVPN 配置可用，定期检查 My Apps 中的剩余天数，也可点剩余天数手动刷新。iOS 的后台调度不保证每次自动刷新成功。
4. 更新 YYReader 时使用同一账号，在 SideStore 导入新版 IPA 覆盖安装，保留已有 App。对于已由其他工具安装的版本，官方 FAQ 也建议保留原 App 再导入同一或新版 IPA；迁移前可先导出 `.yyreader` 书架文件。

按官方 FAQ，免费账号同时可激活3个 App（包含 SideStore 自己），YYReader 占1个名额。作者已于2026年10月9日完成 iOS 1.0.0 发布版 IPA 重新签名、iPhone 安装、启动和正文阅读，并提供共享文件夹同步已启用及同步时间的真机截图。上述 SideStore 操作为兼容性与官方流程说明，此次反馈未确认使用哪种侧载工具，也未验证自动续签。

## 文件与同步

书架右上角“添加”菜单按“添加小说”和“书架传输”分组，提供网页 URL、TXT、`.yyreader` / JSON 和剪贴板导入。TXT 和书架导入先预览，再确认。文件使用系统文件选择器，导出使用系统保存面板，其他 App 打开 TXT 或书架文件时可交给 YYReader。

在“设置 → 书架与阅读进度同步”先选择文件夹，再启用同步。可以选择 Mac 使用的共享父文件夹，也可以直接进入已有的 `YYReaderSync` 文件夹后点“打开”；不要选择 `mac.json` 文件。直接选择同步目录时不会再创建嵌套的 `YYReaderSync`。iOS 先激活文件夹访问权限再保存 security-scoped bookmark，通过文件协调器访问云端占位文件，写入 `YYReaderSync/ios.json`，读取 `mac.json` 与 `windows.json`。新版 Mac 读取 iOS 快照；旧版 Mac 与 Windows 当前不直接读取 `ios.json`，需经新版 Mac 中转或使用书架文件。不同文件提供商的目录同步、下载和变化通知存在延迟，回到前台或“立即同步”可重试。

同步不包含 TXT / 网页正文、Cookie 或验证状态。iOS 进入后台时先保存本地进度；共享目录不可访问时保留本地书架，恢复前台后重试。不要把不同 iOS 设备同时指向同一个 `ios.json`：当前协议以平台为单个写入方，尚不支持多部 iPhone 各自独立快照。

## 书架与设置

冷启动默认进入完整书架，每本书的当前章节和阅读进度仍保存在本地；点开书籍直接继续上次阅读。iPhone 与 iPad 使用 NavigationStack：阅读器占据当前窗口，目录按需在独立弹窗中打开，不固定挤出三栏。启动后的同步合并保持未选书状态。

主题的明暗设置从应用根部生效，覆盖书架、目录、设置和阅读器。选择“系统”时跟随 iOS 的浅色/深色模式；选择具体主题时使用该主题的明暗模式，进入或退出正文不会再改变整个窗口的明暗。论文内容仍使用白纸排版。启动屏使用支持浅色与深色的背景颜色资源。

空书架居中提供添加网址、导入 TXT 和导入书架入口；更新提示限制在舒适的宽度。已有书籍使用 LazyVGrid 卡片，随实际窗口宽度排列 1～3 列，大字体使用单列；iPad 竖屏、横屏及多任务窄窗口都保留书架首页。卡片显示文字封面、作者、来源和缓存状态，读过的书显示当前章节与本章进度。长按书籍可编辑或删除。设置按阅读方式、主题字体、版式间距、离线阅读与同步分组；正文宽度和论文栏数只在宽屏显示。

## 手动验收

- iPhone：从空书架添加网页，取消导入、重试失败；点小说续读，从阅读菜单打开目录，搜索并切章，再返回书架。
- iPad：横竖屏完整书架、卡片列数、空状态和更新提示；正文占满当前窗口，目录打开/关闭与切章后继续阅读；旋转及多任务调整宽度后进度保留。大字体和 VoiceOver 下标签可读、按钮可操作。
- TXT：导入自造 UTF-8 或 GBK 小说，确认标题，阅读后退出/重新打开；开启飞行模式仍能读已缓存内容。
- 阅读设置：主题、字体、字号、行距、段距、连续阅读和论文单栏；切换样式后位置保持。
- 翻页：默认顶部标题与底部工具栏隐藏，轻点正文中央显示/收起；正文应接近填满可用高度（章节末页允许留白）。左右滑动和底部按钮都能前后翻页，章节边界可跨章；在中途切回上下滚动，仍在同一段落附近；横竖屏和增大字体后没有缺字、重复文字或被裁掉的末行。
- 书架传输：导出，再从文件/剪贴板导入；预览新书、已有、错误与重复，正文缓存保留。
- 同步：在真机分别尝试选择共享父目录和直接选择 `YYReaderSync`（含尚未下载的 iCloud 文件），启用后点“立即同步”，确认同目录出现 `ios.json` 且 Mac 书架可读入；Mac 与 iOS 选择同一共享文件夹，前进到下一章并同步；进度不倒退、重复同步不重写、删除可传递。
- 验证：真实网站要求人工验证时手动完成，取消和超时能结束；不循环弹窗。

日常 UI 不使用 Computer Use 自动点击或截图。真实网站和主观视觉效果由用户在设备上验收，测试使用精简 fixture。
