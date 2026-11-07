import SwiftUI

/// Reading-only controls share the same preferences as the full Settings screen.
struct MobileReadingAppearanceView: View {
    let readingManga: Bool
    let automaticLandscapeActive: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(ReaderPreferenceKeys.theme) private var themeName = ReaderTheme.system.rawValue
    @AppStorage(ReaderPreferenceKeys.fontFamily) private var fontName = ReaderFontFamily.serif.rawValue
    @AppStorage(ReaderPreferenceKeys.fontSize) private var fontSize = 20.0
    @AppStorage(ReaderPreferenceKeys.lineSpacing) private var lineSpacing = ReaderLineSpacingPreset.comfortable.value
    @AppStorage(ReaderPreferenceKeys.paragraphSpacing) private var paragraphSpacing = 0.60
    @AppStorage(ReaderPreferenceKeys.paragraphIndent) private var indent = true
    @AppStorage(ReaderPreferenceKeys.contentWidth) private var contentWidth = ReaderViewportLayout.defaultPreferredWidthEM
    @AppStorage(ReaderPreferenceKeys.continuousReading) private var continuous = false
    @AppStorage(ReaderPreferenceKeys.pageTurnMode) private var pageTurnMode = ReaderPageTurnMode.verticalScroll.rawValue
    @AppStorage(ReaderPreferenceKeys.mangaPageTurnMode) private var mangaPageTurnMode = ReaderPageTurnMode.mangaDefault.rawValue
    @AppStorage(ReaderPreferenceKeys.mangaPageLayout) private var mangaLayout = MangaPageLayout.Mode.automatic.rawValue
    @AppStorage(ReaderPreferenceKeys.mangaTabletAutoLandscape) private var autoLandscape = true
    @AppStorage(ReaderPreferenceKeys.mangaFirstPageAlone) private var firstPageAlone = true
    @AppStorage(ReaderPreferenceKeys.mangaDarkBackground) private var mangaDarkBackground = false
    @BookReaderPresentation private var presentation
    @AppStorage(ReaderPreferenceKeys.academicColumnMode) private var columns = AcademicColumnMode.double.rawValue
    @AppStorage(ReaderPreferenceKeys.tavernRemoteAvatars) private var remoteAvatars = true

    var body: some View {
        NavigationStack {
            Form {
                if !readingManga {
                    themeSection
                }
                Section("阅读方式") {
                    if readingManga && automaticLandscapeActive && autoLandscape {
                        LabeledContent("翻页方式", value: ReaderPageTurnMode.horizontalPages.title)
                    } else {
                        Picker("翻页方式", selection: readingManga ? $mangaPageTurnMode : $pageTurnMode) {
                            ForEach(ReaderPageTurnMode.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if readingManga {
                        if UIDevice.current.userInterfaceIdiom == .pad {
                            Toggle("横屏自动双页", isOn: $autoLandscape)
                            if automaticLandscapeActive && autoLandscape {
                                LabeledContent("漫画布局", value: MangaPageLayout.Mode.double.title)
                            } else if mangaPageTurnMode == ReaderPageTurnMode.horizontalPages.rawValue {
                                Picker("漫画布局", selection: $mangaLayout) {
                                    ForEach(MangaPageLayout.Mode.allCases) { Text($0.title).tag($0.rawValue) }
                                }
                            }
                            Toggle("首图单页", isOn: $firstPageAlone)
                        }
                        Toggle("深灰阅读背景", isOn: $mangaDarkBackground)
                    } else {
                        Toggle("连续阅读", isOn: $continuous)
                            .disabled(pageTurnMode == ReaderPageTurnMode.horizontalPages.rawValue
                                      && presentation == ReaderPresentationMode.normal.rawValue)
                        Picker("排版", selection: $presentation) {
                            ForEach(ReaderPresentationMode.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        if presentation == ReaderPresentationMode.sillyTavern.rawValue {
                            Toggle("自动加载图床头像", isOn: $remoteAvatars)
                        }
                        if presentation == ReaderPresentationMode.academicPaper.rawValue && sizeClass == .regular {
                            Picker("论文栏数", selection: $columns) {
                                ForEach(AcademicColumnMode.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                        }
                    }
                }

                if !readingManga {
                    Section("字体与排版") {
                        Picker("字体", selection: $fontName) {
                            ForEach(ReaderFontFamily.allCases) { family in
                                Text(family.title).font(family.font(size: 17)).tag(family.rawValue)
                            }
                        }
                        LabeledContent("字号", value: "\(Int(fontSize)) 点")
                        HStack(spacing: 8) {
                            Button("减小字号", systemImage: "textformat.size.smaller") {
                                fontSize = max(14, fontSize - 1)
                            }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                            .disabled(fontSize <= 14)
                            Slider(value: $fontSize, in: 14...36, step: 1).accessibilityLabel("字号")
                            Button("增大字号", systemImage: "textformat.size.larger") {
                                fontSize = min(36, fontSize + 1)
                            }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                            .disabled(fontSize >= 36)
                        }
                        .buttonStyle(.borderless)
                        LabeledContent("行距", value: lineSpacing.formatted(.number.precision(.fractionLength(1))))
                        Slider(value: $lineSpacing, in: 0...1, step: 0.1).accessibilityLabel("行距")
                        LabeledContent("段距", value: paragraphSpacing.formatted(.number.precision(.fractionLength(1))))
                        Slider(value: $paragraphSpacing, in: 0.2...1.5, step: 0.1).accessibilityLabel("段距")
                        if sizeClass == .regular {
                            LabeledContent("正文宽度") {
                                Slider(value: $contentWidth, in: 20...80, step: 1).accessibilityLabel("正文宽度")
                            }
                        }
                        Toggle("段首缩进", isOn: $indent)
                    }
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: dismiss.callAsFunction) } }
            .onChange(of: pageTurnMode) { _, value in
                if value == ReaderPageTurnMode.horizontalPages.rawValue { presentation = ReaderPresentationMode.normal.rawValue }
            }
        }
    }

    private var themeSection: some View {
        let selectedTheme = ReaderTheme(rawValue: themeName) ?? .system
        let selectedFont = ReaderFontFamily(rawValue: fontName) ?? .serif
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        return Section("阅读主题") {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: paragraphSpacing * fontSize) {
                    ReaderParagraphView(paragraph: "翻开书页，故事缓缓展开。", fontFamily: selectedFont,
                                        fontSize: fontSize, lineSpacing: lineSpacing * fontSize,
                                        usesFirstLineIndent: indent)
                    ReaderParagraphView(paragraph: "此刻，就慢慢读下去。", fontFamily: selectedFont,
                                        fontSize: fontSize, lineSpacing: lineSpacing * fontSize,
                                        usesFirstLineIndent: indent)
                }
                .foregroundStyle(selectedTheme.foreground)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selectedTheme.background, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("阅读效果预览")

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount), spacing: 12) {
                    ForEach(ReaderTheme.allCases) { theme in
                        Button { themeName = theme.rawValue } label: {
                            VStack(spacing: 5) {
                                Text("阅")
                                    .font(.system(size: 23, weight: .medium, design: .serif))
                                    .foregroundStyle(theme.foreground)
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .background(theme.background, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(themeName == theme.rawValue ? Color.accentColor : Color.secondary.opacity(0.25),
                                                      lineWidth: themeName == theme.rawValue ? 2 : 1))
                                    .overlay(alignment: .topTrailing) {
                                        if themeName == theme.rawValue {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(theme.foreground)
                                                .padding(5)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                Text(theme.title).font(.caption).foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("主题：\(theme.title)")
                        .accessibilityAddTraits(themeName == theme.rawValue ? .isSelected : [])
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
