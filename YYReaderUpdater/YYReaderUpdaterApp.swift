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
            .onAppear { installer.start() }
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

    func start() {
        guard !started else { return }
        started = true
        Task { await install() }
    }

    private func install() async {
        let args = ProcessInfo.processInfo.arguments
        var prepared: MacUpdateInstaller.Prepared?
        var archive: URL?
        do {
            guard args.count == 7, args[1] == "--install", let pid = Int32(args[6]),
                  let host = NSRunningApplication(processIdentifier: pid) else { throw MacUpdateInstaller.Failure.invalidPackage }
            let location = URL(fileURLWithPath: args[3]).resolvingSymlinksInPath()
            let embeddedHost = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().resolvingSymlinksInPath()
            guard location == embeddedHost, host.bundleURL?.resolvingSymlinksInPath() == location,
                  host.bundleIdentifier == "com.yyreader.app" else { throw MacUpdateInstaller.Failure.invalidPackage }
            target = location
            let download = URL(fileURLWithPath: args[2]).resolvingSymlinksInPath()
            let cache = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.yyreader.app/Data/Library/Caches/YYReaderUpdates")
                .resolvingSymlinksInPath()
            guard download.lastPathComponent == "update.dmg",
                  UUID(uuidString: download.deletingLastPathComponent().lastPathComponent) != nil,
                  download.deletingLastPathComponent().deletingLastPathComponent() == cache else {
                throw MacUpdateInstaller.Failure.invalidPackage
            }
            archive = download
            let staged = try await worker.prepare(archive: download, target: location, version: args[4], digest: args[5])
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
            let launch = NSWorkspace.OpenConfiguration()
            launch.createsNewApplicationInstance = true
            launch.allowsRunningApplicationSubstitution = false
            do {
                _ = try await NSWorkspace.shared.openApplication(at: location, configuration: launch)
            } catch {
                try await worker.rollback(staged)
                _ = try await NSWorkspace.shared.openApplication(at: location, configuration: launch)
                throw error
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
