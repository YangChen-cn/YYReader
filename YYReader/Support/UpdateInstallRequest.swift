import Foundation

/// Payload describing a pending in-app update.
///
/// A sandboxed host cannot hand launch arguments to the embedded helper: LaunchServices
/// forwards the request through CoreServicesUIAgent and drops the custom arguments, so the
/// helper only sees its own executable path. The host therefore writes this request into the
/// update cache and the helper reads it as a fallback when the command line is incomplete.
struct UpdateInstallRequest: Codable, Sendable {
    var archivePath: String
    var targetPath: String
    var version: String
    var digest: String
    var hostProcessID: Int32
    var markerArgument: String
    var markerPath: String

    static let fileName = "pending-install.json"

    static func arguments(from request: UpdateInstallRequest) -> [String] {
        ["--install", request.archivePath, request.targetPath, request.version, request.digest,
         String(request.hostProcessID), request.markerArgument, request.markerPath]
    }

    static func read(from directory: URL) -> UpdateInstallRequest? {
        let file = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(UpdateInstallRequest.self, from: data)
    }

    static func remove(from directory: URL) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }
}
