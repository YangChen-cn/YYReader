import UIKit

@MainActor
enum MobileReadingFont {
    // Only resolve font metrics here; all body text is rendered by SwiftUI Text.
    static func resolve(_ family: ReaderFontFamily, size: Double) -> UIFont {
        let system = UIFont.systemFont(ofSize: size)
        switch family {
        case .system: return system
        case .serif:
            // Resolve a real Chinese Song face when available. The system serif
            // design can otherwise fall back to the default Chinese sans face.
            let names = ["Songti-SC-Regular", "STSongti-SC-Regular", "Songti SC"]
            for name in names {
                if let font = UIFont(name: name, size: size) { return font }
            }
            return UIFont(descriptor: system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor, size: size)
        case .rounded:
            return UIFont(descriptor: system.fontDescriptor.withDesign(.rounded) ?? system.fontDescriptor, size: size)
        case .kaiti: return UIFont(name: "Kaiti SC", size: size) ?? system
        }
    }
}
