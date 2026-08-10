import Foundation

enum ReaderViewportLayout {
    static let minimumPreferredWidth = 600.0
    static let defaultPreferredWidth = 1_040.0
    static let maximumPreferredWidth = 1_800.0

    static func effectiveContentWidth(preferredWidth: Double, viewportWidth: Double) -> Double {
        let preferredWidth = min(
            max(preferredWidth, minimumPreferredWidth),
            maximumPreferredWidth
        )
        let horizontalMargin = viewportWidth >= 900 ? 52.0 : 40.0
        let availableWidth = max(viewportWidth - (horizontalMargin * 2), 1)
        return min(preferredWidth, availableWidth)
    }
}
