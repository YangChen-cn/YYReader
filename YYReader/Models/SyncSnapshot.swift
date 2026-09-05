import Foundation

struct SyncSnapshot: Codable, Equatable, Sendable {
    static let currentFormat = "yyreader-sync"
    static let currentVersion = 2

    var format: String
    var version: Int
    var device: SyncDevice
    var updatedAt: Date
    var capabilities: [String]
    var books: [SyncBookRecord]

    init(
        device: SyncDevice,
        updatedAt: Date = .now,
        capabilities: [String] = [],
        books: [SyncBookRecord]
    ) {
        format = Self.currentFormat
        version = Self.currentVersion
        self.device = device
        self.updatedAt = updatedAt
        self.capabilities = capabilities
        self.books = books
    }

    private enum CodingKeys: String, CodingKey {
        case format, version, device, updatedAt, capabilities, books
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        device = try container.decode(SyncDevice.self, forKey: .device)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        books = try container.decode([SyncBookRecord].self, forKey: .books)
    }
}
