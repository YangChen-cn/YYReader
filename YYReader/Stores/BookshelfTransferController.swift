import Foundation
import Observation

@MainActor
@Observable
final class BookshelfTransferController {
    private let fileService: BookshelfTransferFileService

    private(set) var isWorking = false
    var pendingImport: BookshelfTransferPendingImport?
    var notice: BookshelfTransferNotice?

    init(fileService: BookshelfTransferFileService = BookshelfTransferFileService()) {
        self.fileService = fileService
    }

    func chooseImportFile(for store: LibraryStore) {
        guard !isWorking, let url = BookshelfTransferPanel.chooseImportFile() else { return }
        loadImport(from: url, for: store)
    }

    func importFromClipboard(for store: LibraryStore) {
        guard !isWorking else { return }
        do {
            let document = try BookshelfTransferCodec.decode(BookshelfTransferPanel.readClipboard())
            prepareImport(document, for: store)
        } catch {
            presentError(title: "无法导入书架", error: error)
        }
    }

    func confirmPendingImport(for store: LibraryStore) {
        guard let pendingImport else { return }
        do {
            let summary = try store.importBookshelfTransfer(
                pendingImport.document,
                preview: pendingImport.preview
            )
            self.pendingImport = nil
            var message = "成功 \(summary.succeeded) 本，跳过 \(summary.skipped) 本，失败 \(summary.failed) 本。"
            if !summary.failures.isEmpty {
                message += "\n" + summary.failures.joined(separator: "\n")
            }
            notice = BookshelfTransferNotice(title: "书架导入完成", message: message)
        } catch {
            self.pendingImport = nil
            presentError(title: "无法导入书架", error: error)
        }
    }

    func exportToFile(from store: LibraryStore) {
        guard !isWorking, store.flushPendingProgress() else { return }
        let document = store.bookshelfTransferDocument()
        let suggestedName = "YYReader-Bookshelf-\(Self.filenameDate()).yyreader"
        guard let url = BookshelfTransferPanel.chooseExportFile(suggestedName: suggestedName) else { return }

        isWorking = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isWorking = false }
            do {
                try await self.fileService.writeDocument(document, to: url)
                self.notice = BookshelfTransferNotice(
                    title: "书架导出完成",
                    message: "已导出 \(document.books.count) 本小说到 \(url.lastPathComponent)。"
                )
            } catch {
                self.presentError(title: "无法导出书架", error: error)
            }
        }
    }

    func copyExportJSON(from store: LibraryStore) {
        guard !isWorking, store.flushPendingProgress() else { return }
        do {
            let document = store.bookshelfTransferDocument()
            try BookshelfTransferPanel.writeClipboard(BookshelfTransferCodec.encode(document))
            notice = BookshelfTransferNotice(
                title: "已复制书架数据",
                message: "已复制 \(document.books.count) 本小说的 JSON。"
            )
        } catch {
            presentError(title: "无法复制书架", error: error)
        }
    }

    private func loadImport(from url: URL, for store: LibraryStore) {
        isWorking = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isWorking = false }
            do {
                let document = try await self.fileService.readDocument(from: url)
                self.prepareImport(document, for: store)
            } catch {
                self.presentError(title: "无法导入书架", error: error)
            }
        }
    }

    private func prepareImport(_ document: BookshelfTransferDocument, for store: LibraryStore) {
        pendingImport = BookshelfTransferPendingImport(
            document: document,
            preview: store.previewBookshelfTransfer(document)
        )
    }

    private func presentError(title: String, error: Error) {
        notice = BookshelfTransferNotice(title: title, message: error.localizedDescription)
    }

    private static func filenameDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: .now)
    }
}
