import UIKit

@MainActor
enum MobileReadingFont {
    // Only resolve font metrics here; all body text is rendered by SwiftUI Text.
    static func resolve(_ family: ReaderFontFamily, size: Double) -> UIFont {
        let system = UIFont.systemFont(ofSize: size)
        switch family {
        case .system: return system
        case .serif:
            return UIFont(descriptor: system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor, size: size)
        case .rounded:
            return UIFont(descriptor: system.fontDescriptor.withDesign(.rounded) ?? system.fontDescriptor, size: size)
        case .kaiti: return UIFont(name: "Kaiti SC", size: size) ?? system
        }
    }
}
