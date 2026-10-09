import SwiftData
import SwiftUI

@main
struct YYReaderIOSApp: App {
    private let container: ModelContainer
    @State private var services = AppServices()
    @AppStorage(ReaderPreferenceKeys.theme) private var themeName = ReaderTheme.system.rawValue

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
            let testTheme = ProcessInfo.processInfo.arguments.contains("--ui-testing-theme-sepia")
                ? ReaderTheme.sepia : ReaderTheme.system
            defaults.set(testTheme.rawValue, forKey: ReaderPreferenceKeys.theme)
            defaults.set(20.0, forKey: ReaderPreferenceKeys.fontSize)
            defaults.removeObject(forKey: ReaderPreferenceKeys.lastReadingBookID)
            defaults.removeObject(forKey: ReaderPreferenceKeys.lastReadingChapterID)
        }
        #endif
        ReaderPreferenceMigration.migrateIfNeeded()
        _themeName = AppStorage(wrappedValue: ReaderTheme.system.rawValue, ReaderPreferenceKeys.theme)
        do {
            let configuration: ModelConfiguration
            #if DEBUG
            if inMemory, ProcessInfo.processInfo.arguments.contains("--ui-testing-relaunch") {
                // Persist only the relaunch fixture, separately from the user's library.
                let directory = URL.cachesDirectory.appendingPathComponent("YYReaderStartupUITest", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                configuration = ModelConfiguration(url: directory.appendingPathComponent("library.store"))
            } else {
                configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
            }
            #else
            configuration = ModelConfiguration(isStoredInMemoryOnly: false)
            #endif
            container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        } catch {
            fatalError("无法打开 YYReader 数据库：\(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MobileLibrarySceneView()
                .environment(services)
                .preferredColorScheme(ReaderTheme(rawValue: themeName)?.preferredColorScheme)
        }
        .modelContainer(container)
    }
}
