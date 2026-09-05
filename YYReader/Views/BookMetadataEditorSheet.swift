import SwiftUI

struct BookMetadataEditorSheet: View {
    let initialTitle: String
    let initialAuthor: String
    let confirm: (String, String) -> Void
    let cancel: () -> Void

    @State private var title: String
    @State private var author: String

    init(
        book: Book,
        confirm: @escaping (String, String) -> Void,
        cancel: @escaping () -> Void
    ) {
        initialTitle = book.title
        initialAuthor = book.author
        self.confirm = confirm
        self.cancel = cancel
        _title = State(initialValue: book.title)
        _author = State(initialValue: book.author)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("编辑书籍信息")
                .font(.title2.bold())
            Form {
                TextField("书名", text: $title)
                TextField("作者", text: $author)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存") { confirm(title, author) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
