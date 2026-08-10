import Foundation

enum ReaderPreferenceMigration {
    static let currentVersion = 2

    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.integer(forKey: ReaderPreferenceKeys.preferenceVersion) < currentVersion else {
            return
        }

        migrateKnownDefault(
            key: ReaderPreferenceKeys.contentWidth,
            knownDefaults: [680, 720, 880],
            recommendedValue: ReaderViewportLayout.defaultPreferredWidth,
            validRange: ReaderViewportLayout.minimumPreferredWidth...ReaderViewportLayout.maximumPreferredWidth,
            defaults: defaults
        )
        migrateKnownDefault(
            key: ReaderPreferenceKeys.lineSpacing,
            knownDefaults: [9],
            recommendedValue: ReaderLineSpacingPreset.comfortable.value,
            validRange: 2...20,
            defaults: defaults
        )
        migrateKnownDefault(
            key: ReaderPreferenceKeys.paragraphSpacing,
            knownDefaults: [18],
            recommendedValue: 12,
            validRange: 8...36,
            defaults: defaults
        )

        defaults.set(currentVersion, forKey: ReaderPreferenceKeys.preferenceVersion)
    }

    private static func migrateKnownDefault(
        key: String,
        knownDefaults: Set<Double>,
        recommendedValue: Double,
        validRange: ClosedRange<Double>,
        defaults: UserDefaults
    ) {
        guard let storedValue = defaults.object(forKey: key) as? NSNumber else {
            defaults.set(recommendedValue, forKey: key)
            return
        }

        let value = storedValue.doubleValue
        if knownDefaults.contains(value) {
            defaults.set(recommendedValue, forKey: key)
        } else {
            defaults.set(min(max(value, validRange.lowerBound), validRange.upperBound), forKey: key)
        }
    }
}
