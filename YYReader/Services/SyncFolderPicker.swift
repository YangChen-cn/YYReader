import AppKit

@MainActor
enum SyncFolderPicker {
    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择文件夹同步位置"
        panel.message = "YYReader 会在所选位置创建 YYReaderSync 文件夹。"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
