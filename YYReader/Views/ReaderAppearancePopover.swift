import SwiftUI

struct ReaderAppearancePopover: View {
    @AppStorage(ReaderPreferenceKeys.fontFamily) private var fontFamily = ReaderFontFamily.serif.rawValue
    @AppStorage(ReaderPreferenceKeys.fontSize) private var fontSize = 20.0
    @AppStorage(ReaderPreferenceKeys.lineSpacing) private var lineSpacing = 8.0
    @AppStorage(ReaderPreferenceKeys.contentWidth) private var contentWidth = ReaderViewportLayout.defaultPreferredWidth
    @AppStorage(ReaderPreferenceKeys.theme) private var theme = ReaderTheme.system.rawValue
    @AppStorage(ReaderPreferenceKeys.paragraphIndent) private var paragraphIndent = true
    @AppStorage(ReaderPreferenceKeys.continuousReading) private var continuousReading = false

    let showAdvancedSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    fontSize = max(14, fontSize - 1)
                } label: {
                    Image(systemName: "textformat.size.smaller")
                        .frame(width: 34, height: 26)
                }
                .disabled(fontSize <= 14)
                .accessibilityLabel("减小字号")

                Spacer()
                Text("\(Int(fontSize)) 点")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()

                Button {
                    fontSize = min(36, fontSize + 1)
                } label: {
                    Image(systemName: "textformat.size.larger")
                        .frame(width: 34, height: 26)
                }
                .disabled(fontSize >= 36)
                .accessibilityLabel("增大字号")
            }
            .buttonStyle(.borderless)

            preferenceSection("主题", systemImage: "paintpalette") {
                ReaderThemePicker(selection: $theme)
            }

            preferenceSection("字体", systemImage: "textformat") {
                ReaderFontPicker(selection: $fontFamily)
            }

            preferenceSection("行距", systemImage: "arrow.up.and.down") {
                Picker("行距", selection: lineSpacingPreset) {
                    ForEach(ReaderLineSpacingPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            preferenceSection("正文宽度", systemImage: "rectangle.compress.vertical") {
                Picker("正文宽度", selection: contentWidthPreset) {
                    ForEach(ReaderContentWidthPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Toggle("段首缩进 2 字符", isOn: $paragraphIndent)
            Toggle("连续阅读", isOn: $continuousReading)

            Divider()

            Button("更多阅读设置…", action: showAdvancedSettings)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(width: 320)
    }

    private var lineSpacingPreset: Binding<ReaderLineSpacingPreset> {
        Binding(
            get: { ReaderLineSpacingPreset.closest(to: lineSpacing) },
            set: { lineSpacing = $0.value }
        )
    }

    private var contentWidthPreset: Binding<ReaderContentWidthPreset> {
        Binding(
            get: { ReaderContentWidthPreset.closest(to: contentWidth) },
            set: { contentWidth = $0.value }
        )
    }

    private func preferenceSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
