import SwiftUI

struct AcademicPaperTableView: View {
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Table \(number)")
                .font(.caption.bold())
            Text("Comparative estimates for the principal textual indicators")
                .font(.caption)

            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 7) {
                Divider()
                    .gridCellColumns(4)

                GridRow {
                    Text("Indicator")
                    Text("Estimate")
                    Text("95% CI")
                    Text("p")
                }
                .bold()

                Divider()
                    .gridCellColumns(4)

                tableRow("Context continuity", estimate: "0.842", interval: "0.781–0.903", probability: "< .001")
                tableRow("Sequential coherence", estimate: "0.716", interval: "0.648–0.784", probability: ".004")
                tableRow("Lexical stability", estimate: "0.593", interval: "0.521–0.665", probability: ".018")
                tableRow("Transition density", estimate: "0.438", interval: "0.361–0.515", probability: ".032")

                Divider()
                    .gridCellColumns(4)
            }
            .font(.caption.monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Note. Estimates are standardized; CI = confidence interval. Values are illustrative and generated deterministically.")
                .font(.caption)
                .italic()
                .foregroundStyle(.secondary)
        }
    }

    private func tableRow(
        _ indicator: String,
        estimate: String,
        interval: String,
        probability: String
    ) -> some View {
        GridRow {
            Text(indicator)
            Text(estimate)
            Text(interval)
            Text(probability)
        }
    }
}
