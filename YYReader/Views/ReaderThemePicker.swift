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
                swatch(for: theme)
            }
        }
    }

    private func swatch(for theme: ReaderTheme) -> some View {
        let isSelected = selection == theme.rawValue

        return Button {
            selection = theme.rawValue
        } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.background)
                    .frame(height: 56)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule()
                                .fill(theme.accent)
                                .frame(width: 20, height: 3)
                            Capsule()
                                .fill(theme.foreground.opacity(0.55))
                                .frame(height: 2)
                            Capsule()
                                .fill(theme.tertiaryForeground.opacity(0.7))
                                .frame(height: 2)
                            Capsule()
                                .fill(theme.tertiaryForeground.opacity(0.45))
                                .frame(height: 2)
                        }
                        .padding(6)
                        .accessibilityHidden(true)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isSelected ? Color.accentColor : theme.separator,
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.accentColor)
                            .padding(3)
                            .opacity(isSelected ? 1 : 0)
                    }

                Text(theme.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.title)主题")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
