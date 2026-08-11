import Foundation

enum ReaderChapterHeaderStyle {
    case prominent
    case compact

    var topPadding: Double {
        switch self {
        case .prominent: 92
        case .compact: 48
        }
    }

    var bottomPadding: Double {
        switch self {
        case .prominent: 36
        case .compact: 28
        }
    }
}
