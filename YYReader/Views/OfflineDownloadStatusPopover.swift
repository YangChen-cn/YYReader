import SwiftUI

struct OfflineDownloadStatusPopover: View {
    let downloads: OfflineDownloadManager
    let cancel: () -> Void
    let dismiss: () -> Void
    let dismissFailure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(downloads.progressMessage, systemImage: downloads.isDownloading ? "arrow.down.circle" : "exclamationmark.triangle")
                .font(.headline)

            if let failureMessage = downloads.failureMessage {
                Text(failureMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if downloads.isDownloading {
                Text("下载正在后台进行，不会影响阅读。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if downloads.isDownloading {
                    Button("取消下载", role: .cancel, action: cancel)
                }
                Spacer()
                if downloads.failureMessage != nil, !downloads.isDownloading {
                    Button("关闭状态") {
                        dismissFailure()
                        dismiss()
                    }
                } else {
                    Button("隐藏", action: dismiss)
                }
            }
        }
        .padding()
        .frame(width: 280)
        .accessibilityElement(children: .contain)
    }
}
