import SwiftUI

/// Clicks live on the page canvas; controls and scrolling never share these hit regions.
struct MangaPageTurnGesture: ViewModifier {
    let width: Double
    let backward: () -> Void
    let forward: () -> Void
    let controls: () -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        content.gesture(SpatialTapGesture().exclusively(before: DragGesture(minimumDistance: 30)).onEnded { value in
            switch value {
            case let .first(tap): handleTap(tap.location.x)
            case let .second(drag):
                guard abs(drag.translation.width) > abs(drag.translation.height) * 1.3 else { return }
                if drag.translation.width < 0 { forward() } else { backward() }
            }
        })
        #else
        // Mouse drags and trackpad scrolling must not turn a page.
        content.gesture(SpatialTapGesture().onEnded { handleTap($0.location.x) })
        #endif
    }

    private func handleTap(_ x: Double) {
        switch MangaPageLayout.tap(at: x, width: width) {
        case .backward: backward()
        case .forward: forward()
        case .controls: controls()
        }
    }
}
