import SwiftData
import SwiftUI

@main
struct YYReaderIOSApp: App {
    private let container: ModelContainer
    @State private var services = AppServices()

    init() {
        let inMemory = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #if DEBUG
        if inMemory {
            // Launch-argument UserDefaults overrides cannot be changed by Settings.
            // Seed the test preferences normally so the actual controls remain editable.
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: "folderSync.enabled")
            defaults.set(false, forKey: ReaderPreferenceKeys.continuousReading)
            defaults.set(ReaderPresentationMode.normal.rawValue, forKey: ReaderPreferenceKeys.presentationMode)
            defaults.set(ReaderPageTurnMode.verticalScroll.rawValue, forKey: ReaderPreferenceKeys.pageTurnMode)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-uncached") {
                defaults.set(ReaderPageTurnMode.horizontalPages.rawValue, forKey: ReaderPreferenceKeys.pageTurnMode)
                defaults.set(false, forKey: ReaderPreferenceKeys.prefetchNext)
            }
            defaults.set(20.0, forKey: ReaderPreferenceKeys.fontSize)
            defaults.removeObject(forKey: ReaderPreferenceKeys.lastReadingBookID)
            defaults.removeObject(forKey: ReaderPreferenceKeys.lastReadingChapterID)
        }
        #endif
        ReaderPreferenceMigration.migrateIfNeeded()
        do {
            container = try ModelContainer(for: Book.self, Chapter.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
        } catch {
            fatalError("无法打开 YYReader 数据库：\(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MobileLibrarySceneView()
                .environment(services)
        }
        .modelContainer(container)
    }
}
