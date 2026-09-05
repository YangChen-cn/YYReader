import Charts
import SwiftUI

struct AcademicPaperFigureView: View {
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Chart {
                RuleMark(y: .value("Reference", 0.5))
                    .foregroundStyle(Color(white: 0.75))
                    .lineStyle(.init(lineWidth: 0.8, dash: [4, 4]))

                ForEach(0..<7, id: \.self) { index in
                    LineMark(
                        x: .value("Observation (t)", index + 1),
                        y: .value("Observed", observedValue(at: index))
                    )
                    .foregroundStyle(by: .value("Series", "Proposed Formulation"))
                    .symbol(by: .value("Series", "Proposed Formulation"))

                    LineMark(
                        x: .value("Observation (t)", index + 1),
                        y: .value("Baseline", baselineValue(at: index))
                    )
                    .foregroundStyle(by: .value("Series", "Reference Baseline"))
                    .symbol(by: .value("Series", "Reference Baseline"))
                    .lineStyle(.init(lineWidth: 1.2, dash: [3, 3]))
                }
            }
            .chartForegroundStyleScale([
                "Proposed Formulation": Color(red: 0.12, green: 0.40, blue: 0.75),
                "Reference Baseline": Color(white: 0.50)
            ])
            .chartXAxis {
                AxisMarks(position: .bottom, values: .stride(by: 1)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color(white: 0.85))
                    AxisTick()
                    AxisValueLabel()
                        .font(.system(size: 9, design: .monospaced))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color(white: 0.85))
                    AxisTick()
                    AxisValueLabel()
                        .font(.system(size: 9, design: .monospaced))
                }
            }
            .chartLegend(position: .bottom, alignment: .center, spacing: 16)
            .frame(height: 175)

            (Text("Fig. \(number). ")
                .font(.system(size: 9, weight: .bold, design: .serif))
            +
            Text("Standardized trajectory across sequential evaluation epochs. The blue solid curve depicts the observed representation metrics; the dashed rule tracks baseline convergence under fixed calibration.")
                .font(.system(size: 9, design: .serif))
                .foregroundStyle(Color(white: 0.38)))
            .lineSpacing(3)
        }
    }

    private func observedValue(at index: Int) -> Double {
        let values = [0.36, 0.49, 0.57, 0.53, 0.68, 0.72, 0.79]
        let adjustment = Double(number % 4) * 0.012
        return min(values[index] + adjustment, 0.92)
    }

    private func baselineValue(at index: Int) -> Double {
        let values = [0.31, 0.39, 0.45, 0.52, 0.56, 0.63, 0.67]
        let adjustment = Double(number % 3) * 0.008
        return min(values[index] + adjustment, 0.88)
    }
}
