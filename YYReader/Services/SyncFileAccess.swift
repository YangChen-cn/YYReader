import Foundation

enum SyncFileAccess {
    // File Providers materialize cloud items through coordination. A direct
    // fileExists/Data read can mistake an undownloaded snapshot for an absent one.
    static func coordinate<T>(at url: URL, writing: Bool, _ operation: (URL) throws -> T) throws -> T {
        try Task.checkCancellation()
        #if os(iOS)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, any Error>?
        if writing {
            coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
                result = Result { try operation(coordinatedURL) }
            }
        } else {
            coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinatedURL in
                result = Result { try operation(coordinatedURL) }
            }
        }
        try Task.checkCancellation()
        if let coordinationError { throw coordinationError }
        guard let result else { throw SyncError.folderUnavailable }
        return try result.get()
        #else
        return try operation(url)
        #endif
    }

    static func isMissing(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain
            && (error.code == CocoaError.fileNoSuchFile.rawValue || error.code == CocoaError.fileReadNoSuchFile.rawValue)
    }
}
