import Foundation

enum SyncDevice: String, Codable, Sendable {
    case mac
    case windows
    case ios

    static var current: Self {
        #if os(iOS)
        .ios
        #else
        .mac
        #endif
    }

    var fileName: String { rawValue + ".json" }

    var peers: [Self] {
        switch self {
        case .mac: [.windows, .ios]
        case .ios: [.mac, .windows]
        case .windows: [.mac, .ios]
        }
    }
}
