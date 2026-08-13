import AppKit

enum ReaderKeyboardCommand: Equatable {
    case moveUp
    case moveDown
    case pageBackward
    case pageForward

    static func resolve(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Self? {
        let unsupportedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard modifierFlags.intersection(unsupportedModifiers).isEmpty else { return nil }

        switch keyCode {
        case 126: return .moveUp
        case 125: return .moveDown
        case 123: return .pageBackward
        case 124: return .pageForward
        default: return nil
        }
    }
}

enum ReaderKeyboardRouting {
    @MainActor
    static func shouldDeferToFocusedControl(
        _ responder: NSResponder?,
        in window: NSWindow? = nil
    ) -> Bool {
        if let window,
           let view = responder as? NSView,
           (view.window !== window || view.isHiddenOrHasHiddenAncestor) {
            return false
        }
        if isDirectionalControl(responder, in: window) { return true }
        guard let view = responder as? NSView else { return false }

        var ancestor: NSView? = view.superview
        while let current = ancestor {
            if let window,
               (current.window !== window || current.isHiddenOrHasHiddenAncestor) {
                return false
            }
            if isDirectionalControl(current, in: window) { return true }
            ancestor = current.superview
        }
        return false
    }

    private static func isDirectionalControl(
        _ responder: NSResponder?,
        in window: NSWindow?
    ) -> Bool {
        if let textView = responder as? NSTextView {
            if textView.isFieldEditor,
               let owner = textView.delegate as? NSView,
               let window,
               (owner.window !== window || owner.isHiddenOrHasHiddenAncestor) {
                return false
            }
            return textView.isEditable || textView.isFieldEditor
        }
        return responder is NSTextField
            || responder is NSComboBox
            || responder is NSTableView
            || responder is NSOutlineView
            || responder is NSCollectionView
            || responder is NSSlider
            || responder is NSSegmentedControl
    }
}
