import AppKit
import SwiftUI

/// SwiftUI has no imperative API for narrowing the current window on a mode change.
struct MangaWindowWidthBridge: NSViewRepresentable {
    let enabled: Bool

    func makeNSView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.enabled = enabled
        return view
    }

    func updateNSView(_ view: WindowProbe, context: Context) { view.enabled = enabled }

    static func dismantleNSView(_ view: WindowProbe, coordinator: ()) { view.resizeTask?.cancel() }

    static func narrowedFrame(current: CGRect, visible: CGRect) -> CGRect? {
        let width = min(visible.width, max(600, visible.width / 2))
        guard current.width > width + 24 else { return nil }
        var result = current
        result.size.width = width
        result.origin.x = min(max(current.midX - width / 2, visible.minX), visible.maxX - width)
        return result
    }

    @MainActor final class WindowProbe: NSView {
        var resizeTask: Task<Void, Never>?
        var enabled = false {
            didSet { if enabled && !oldValue { scheduleResize() } }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if enabled { scheduleResize() }
        }

        private func scheduleResize() {
            resizeTask?.cancel()
            resizeTask = Task { @MainActor [weak self] in
                // Allow SwiftUI's new minimum width to reach the hosting window first.
                await Task.yield()
                guard !Task.isCancelled, let self, self.enabled, let window = self.window,
                      !window.styleMask.contains(.fullScreen), !window.inLiveResize,
                      let screen = window.screen,
                      let frame = MangaWindowWidthBridge.narrowedFrame(current: window.frame, visible: screen.visibleFrame) else { return }
                window.setFrame(frame, display: true)
            }
        }
    }
}
