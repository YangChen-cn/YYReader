import SwiftUI

struct ReaderCommandActions {
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
