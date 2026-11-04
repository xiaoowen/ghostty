import AppKit

/// A menu shortcut chosen by the user, e.g. ⌃⌘A.
struct ToolShortcut: Equatable {
    /// The key, lowercased, as in `NSEvent.charactersIgnoringModifiers`.
    var key: String

    /// Some of ⌃ ⌥ ⇧ ⌘. At least one of ⌃ ⌥ ⌘ is required so typing in a
    /// terminal never triggers it by accident.
    var modifiers: NSEvent.ModifierFlags

    static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    static let keepAwakeDefault = ToolShortcut(key: "a", modifiers: [.control, .command])

    init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.key = key.lowercased()
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    /// The shortcut for a key press, or nil if it can't be one (no ⌃ ⌥ ⌘,
    /// or not a single printable key).
    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(Self.relevantModifiers)
        guard !modifiers.isDisjoint(with: [.control, .option, .command]),
              let key = event.charactersIgnoringModifiers?.lowercased(),
              key.count == 1,
              let scalar = key.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              !CharacterSet.whitespacesAndNewlines.contains(scalar),
              // Function keys and arrows arrive as private-use characters.
              !(0xF700...0xF8FF).contains(scalar.value) else { return nil }
        self.init(key: key, modifiers: modifiers)
    }

    func matches(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(Self.relevantModifiers) == modifiers
            && event.charactersIgnoringModifiers?.lowercased() == key
    }

    /// e.g. ["⌃", "⌘", "A"], in the order macOS menus use.
    var symbols: [String] {
        var result: [String] = []
        if modifiers.contains(.control) { result.append("⌃") }
        if modifiers.contains(.option) { result.append("⌥") }
        if modifiers.contains(.shift) { result.append("⇧") }
        if modifiers.contains(.command) { result.append("⌘") }
        result.append(key.uppercased())
        return result
    }

    var displayString: String { symbols.joined() }

    // MARK: Storage, e.g. "ctrl+cmd+a"

    private static let names: [(String, NSEvent.ModifierFlags)] = [
        ("ctrl", .control), ("opt", .option), ("shift", .shift), ("cmd", .command),
    ]

    var storageValue: String {
        (Self.names.filter { modifiers.contains($0.1) }.map(\.0) + [key]).joined(separator: "+")
    }

    init?(storageValue: String) {
        var parts = storageValue.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // "+" itself as the key ends in an empty part.
        guard let last = parts.popLast() else { return nil }
        let key = last.isEmpty && storageValue.hasSuffix("++") ? "+" : last
        var modifiers: NSEvent.ModifierFlags = []
        for part in parts where !part.isEmpty {
            guard let flag = Self.names.first(where: { $0.0 == part })?.1 else { return nil }
            modifiers.insert(flag)
        }
        guard key.count == 1, !modifiers.isDisjoint(with: [.control, .option, .command]) else { return nil }
        self.init(key: key, modifiers: modifiers)
    }
}

/// Preferences for the Tools menu, stored in Ghostty's user defaults.
/// Use from the main thread only.
final class ToolsPreferences: ObservableObject {
    static let shared = ToolsPreferences(defaults: .ghostty)

    private static let shortcutKey = "KeepAwakeShortcut"
    private static let onLaunchKey = "KeepAwakeOnLaunch"

    /// Toggles keep-awake. Nil means no shortcut.
    @Published var keepAwakeShortcut: ToolShortcut? {
        didSet {
            defaults.set(keepAwakeShortcut?.storageValue ?? "", forKey: Self.shortcutKey)
        }
    }

    /// Turn keep-awake on (untimed) when Ghostty starts.
    @Published var keepAwakeOnLaunch: Bool {
        didSet { defaults.set(keepAwakeOnLaunch, forKey: Self.onLaunchKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Self.shortcutKey) {
            // "" is an explicitly removed shortcut; garbage falls back to the default.
            keepAwakeShortcut = stored.isEmpty ? nil : (ToolShortcut(storageValue: stored) ?? .keepAwakeDefault)
        } else {
            keepAwakeShortcut = .keepAwakeDefault
        }
        keepAwakeOnLaunch = defaults.bool(forKey: Self.onLaunchKey)
    }
}
