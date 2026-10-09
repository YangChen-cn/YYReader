import Foundation

enum TestFixture {
    static func html(_ name: String) throws -> String {
        try load(name, subdirectory: "Fixtures")
    }

    static func sharedHTML(_ name: String) throws -> String {
        try load(name, subdirectory: "cases")
    }

    private static func load(_ name: String, subdirectory: String) throws -> String {
        let bundle = Bundle(for: FixtureBundleMarker.self)
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: subdirectory) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "缺少测试样例：\(subdirectory)/\(name).html"])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private final class FixtureBundleMarker: NSObject {}
