import SwiftUI

struct AcademicPaperEquationView: View {
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Spacer()
                Text("Sₜ = α · Cₜ + β · Eₜ₋₁ + εₜ")
                    .font(.system(size: 19, design: .serif))
                    .italic()
                Spacer()
                Text("(\(number))")
                    .font(.caption.monospacedDigit())
            }

            Text("where Cₜ denotes the contextual observation, Eₜ₋₁ the preceding state, and εₜ the residual term.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
