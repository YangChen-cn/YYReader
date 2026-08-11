import SwiftUI

struct AppearanceInspectorView: View {
    @AppStorage(ReaderPreferenceKeys.fontFamily) private var fontFamily = ReaderFontFamily.serif.rawValue
    @AppStorage(ReaderPreferenceKeys.fontSize) private var fontSize = 20.0
    @AppStorage(ReaderPreferenceKeys.lineSpacing) private var lineSpacing = ReaderLineSpacingPreset.comfortable.value
    @AppStorage(ReaderPreferenceKeys.paragraphSpacing) private var paragraphSpacing = 0.60
    @AppStorage(ReaderPreferenceKeys.contentWidth) private var contentWidth = ReaderViewportLayout.defaultPreferredWidthEM
    @AppStorage(ReaderPreferenceKeys.theme) private var theme = ReaderTheme.system.rawValue
    @AppStorage(ReaderPreferenceKeys.paragraphIndent) private var paragraphIndent = true
    var dismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if let dismiss {
                HStack {
                    Spacer()
                    Button("完成", action: dismiss)
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

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
                        Text(lineSpacing, format: .number.precision(.fractionLength(2)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $lineSpacing, in: 0.20...0.65, step: 0.05)

                    LabeledContent("段距") {
                        Text(paragraphSpacing, format: .number.precision(.fractionLength(2)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $paragraphSpacing, in: 0.35...0.90, step: 0.05)

                    LabeledContent("正文宽度") {
                        Text("\(Int(contentWidth)) em")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: $contentWidth,
                        in: ReaderViewportLayout.minimumPreferredWidthEM...ReaderViewportLayout.maximumPreferredWidthEM,
                        step: 1
                    )

                    Toggle("段首缩进 2 字符", isOn: $paragraphIndent)
                }
            }
            .formStyle(.grouped)
        }
    }
}
