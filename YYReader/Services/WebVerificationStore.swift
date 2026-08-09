import Foundation
import Observation

@MainActor
@Observable
final class WebVerificationStore {
    var request: VerificationRequest?
    private var continuation: CheckedContinuation<LoadedHTML, any Error>?
    private var userAgentsByHost: [String: String] = [:]

    func load(_ url: URL) async throws -> LoadedHTML {
        guard request == nil else { throw HTMLLoadError.invalidResponse }
        let id = UUID()
        request = VerificationRequest(id: id, url: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        } onCancel: {
            Task { @MainActor in
                self.cancel()
            }
        }
    }

    func complete(html: String, finalURL: URL, userAgent: String) {
        guard let request, let continuation else { return }
        if let host = finalURL.host?.lowercased(), !userAgent.isEmpty {
            userAgentsByHost[host] = userAgent
        }
        self.request = nil
        self.continuation = nil
        continuation.resume(returning: LoadedHTML(
            requestedURL: request.url,
            finalURL: finalURL,
            html: html,
            retrievalKind: .webKit
        ))
    }

    func userAgent(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return userAgentsByHost[host]
    }

    func fail(_ error: HTMLLoadError) {
        request = nil
        let pending = continuation
        continuation = nil
        pending?.resume(throwing: error)
    }

    func cancel() {
        fail(.cancelled)
    }
}
