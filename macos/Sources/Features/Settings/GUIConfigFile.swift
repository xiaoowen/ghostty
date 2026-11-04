import Foundation

/// A configuration option the Settings window can change.
///
/// The order of the cases is the order they're written to `gui.ghostty`.
enum SettingKey: String, CaseIterable {
    case theme
    case backgroundOpacity = "background-opacity"
    case backgroundBlur = "background-blur"
    case cursorStyle = "cursor-style"
    case cursorStyleBlink = "cursor-style-blink"
    case fontFamily = "font-family"
    case fontSize = "font-size"
    case fontThicken = "font-thicken"
    case adjustCellHeight = "adjust-cell-height"
    case macosTitlebarStyle = "macos-titlebar-style"
    case windowWidth = "window-width"
    case windowHeight = "window-height"
    case windowSaveState = "window-save-state"
    case windowPaddingX = "window-padding-x"
    case windowPaddingY = "window-padding-y"
    case windowPaddingBalance = "window-padding-balance"

    /// Ghostty's default, used when neither file sets the option. Nil means
    /// "unset" (e.g. no theme).
    var defaultValue: String? {
        switch self {
        case .theme: nil
        case .backgroundOpacity: "1"
        case .backgroundBlur: "false"
        case .cursorStyle: "block"
        case .cursorStyleBlink: ""
        case .fontFamily: ""
        case .fontSize: "13"
        case .fontThicken: "false"
        case .adjustCellHeight: "0%"
        case .macosTitlebarStyle: "transparent"
        case .windowWidth, .windowHeight: "0"
        case .windowSaveState: "default"
        case .windowPaddingX, .windowPaddingY: "2"
        case .windowPaddingBalance: "false"
        }
    }

    /// Values written as quoted strings.
    var isString: Bool {
        self == .theme || self == .fontFamily
    }
}

/// The Settings window's own config file, `gui.ghostty`, next to the main
/// config and pulled in from it with `config-file = ?gui.ghostty`.
///
/// Included files load after the file that includes them, so these values
/// win over the main config. The file is regenerated on every save, which is
/// why hand edits to it don't survive; the main config is never rewritten
/// apart from adding the include line once.
struct GUIConfigFile: Equatable {
    static let fileName = "gui.ghostty"
    static let includeDirective = "config-file = ?gui.ghostty"

    static let header = """
        # Written by Ghostty's Settings window (设置页). It is regenerated on every
        # change, so edit config.ghostty instead. Values here override config.ghostty
        # because this file is included from it with: config-file = ?gui.ghostty

        """

    var values: [SettingKey: String] = [:]

    /// Whether `value` can be written for `key` without breaking the file.
    static func isWritable(_ value: String, for key: SettingKey) -> Bool {
        !value.contains { $0.isNewline || $0 == "\"" || $0 == "\\" }
    }

    func render() -> String {
        var lines: [String] = []
        for key in SettingKey.allCases {
            guard let value = values[key] else { continue }
            switch key {
            case .fontFamily:
                // font-family is a list and later lines append fallbacks, so
                // reset it first to replace what config.ghostty set.
                lines.append(#"font-family = """#)
                if !value.isEmpty { lines.append("font-family = \"\(value)\"") }
            default:
                let rendered = key.isString ? "\"\(value)\"" : value
                lines.append(value.isEmpty ? "\(key.rawValue) =" : "\(key.rawValue) = \(rendered)")
            }
        }
        return Self.header + lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    static func parse(_ text: String) -> GUIConfigFile {
        GUIConfigFile(values: ConfigText.values(in: text))
    }
}

/// Minimal reading of Ghostty's `key = value` config syntax for the options
/// in `SettingKey`.
enum ConfigText {
    /// The value each option ends up with when only this text is loaded
    /// (includes and themes aren't followed). For `font-family` this is the
    /// primary family, or "" when the list was reset and left empty.
    static func values(in text: String) -> [SettingKey: String] {
        var values: [SettingKey: String] = [:]
        var families: [String]?

        for (key, value) in entries(in: text) {
            guard let setting = SettingKey(rawValue: key) else { continue }
            if setting == .fontFamily {
                if value.isEmpty {
                    families = []
                } else {
                    families = (families ?? []) + [value]
                }
            } else {
                values[setting] = value
            }
        }

        if let families { values[.fontFamily] = families.first ?? "" }
        return values
    }

    /// Whether the text includes `gui.ghostty` with a `config-file` line.
    static func includesGUIFile(_ text: String, guiFilePath: String? = nil) -> Bool {
        entries(in: text).contains { key, value in
            guard key == "config-file" else { return false }
            var path = value
            if path.hasPrefix("?") { path = unquote(String(path.dropFirst())) }
            if path.hasPrefix("./") { path = String(path.dropFirst(2)) }
            if path == GUIConfigFile.fileName { return true }
            guard let guiFilePath else { return false }
            return (path as NSString).expandingTildeInPath == guiFilePath
        }
    }

    /// `text` with the include line for `gui.ghostty` appended.
    static func addingGUIInclude(to text: String) -> String {
        var result = text
        if !result.isEmpty && !result.hasSuffix("\n") { result += "\n" }
        if !result.isEmpty { result += "\n" }
        return result + "# 设置页（Settings window）的修改，放在最后以便覆盖上面的值\n"
            + GUIConfigFile.includeDirective + "\n"
    }

    /// `key = value` pairs in order, skipping comments and blank lines.
    static func entries(in text: String) -> [(String, String)] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"),
                  let equals = line.firstIndex(of: "=") else { return nil }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            return (key, unquote(value))
        }
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
    }
}

/// The `theme` option: none, one theme, or a light/dark pair.
enum ThemeSelection: Equatable {
    case none
    case single(String)
    case pair(light: String, dark: String)

    init(configValue: String?) {
        guard let value = configValue?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            self = .none
            return
        }

        var light: String?
        var dark: String?
        for part in value.split(separator: ",") {
            let piece = part.trimmingCharacters(in: .whitespaces)
            if piece.hasPrefix("light:") {
                light = piece.dropFirst("light:".count).trimmingCharacters(in: .whitespaces)
            } else if piece.hasPrefix("dark:") {
                dark = piece.dropFirst("dark:".count).trimmingCharacters(in: .whitespaces)
            }
        }

        if let light, let dark {
            self = .pair(light: light, dark: dark)
        } else {
            self = .single(value)
        }
    }

    var configValue: String {
        switch self {
        case .none: ""
        case .single(let name): name
        case .pair(let light, let dark): "light:\(light),dark:\(dark)"
        }
    }

    /// The theme in effect for an appearance.
    func name(dark isDark: Bool) -> String? {
        switch self {
        case .none: nil
        case .single(let name): name
        case .pair(let light, let dark): isDark ? dark : light
        }
    }
}
