import SwiftUI

struct LocalTextImportSheet: View {
    let draft: LocalTextImportDraft
    let confirm: (String, String) -> Void
    let cancel: () -> Void

    @State private var title: String
    @State private var author = "未知作者"

    init(
        draft: LocalTextImportDraft,
        confirm: @escaping (String, String) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.confirm = confirm
        self.cancel = cancel
        _title = State(initialValue: draft.suggestedTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("导入本地 TXT")
                    .font(.title2.bold())
                Text("正文会复制到 YYReader，本地文件之后可以移动或删除。")
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("书名", text: $title)
                TextField("作者", text: $author)
                LabeledContent("识别编码", value: draft.detectedEncoding)
                LabeledContent("章节", value: "\(draft.chapters.count) 章")
                LabeledContent("文件大小", value: ByteCountFormatter.string(fromByteCount: Int64(draft.byteCount), countStyle: .file))
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("导入") { confirm(title, author) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
