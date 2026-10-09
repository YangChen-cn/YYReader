# YYReader 协作规范

适用于仓库及全部子目录；更具体的子目录规范仅覆盖对应目录，用户当前要求优先。本项目主要供个人使用，优先简单、稳定、可复用的实现，避免过度工程。

## 工作范围与验证

- 只做指定任务和平台，不顺手扩展功能、引入框架或改造流程。共用代码确实影响其他平台时，才说明理由并扩大检查范围。
- 功能改动只运行风险相称的最小相关测试；通过后无新变化或具体问题就停止。全量测试仅用于重大或影响范围不明的核心改动、明确回归问题，或用户要求。
- UI 的布局、动画和手势默认交给用户人工验收，提供简短步骤；不要反复调试 XCUITest 来代替人工看界面。用户要求停止自动验证后，不再继续相关测试。
- 仅改文档、版本号、About 文案、下载链接或打包配置时，不重跑功能测试，不启动 App、模拟器或浏览器。已通过的检查和源码未变的产物直接复用。
- 每个耗时操作都必须有具体目的，不以“保险起见”重复构建或检查。普通开发不生成 Release、IPA 或 DMG；仅在用户要求打包、发布或检查发布流程时生成。
- Computer Use 默认禁用；仅在当前请求明确授权，或人工验证客观无法完成且用户同意时使用。
- iOS 始终复用用户正在使用的一台模拟器，覆盖 App 并保留数据；未经要求不新建、不同时启动第二台。

## 工程与命令

- macOS 15+、iOS 18+；Swift 6 严格并发、SwiftUI、SwiftData、SwiftSoup **2.13.5**。Mac 只构建 `arm64`，除非用户另有要求；保留 App Sandbox，不额外扩大权限。
- `project.yml` 是工程配置唯一来源。不要手改 `project.pbxproj`；配置或源文件列表变化后运行 `xcodegen generate`，保留生成的工程改动。
- 目录沿用现有职责：`Views` 界面、`Stores` UI 编排、`Services` 网络与缓存、`Parsing` 解析、`Persistence` 持久化、`Support` 共用辅助；主要类型保持单一职责。

| 用途 | 命令 |
| --- | --- |
| 生成工程 | `xcodegen generate` |
| Mac Debug 交付与运行 | `./script/build_and_run.sh run` |
| iOS 模拟器更新 | `YYREADER_SIMULATOR_ID=<当前模拟器UDID> ./script/build_ios.sh simulator` |
| Mac 发布打包 | `./script/package_release.sh` |
| iOS 发布打包 | `./script/build_ios.sh release` |

Mac Debug 必须经现有脚本便携化、签名后交付 `dist/YYReader.app`，不直接交付 DerivedData 里的 App。仅做 iOS / Windows 任务时不运行 Mac 脚本。测试按需使用 `xcodebuild test -only-testing:目标/测试类`，不得把全量测试当成默认步骤。

## Swift 与原生界面

- UI 状态、Store 与 SwiftData `ModelContext` 隔离到 `@MainActor`；可变缓存、网络队列和同步 I/O 使用 actor。不要用 `Task.detached` 绕过隔离；必要的 `@unchecked Sendable` 必须说明保护方式。
- 异步操作传播取消，旧请求不得覆盖新页面。取消不弹失败提示；前台错误不得用 `try?` 静默吞掉，预取失败可忽略但需说明。
- 小说正文用 SwiftUI `ScrollView`、`LazyVStack`、`Text`；漫画用原生 `Image`。`WKWebView` 仅用于网页验证、公开脚本执行及提取内容，不能渲染阅读正文。
- Mac 沿用原生 `NavigationSplitView`、工具栏、菜单、Settings 和 Inspector；仅在必要时做窄边界 AppKit bridge。空状态使用 `ContentUnavailableView`，不自绘窗口框架。
- 段落、图片和滚动锚点保持稳定身份，恢复进度不随视图重建丢失。按钮有可读标签，兼顾键盘、VoiceOver、字体放大、对比度和减少动态效果。
- 文案简洁，避免说明小字堆积；About 保留版本、作者 **YangChen** 和仓库链接。新增文案维护字符串目录。

## 漫画阅读约定

- 漫画与小说独立保存阅读方式；漫画默认 **Mac 左右翻页、iOS 上下滚动**，保留用户后续选择。
- Mac 支持自动 / 单页 / 双页；宽窗口自动组合两张竖图，窄窗口单页。横图独占、支持首图单页与奇数尾页，双页不跨章。等比完整显示、居中，页间有区分，工具栏不得遮挡图片。
- 页码与持久化进度始终使用原始图片索引；分组、窗口缩放、模式切换和重新打开不改写位置。跨章前进到首页、后退到末页；Slider 拖动只预览，松手才跳转。
- iOS 左右翻页支持点击两侧和跟手滑动动画，中间点击切换工具栏；上下滚动也能切换标题栏与进度栏，但不强制点击翻页。双击图片进入放大查看，支持捏合与拖动，避免与翻页手势冲突。Mac 保留鼠标和键盘翻页、自然滚轮与触控板滚动。
- 连续滚动保留 `LazyVStack` 和锚点恢复，宽度随窗口适配；普通页留小间距、长条尽量连续，优先用已知宽高比占位以减少跳动。
- 只渲染可见页和有限相邻页，复用缩略图内存缓存、原图磁盘缓存与预取，不加载整本图片。纯布局改动不修改 SwiftData schema、同步协议或解析器，不引入大型依赖。

## 加载、解析与缓存

- 静态 HTML 优先 `URLSessionHTMLLoader`；检查 HTTP 状态、重定向、编码、challenge 和取消。同域串行限速，429 尊重 `Retry-After`，不紧密重试。
- 不绕过 CAPTCHA、登录、付费墙或访问控制。同次导入同域最多展示一次人工验证，继续拒绝则停止；验证可取消、有限等待，并把 Cookie / 真实 User-Agent 同步到后续请求。
- 所有站点沿用 `NovelSourceAdapter`，专用适配优先于通用解析，不在 UI 写站点判断或 CSS selector；通用解析优先结构化元数据、语义正文与导航关系，再用正文密度评分。只适配能正常访问的示例；403 或无响应的跳过，不反复尝试。
- 分页只跟随解析出的同源链接，以 visited 防循环；章节最多 20 页、目录最多 200 页。合并去除边界重复、广告和分页噪声；错误区分请求失败、正文或目录缺失、循环等原因。
- 章节 URL 规范化不能误合并不同章节；目录按页面与 DOM 顺序排序，不能只按标题章节号。书籍按规范目录 URL 或稳定的 `sourceBookURL` 去重，章节按规范章节 URL 去重，合并保留缓存和进度。
- 打开书籍只读本地目录，过期不自动刷新全目录；刷新由导入或用户主动触发，可取消。切章、关闭或退出前持久化段落 / 图片索引及阅读比例；删除书籍级联清理章节与缓存。
- 默认开启预取：小说最多 3 章，漫画提前缓存最多 10 张图片。预取失败不影响当前阅读；用户主动下载沿用现有功能。
- 每本漫画磁盘缓存预算 **512 MB**；退出或切书时优先清理最早读过的章节，保留当前章和未读预取 / 下载内容，受保护内容超预算时不强删。缓存管理可清空全部或单本，保留书架、进度和本地 TXT。

## 文件夹同步与书架传输

- 用户选择任意共享文件夹，不硬编码云盘路径。Mac 用 `NSOpenPanel`，iOS 用系统文件夹选择器；保存 security-scoped bookmark，配对开始 / 结束访问。iOS 选文件夹，不选 `mac.json`。
- 同步目录固定 `YYReaderSync/`，各端只写自己的 `mac.json` / `ios.json` / `windows.json`；互读范围及格式以 `shared/sync/README.md`、`shared/sync/sync-snapshot-v2.schema.json` 为准，兼容 v1。
- 按 canonical `sourceURL` 合并；阅读位置选更后章节，同章只前进，不以 `lastReadAt` 决策；元数据按 `updatedAt`、删除按 `deletedAt` tombstone。当前阅读书的远端删除延迟到退出或安全时机处理。
- 同步只含书架、元数据和进度，不含正文、图片、Cookie 或验证状态；同目录临时文件原子替换。目录不可访问、文件无效或版本不支持时，不清空或覆盖本地书架。
- 同步 I/O、编解码、合并在独立 actor，避开滚动热路径；本地进度 debounce 保存后再延迟 1～2 秒同步。对端签名变化才合并，低频轮询兜底，未变不重写，重复同步幂等。
- 本地变化走 `publishLocal()`，只写本端快照，不读取对端或重建 Reader session；对端签名在合并落库成功后才确认，失败保留重试机会。
- 手动传输遵循 `shared/bookshelf-transfer/bookshelf-transfer-v1.schema.json`；导入前预览新书、已存在、重复及无效条目，按规范来源合并并保留本地缓存。导出不含正文。

## Git、测试与发布

- 保留用户已有改动，不覆盖无关文件；提交前检查 `git status`、`git diff --check`、敏感信息和产物。不使用 `git reset --hard` 或强推，不擅自创建公开仓库。
- 不提交 `DerivedData/`、`dist/`、Xcode 用户状态、网页抓取内容、Cookie 或临时文件；工程配置与生成的 `.xcodeproj` 保持一致。
- 测试只覆盖本次风险与回归，fixture 使用精简自造内容，不依赖实时第三方网站、不提交完整版权章节。主观 UI 验收交给用户，不能声称编译通过等于界面通过。
- 发布只更新指定平台版本，同步维护 `project.yml`、README、RELEASE_NOTES 和 About 可见内容，生成工程后提交，再推送 `main` 与对应版本标签。发布前确认仓库可见性。
- Mac 发布 arm64、ad-hoc 签名 DMG，通过 `codesign --verify --strict` 和 DMG 完整性检查；iOS IPA 供 SideStore 等侧载工具自行重新签名。只检查目标平台版本、架构、资源、包完整性和校验值，不重复构建已有产物。
- 图标与 Asset Catalog 必须进入目标资源；Mac 发布包含 `AppIcon.icns`、`Assets.car`，保持 `AppIcon` 配置。交付说明实际改动、必要检查结果和仍需人工验收的部分。

更多实现细节按任务查阅 `docs/IOS_DEVELOPMENT.md`、`docs/MANGA_SUPPORT.md` 和 `shared/` 协议文档，不把全部说明堆进本文件。
