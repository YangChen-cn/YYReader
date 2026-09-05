import Foundation

struct AcademicPaperPlan: Equatable, Sendable {
    struct Paragraph: Equatable, Sendable {
        let index: Int
        let text: String
        let citations: [Int]
    }

    enum SupplementKind: String, Equatable, Sendable {
        case equation
        case table
        case figure
    }

    struct Supplement: Equatable, Sendable {
        let beforeParagraphIndex: Int
        let kind: SupplementKind
        let number: Int
    }

    let paperTitle: String
    let abstract: String
    let keywords: String
    let sectionTitle: String
    let paragraphs: [Paragraph]
    let supplements: [Supplement]
}

extension AcademicPaperPlan {
    enum Formatting {
        static func citationLabel(for citations: [Int]) -> String? {
            let unique = Array(Set(citations)).sorted()
            guard !unique.isEmpty else { return nil }
            return unique.map { "\($0)" }.joined(separator: ", ")
        }

        static func romanNumeral(for number: Int) -> String {
            let lookup: [(Int, String)] = [
                (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
            ]
            var result = ""
            var value = max(number, 1)
            for (threshold, numeral) in lookup {
                while value >= threshold {
                    result += numeral
                    value -= threshold
                }
            }
            return result.isEmpty ? "\(number)" : result
        }

        static func equationData(for number: Int) -> (formula: String, annotation: String) {
            switch number % 4 {
            case 1:
                return (
                    "Sₜ = α · Cₜ + β · Eₜ₋₁ + εₜ",
                    "where Cₜ denotes contextual observation, Eₜ₋₁ the preceding state, and εₜ ~ 𝒩(0, σ²) the residual stochastic term."
                )
            case 2:
                return (
                    "Attn(Q, K, V) = softmax((Q · Kᵀ) / √dₖ) · V",
                    "where Q, K, V ∈ ℝⁿˣᵈ denote query, key, and value representations, and dₖ represents the scaling dimension."
                )
            case 3:
                return (
                    "ℒ(θ) = - (1/N) ∑ᵢ₌₁ᴺ log P(yᵢ | xᵢ; θ) + (λ/2) ||θ||₂²",
                    "where ℒ(θ) specifies the cross-entropy objective and λ controls L₂ weight regularization."
                )
            default:
                return (
                    "P(Sₜ | Sₜ₋₁, Oₜ) ∝ πₜ · ∏ₖ₌₁ᴷ ϕₖ(Sₜ, Oₜ)",
                    "where ϕₖ(·) denotes the empirical state transition kernel and πₜ the prior state distribution."
                )
            }
        }
    }
}
