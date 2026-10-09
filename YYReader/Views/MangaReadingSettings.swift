import SwiftUI

struct MangaReadingSettings: View {
    @AppStorage(ReaderPreferenceKeys.mangaPageTurnMode) private var pageTurnMode = ReaderPageTurnMode.mangaDefault.rawValue
    @AppStorage(ReaderPreferenceKeys.mangaPageLayout) private var layout = MangaPageLayout.Mode.automatic.rawValue
    @AppStorage(ReaderPreferenceKeys.mangaFirstPageAlone) private var firstPageAlone = true
    @AppStorage(ReaderPreferenceKeys.mangaDarkBackground) private var darkBackground = false

    var body: some View {
        Section("漫画阅读方式") {
            Picker("阅读方式", selection: $pageTurnMode) {
                ForEach(ReaderPageTurnMode.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("manga.readingMode")
            if pageTurnMode == ReaderPageTurnMode.horizontalPages.rawValue {
                Picker("漫画布局", selection: $layout) {
                    ForEach(MangaPageLayout.Mode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("manga.layout")
            }
        }
        Section("显示选项") {
            Toggle("首图单页", isOn: $firstPageAlone)
            Toggle("深灰阅读背景", isOn: $darkBackground)
        }
    }
}
