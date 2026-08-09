import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case sepia
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "系统"
        case .light: "白色"
        case .sepia: "纸张"
        case .dark: "夜间"
        }
    }

    var background: Color {
        switch self {
        case .system: Color(nsColor: .textBackgroundColor)
        case .light: Color(red: 0.985, green: 0.982, blue: 0.972)
        case .sepia: Color(red: 0.955, green: 0.938, blue: 0.90)
        case .dark: Color(red: 0.105, green: 0.11, blue: 0.12)
        }
    }

    var foreground: Color {
        switch self {
        case .system: .primary
        case .light: Color(red: 0.13, green: 0.13, blue: 0.12)
        case .sepia: Color(red: 0.20, green: 0.18, blue: 0.14)
        case .dark: Color(red: 0.89, green: 0.89, blue: 0.87)
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light, .sepia: .light
        case .dark: .dark
        }
    }
}
