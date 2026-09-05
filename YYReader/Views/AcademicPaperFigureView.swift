import Charts
import SwiftUI

struct AcademicPaperFigureView: View {
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Chart {
                RuleMark(y: .value("Reference", 0.5))
                    .foregroundStyle(.gray.opacity(0.35))
                    .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                ForEach(0..<7, id: \.self) { index in
                    LineMark(
                        x: .value("Observation", index + 1),
                        y: .value("Observed", observedValue(at: index))
                    )
                    .foregroundStyle(by: .value("Series", "Observed"))
                    .symbol(by: .value("Series", "Observed"))

                    LineMark(
                        x: .value("Observation", index + 1),
                        y: .value("Baseline", baselineValue(at: index))
                    )
                    .foregroundStyle(by: .value("Series", "Reference model"))
                    .symbol(by: .value("Series", "Reference model"))
                }
            }
            .chartForegroundStyleScale([
                "Observed": Color(white: 0.18),
                "Reference model": Color(white: 0.58)
            ])
            .chartXAxis {
                AxisMarks(position: .bottom, values: .stride(by: 1))
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 18)
            .frame(height: 180)

            Text("Figure \(number). Standardized variation across sequential observations.")
                .font(.caption.bold())
            Text("Whisker-free estimates are shown for visual comparison; the dashed rule indicates the reference threshold.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
