import SwiftUI

struct ReaderCommandActions {
    let canAddURL: Bool
    let canRefreshCatalog: Bool
    let canNavigatePreviousChapter: Bool
    let canNavigateNextChapter: Bool
    let canToggleCatalog: Bool
    let canChangeAppearance: Bool
    let addURL: @MainActor () -> Void
    let refreshCatalog: @MainActor () -> Void
    let previousChapter: @MainActor () -> Void
    let nextChapter: @MainActor () -> Void
    let toggleCatalog: @MainActor () -> Void
    let toggleAppearance: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var readerCommandActions: ReaderCommandActions?
}
