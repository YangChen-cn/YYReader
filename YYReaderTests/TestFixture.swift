import Foundation

enum TestFixture {
    static func html(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures")
            .appending(path: "\(name).html")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
