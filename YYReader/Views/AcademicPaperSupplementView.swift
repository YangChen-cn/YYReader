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
        .padding(.vertical, 18)
        .overlay(alignment: .top) {
            Divider()
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
    }
}
