import SwiftUI

struct MobileBookCover: View {
    let title: String

    private var color: Color {
        let colors: [Color] = [.indigo, .teal, .brown, .blue, .purple]
        let index = title.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % colors.count }
        return colors[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(title.prefix(2)))
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            Image(systemName: "book.closed")
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(width: 68, height: 94, alignment: .leading)
        .background(color.gradient, in: .rect(cornerRadius: 7))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(.black.opacity(0.12)).frame(width: 4).padding(.leading, 5)
        }
        .accessibilityHidden(true)
    }
}
