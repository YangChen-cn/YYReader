import Foundation
import SwiftUI
import Testing
@testable import YYReader

struct ReaderPresentationTests {
    @Test
    func paragraphFormatterAddsTwoCharacterIndentOnlyWhenNeeded() {
        #expect(
            ReaderParagraphFormatter.format("第一段正文。", usesFirstLineIndent: true)
                == "　　第一段正文。"
        )
        #expect(
            ReaderParagraphFormatter.format("　　已经缩进。", usesFirstLineIndent: true)
                == "　　已经缩进。"
        )
        #expect(
            ReaderParagraphFormatter.format("  已经留白。", usesFirstLineIndent: true)
                == "  已经留白。"
        )
        #expect(ReaderParagraphFormatter.format("", usesFirstLineIndent: true).isEmpty)
        #expect(
            ReaderParagraphFormatter.format("关闭缩进。", usesFirstLineIndent: false)
                == "关闭缩进。"
        )
    }

    @Test
    func readerPresetsUseBoundedNovelReadingValues() {
        #expect(ReaderLineSpacingPreset.compact.value == 5)
        #expect(ReaderLineSpacingPreset.comfortable.value == 8)
        #expect(ReaderLineSpacingPreset.spacious.value == 12)
        #expect(ReaderLineSpacingPreset.closest(to: 9) == .comfortable)

        #expect(ReaderContentWidthPreset.narrow.value == 720)
        #expect(ReaderContentWidthPreset.medium.value == 1_040)
        #expect(ReaderContentWidthPreset.wide.value == 1_600)
        #expect(ReaderContentWidthPreset.closest(to: 940) == .medium)
    }

    @Test
    func readerWidthUsesViewportWithoutGrowingPastPreference() {
        #expect(
            ReaderViewportLayout.effectiveContentWidth(preferredWidth: 1_040, viewportWidth: 1_500) == 1_040
        )
        #expect(
            ReaderViewportLayout.effectiveContentWidth(preferredWidth: 1_040, viewportWidth: 800) == 720
        )
        #expect(
            ReaderViewportLayout.effectiveContentWidth(preferredWidth: 2_000, viewportWidth: 2_000) == 1_800
        )
    }

    @Test
    func migratesOnlyKnownReaderDefaultsOnce() throws {
        let suiteName = "ReaderPreferenceMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(680.0, forKey: ReaderPreferenceKeys.contentWidth)
        defaults.set(9.0, forKey: ReaderPreferenceKeys.lineSpacing)
        defaults.set(18.0, forKey: ReaderPreferenceKeys.paragraphSpacing)

        ReaderPreferenceMigration.migrateIfNeeded(defaults: defaults)

        #expect(defaults.double(forKey: ReaderPreferenceKeys.contentWidth) == 1_040)
        #expect(defaults.double(forKey: ReaderPreferenceKeys.lineSpacing) == 8)
        #expect(defaults.double(forKey: ReaderPreferenceKeys.paragraphSpacing) == 12)

        defaults.set(940.0, forKey: ReaderPreferenceKeys.contentWidth)
        ReaderPreferenceMigration.migrateIfNeeded(defaults: defaults)
        #expect(defaults.double(forKey: ReaderPreferenceKeys.contentWidth) == 940)
    }

    @Test
    func customReaderPreferencesArePreservedAndClamped() throws {
        let suiteName = "ReaderPreferenceCustomTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(940.0, forKey: ReaderPreferenceKeys.contentWidth)
        defaults.set(7.0, forKey: ReaderPreferenceKeys.lineSpacing)
        defaults.set(50.0, forKey: ReaderPreferenceKeys.paragraphSpacing)

        ReaderPreferenceMigration.migrateIfNeeded(defaults: defaults)

        #expect(defaults.double(forKey: ReaderPreferenceKeys.contentWidth) == 940)
        #expect(defaults.double(forKey: ReaderPreferenceKeys.lineSpacing) == 7)
        #expect(defaults.double(forKey: ReaderPreferenceKeys.paragraphSpacing) == 36)
        #expect(ReaderTheme.dark.preferredColorScheme == .dark)
        #expect(ReaderTheme.sepia.preferredColorScheme == .light)
        #expect(ReaderTheme.system.preferredColorScheme == nil)
    }

    @Test
    func arrowKeyScrollingStaysWithinParagraphBounds() {
        #expect(
            ReaderKeyboardScroll.target(
                currentParagraphIndex: 2,
                fallbackParagraphIndex: 0,
                paragraphCount: 5,
                offset: 1
            ) == 3
        )
        #expect(
            ReaderKeyboardScroll.target(
                currentParagraphIndex: 0,
                fallbackParagraphIndex: 4,
                paragraphCount: 5,
                offset: -1
            ) == 0
        )
        #expect(
            ReaderKeyboardScroll.target(
                currentParagraphIndex: nil,
                fallbackParagraphIndex: 10,
                paragraphCount: 5,
                offset: 1
            ) == 4
        )
        #expect(
            ReaderKeyboardScroll.target(
                currentParagraphIndex: nil,
                fallbackParagraphIndex: 0,
                paragraphCount: 0,
                offset: 1
            ) == nil
        )
    }
}
