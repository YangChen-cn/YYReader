import SwiftUI

struct ReaderChapterFooter: View {
    let store: LibraryStore

    var body: some View {
        HStack {
            Button("上一章", systemImage: "chevron.left", action: store.goToPreviousChapter)
            Spacer()
            Button("下一章", systemImage: "chevron.right", action: store.goToNextChapter)
        }
        .buttonStyle(.bordered)
        .padding(.top, 32)
    }
}
