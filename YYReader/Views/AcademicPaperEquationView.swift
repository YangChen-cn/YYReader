import SwiftUI

struct AcademicPaperEquationView: View {
    let number: Int

    var body: some View {
        let (formula, annotation) = AcademicPaperPlan.Formatting.equationData(for: number)
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Spacer()
                Text(formula)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .italic()
                Spacer()
                Text("(\(number))")
                    .font(.system(size: 12.5, design: .serif))
                    .foregroundStyle(Color(white: 0.35))
            }
            .padding(.vertical, 4)

            Text(annotation)
                .font(.system(size: 9.5, design: .serif))
                .foregroundStyle(Color(white: 0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Color(white: 0.985))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
