import SwiftUI

struct BookshelfTransferPreviewSheet: View {
    let pendingImport: BookshelfTransferPendingImport
    let confirmImport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入书架预览")
                .font(.title2)
                .bold()

            Text("检测到 \(pendingImport.preview.totalCount) 本小说。导入会更新已存在书籍的元数据和阅读位置，但不会导入正文缓存。")
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                GridRow {
                    Label("新书", systemImage: "book.closed.badge.plus")
                    Text(pendingImport.preview.newCount, format: .number)
                }
                GridRow {
                    Label("已存在", systemImage: "books.vertical")
                    Text(pendingImport.preview.existingCount, format: .number)
                }
                if pendingImport.preview.invalidCount > 0 {
                    GridRow {
                        Label("数据错误", systemImage: "exclamationmark.triangle")
                        Text(pendingImport.preview.invalidCount, format: .number)
                    }
                }
                if pendingImport.preview.duplicateCount > 0 {
                    GridRow {
                        Label("文件内重复", systemImage: "doc.on.doc")
                        Text(pendingImport.preview.duplicateCount, format: .number)
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel, action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                Button("导入", action: importAndDismiss)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }

    private func importAndDismiss() {
        confirmImport()
        dismiss()
    }
}
