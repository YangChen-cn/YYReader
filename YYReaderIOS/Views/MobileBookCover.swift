import SwiftUI

struct MobileBookCover: View {
    let title: String

    private var color: Color {
        let colors: [Color] = [
            Color(red: 0.34, green: 0.39, blue: 0.58),
            Color(red: 0.20, green: 0.49, blue: 0.48),
            Color(red: 0.58, green: 0.40, blue: 0.32),
            Color(red: 0.25, green: 0.42, blue: 0.62),
            Color(red: 0.50, green: 0.38, blue: 0.57)
        ]
        let index = title.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % colors.count }
        return colors[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(title.prefix(4)))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 2)
            Image(systemName: "book.closed")
                .font(.caption.weight(.medium))
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 11)
        .frame(width: 72, height: 100, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [color.opacity(0.85), color],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(.black.opacity(0.12))
                .frame(width: 3)
                .padding(.leading, 5)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15)))
        // The cover text is decorative; the full title alongside it scales freely.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityHidden(true)
    }
}
