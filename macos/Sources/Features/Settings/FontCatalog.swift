import AppKit

/// Font families offered by the Settings window.
enum FontCatalog {
    /// Families with at least one fixed-pitch member, sorted.
    static func monospacedFamilies() -> [String] {
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        let families = Set(names.compactMap { NSFont(name: $0, size: 12)?.familyName })
        return families.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Every installed family, sorted.
    static func allFamilies() -> [String] {
        NSFontManager.shared.availableFontFamilies
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func isInstalled(_ family: String) -> Bool {
        NSFontManager.shared.availableFontFamilies.contains(family)
    }
}
