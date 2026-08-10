import SwiftUI

struct ReaderThemePicker: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
            alignment: .leading,
            spacing: 12
        ) {
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
                                        selection == theme.rawValue ? Color.accentColor : theme.separator,
                                        lineWidth: selection == theme.rawValue ? 2 : 1
                                    )
                            }
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "checkmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.white, Color.accentColor)
                                    .padding(3)
                                    .opacity(selection == theme.rawValue ? 1 : 0)
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
