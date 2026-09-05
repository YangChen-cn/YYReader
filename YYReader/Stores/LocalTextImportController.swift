import AppKit
import Observation

@MainActor
@Observable
final class LocalTextImportController {
    private let service = LocalTextImportService()
    private var task: Task<Void, Never>?

    private(set) var isWorking = false
    var pendingDraft: LocalTextImportDraft?
    var errorMessage: String?

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "导入本地 TXT 小说"
        panel.prompt = "读取"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        task?.cancel()
        isWorking = true
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isWorking = false
                self.task = nil
            }
            do {
                pendingDraft = try await service.prepareImport(from: url)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isWorking = false
    }
}
