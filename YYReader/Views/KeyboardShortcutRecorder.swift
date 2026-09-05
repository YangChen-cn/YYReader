import AppKit
import SwiftUI

struct KeyboardShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: String

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: $shortcut)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: displayName, target: context.coordinator, action: #selector(Coordinator.beginRecording))
        button.bezelStyle = .rounded
        button.setAccessibilityLabel("录制摸鱼模式快捷键")
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.shortcut = $shortcut
        guard !context.coordinator.isRecording else { return }
        button.title = displayName
    }

    static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) {
        coordinator.stopRecording()
    }

    private var displayName: String {
        (ReaderKeyboardShortcut(storageValue: shortcut) ?? .defaultValue).displayName
    }

    @MainActor
    final class Coordinator: NSObject {
        var shortcut: Binding<String>
        weak var button: NSButton?
        private(set) var isRecording = false
        private var eventMonitor: Any?

        init(shortcut: Binding<String>) {
            self.shortcut = shortcut
        }

        @objc func beginRecording() {
            guard !isRecording else { return }
            isRecording = true
            button?.title = "请按快捷键…"
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.record(event)
                }
                return nil
            }
        }

        func stopRecording() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            isRecording = false
            button?.title = (ReaderKeyboardShortcut(storageValue: shortcut.wrappedValue) ?? .defaultValue).displayName
        }

        private func record(_ event: NSEvent) {
            if event.keyCode == 53 {
                stopRecording()
                return
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let primaryModifierCount = [flags.contains(.control), flags.contains(.option), flags.contains(.command)]
                .filter { $0 }
                .count
            guard primaryModifierCount >= 2,
                  let characters = event.charactersIgnoringModifiers,
                  let value = ReaderKeyboardShortcut(
                      key: characters,
                      usesControl: flags.contains(.control),
                      usesOption: flags.contains(.option),
                      usesShift: flags.contains(.shift),
                      usesCommand: flags.contains(.command)
                  ) else {
                button?.title = "需要两个修饰键"
                return
            }

            shortcut.wrappedValue = value.storageValue
            stopRecording()
        }
    }
}
