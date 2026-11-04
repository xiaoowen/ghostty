import Foundation

/// An sRGB color from a theme file.
struct ThemeColor: Hashable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    /// Parses `#rrggbb` or `rrggbb`.
    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        red = UInt8((value >> 16) & 0xFF)
        green = UInt8((value >> 8) & 0xFF)
        blue = UInt8(value & 0xFF)
    }

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Whether text on this color should be dark, using the same formula as
    /// Ghostty's `NSColor.isLightColor` (perceived luminance above 0.5).
    var isLight: Bool {
        (0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue)) / 255 > 0.5
    }

    /// Relative luminance (WCAG), 0 for black to 1 for white.
    var luminance: Double {
        func channel(_ c: UInt8) -> Double {
            let v = Double(c) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

/// The colors of one theme, enough for a preview swatch.
struct ThemeInfo: Identifiable, Hashable {
    let name: String
    let background: ThemeColor?
    let foreground: ThemeColor?
    /// Palette entries 0–15 that the theme sets, by index.
    let palette: [Int: ThemeColor]

    var id: String { name }

    var isDark: Bool { (background?.luminance ?? 0) < 0.2 }

    init(name: String, text: String) {
        self.name = name
        var background: ThemeColor?
        var foreground: ThemeColor?
        var palette: [Int: ThemeColor] = [:]

        for (key, value) in ConfigText.entries(in: text) {
            switch key {
            case "background":
                background = ThemeColor(hex: value)
            case "foreground":
                foreground = ThemeColor(hex: value)
            case "palette":
                // palette = N=#rrggbb
                let parts = value.split(separator: "=", maxSplits: 1)
                if parts.count == 2, let index = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                   (0..<16).contains(index), let color = ThemeColor(hex: String(parts[1])) {
                    palette[index] = color
                }
            default:
                break
            }
        }

        self.background = background
        self.foreground = foreground
        self.palette = palette
    }
}

/// The themes Ghostty can load by name: the user's themes directory first,
/// then the ones bundled with the app, matching Ghostty's own search order.
enum ThemeCatalog {
    /// `$XDG_CONFIG_HOME/ghostty/themes` (default ~/.config) and
    /// `Ghostty.app/Contents/Resources/ghostty/themes`.
    static func directories(bundle: Bundle = .main) -> [URL] {
        var result: [URL] = []
        let environment = ProcessInfo.processInfo.environment
        let configHome: URL
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            configHome = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            configHome = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
        }
        result.append(configHome.appendingPathComponent("ghostty/themes", isDirectory: true))
        if let resources = bundle.resourceURL {
            result.append(resources.appendingPathComponent("ghostty/themes", isDirectory: true))
        }
        return result
    }

    /// All themes found in `directories`, sorted by name. A name found in an
    /// earlier directory hides the same name in later ones.
    static func load(from directories: [URL]) -> [ThemeInfo] {
        var byName: [String: ThemeInfo] = [:]
        for directory in directories {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for file in files {
                let name = file.lastPathComponent
                guard byName[name] == nil,
                      (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                      let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                byName[name] = ThemeInfo(name: name, text: text)
            }
        }
        return byName.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
