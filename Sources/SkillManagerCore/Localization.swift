import Foundation

/// Looks up a user-facing string in this target's localization table.
/// Source strings are Simplified Chinese; `en.lproj` provides English.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
