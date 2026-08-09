import SwiftUI

struct AppearanceInspectorView: View {
    @AppStorage(ReaderPreferenceKeys.fontFamily) private var fontFamily = ReaderFontFamily.serif.rawValue
    @AppStorage(ReaderPreferenceKeys.fontSize) private var fontSize = 20.0
    @AppStorage(ReaderPreferenceKeys.lineSpacing) private var lineSpacing = 8.0
    @AppStorage(ReaderPreferenceKeys.paragraphSpacing) private var paragraphSpacing = 12.0
    @AppStorage(ReaderPreferenceKeys.contentWidth) private var contentWidth = ReaderViewportLayout.defaultPreferredWidth
    @AppStorage(ReaderPreferenceKeys.theme) private var theme = ReaderTheme.system.rawValue
    @AppStorage(ReaderPreferenceKeys.paragraphIndent) private var paragraphIndent = true

    var body: some View {
        Form {
            Section("高级阅读设置") {
                Text("日常调整请使用工具栏中的 Aa。这里保留精确排版控制。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("主题") {
                ReaderThemePicker(selection: $theme)
            }

            Section("字体") {
                ReaderFontPicker(selection: $fontFamily)
            }

            Section("排版") {
                LabeledContent("字号") {
                    Text("\(Int(fontSize)) 点")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $fontSize, in: 14...36, step: 1)

                LabeledContent("行距") {
                    Text("\(Int(lineSpacing)) 点")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $lineSpacing, in: 2...20, step: 1)

                LabeledContent("段距") {
                    Text("\(Int(paragraphSpacing)) 点")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $paragraphSpacing, in: 8...36, step: 1)

                LabeledContent("正文宽度") {
                    Text("\(Int(contentWidth)) 点")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $contentWidth,
                    in: ReaderViewportLayout.minimumPreferredWidth...ReaderViewportLayout.maximumPreferredWidth,
                    step: 20
                )

                Toggle("段首缩进 2 字符", isOn: $paragraphIndent)
            }
        }
        .formStyle(.grouped)
    }
}
