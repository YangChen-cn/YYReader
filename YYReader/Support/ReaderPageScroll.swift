enum ReaderPageScroll {
    static let pageFraction = 0.88
    static let pageOverlap = 1 - pageFraction
    static let smallStep = 112.0
    static let animationDuration = 0.15

    static func pageDistance(viewportHeight: Double) -> Double {
        max(viewportHeight, 0) * pageFraction
    }

    static func pageDestinationY(
        currentY: Double,
        viewportHeight: Double,
        contentHeight: Double,
        direction: Double
    ) -> Double {
        destinationY(
            currentY: currentY,
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            distance: pageDistance(viewportHeight: viewportHeight) * direction
        )
    }

    static func destinationY(
        currentY: Double,
        viewportHeight: Double,
        contentHeight: Double,
        distance: Double
    ) -> Double {
        let maximumY = max(contentHeight - viewportHeight, 0)
        return min(max(currentY + distance, 0), maximumY)
    }

    static func shouldAnimate(reduceMotion: Bool, isKeyRepeat: Bool = false) -> Bool {
        !reduceMotion && !isKeyRepeat
    }
}
