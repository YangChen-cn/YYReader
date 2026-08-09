import SwiftData
import SwiftUI

@main
struct YYReaderApp: App {
    private let modelContainer: ModelContainer
    @State private var services: AppServices

    init() {
        ReaderPreferenceMigration.migrateIfNeeded()
        let inMemory = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            modelContainer = try ModelContainer(
                for: Book.self,
                Chapter.self,
                configurations: configuration
            )
        } catch {
            fatalError("无法创建 YYReader 数据库：\(error.localizedDescription)")
        }
        _services = State(initialValue: AppServices())
    }

    var body: some Scene {
        WindowGroup("YYReader", id: "library") {
            LibrarySceneView()
                .environment(services)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1240, height: 820)
        .modelContainer(modelContainer)
        .commands {
            YYReaderCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
