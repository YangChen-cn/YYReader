import Foundation

enum ReaderPreferenceMigration {
    static let currentVersion = 4

    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        let storedVersion = defaults.integer(forKey: ReaderPreferenceKeys.preferenceVersion)
        guard storedVersion < currentVersion else {
            return
        }

        if defaults.string(forKey: ReaderPreferenceKeys.theme) == "ivory" {
            defaults.set(ReaderTheme.rose.rawValue, forKey: ReaderPreferenceKeys.theme)
        }

        if storedVersion < 4 {
            let storedFontSize = defaults.double(forKey: ReaderPreferenceKeys.fontSize)
            let fontSize = storedFontSize > 0 ? storedFontSize : 20
            migratePointValueToEM(
                key: ReaderPreferenceKeys.contentWidth,
                knownDefaults: [680, 720, 880, 1_040, 1_600],
                recommendedValue: ReaderViewportLayout.defaultPreferredWidthEM,
                validRange: ReaderViewportLayout.minimumPreferredWidthEM...ReaderViewportLayout.maximumPreferredWidthEM,
                fontSize: fontSize,
                defaults: defaults
            )
            migratePointValueToEM(
                key: ReaderPreferenceKeys.lineSpacing,
                knownDefaults: [8, 9],
                recommendedValue: ReaderLineSpacingPreset.comfortable.value,
                validRange: 0.20...0.65,
                fontSize: fontSize,
                defaults: defaults
            )
            migratePointValueToEM(
                key: ReaderPreferenceKeys.paragraphSpacing,
                knownDefaults: [12, 18],
                recommendedValue: 0.60,
                validRange: 0.35...0.90,
                fontSize: fontSize,
                defaults: defaults
            )
        }

        defaults.set(currentVersion, forKey: ReaderPreferenceKeys.preferenceVersion)
    }

    private static func migratePointValueToEM(
        key: String,
        knownDefaults: Set<Double>,
        recommendedValue: Double,
        validRange: ClosedRange<Double>,
        fontSize: Double,
        defaults: UserDefaults
    ) {
        guard let storedValue = defaults.object(forKey: key) as? NSNumber else {
            defaults.set(recommendedValue, forKey: key)
            return
        }

        let pointValue = storedValue.doubleValue
        let value = knownDefaults.contains(pointValue) ? recommendedValue : pointValue / fontSize
        defaults.set(min(max(value, validRange.lowerBound), validRange.upperBound), forKey: key)
    }
}
