import SwiftUI

struct AppUpdateSettingsView: View {
    @Environment(AppServices.self) private var services
    @AppStorage(AppUpdateController.automaticCheckKey) private var automaticCheck = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("自动检查更新", isOn: $automaticCheck)
                .onChange(of: automaticCheck) { _, enabled in
                    if enabled { Task { await services.updates.check() } }
                }
            HStack {
                Text(verbatim: "YYReader \(services.updates.installedVersion)").foregroundStyle(.secondary)
                Spacer()
                Button("检查更新") { Task { await services.updates.check(force: true) } }
                    .disabled(services.updates.isChecking || services.updates.isBusy || services.updates.downloadedArchive != nil)
            }
            if services.updates.isChecking { ProgressView("正在检查更新…") }
            if let message = services.updates.statusMessage { Label(message, systemImage: "checkmark.circle").foregroundStyle(.secondary) }
            if services.updates.release != nil {
                AppUpdateCard(updates: services.updates)
            } else if let error = services.updates.errorMessage {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
            }
        }
        .task { await services.updates.check() }
    }
}
