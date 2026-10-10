#if os(macOS)
import Foundation

/// The update helper keeps the previous version as a sibling backup until the new
/// build proves it actually reached a usable state. Launching the process is not
/// that proof: a build that crashes while opening the store would otherwise leave
/// no backup to roll back to. This marker is the proof, and it is written only
/// after the store is open and the reading selection restored.
enum LaunchConfirmation {
    static let markerArgument = "--launch-marker"
    static let markerFileName = "launched.marker"

    static func markerURL(in arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: markerArgument),
              arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    /// Marker next to the downloaded archive, so the helper's own folder checks
    /// already cover it and its cleanup removes the marker with the folder.
    static func markerURL(forArchive archive: URL) -> URL {
        archive.deletingLastPathComponent().appendingPathComponent(markerFileName)
    }

    /// Writes the confirmation when the helper asked for one. Only paths inside
    /// this app's own container are accepted, so a stray argument cannot turn a
    /// launch into an arbitrary file write.
    @discardableResult
    static func confirmIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        guard let marker = markerURL(in: arguments), marker.path.hasPrefix(NSHomeDirectory()) else { return false }
        let payload = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")\n\(Date.now.formatted(.iso8601))\n"
        do {
            try FileManager.default.createDirectory(
                at: marker.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(payload.utf8).write(to: marker, options: .atomic)
            return true
        } catch {
            NSLog("YYReader launch confirmation: %@", error.localizedDescription)
            return false
        }
    }
}
#endif
