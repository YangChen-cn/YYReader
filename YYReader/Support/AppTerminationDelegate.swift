#if os(macOS)
import AppKit

@MainActor
final class AppTerminationDelegate: NSObject, NSApplicationDelegate {
    weak var services: AppServices?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store = services?.libraryStore, !store.flushPendingProgress() else {
            return .terminateNow
        }
        // A save that keeps failing (full disk, unreadable store) must not trap the
        // user in the app: let them quit knowingly instead of forcing a Force Quit.
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "阅读进度尚未保存"
        alert.informativeText = "\(store.presentedError?.message ?? "写入数据库失败。")仍要退出吗？未保存的进度会丢失。"
        alert.addButton(withTitle: "仍要退出")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
#endif
