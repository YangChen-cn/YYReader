import Foundation

/// Presentation only: original paragraph indices remain the scroll/sync anchors.
struct TavernReadingPlan: Sendable {
    struct Segment: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case narration
            case dialogue(speaker: String)
            case auxiliary(title: String)
        }
        let kind: Kind
        let text: String
    }
    struct Block: Identifiable, Sendable, Equatable {
        let id: Int
        var segments: [Segment]
    }
    let blocks: [Block]

    var firstSpeaker: String? {
        for block in blocks {
            for segment in block.segments {
                if case let .dialogue(speaker) = segment.kind { return speaker }
            }
        }
        return nil
    }

    func anchor(for sourceIndex: Int) -> Int? {
        // Hidden metadata and multiline auxiliary cards map to a visible block.
        blocks.last(where: { $0.id <= sourceIndex })?.id ?? blocks.first?.id
    }
}
