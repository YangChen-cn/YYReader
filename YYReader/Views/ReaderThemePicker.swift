import SwiftUI

struct ReaderThemePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(ReaderTheme.allCases) { theme in
                Button {
                    selection = theme.rawValue
                } label: {
                    VStack(spacing: 6) {
                        Text("Aa")
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .foregroundStyle(theme.foreground)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(theme.background, in: .rect(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        selection == theme.rawValue ? Color.accentColor : Color.secondary.opacity(0.24),
                                        lineWidth: selection == theme.rawValue ? 2 : 1
                                    )
                            }

                        Text(theme.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(theme.title)主题")
                .accessibilityAddTraits(selection == theme.rawValue ? .isSelected : [])
            }
        }
    }
}
