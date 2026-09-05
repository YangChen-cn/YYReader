import SwiftUI

struct AcademicPaperSupplementView: View {
    let supplement: AcademicPaperPlan.Supplement

    var body: some View {
        Group {
            switch supplement.kind {
            case .equation:
                AcademicPaperEquationView(number: supplement.number)
            case .table:
                AcademicPaperTableView(number: supplement.number)
            case .figure:
                AcademicPaperFigureView(number: supplement.number)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(white: 0.80))
                .frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(white: 0.80))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}
