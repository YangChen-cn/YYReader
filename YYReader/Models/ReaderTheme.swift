import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case ivory
    case sepia
    case mist
    case sage
    case dark
    case midnight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "系统"
        case .light: "纯净"
        case .ivory: "象牙"
        case .sepia: "纸张"
        case .mist: "雾灰"
        case .sage: "青灰"
        case .dark: "炭黑"
        case .midnight: "深夜"
        }
    }

    var background: Color {
        palette.background
    }

    var foreground: Color {
        palette.foreground
    }

    var secondaryForeground: Color {
        palette.secondaryForeground
    }

    var tertiaryForeground: Color {
        palette.tertiaryForeground
    }

    var separator: Color {
        palette.separator
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light, .ivory, .sepia, .mist, .sage: .light
        case .dark, .midnight: .dark
        }
    }

    private var palette: (
        background: Color,
        foreground: Color,
        secondaryForeground: Color,
        tertiaryForeground: Color,
        separator: Color
    ) {
        switch self {
        case .system:
            (
                Color(nsColor: .textBackgroundColor),
                Color(nsColor: .labelColor),
                Color(nsColor: .secondaryLabelColor),
                Color(nsColor: .tertiaryLabelColor),
                Color(nsColor: .separatorColor)
            )
        case .light:
            (
                Color(red: 0.969, green: 0.969, blue: 0.957),
                Color(red: 0.157, green: 0.153, blue: 0.141),
                Color(red: 0.396, green: 0.388, blue: 0.365),
                Color(red: 0.522, green: 0.510, blue: 0.478),
                Color(red: 0.851, green: 0.843, blue: 0.816)
            )
        case .ivory:
            (
                Color(red: 0.973, green: 0.957, blue: 0.910),
                Color(red: 0.188, green: 0.173, blue: 0.145),
                Color(red: 0.427, green: 0.400, blue: 0.357),
                Color(red: 0.541, green: 0.506, blue: 0.451),
                Color(red: 0.871, green: 0.835, blue: 0.765)
            )
        case .sepia:
            (
                Color(red: 0.949, green: 0.925, blue: 0.878),
                Color(red: 0.224, green: 0.184, blue: 0.145),
                Color(red: 0.455, green: 0.396, blue: 0.333),
                Color(red: 0.580, green: 0.510, blue: 0.443),
                Color(red: 0.851, green: 0.800, blue: 0.725)
            )
        case .mist:
            (
                Color(red: 0.925, green: 0.933, blue: 0.929),
                Color(red: 0.145, green: 0.165, blue: 0.161),
                Color(red: 0.384, green: 0.416, blue: 0.408),
                Color(red: 0.486, green: 0.518, blue: 0.510),
                Color(red: 0.808, green: 0.827, blue: 0.820)
            )
        case .sage:
            (
                Color(red: 0.914, green: 0.933, blue: 0.914),
                Color(red: 0.153, green: 0.188, blue: 0.169),
                Color(red: 0.392, green: 0.439, blue: 0.408),
                Color(red: 0.490, green: 0.537, blue: 0.506),
                Color(red: 0.796, green: 0.835, blue: 0.804)
            )
        case .dark:
            (
                Color(red: 0.145, green: 0.145, blue: 0.137),
                Color(red: 0.898, green: 0.886, blue: 0.863),
                Color(red: 0.671, green: 0.659, blue: 0.631),
                Color(red: 0.522, green: 0.510, blue: 0.482),
                Color(red: 0.255, green: 0.255, blue: 0.243)
            )
        case .midnight:
            (
                Color(red: 0.114, green: 0.133, blue: 0.157),
                Color(red: 0.875, green: 0.890, blue: 0.898),
                Color(red: 0.647, green: 0.678, blue: 0.706),
                Color(red: 0.490, green: 0.529, blue: 0.565),
                Color(red: 0.204, green: 0.235, blue: 0.267)
            )
        }
    }
}
