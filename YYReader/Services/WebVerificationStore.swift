import Foundation
import Observation

@MainActor
@Observable
final class WebVerificationStore {
    var request: VerificationRequest?

    func present(session: WebKitHostSession, url: URL) -> Bool {
        if request?.session === session { return false }
        guard request == nil else {
            session.failCurrentLoad(HTMLLoadError.verificationFailed(
                "另一个网站验证仍在进行，请完成或取消后重试。"
            ))
            return false
        }
        request = VerificationRequest(id: UUID(), url: url, session: session)
        return true
    }

    func complete(session: WebKitHostSession) {
        guard request?.session === session else { return }
        request = nil
    }

    func retry() {
        request?.session.reloadForVerification()
    }

    func fail(_ error: HTMLLoadError) {
        guard let request else { return }
        self.request = nil
        request.session.failCurrentLoad(error)
    }

    func cancel() {
        fail(.cancelled)
    }
}
