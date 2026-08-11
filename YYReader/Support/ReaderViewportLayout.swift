import Foundation

enum ReaderViewportLayout {
    static let minimumPreferredWidthEM = 20.0
    static let defaultPreferredWidthEM = ReaderContentWidthPreset.medium.value
    static let maximumPreferredWidthEM = 80.0

    static func effectiveContentWidth(
        preferredWidthEM: Double,
        fontSize: Double,
        viewportWidth: Double
    ) -> Double {
        let preferredWidthEM = min(
            max(preferredWidthEM, minimumPreferredWidthEM),
            maximumPreferredWidthEM
        )
        let preferredWidth = preferredWidthEM * fontSize
        let horizontalMargin = viewportWidth >= 900 ? 52.0 : 40.0
        let availableWidth = max(viewportWidth - (horizontalMargin * 2), 1)
        return min(preferredWidth, availableWidth)
    }
}
