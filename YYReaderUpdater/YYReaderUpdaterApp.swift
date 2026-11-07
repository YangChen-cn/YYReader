import AppKit
import Observation
import SwiftUI

@main
struct YYReaderUpdaterApp: App {
    @State private var installer = InstallerController()

    var body: some Scene {
        WindowGroup("YYReader 更新") {
            VStack(alignment: .leading, spacing: 18) {
                Label("安装 YYReader 更新", systemImage: "arrow.down.circle.fill").font(.title2)
                if let error = installer.error {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    Button("返回 YYReader") { Task { await installer.returnToReader() } }
                        .buttonStyle(.borderedProminent)
                } else {
                    ProgressView(installer.message)
                    Text("安装完成后会自动重新打开。")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(width: 420)
            .fixedSize(horizontal: true, vertical: true)
            .onAppear {
                // The helper runs as a background UIElement app; float its window above the
                // reader and bring it forward so progress and failures are actually visible.
                NSApp.activate()
                NSApp.windows.forEach {
                    $0.level = .floating
                    $0.makeKeyAndOrderFront(nil)
                }
                installer.start()
            }
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
@Observable
private final class InstallerController {
    var message = "正在校验安装包…"
    var error: String?
    private var started = false
    private var target: URL?
    private let worker = MacUpdateInstaller()
    private let cacheDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.yyreader.app/Data/Library/Caches/YYReaderUpdates", isDirectory: true)

    func start() {
        guard !started else { return }
        started = true
        Task { await install() }
    }

    /// Sandboxed hosts cannot pass launch arguments through `NSWorkspace` (LaunchServices
    /// routes the launch through CoreServicesUIAgent and drops them), so fall back to the
    /// request file the host writes into the update cache.
    private func installRequest() throws -> UpdateInstallRequest {
        let args = ProcessInfo.processInfo.arguments
        if args.count == 9, args[1] == "--install" {
            guard let pid = Int32(args[6]) else { throw MacUpdateInstaller.Failure.invalidPackage }
            return UpdateInstallRequest(archivePath: args[2], targetPath: args[3], version: args[4],
                                        digest: args[5], hostProcessID: pid,
                                        markerArgument: args[7], markerPath: args[8])
        }
        guard let request = UpdateInstallRequest.read(from: cacheDirectory) else {
            throw MacUpdateInstaller.Failure.invalidPackage
        }
        UpdateInstallRequest.remove(from: cacheDirectory)
        return request
    }

    private func install() async {
        let request: UpdateInstallRequest
        do { request = try installRequest() }
        catch {
            self.error = error.localizedDescription
            return
        }
        let download = URL(fileURLWithPath: request.archivePath).resolvingSymlinksInPath()
        var prepared: MacUpdateInstaller.Prepared?
        // Resolve the archive before validating so a guard failure is still reported to the host.
        var archive: URL? = download
        do {
            guard request.markerArgument == LaunchConfirmation.markerArgument,
                  let host = NSRunningApplication(processIdentifier: request.hostProcessID) else {
                throw MacUpdateInstaller.Failure.invalidPackage
            }
            let location = URL(fileURLWithPath: request.targetPath).resolvingSymlinksInPath()
            let embeddedHost = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().resolvingSymlinksInPath()
            guard location == embeddedHost, host.bundleURL?.resolvingSymlinksInPath() == location,
                  host.bundleIdentifier == "com.yyreader.app" else { throw MacUpdateInstaller.Failure.invalidPackage }
            target = location
            let cache = cacheDirectory.resolvingSymlinksInPath()
            guard download.lastPathComponent == "update.dmg",
                  UUID(uuidString: download.deletingLastPathComponent().lastPathComponent) != nil,
                  download.deletingLastPathComponent().deletingLastPathComponent() == cache else {
                throw MacUpdateInstaller.Failure.invalidPackage
            }
            let staged = try await worker.prepare(archive: download, target: location,
                                                  version: request.version, digest: request.digest)
            prepared = staged
            message = "正在保存进度并退出 YYReader…"
            guard host.terminate() else { throw MacUpdateInstaller.Failure.quit }
            for _ in 0..<90 {
                if host.isTerminated { break }
                try await Task.sleep(for: .milliseconds(500))
            }
            guard host.isTerminated else { throw MacUpdateInstaller.Failure.quit }
            message = "正在替换并重新打开…"
            try await worker.replace(staged)
            let marker: URL? = request.markerPath.isEmpty ? nil : URL(fileURLWithPath: request.markerPath)
            if let marker { try? FileManager.default.removeItem(at: marker) }
            let launch = NSWorkspace.OpenConfiguration()
            launch.createsNewApplicationInstance = true
            launch.allowsRunningApplicationSubstitution = false
            if let marker { launch.arguments = [LaunchConfirmation.markerArgument, marker.path] }
            // Process launch alone is not proof the new build is usable: the backup
            // is discarded only after the new app confirms it opened its store.
            message = "正在确认新版本可以打开…"
            do {
                _ = try await NSWorkspace.shared.openApplication(at: location, configuration: launch)
            } catch {
                // Launching itself failed: the previous version is restored.
                try await worker.rollback(staged)
                _ = try? await NSWorkspace.shared.openApplication(at: location, configuration: .init())
                throw MacUpdateInstaller.Failure.launchFailed(error.localizedDescription)
            }
            if let marker, await !MacUpdateInstaller.waitForLaunchMarker(at: marker, timeout: .seconds(60)) {
                // The app is running but never confirmed it opened its store. Keep
                // the previous version as a backup rather than discarding it or
                // forcing a rollback of a build that may be perfectly fine.
                throw MacUpdateInstaller.Failure.upgradeUnconfirmed("启动后 60 秒内没有完成打开。")
            }
            do { try await worker.finish(staged, archive: download) }
            catch { NSLog("YYReader update cleanup: %@", error.localizedDescription) } // Update already succeeded; keep any leftover backup.
            NSApp.terminate(nil)
        } catch {
            self.error = error.localizedDescription
            if let prepared {
                do { try await worker.discardStaging(prepared) }
                catch { NSLog("YYReader staging cleanup: %@", error.localizedDescription) }
            }
            if let archive {
                do { try Data(error.localizedDescription.utf8).write(to: archive.deletingLastPathComponent().appendingPathComponent("failure.txt"), options: .atomic) }
                catch { NSLog("YYReader update status: %@", error.localizedDescription) }
            }
        }
    }

    func returnToReader() async {
        if let target {
            do { _ = try await NSWorkspace.shared.openApplication(at: target, configuration: .init()) }
            catch { self.error = error.localizedDescription; return }
        }
        NSApp.terminate(nil)
    }
}
