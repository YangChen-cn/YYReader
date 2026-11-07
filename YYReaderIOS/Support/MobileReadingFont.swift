import UIKit
import SwiftUI

@MainActor
enum MobileReadingFont {
    private static var lineHeights: [String: Double] = [:]

    /// UIFont includes leading that SwiftUI Text does not always render. Measure
    /// the same fixed font as the page, once per font/size/display scale.
    static func paginationLineHeight(_ font: UIFont, displayScale: Double) -> Double {
        let key = "\(font.fontName)|\(font.pointSize)|\(displayScale)"
        if let cached = lineHeights[key] { return cached }
        let sample = Text("国Ag").font(.custom(font.fontName, fixedSize: font.pointSize)).fixedSize()
            .environment(\.displayScale, displayScale)
        let host = UIHostingController(rootView: sample)
        let measured = host.sizeThatFits(in: CGSize(width: 10000, height: 10000)).height
        let scale = max(displayScale, 1)
        let height = measured > 0 ? ceil(measured * scale) / scale : font.lineHeight
        if lineHeights.count >= 16 { lineHeights.removeAll(keepingCapacity: true) }
        lineHeights[key] = height
        return height
    }

    // All body text is rendered by SwiftUI Text.
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
