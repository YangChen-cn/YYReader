import AppKit
import UniformTypeIdentifiers

@MainActor
enum BookshelfTransferPanel {
    static func chooseImportFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "导入 YYReader 书架"
        panel.message = "选择 Windows 或 macOS YYReader 导出的 .yyreader 或 .json 文件。"
        panel.prompt = "导入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, yyreaderType]
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseExportFile(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "导出 YYReader 书架"
        panel.message = "只导出书架元数据与阅读位置，不包含正文缓存或 Cookie。"
        panel.prompt = "导出"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [yyreaderType]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func readClipboard() throws -> Data {
        guard let text = NSPasteboard.general.string(forType: .string),
              text.localizedCaseInsensitiveContains(BookshelfTransferCodec.currentFormat) else {
            throw BookshelfTransferError.clipboardUnavailable
        }
        return Data(text.utf8)
    }

    static func writeClipboard(_ data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw BookshelfTransferError.invalidDocument("无法生成 UTF-8 书架 JSON。")
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw BookshelfTransferError.invalidDocument("无法写入系统剪贴板。")
        }
    }

    private static let yyreaderType = UTType(filenameExtension: "yyreader", conformingTo: .json) ?? .json
}
