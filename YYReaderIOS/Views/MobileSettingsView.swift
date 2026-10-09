import SwiftUI
import UniformTypeIdentifiers

struct MobileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @AppStorage(ReaderPreferenceKeys.theme) private var theme = ReaderTheme.system.rawValue
    @AppStorage(ReaderPreferenceKeys.fontFamily) private var font = ReaderFontFamily.serif.rawValue
    @AppStorage(ReaderPreferenceKeys.fontSize) private var fontSize = 20.0
    @AppStorage(ReaderPreferenceKeys.lineSpacing) private var lineSpacing = ReaderLineSpacingPreset.comfortable.value
    @AppStorage(ReaderPreferenceKeys.paragraphSpacing) private var paragraphSpacing = 0.60
    @AppStorage(ReaderPreferenceKeys.contentWidth) private var contentWidth = ReaderViewportLayout.defaultPreferredWidthEM
    @AppStorage(ReaderPreferenceKeys.paragraphIndent) private var indent = true
    @AppStorage(ReaderPreferenceKeys.continuousReading) private var continuous = false
    @AppStorage(ReaderPreferenceKeys.pageTurnMode) private var pageTurnMode = ReaderPageTurnMode.verticalScroll.rawValue
    @AppStorage(ReaderPreferenceKeys.prefetchNext) private var prefetch = true
    @AppStorage(ReaderPreferenceKeys.presentationMode) private var presentation = ReaderPresentationMode.normal.rawValue
    @AppStorage(ReaderPreferenceKeys.academicColumnMode) private var columns = AcademicColumnMode.double.rawValue
    @State private var choosingFolder = false
    @State private var pickerError: PresentedError?

    var body: some View {
        @Bindable var sync = services.folderSync
        NavigationStack {
            Form {
                Section {
                    Picker("翻页方式", selection: $pageTurnMode) {
                        ForEach(ReaderPageTurnMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("ios.pageTurnMode")
                    Toggle("连续阅读", isOn: $continuous)
                        .disabled(pageTurnMode == ReaderPageTurnMode.horizontalPages.rawValue)
                } header: { Text("阅读方式") } footer: {
                    Text("上下滚动支持连续阅读；左右翻页按屏幕分页，章末继续左滑进入下一章。左右翻页使用常规排版，学术论文使用上下滚动。")
                }
                Section("阅读外观") {
                    Picker("主题", selection: $theme) {
                        ForEach(ReaderTheme.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("字体", selection: $font) {
                        ForEach(ReaderFontFamily.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    LabeledContent("字号", value: "\(Int(fontSize)) 点")
                    Slider(value: $fontSize, in: 14...36, step: 1).accessibilityLabel("字号")
                    LabeledContent("行距", value: lineSpacing.formatted(.number.precision(.fractionLength(1))))
                    Slider(value: $lineSpacing, in: 0...1, step: 0.1).accessibilityLabel("行距")
                    LabeledContent("段落间距") {
                        Slider(value: $paragraphSpacing, in: 0.2...1.5, step: 0.1)
                            .accessibilityLabel("段落间距")
                    }
                    LabeledContent("正文宽度") {
                        Slider(value: $contentWidth, in: 20...80, step: 1)
                            .accessibilityLabel("正文宽度")
                    }
                    Toggle("段首缩进", isOn: $indent)
                    Toggle("预取下一章", isOn: $prefetch)
                    Picker("排版", selection: $presentation) {
                        Text("常规").tag(ReaderPresentationMode.normal.rawValue)
                        Text("学术论文").tag(ReaderPresentationMode.academicPaper.rawValue)
                    }
                    if presentation == ReaderPresentationMode.academicPaper.rawValue {
                        Picker("论文栏数", selection: $columns) {
                            ForEach(AcademicColumnMode.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        Text("窄屏自动使用单栏。文字内容保持不变。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle("启用文件夹同步", isOn: $sync.isEnabled)
                        .disabled(!sync.hasSelectedFolder)
                    Button("选择共享文件夹", systemImage: "folder") { choosingFolder = true }
                        .accessibilityIdentifier("ios.chooseSyncFolder")
                    if let path = sync.folderDisplayPath { Text(path).font(.caption).foregroundStyle(.secondary) }
                    Button("立即同步", systemImage: "arrow.triangle.2.circlepath", action: sync.syncNow)
                        .disabled(!sync.isEnabled || sync.isSyncing)
                    if sync.isSyncing { ProgressView("正在同步…") }
                    if let date = sync.lastSyncAt { LabeledContent("上次同步", value: date.formatted()) }
                    if let error = sync.errorMessage { Text(error).foregroundStyle(.red) }
                } header: { Text("书架与阅读进度同步") } footer: {
                    Text("在“文件”中选择共享文件夹。iOS 写入 YYReaderSync/ios.json，读取 Mac 和 Windows 快照。同步不包含正文；本地 TXT 需在各设备分别导入。文件提供商的更新速度可能不同。")
                }
                Section("关于") {
                    LabeledContent("YYReader", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    Text("原生阅读 · 与 Mac 共用解析、缓存和进度逻辑")
                    Text("本次更新：上下滚动与左右翻页、TXT 导入、离线缓存和跨端书架传输。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("网站要求验证时，请手动完成；不绕过登录或付费访问。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
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
}
