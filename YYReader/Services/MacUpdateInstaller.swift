#if os(macOS)
import Foundation

/// Runs only in the independent installer app. No shell interpolation and no
/// elevated privileges; an unwritable installation falls back to manual install.
actor MacUpdateInstaller {
    struct Prepared: Sendable {
        let target: URL
        let staging: URL
        let backup: URL
    }

    enum Failure: LocalizedError {
        case invalidPackage, location, command(String), quit, rollback(URL)
        var errorDescription: String? {
            switch self {
            case .invalidPackage: "安装包与预期版本不符，更新已停止。"
            case .location: "当前位置无法更新，请手动将 YYReader 安装到“应用程序”。"
            case .command(let name): "\(name)未能完成，原版本仍保留。"
            case .quit: "YYReader 未正常退出，更新已停止。请保存后重试。"
            case .rollback(let url): "恢复原版本失败，原 App 保留在：\(url.path)"
            }
        }
    }

    func prepare(archive: URL, target: URL, version: String, digest: String) throws -> Prepared {
        guard digest.count == 64, digest.allSatisfy(\.isHexDigit),
              try UpdateChecksum.sha256(of: archive) == digest else { throw Failure.invalidPackage }
        let manager = FileManager.default
        let parent = target.deletingLastPathComponent()
        guard manager.isWritableFile(atPath: parent.path), manager.isWritableFile(atPath: target.path),
              !target.path.hasPrefix("/Volumes/"), !target.path.contains("/AppTranslocation/") else { throw Failure.location }
        let mount = manager.temporaryDirectory.appendingPathComponent("YYReaderUpdate-\(UUID().uuidString)")
        try manager.createDirectory(at: mount, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: mount) }
        try run("/usr/bin/hdiutil", ["attach", archive.path, "-readonly", "-nobrowse", "-mountpoint", mount.path, "-quiet"])
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"]) }
        let source = mount.appendingPathComponent("YYReader.app")
        try validate(source, installedAt: target, version: version)
        let id = UUID().uuidString
        let prepared = Prepared(target: target, staging: parent.appendingPathComponent(".YYReader-update-\(id).app"),
                                backup: parent.appendingPathComponent(".YYReader-backup-\(id).app"))
        do {
            try run("/usr/bin/ditto", [source.path, prepared.staging.path])
            try validate(prepared.staging, installedAt: target, version: version)
            return prepared
        } catch {
            try? manager.removeItem(at: prepared.staging)
            throw error
        }
    }

    private func validate(_ source: URL, installedAt target: URL, version: String) throws {
        guard let info = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: source.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any],
              let oldInfo = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: target.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "com.yyreader.app",
              oldInfo["CFBundleIdentifier"] as? String == "com.yyreader.app",
              info["CFBundleShortVersionString"] as? String == version,
              let incoming = ReleaseVersion(version),
              let installed = ReleaseVersion(oldInfo["CFBundleShortVersionString"] as? String ?? ""), incoming > installed,
              let minimum = ReleaseVersion(info["LSMinimumSystemVersion"] as? String ?? ""),
              let executable = info["CFBundleExecutable"] as? String, executable == "YYReader" else { throw Failure.invalidPackage }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        guard let currentOS = ReleaseVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"), minimum <= currentOS else { throw Failure.invalidPackage }
        try run("/usr/bin/lipo", [source.appendingPathComponent("Contents/MacOS/YYReader").path, "-verify_arch", "arm64"])
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", source.path])
    }

    func replace(_ prepared: Prepared) throws {
        try Self.replace(prepared, move: { try FileManager.default.moveItem(at: $0, to: $1) })
    }

    /// The old App stays as a sibling backup until the new App launches.
    nonisolated static func replace(_ prepared: Prepared, move: (URL, URL) throws -> Void) throws {
        try move(prepared.target, prepared.backup)
        do { try move(prepared.staging, prepared.target) }
        catch {
            let original = error
            do { try move(prepared.backup, prepared.target) }
            catch { throw Failure.rollback(prepared.backup) }
            throw original
        }
    }

    func rollback(_ prepared: Prepared) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: prepared.backup.path) else { return }
        // Keep the failed new bundle in staging so rollback never deletes the backup.
        if manager.fileExists(atPath: prepared.target.path) {
            try manager.moveItem(at: prepared.target, to: prepared.staging)
        }
        do { try manager.moveItem(at: prepared.backup, to: prepared.target) }
        catch { throw Failure.rollback(prepared.backup) }
    }

    func discardStaging(_ prepared: Prepared) throws {
        if FileManager.default.fileExists(atPath: prepared.staging.path) {
            try FileManager.default.removeItem(at: prepared.staging)
        }
    }

    func finish(_ prepared: Prepared, archive: URL) throws {
        try FileManager.default.removeItem(at: prepared.backup)
        try FileManager.default.removeItem(at: archive.deletingLastPathComponent())
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.command(URL(fileURLWithPath: executable).lastPathComponent) }
    }
}
#endif
