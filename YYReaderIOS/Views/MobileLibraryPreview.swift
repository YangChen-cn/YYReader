import SwiftData
import SwiftUI

#if DEBUG
// All preview text is invented. Previews use a separate in-memory library and no network.
struct MobileLibraryPreview: View {
    let showsReader: Bool
    @State private var container: ModelContainer?
    @State private var store: LibraryStore?
    @State private var services = AppServices()
    @State private var failure: String?

    var body: some View {
        Group {
            if let container, let store {
                Group {
                    if showsReader {
                        NavigationStack {
                            MobileReaderView(store: store, showLibrary: {}, showCatalog: {})
                        }
                    } else {
                        MobileLibraryView(store: store)
                    }
                }
                .modelContainer(container)
                .environment(services)
            } else if let failure {
                ContentUnavailableView("预览初始化失败", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else {
                ProgressView()
            }
        }
        .task {
            guard container == nil else { return }
            do {
                let container = try ModelContainer(for: Book.self, Chapter.self,
                                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
                let store = LibraryStore(modelContext: container.mainContext, coordinator: services.importCoordinator)
                let titles = showsReader ? ["山间来信"] : ["山间来信", "海边慢行", "旅途札记", "春日读书"]
                for title in titles {
                    let sample = "\(title)\n\n\(MobileSampleContent.text)"
                    let draft = try LocalTextImportService.prepareImport(data: Data(sample.utf8), fileName: title)
                    try store.importLocalText(draft, title: title, author: "预览作者")
                }
                services.libraryStore = store
                if !showsReader { store.selectBook(nil) }
                self.container = container
                self.store = store
                if showsReader { store.beginReaderPresentation() }
            } catch {
                failure = error.localizedDescription
            }
        }
    }


}

#Preview("书架") { MobileLibraryPreview(showsReader: false) }
#Preview("阅读器") { MobileLibraryPreview(showsReader: true) }
#endif
