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

    static func dismantleNSView(_ view: WindowProbe, coordinator: ()) {
        view.resizeTask?.cancel()
        NotificationCenter.default.removeObserver(view)
    }

    static func narrowedFrame(current: CGRect, visible: CGRect) -> CGRect? {
        let width = min(visible.width, max(600, visible.width / 2))
        guard current.width > width + 24 else { return nil }
        var result = current
        result.size.width = width
        result.origin.x = min(max(current.midX - width / 2, visible.minX), visible.maxX - width)
        return result
    }

    static func restoredFrame(current: CGRect, originalWidth: CGFloat, visible: CGRect) -> CGRect {
        var result = current
        result.size.width = min(originalWidth, visible.width)
        result.origin.x = min(max(current.midX - result.width / 2, visible.minX), visible.maxX - result.width)
        return result
    }

    @MainActor final class WindowProbe: NSView {
        var resizeTask: Task<Void, Never>?
        private weak var managedWindow: NSWindow?
        private var originalWidth: CGFloat?
        var enabled = false {
            didSet { if enabled != oldValue { scheduleResize() } }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if window !== managedWindow {
                managedWindow = window
                originalWidth = nil
            }
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(windowLeftFullScreen),
                    name: NSWindow.didExitFullScreenNotification, object: window)
            }
            if enabled || originalWidth != nil { scheduleResize() }
        }

        @objc private func windowLeftFullScreen(_ notification: Notification) {
            if originalWidth != nil || enabled { scheduleResize() }
        }

        private func scheduleResize() {
            resizeTask?.cancel()
            resizeTask = Task { @MainActor [weak self] in
                // Allow SwiftUI's new minimum width to reach the hosting window first.
                await Task.yield()
                guard !Task.isCancelled, let self, let window = self.window,
                      !window.styleMask.contains(.fullScreen), !window.inLiveResize,
                      let screen = window.screen else { return }
                if self.enabled {
                    guard let frame = MangaWindowWidthBridge.narrowedFrame(current: window.frame, visible: screen.visibleFrame) else { return }
                    if self.originalWidth == nil { self.originalWidth = window.frame.width }
                    window.setFrame(frame, display: true)
                } else if let width = self.originalWidth {
                    window.setFrame(MangaWindowWidthBridge.restoredFrame(current: window.frame,
                        originalWidth: width, visible: screen.visibleFrame), display: true)
                    self.originalWidth = nil
                }
            }
        }
    }
}
