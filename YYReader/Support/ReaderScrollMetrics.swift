import SwiftUI

struct ReaderScrollMetrics: Equatable {
    static let zero = ReaderScrollMetrics(contentOffsetY: 0, viewportHeight: 0, contentHeight: 0)

    let contentOffsetY: Double
    let viewportHeight: Double
    let contentHeight: Double

    init(contentOffsetY: Double, viewportHeight: Double, contentHeight: Double) {
        self.contentOffsetY = contentOffsetY
        self.viewportHeight = viewportHeight
        self.contentHeight = contentHeight
    }

    init(geometry: ScrollGeometry) {
        self.init(
            contentOffsetY: geometry.contentOffset.y,
            viewportHeight: geometry.containerSize.height,
            contentHeight: geometry.contentSize.height
        )
    }
}
