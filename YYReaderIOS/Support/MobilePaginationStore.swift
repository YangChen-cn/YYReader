import Foundation
import Observation

@MainActor
@Observable
final class MobilePaginationStore {
    private let paginator = MobileTextPaginator()
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private(set) var pages: [MobileReadingPage] = []
    private(set) var isPaginating = false
    private(set) var completedRequest: MobilePaginationRequest?
    private(set) var errorMessage: String?

    // Own the work independently of the ScrollView's task lifecycle: toolbar
    // transitions can cancel a view task while leaving its loading overlay alive.
    @discardableResult
    func start(request: MobilePaginationRequest, paragraphs: [String]) -> Task<Void, Never>? {
        if completedRequest == request, !pages.isEmpty {
            cancel()
            return nil
        }
        task?.cancel()
        let id = UUID()
        generation = id
        isPaginating = true
        errorMessage = nil
        let work = Task {
            defer {
                if generation == id {
                    isPaginating = false
                    task = nil
                }
            }
            do {
                let result = try await paginator.pages(paragraphs: paragraphs, layout: request.layout)
                try Task.checkCancellation()
                guard generation == id else { return }
                pages = result
                completedRequest = request
            } catch is CancellationError {
                // A replacement request owns the spinner; a cancelled current
                // request still clears it through defer.
            } catch {
                guard generation == id else { return }
                errorMessage = "章节分页失败：\(error.localizedDescription)"
            }
        }
        task = work
        return work
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        isPaginating = false
    }
}
