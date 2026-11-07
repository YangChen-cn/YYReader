import Foundation

struct TavernCharacterAppearance: Codable {
    var colorHex = "D88DA3"
    var avatarFile: String?

    static func characters(from data: Data) -> [String: Self] {
        // Missing/old preferences simply use the default appearance.
        (try? JSONDecoder().decode([String: Self].self, from: data)) ?? [:]
    }
}
