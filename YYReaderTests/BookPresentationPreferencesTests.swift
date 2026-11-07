import Foundation
import Testing
@testable import YYReader

struct BookPresentationPreferencesTests {
    @Test func detectionDoesNotLeakAndManualChoiceSurvivesReload() throws {
        let tavern = "yyreader-local://txt/tavern"
        let novel = "https://example.com/novel/"
        let global = ReaderPresentationMode.sillyTavern.rawValue
        #expect(BookPresentationPreferences.resolve(sourceURL: tavern, data: Data(), globalMode: global, isTavern: true) == .sillyTavern)
        #expect(BookPresentationPreferences.resolve(sourceURL: novel, data: Data(), globalMode: global, isTavern: false) == .normal)
        var data = BookPresentationPreferences.setting(.normal, sourceURL: tavern, data: Data())
        data = BookPresentationPreferences.setting(.academicPaper, sourceURL: novel, data: data)
        let preferences = UserDefaults(suiteName: "BookPresentationTests-\(UUID().uuidString)")!
        defer { preferences.removeObject(forKey: ReaderPreferenceKeys.bookPresentations) }
        preferences.set(data, forKey: ReaderPreferenceKeys.bookPresentations)
        let reloaded = try #require(preferences.data(forKey: ReaderPreferenceKeys.bookPresentations))
        #expect(BookPresentationPreferences.resolve(sourceURL: tavern, data: reloaded, globalMode: global, isTavern: true) == .normal)
        #expect(BookPresentationPreferences.resolve(sourceURL: novel, data: reloaded, globalMode: global, isTavern: false) == .academicPaper)
        #expect(BookPresentationPreferences.resolve(sourceURL: "another", data: reloaded, globalMode: global, isTavern: false) == .normal)
    }

    @Test func explicitTavernChoiceIsLocalAndInvalidPreferencesFallBack() {
        let data = BookPresentationPreferences.setting(.sillyTavern, sourceURL: "one", data: Data("invalid".utf8))
        #expect(BookPresentationPreferences.resolve(sourceURL: "one", data: data, globalMode: "normal", isTavern: false) == .sillyTavern)
        #expect(BookPresentationPreferences.resolve(sourceURL: "two", data: data, globalMode: "normal", isTavern: false) == .normal)
        #expect(BookPresentationPreferences.resolve(sourceURL: "two", data: Data("invalid".utf8), globalMode: "unknown", isTavern: false) == .normal)
    }
}
