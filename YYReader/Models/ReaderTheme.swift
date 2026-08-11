import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case rose
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
        case .rose: "绯霞"
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

    var accent: Color {
        palette.accent
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
        case .light, .rose, .sepia, .mist, .sage: .light
        case .dark, .midnight: .dark
        }
    }

    var isLight: Bool {
        preferredColorScheme != .dark
    }

    var usesBookishChapterOrnament: Bool {
        self == .rose || self == .sepia
    }

    private var palette: (
        background: Color,
        accent: Color,
        foreground: Color,
        secondaryForeground: Color,
        tertiaryForeground: Color,
        separator: Color
    ) {
        switch self {
        case .system:
            (
                Color(nsColor: .textBackgroundColor),
                Color(nsColor: .controlAccentColor),
                Color(nsColor: .labelColor),
                Color(nsColor: .secondaryLabelColor),
                Color(nsColor: .tertiaryLabelColor),
                Color(nsColor: .separatorColor)
            )
        case .light:
            (
                Color(red: 0.975, green: 0.978, blue: 0.973),
                Color(red: 0.180, green: 0.440, blue: 0.720),
                Color(red: 0.130, green: 0.140, blue: 0.150),
                Color(red: 0.360, green: 0.380, blue: 0.400),
                Color(red: 0.520, green: 0.540, blue: 0.560),
                Color(red: 0.850, green: 0.860, blue: 0.870)
            )
        case .rose:
            (
                Color(red: 0.965, green: 0.925, blue: 0.930),
                Color(red: 0.720, green: 0.280, blue: 0.440),
                Color(red: 0.320, green: 0.180, blue: 0.220),
                Color(red: 0.550, green: 0.400, blue: 0.450),
                Color(red: 0.660, green: 0.520, blue: 0.560),
                Color(red: 0.870, green: 0.780, blue: 0.800)
            )
        case .sepia:
            (
                Color(red: 0.949, green: 0.925, blue: 0.878),
                Color(red: 0.700, green: 0.400, blue: 0.280),
                Color(red: 0.230, green: 0.180, blue: 0.140),
                Color(red: 0.460, green: 0.390, blue: 0.330),
                Color(red: 0.580, green: 0.510, blue: 0.440),
                Color(red: 0.850, green: 0.800, blue: 0.720)
            )
        case .mist:
            (
                Color(red: 0.928, green: 0.938, blue: 0.937),
                Color(red: 0.320, green: 0.480, blue: 0.580),
                Color(red: 0.150, green: 0.170, blue: 0.180),
                Color(red: 0.390, green: 0.430, blue: 0.440),
                Color(red: 0.500, green: 0.540, blue: 0.550),
                Color(red: 0.810, green: 0.840, blue: 0.850)
            )
        case .sage:
            (
                Color(red: 0.918, green: 0.940, blue: 0.922),
                Color(red: 0.220, green: 0.560, blue: 0.420),
                Color(red: 0.150, green: 0.200, blue: 0.180),
                Color(red: 0.380, green: 0.460, blue: 0.420),
                Color(red: 0.500, green: 0.580, blue: 0.540),
                Color(red: 0.790, green: 0.850, blue: 0.810)
            )
        case .dark:
            (
                Color(red: 0.145, green: 0.145, blue: 0.137),
                Color(red: 0.780, green: 0.620, blue: 0.360),
                Color(red: 0.898, green: 0.886, blue: 0.863),
                Color(red: 0.671, green: 0.659, blue: 0.631),
                Color(red: 0.522, green: 0.510, blue: 0.482),
                Color(red: 0.255, green: 0.255, blue: 0.243)
            )
        case .midnight:
            (
                Color(red: 0.114, green: 0.133, blue: 0.157),
                Color(red: 0.350, green: 0.720, blue: 0.820),
                Color(red: 0.875, green: 0.890, blue: 0.898),
                Color(red: 0.647, green: 0.678, blue: 0.706),
                Color(red: 0.490, green: 0.529, blue: 0.565),
                Color(red: 0.204, green: 0.235, blue: 0.267)
            )
        }
    }
}
