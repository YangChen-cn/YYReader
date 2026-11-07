import SwiftUI

/// All reader surfaces use the same per-source preference; auto detection is
/// only a fallback and never writes the user's global reading defaults.
@propertyWrapper
@MainActor
struct BookReaderPresentation: DynamicProperty {
    @Environment(AppServices.self) private var services
    @AppStorage(ReaderPreferenceKeys.bookPresentations) private var overrides = Data()
    @AppStorage(ReaderPreferenceKeys.presentationMode) private var globalMode = ReaderPresentationMode.normal.rawValue

    var wrappedValue: String {
        get {
            let book = services.libraryStore?.selectedBook
            return BookPresentationPreferences.resolve(
                sourceURL: book?.sourceBookURL, data: overrides, globalMode: globalMode,
                isTavern: detectsTavern(book)
            ).rawValue
        }
        nonmutating set {
            guard let mode = ReaderPresentationMode(rawValue: newValue) else { return }
            if let source = services.libraryStore?.selectedBook?.sourceBookURL {
                overrides = BookPresentationPreferences.setting(mode, sourceURL: source, data: overrides)
            } else {
                globalMode = mode.rawValue
            }
        }
    }

    private func detectsTavern(_ book: Book?) -> Bool {
        guard let book, book.isLocalText else { return false }
        // Export floors dominate the chapter list; bound the check so ordinary
        // TXT books with thousands of chapters stay cheap to render.
        return book.chapters.prefix(8).filter {
            $0.title.range(of: #"^第[0-9]+楼$"#, options: .regularExpression) != nil
        }.count >= 2
    }

    var projectedValue: Binding<String> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}
