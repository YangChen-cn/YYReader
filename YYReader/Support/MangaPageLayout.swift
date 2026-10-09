import Foundation

/// Ephemeral display groups. Stored reading positions always remain original image indices.
struct MangaPageLayout: Equatable, Sendable {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case automatic, single, double
        var id: Self { self }
        var title: String { switch self { case .automatic: "自动"; case .single: "单页"; case .double: "双页" } }
    }

    let groups: [Range<Int>]

    init(aspectRatios: [Double?], mode: Mode, firstPageAlone: Bool, viewport: CGSize) {
        let double = mode == .double || (mode == .automatic && viewport.width >= 780 && viewport.width >= viewport.height * 1.15)
        var result: [Range<Int>] = []
        var index = 0
        while index < aspectRatios.count {
            let canPair = double && !(firstPageAlone && index == 0)
                && (aspectRatios[index] ?? 0.7) < 1
                && index + 1 < aspectRatios.count && (aspectRatios[index + 1] ?? 0.7) < 1
            let end = index + (canPair ? 2 : 1)
            result.append(index..<end)
            index = end
        }
        groups = result
    }

    func group(containing index: Int) -> Range<Int> {
        groups.first { $0.contains(index) } ?? 0..<0
    }

    func adjacentIndex(from index: Int, direction: Int) -> Int? {
        guard let position = groups.firstIndex(where: { $0.contains(index) }),
              groups.indices.contains(position + direction) else { return nil }
        return groups[position + direction].lowerBound
    }

    static func fittedHeight(ratios: [Double], viewport: CGSize, gap: Double = 4) -> Double {
        let sum = ratios.reduce(0) { $0 + max($1, 0.01) }
        guard sum > 0 else { return 0 }
        return max(1, min(viewport.height, (viewport.width - gap * Double(max(0, ratios.count - 1))) / sum))
    }

    static func scrollWidth(viewportWidth: Double, desktop: Bool) -> Double {
        let available = max(1, viewportWidth - (desktop ? 24 : 0))
        return desktop ? min(available, max(560, min(1200, available * 0.86))) : available
    }

    static func gap(after index: Int, ratios: [Double?]) -> Double {
        let longStrip = ratios.compactMap { $0 }.prefix(3).filter { $0 < 0.45 }.count >= 2
        return longStrip || (ratios.indices.contains(index) && (ratios[index] ?? 0.7) < 0.45) ? 0 : 4
    }

    enum Tap: Equatable { case backward, controls, forward }
    static func tap(at x: Double, width: Double) -> Tap {
        if x < width * 0.3 { return .backward }
        if x > width * 0.7 { return .forward }
        return .controls
    }

    static func swipeDirection(translation: CGSize, predictedWidth: Double, viewportWidth: Double) -> Int? {
        guard abs(translation.width) >= 12,
              abs(translation.width) > abs(translation.height) * 1.3 else { return nil }
        let distance = abs(predictedWidth) > abs(translation.width) ? predictedWidth : translation.width
        guard abs(distance) >= max(44, viewportWidth * 0.2) else { return nil }
        return distance < 0 ? 1 : -1
    }
}
