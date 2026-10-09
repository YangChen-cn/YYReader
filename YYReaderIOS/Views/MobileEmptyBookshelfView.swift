import SwiftUI

struct MobileEmptyBookshelfView: View {
    let addWeb: () -> Void
    let importText: () -> Void
    let importBookshelf: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("从一本好书开始", systemImage: "books.vertical")
                .foregroundStyle(.tint)
        } description: {
            Text("把喜欢的故事放进书架。\n添加小说网址，或导入自己的 TXT 文件。")
        } actions: {
            VStack(spacing: 12) {
                Button("添加小说网址", systemImage: "link", action: addWeb)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("导入 TXT", systemImage: "doc.text", action: importText)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("导入已有书架", systemImage: "square.and.arrow.down", action: importBookshelf)
                    .font(.subheadline)
            }
        }
        .accessibilityIdentifier("ios.emptyBookshelf")
    }
}
