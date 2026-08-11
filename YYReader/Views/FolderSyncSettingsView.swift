import SwiftUI

struct FolderSyncSettingsView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var sync = services.folderSync

        Form {
            Section("文件夹同步") {
                Toggle("启用", isOn: $sync.isEnabled)

                Text("Mac 只写入 YYReaderSync/mac.json，并读取 Windows 写入的 windows.json。不会同步正文缓存、Cookie 或网页验证状态。")
                    .foregroundStyle(.secondary)

                LabeledContent("同步文件夹") {
                    Text(sync.folderDisplayPath ?? "尚未选择")
                        .foregroundStyle(sync.hasSelectedFolder ? .primary : .secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Button(
                    sync.hasSelectedFolder ? "更换文件夹…" : "选择同步文件夹…",
                    systemImage: "folder",
                    action: sync.chooseFolder
                )

                if sync.hasSelectedFolder {
                    Text("应用会在所选位置管理 YYReaderSync 文件夹。可以选择 iCloud Drive、Dropbox、OneDrive、Syncthing 或任意共享目录。")
                        .foregroundStyle(.secondary)
                }
            }

            Section("同步状态") {
                LabeledContent("最近同步") {
                    if let lastSyncAt = sync.lastSyncAt {
                        Text(lastSyncAt, format: .dateTime.year().month().day().hour().minute().second())
                    } else {
                        Text("尚未同步")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("立即同步", systemImage: "arrow.trianglehead.2.clockwise", action: sync.syncNow)
                    .disabled(!sync.isEnabled || !sync.hasSelectedFolder || sync.isSyncing)

                if sync.isSyncing {
                    Label("正在同步…", systemImage: "arrow.trianglehead.2.clockwise")
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = sync.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
