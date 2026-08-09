import SwiftUI

struct LibrarySelectionDetailView: View {
    let bookTitle: String?
    let chapterTitle: String?
    let continueReading: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(bookTitle ?? "选择一本小说", systemImage: "book.pages")
        } description: {
            if let chapterTitle {
                Text("已选择“\(chapterTitle)”。打开后将恢复上次阅读位置。")
            } else {
                Text("在书架和目录中选择内容，然后开始阅读。")
            }
        } actions: {
            if chapterTitle != nil {
                Button("继续阅读", systemImage: "book.pages", action: continueReading)
            }
        }
    }
}
