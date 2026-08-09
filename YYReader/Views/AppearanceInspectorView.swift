import SwiftUI

struct AppearanceInspectorView: View {
    @AppStorage(ReaderPreferenceKeys.fontFamily) private var fontFamily = ReaderFontFamily.serif.rawValue
    @AppStorage(ReaderPreferenceKeys.fontSize) private var fontSize = 20.0
    @AppStorage(ReaderPreferenceKeys.lineSpacing) private var lineSpacing = 9.0
    @AppStorage(ReaderPreferenceKeys.paragraphSpacing) private var paragraphSpacing = 18.0
    @AppStorage(ReaderPreferenceKeys.contentWidth) private var contentWidth = 720.0
    @AppStorage(ReaderPreferenceKeys.horizontalPadding) private var horizontalPadding = 36.0
    @AppStorage(ReaderPreferenceKeys.theme) private var theme = ReaderTheme.system.rawValue

    var body: some View {
        Form {
            Picker("字体", selection: $fontFamily) {
                ForEach(ReaderFontFamily.allCases) { family in
                    Text(family.title).tag(family.rawValue)
                }
            }

            Picker("主题", selection: $theme) {
                ForEach(ReaderTheme.allCases) { theme in
                    Text(theme.title).tag(theme.rawValue)
                }
            }

            LabeledContent("字号") {
                Slider(value: $fontSize, in: 14...36, step: 1)
            }
            LabeledContent("行距") {
                Slider(value: $lineSpacing, in: 2...20, step: 1)
            }
            LabeledContent("段距") {
                Slider(value: $paragraphSpacing, in: 8...36, step: 1)
            }
            LabeledContent("正文宽度") {
                Slider(value: $contentWidth, in: 520...1_000, step: 20)
            }
            LabeledContent("页边距") {
                Slider(value: $horizontalPadding, in: 16...80, step: 4)
            }
        }
        .formStyle(.grouped)
        .padding(.top)
    }
}
