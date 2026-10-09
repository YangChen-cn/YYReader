import SwiftUI
import UniformTypeIdentifiers

struct MobileSettingsView: View {
    var readingManga: Bool? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(ReaderPreferenceKeys.theme) private var theme = ReaderTheme.system.rawValue
    @AppStorage(ReaderPreferenceKeys.fontFamily) private var font = ReaderFontFamily.serif.rawValue
    @AppStorage(ReaderPreferenceKeys.fontSize) private var fontSize = 20.0
    @AppStorage(ReaderPreferenceKeys.lineSpacing) private var lineSpacing = ReaderLineSpacingPreset.comfortable.value
    @AppStorage(ReaderPreferenceKeys.paragraphSpacing) private var paragraphSpacing = 0.60
    @AppStorage(ReaderPreferenceKeys.contentWidth) private var contentWidth = ReaderViewportLayout.defaultPreferredWidthEM
    @AppStorage(ReaderPreferenceKeys.paragraphIndent) private var indent = true
    @AppStorage(ReaderPreferenceKeys.continuousReading) private var continuous = false
    @AppStorage(ReaderPreferenceKeys.pageTurnMode) private var pageTurnMode = ReaderPageTurnMode.verticalScroll.rawValue
    @AppStorage(ReaderPreferenceKeys.mangaPageTurnMode) private var mangaPageTurnMode = ReaderPageTurnMode.mangaDefault.rawValue
    @AppStorage(ReaderPreferenceKeys.prefetchNext) private var prefetch = true
    @AppStorage(ReaderPreferenceKeys.presentationMode) private var presentation = ReaderPresentationMode.normal.rawValue
    @AppStorage(ReaderPreferenceKeys.academicColumnMode) private var columns = AcademicColumnMode.double.rawValue
    @State private var choosingFolder = false
    @State private var pickerError: PresentedError?

    var body: some View {
        @Bindable var sync = services.folderSync
        NavigationStack {
            Form {
                readingOptions
                Section("主题与字体") {
                    Picker("主题", selection: $theme) {
                        ForEach(ReaderTheme.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("字体", selection: $font) {
                        ForEach(ReaderFontFamily.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    LabeledContent("字号", value: "\(Int(fontSize)) 点")
                    Slider(value: $fontSize, in: 14...36, step: 1).accessibilityLabel("字号")
                }
                Section("版式与间距") {
                    LabeledContent("行距", value: lineSpacing.formatted(.number.precision(.fractionLength(1))))
                    Slider(value: $lineSpacing, in: 0...1, step: 0.1).accessibilityLabel("行距")
                    LabeledContent("段落间距") {
                        Slider(value: $paragraphSpacing, in: 0.2...1.5, step: 0.1)
                            .accessibilityLabel("段落间距")
                    }
                    if sizeClass == .regular {
                        LabeledContent("正文宽度") {
                            Slider(value: $contentWidth, in: 20...80, step: 1)
                                .accessibilityLabel("正文宽度")
                        }
                    }
                    Toggle("段首缩进", isOn: $indent)
                    Picker("排版", selection: $presentation) {
                        Text("常规").tag(ReaderPresentationMode.normal.rawValue)
                        Text("学术论文").tag(ReaderPresentationMode.academicPaper.rawValue)
                    }
                    if presentation == ReaderPresentationMode.academicPaper.rawValue {
                        if sizeClass == .regular {
                            Picker("论文栏数", selection: $columns) {
                                ForEach(AcademicColumnMode.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                        }
                        Text("窄屏自动使用单栏。文字内容保持不变。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle("自动预取", isOn: $prefetch)
                    if let store = services.libraryStore {
                        NavigationLink("本地缓存管理") { LocalCacheManagementView(store: store) }
                    }
                } header: { Text("离线阅读") } footer: {
                    Text("小说最多预取 3 章，漫画最多预取 10 张图片。更多下载选项在阅读菜单中。")
                }
                Section {
                    Button("选择共享文件夹", systemImage: "folder") { choosingFolder = true }
                        .accessibilityIdentifier("ios.chooseSyncFolder")
                    if sync.isPreparingFolderAccess {
                        ProgressView("正在获取文件夹权限…")
                    } else if let path = sync.folderDisplayPath {
                        LabeledContent("当前文件夹", value: URL(fileURLWithPath: path).lastPathComponent)
                    } else {
                        Text("先选择文件夹，再启用同步。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Toggle("启用文件夹同步", isOn: $sync.isEnabled)
                        .disabled(!sync.hasSelectedFolder)
                    Button("立即同步", systemImage: "arrow.triangle.2.circlepath", action: sync.syncNow)
                        .disabled(!sync.isEnabled || sync.isSyncing)
                    if sync.isSyncing { ProgressView("正在同步…") }
                    if let date = sync.lastSyncAt { LabeledContent("上次同步", value: date.formatted(date: .abbreviated, time: .shortened)) }
                    if let error = sync.errorMessage { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red) }
                } header: { Text("书架与阅读进度同步") } footer: {
                    Text("选择 Mac 使用的共享位置，或直接选择 YYReaderSync 文件夹，进入后点“打开”。不要选择 mac.json 文件。iOS 写入 ios.json，读取 Mac 和 Windows 快照。同步不包含正文；本地 TXT 需在各设备分别导入。")
                }
                Section("关于") {
                    LabeledContent("YYReader", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    LabeledContent("作者", value: "YangChen")
                    LabeledContent("本次更新", value: "漫画阅读与导入选择")
                    if let repositoryURL = URL(string: "https://github.com/YangChen-cn/YYReader") {
                        Link("github.com/YangChen-cn/YYReader", destination: repositoryURL)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: pageTurnMode) { _, value in
                if value == ReaderPageTurnMode.horizontalPages.rawValue {
                    presentation = ReaderPresentationMode.normal.rawValue
                }
            }
            .onChange(of: presentation) { _, value in
                if value == ReaderPresentationMode.academicPaper.rawValue {
                    pageTurnMode = ReaderPageTurnMode.verticalScroll.rawValue
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: dismiss.callAsFunction) } }
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): services.folderSync.selectFolder(url)
            case .failure(let error): pickerError = PresentedError(message: error.localizedDescription)
            }
        }
        .alert(item: $pickerError) { error in
            Alert(title: Text("无法选择文件夹"), message: Text(error.message), dismissButton: .default(Text("好")))
        }
    }

    @ViewBuilder private var readingOptions: some View {
        if let readingManga {
            Section(readingManga ? "漫画阅读方式" : "小说阅读方式") {
                pageTurnPicker(manga: readingManga)
                if !readingManga { continuousReadingToggle }
            }
        } else {
            Section("小说阅读方式") {
                pageTurnPicker(manga: false)
                continuousReadingToggle
            }
            Section("漫画阅读方式") { pageTurnPicker(manga: true) }
        }
    }

    private func pageTurnPicker(manga: Bool) -> some View {
        Picker("翻页方式", selection: manga ? $mangaPageTurnMode : $pageTurnMode) {
            ForEach(ReaderPageTurnMode.allCases) { Text($0.title).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(manga ? "ios.mangaPageTurnMode" : "ios.pageTurnMode")
    }

    private var continuousReadingToggle: some View {
        Toggle("连续阅读", isOn: $continuous)
            .disabled(pageTurnMode == ReaderPageTurnMode.horizontalPages.rawValue)
    }
}
