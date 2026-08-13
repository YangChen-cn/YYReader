import AppKit
import SwiftUI

struct ReaderKeyboardEventBridge: NSViewRepresentable {
    let handle: @MainActor (ReaderKeyboardCommand) -> Void

    func makeNSView(context: Context) -> ReaderKeyboardEventView {
        let view = ReaderKeyboardEventView()
        view.handle = handle
        return view
    }

    func updateNSView(_ nsView: ReaderKeyboardEventView, context: Context) {
        nsView.handle = handle
    }

    static func dismantleNSView(_ nsView: ReaderKeyboardEventView, coordinator: ()) {
        nsView.stopObservingWindow()
    }
}

@MainActor
final class ReaderKeyboardEventView: NSView {
    var handle: (@MainActor (ReaderKeyboardCommand) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObservingWindow()
        guard let window else { return }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowMayNeedReaderResponder(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowMayNeedReaderResponder(_:)),
            name: NSWindow.didUpdateNotification,
            object: window
        )
        claimFirstResponderIfAppropriate()
    }

    override func keyDown(with event: NSEvent) {
        guard let command = ReaderKeyboardCommand.resolve(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        ) else {
            nextResponder?.keyDown(with: event)
            return
        }

        handle?(command)
    }

    func stopObservingWindow() {
        NotificationCenter.default.removeObserver(self)
        if let window, window.firstResponder === self {
            window.makeFirstResponder(nil)
        }
    }

    @objc
    private func windowMayNeedReaderResponder(_ notification: Notification) {
        claimFirstResponderIfAppropriate()
    }

    private func claimFirstResponderIfAppropriate() {
        guard let window,
              window.isKeyWindow,
              window.firstResponder !== self,
              !ReaderKeyboardRouting.shouldDeferToFocusedControl(
                window.firstResponder,
                in: window
              ) else {
            return
        }
        window.makeFirstResponder(self)
    }
}
