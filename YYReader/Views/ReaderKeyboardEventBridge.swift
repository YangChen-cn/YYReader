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
        nsView.stopMonitoring()
    }
}

@MainActor
final class ReaderKeyboardEventView: NSView {
    var handle: (@MainActor (ReaderKeyboardCommand) -> Void)?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    func stopMonitoring() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @MainActor [weak self] event in
            self?.process(event) ?? event
        }
    }

    private func process(_ event: NSEvent) -> NSEvent? {
        guard let window,
              window.isKeyWindow,
              eventBelongsToReaderWindow(event, window: window),
              let command = ReaderKeyboardCommand.resolve(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags
              ),
              !ReaderKeyboardRouting.shouldDeferToFocusedControl(
                window.firstResponder,
                in: window
              ) else {
            return event
        }

        handle?(command)
        // Returning nil is essential: forwarding an already-handled arrow key to
        // the responder chain makes AppKit emit the system "unhandled key" beep.
        return nil
    }

    private func eventBelongsToReaderWindow(_ event: NSEvent, window: NSWindow) -> Bool {
        if event.window === window { return true }
        return event.windowNumber == window.windowNumber
    }
}
