import SwiftUI

struct MobileEmptyBookshelfView: View {
    let addWeb: () -> Void
    let importText: () -> Void
    let importBookshelf: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("从一本好书开始")
            } icon: {
                Image(systemName: "books.vertical")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
            }
        } description: {
            Text("添加网页或导入 TXT，开始阅读。")
                .multilineTextAlignment(.center)
        } actions: {
            VStack(spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        addWebButton
                        importTextButton
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(spacing: 8) {
                        addWebButton
                        importTextButton
                    }
                }
                Button("导入已有书架", systemImage: "square.and.arrow.down", action: importBookshelf)
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .labelStyle(.titleAndIcon)
        }
        .accessibilityIdentifier("ios.emptyBookshelf")
    }

    private var addWebButton: some View {
        Button(action: addWeb) {
            Label("添加网页", systemImage: "link")
                .frame(minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
    }

    private var importTextButton: some View {
        Button(action: importText) {
            Label("导入 TXT", systemImage: "doc.text")
                .frame(minHeight: 30)
        }
        .buttonStyle(.bordered)
    }
}
