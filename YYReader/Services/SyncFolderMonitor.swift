import Darwin
import Dispatch
import Foundation

@MainActor
final class SyncFolderMonitor {
    private var source: DispatchSourceFileSystemObject?

    func start(directory: URL, onChange: @escaping @Sendable () -> Void) {
        stop()
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            // This type is MainActor-isolated. Dispatch invokes both the event and
            // cancellation handlers on the source queue, so they must use the same
            // executor instead of a global queue that trips Swift 6 isolation checks.
            queue: .main
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        source?.cancel()
    }
}
