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
            queue: .global(qos: .utility)
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
