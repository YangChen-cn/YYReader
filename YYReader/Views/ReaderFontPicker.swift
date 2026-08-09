import SwiftUI

struct ReaderFontPicker: View {
    @Binding var selection: String

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ReaderFontFamily.allCases) { family in
                Button {
                    selection = family.rawValue
                } label: {
                    HStack(spacing: 12) {
                        Text(family.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .leading)

                        Text("小说正文")
                            .font(family.font(size: 17))

                        Spacer(minLength: 8)

                        if selection == family.rawValue {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(.rect)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(family.title)，小说正文预览")
                .accessibilityAddTraits(selection == family.rawValue ? .isSelected : [])
            }
        }
    }
}
