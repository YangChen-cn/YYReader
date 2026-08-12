import Darwin
import Dispatch
import Foundation

actor SyncFolderMonitor {
    private let eventQueue = DispatchQueue(label: "com.yyreader.folder-sync-monitor")
    private var source: DispatchSourceFileSystemObject?

    func start(directory: URL, onChange: @escaping @Sendable () -> Void) {
        stop()

        // Opening a File Provider or network directory can block. This actor is
        // intentionally independent from MainActor so startup and Reader UI stay usable.
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: eventQueue
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
