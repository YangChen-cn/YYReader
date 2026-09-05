import SwiftUI

struct AcademicPaperTableView: View {
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 3) {
                Text("TABLE \(AcademicPaperPlan.Formatting.romanNumeral(for: number))")
                    .font(.system(size: 9.5, weight: .bold, design: .serif))
                    .tracking(1.2)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("COMPARATIVE ESTIMATES FOR EMPIRICAL TEXTUAL INDICATORS")
                    .font(.system(size: 8.5, weight: .medium, design: .serif))
                    .tracking(0.5)
                    .foregroundStyle(Color(white: 0.35))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.bottom, 2)

            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 6) {
                Rectangle()
                    .fill(Color(white: 0.15))
                    .frame(height: 1.4)
                    .gridCellColumns(4)

                GridRow {
                    Text("Indicator")
                    Text("Estimate")
                    Text("95% CI")
                    Text("p-value")
                }
                .font(.system(size: 10.5, weight: .bold, design: .serif))

                Rectangle()
                    .fill(Color(white: 0.40))
                    .frame(height: 0.7)
                    .gridCellColumns(4)

                tableRow("Context continuity", estimate: "0.842***", interval: "0.781–0.903", probability: "< .001")
                tableRow("Sequential coherence", estimate: "0.716**", interval: "0.648–0.784", probability: ".004")
                tableRow("Lexical stability", estimate: "0.593*", interval: "0.521–0.665", probability: ".018")
                tableRow("Transition density", estimate: "0.438*", interval: "0.361–0.515", probability: ".032")

                Rectangle()
                    .fill(Color(white: 0.15))
                    .frame(height: 1.4)
                    .gridCellColumns(4)
            }
            .font(.system(size: 10, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Note. *** p < 0.001, ** p < 0.01, * p < 0.05. Estimates are standardized coefficients; CI = confidence interval. Deterministically generated.")
                .font(.system(size: 9, design: .serif))
                .italic()
                .foregroundStyle(Color(white: 0.42))
        }
        .padding(.vertical, 6)
    }

    private func tableRow(
        _ indicator: String,
        estimate: String,
        interval: String,
        probability: String
    ) -> some View {
        GridRow {
            Text(indicator)
                .font(.system(size: 10, design: .serif))
            Text(estimate)
            Text(interval)
            Text(probability)
        }
    }
}
