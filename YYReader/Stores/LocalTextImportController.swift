#if os(macOS)
import AppKit
#endif
import Foundation
import Observation

@MainActor
@Observable
final class LocalTextImportController {
    private let service = LocalTextImportService()
    private var task: Task<Void, Never>?
    private var requestID: UUID?

    private(set) var isWorking = false
    var pendingDraft: LocalTextImportDraft?
    var errorMessage: String?

    func chooseFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "导入本地 TXT 小说"
        panel.prompt = "读取"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        loadFile(url)
        #endif
    }

    func loadFile(_ url: URL) {
        task?.cancel()
        let id = UUID()
        requestID = id
        isWorking = true
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.requestID == id {
                    self.isWorking = false
                    self.task = nil
                    self.requestID = nil
                }
            }
            do {
                let draft = try await service.prepareImport(from: url)
                guard !Task.isCancelled, requestID == id else { return }
                pendingDraft = draft
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        requestID = nil
        isWorking = false
    }
}
