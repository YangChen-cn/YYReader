#if os(macOS)
import AppKit

@MainActor
final class AppTerminationDelegate: NSObject, NSApplicationDelegate {
    weak var services: AppServices?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        services?.libraryStore?.flushPendingProgress() == false ? .terminateCancel : .terminateNow
    }
}
#endif
