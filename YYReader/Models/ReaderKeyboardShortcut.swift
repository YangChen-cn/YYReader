import Foundation
import SwiftUI

struct ReaderKeyboardShortcut: Equatable, Sendable {
    static let defaultValue = ReaderKeyboardShortcut(
        key: "p",
        usesControl: true,
        usesOption: true,
        usesShift: false,
        usesCommand: false
    )!

    let key: String
    let usesControl: Bool
    let usesOption: Bool
    let usesShift: Bool
    let usesCommand: Bool

    init?(
        key: String,
        usesControl: Bool,
        usesOption: Bool,
        usesShift: Bool,
        usesCommand: Bool
    ) {
        let normalizedKey = key.lowercased()
        guard normalizedKey.count == 1,
              normalizedKey.unicodeScalars.allSatisfy({
                  !CharacterSet.whitespacesAndNewlines.contains($0)
                      && !CharacterSet.controlCharacters.contains($0)
              }) else {
            return nil
        }
        self.key = normalizedKey
        self.usesControl = usesControl
        self.usesOption = usesOption
        self.usesShift = usesShift
        self.usesCommand = usesCommand
    }

    init?(storageValue: String) {
        let components = storageValue.split(separator: "|", omittingEmptySubsequences: false)
        guard components.count == 2 else { return nil }
        let modifiers = Set(components[1].split(separator: ",").map(String.init))
        self.init(
            key: String(components[0]),
            usesControl: modifiers.contains("control"),
            usesOption: modifiers.contains("option"),
            usesShift: modifiers.contains("shift"),
            usesCommand: modifiers.contains("command")
        )
    }

    var storageValue: String {
        let modifiers = [
            usesControl ? "control" : nil,
            usesOption ? "option" : nil,
            usesShift ? "shift" : nil,
            usesCommand ? "command" : nil
        ].compactMap(\.self)
        return "\(key)|\(modifiers.joined(separator: ","))"
    }

    var keyEquivalent: KeyEquivalent {
        KeyEquivalent(Character(key))
    }

    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if usesControl { modifiers.insert(.control) }
        if usesOption { modifiers.insert(.option) }
        if usesShift { modifiers.insert(.shift) }
        if usesCommand { modifiers.insert(.command) }
        return modifiers
    }

    var displayName: String {
        let modifiers = [
            usesControl ? "⌃" : nil,
            usesOption ? "⌥" : nil,
            usesShift ? "⇧" : nil,
            usesCommand ? "⌘" : nil
        ].compactMap(\.self).joined()
        return modifiers + key.uppercased()
    }
}
