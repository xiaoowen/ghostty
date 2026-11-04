import Foundation
import Testing
@testable import Ghostty

@Suite
struct GUIConfigFileTests {
    @Test func rendersInKeyOrderWithFontFamilyReset() {
        let file = GUIConfigFile(values: [
            .fontSize: "14",
            .fontFamily: "JetBrains Mono",
            .theme: "light:Rose Pine Dawn,dark:Rose Pine",
            .cursorStyleBlink: "",
        ])
        #expect(file.render() == GUIConfigFile.header + """
            theme = "light:Rose Pine Dawn,dark:Rose Pine"
            cursor-style-blink =
            font-family = ""
            font-family = "JetBrains Mono"
            font-size = 14

            """)
    }

    @Test func emptyFontFamilyOnlyResets() {
        // Selecting the built-in font must drop config.ghostty's families.
        let file = GUIConfigFile(values: [.fontFamily: ""])
        #expect(file.render() == GUIConfigFile.header + "font-family = \"\"\n")
    }

    @Test func emptyFileHasOnlyHeader() {
        #expect(GUIConfigFile().render() == GUIConfigFile.header)
    }

    @Test(arguments: [
        [SettingKey.fontFamily: "Maple Mono", .fontSize: "13.5", .fontThicken: "true"],
        [.fontFamily: "", .theme: ""],
        [.theme: "Catppuccin Macchiato", .backgroundOpacity: "0.85", .backgroundBlur: "macos-glass-regular"],
        [.cursorStyle: "bar", .cursorStyleBlink: "false", .adjustCellHeight: "10%"],
    ])
    func roundTrips(values: [SettingKey: String]) {
        let file = GUIConfigFile(values: values)
        #expect(GUIConfigFile.parse(file.render()) == file)
    }

    @Test func rejectsValuesThatWouldBreakTheFile() {
        #expect(GUIConfigFile.isWritable("JetBrains Mono", for: .fontFamily))
        #expect(!GUIConfigFile.isWritable("a\"b", for: .fontFamily))
        #expect(!GUIConfigFile.isWritable("a\\b", for: .theme))
        #expect(!GUIConfigFile.isWritable("a\nfont-size = 99", for: .fontFamily))
    }
}

@Suite
struct ConfigTextTests {
    @Test func readsMainConfigIgnoringComments() {
        let text = """
            term = xterm-256color

            # theme = GitHub Light Default
            theme = Catppuccin Macchiato

            # 设置主字体
            font-family = Maple Mono NF CN
            # font-family = MesloLGS NF
            font-size = 13
            # font-thicken = true
            """
        #expect(ConfigText.values(in: text) == [
            .theme: "Catppuccin Macchiato",
            .fontFamily: "Maple Mono NF CN",
            .fontSize: "13",
        ])
    }

    @Test(arguments: [
        ("font-family = A\nfont-family = B", "A"),
        ("font-family = A\nfont-family = \"\"\nfont-family = C", "C"),
        ("font-family = A\nfont-family =", ""),
        ("font-family=\"Fira Code\"", "Fira Code"),
    ])
    func fontFamilyIsThePrimaryOfTheList(text: String, expected: String) {
        #expect(ConfigText.values(in: text)[.fontFamily] == expected)
    }

    @Test(arguments: [
        ("config-file = ?gui.ghostty", true),
        ("config-file=gui.ghostty", true),
        ("config-file = ?./gui.ghostty", true),
        ("config-file = ?/cfg/gui.ghostty", true),
        ("# config-file = ?gui.ghostty", false),
        ("config-file = ?other.ghostty", false),
        ("", false),
    ])
    func detectsInclude(text: String, included: Bool) {
        #expect(ConfigText.includesGUIFile(text, guiFilePath: "/cfg/gui.ghostty") == included)
    }

    @Test func appendsIncludeAfterExistingContent() {
        let added = ConfigText.addingGUIInclude(to: "font-size = 13")
        #expect(added.hasPrefix("font-size = 13\n\n# "))
        #expect(added.hasSuffix("\n" + GUIConfigFile.includeDirective + "\n"))
        #expect(ConfigText.includesGUIFile(added))
        #expect(ConfigText.addingGUIInclude(to: "").hasPrefix("# "))
        #expect(ConfigText.addingGUIInclude(to: "a = 1\n").hasPrefix("a = 1\n\n# "))
    }
}

@Suite
struct ThemeSelectionTests {
    @Test(arguments: [
        (nil, ThemeSelection.none),
        ("", .none),
        ("Rose Pine", .single("Rose Pine")),
        ("light:Rose Pine Dawn,dark:Rose Pine", .pair(light: "Rose Pine Dawn", dark: "Rose Pine")),
        (" dark: Rose Pine , light: Rose Pine Dawn ", .pair(light: "Rose Pine Dawn", dark: "Rose Pine")),
    ])
    func parses(value: String?, expected: ThemeSelection) {
        #expect(ThemeSelection(configValue: value) == expected)
    }

    @Test func configValueAndAppearance() {
        let pair = ThemeSelection.pair(light: "L", dark: "D")
        #expect(pair.configValue == "light:L,dark:D")
        #expect(pair.name(dark: true) == "D")
        #expect(pair.name(dark: false) == "L")
        #expect(ThemeSelection.single("S").name(dark: true) == "S")
        #expect(ThemeSelection.none.configValue == "")
    }
}

@Suite
struct ThemeCatalogTests {
    @Test func parsesColors() {
        let theme = ThemeInfo(name: "Rose Pine", text: """
            palette = 0=#26233a
            palette = 1=#eb6f92
            palette = 99=#ffffff
            background = #191724
            foreground = e0def4
            """)
        #expect(theme.background == ThemeColor(hex: "191724"))
        #expect(theme.foreground == ThemeColor(hex: "#e0def4"))
        #expect(theme.palette == [0: ThemeColor(hex: "#26233a")!, 1: ThemeColor(hex: "#eb6f92")!])
        #expect(theme.isDark)
        #expect(!ThemeInfo(name: "Dawn", text: "background = #faf4ed").isDark)
    }

    @Test func userThemesHideBundledOnesWithTheSameName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ThemeCatalogTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let user = root.appendingPathComponent("user")
        let bundled = root.appendingPathComponent("bundled")
        for dir in [user, bundled] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try "background = #ffffff".write(to: user.appendingPathComponent("Alpha"), atomically: true, encoding: .utf8)
        try "background = #000000".write(to: bundled.appendingPathComponent("Alpha"), atomically: true, encoding: .utf8)
        try "background = #000000".write(to: bundled.appendingPathComponent("beta"), atomically: true, encoding: .utf8)

        let themes = ThemeCatalog.load(from: [user, bundled, root.appendingPathComponent("missing")])
        #expect(themes.map(\.name) == ["Alpha", "beta"])
        #expect(themes.first?.isDark == false)
    }
}

@Suite
struct SettingsModelTests {
    /// A temporary config directory and a model wired to it.
    final class Fixture {
        let dir: URL
        let main: URL
        var problems: [String] = []
        var reloads = 0
        lazy var model = SettingsModel(environment: .init(
            mainConfigURL: { [main] in main },
            validate: { [unowned self] _ in self.problems },
            reload: { [unowned self] in self.reloads += 1 },
            loadThemes: { [] }
        ))

        init(main text: String?) throws {
            dir = FileManager.default.temporaryDirectory.appendingPathComponent("SettingsModelTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            main = dir.appendingPathComponent("config.ghostty")
            if let text { try text.write(to: main, atomically: true, encoding: .utf8) }
        }

        deinit { try? FileManager.default.removeItem(at: dir) }

        var guiText: String? { try? String(contentsOf: dir.appendingPathComponent("gui.ghostty"), encoding: .utf8) }
        var mainText: String? { try? String(contentsOf: main, encoding: .utf8) }
    }

    @Test func savesToGuiFileAndAsksForIncludeBeforeReloading() throws {
        let f = try Fixture(main: "# mine\nfont-size = 13\ntheme = A\n")
        let model = f.model
        #expect(model.value(.fontSize) == "13")
        #expect(model.value(.cursorStyle) == "block")
        #expect(model.includeMissing)

        model.set(.fontSize, "15")
        #expect(model.hasPendingSave)
        model.saveNow()
        #expect(f.guiText == GUIConfigFile.header + "font-size = 15\n")
        #expect(model.value(.fontSize) == "15" && model.isOverridden(.fontSize))
        // Without the include the change can't take effect, so don't reload.
        #expect(f.reloads == 0)

        model.addInclude()
        #expect(!model.includeMissing)
        #expect(f.reloads == 1)
        #expect(f.mainText?.hasPrefix("# mine\nfont-size = 13\ntheme = A\n") == true)
        #expect(f.mainText?.hasSuffix(GUIConfigFile.includeDirective + "\n") == true)

        model.set(.theme, "B")
        model.saveNow()
        #expect(f.reloads == 2)

        // Resetting falls back to config.ghostty's value.
        model.reset(.fontSize)
        model.saveNow()
        #expect(model.value(.fontSize) == "13" && !model.isOverridden(.fontSize))
        #expect(f.guiText == GUIConfigFile.header + "theme = \"B\"\n")
    }

    @Test func invalidValuesAreNotWritten() throws {
        let f = try Fixture(main: GUIConfigFile.includeDirective + "\n")
        let model = f.model
        model.set(.fontSize, "14")
        model.saveNow()
        let saved = f.guiText

        f.problems = ["/tmp/x: font-size: invalid"]
        model.set(.fontSize, "abc")
        model.saveNow()
        #expect(f.guiText == saved)
        #expect(model.saveError?.hasPrefix("设置未保存：") == true)
        #expect(f.reloads == 1)

        model.set(.fontFamily, "bad\"name")
        #expect(model.saveError == "font-family 的值不能包含引号、反斜杠或换行")
        #expect(!model.isOverridden(.fontFamily))
    }

    @Test func addIncludeAppendsThroughSymlinks() throws {
        let f = try Fixture(main: nil)
        let target = f.dir.appendingPathComponent("dotfiles-config")
        try "font-size = 12\n".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: f.main, withDestinationURL: target)

        f.model.set(.fontSize, "16")
        f.model.addInclude()

        let attributes = try FileManager.default.attributesOfItem(atPath: f.main.path)
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
        let targetText = try String(contentsOf: target, encoding: .utf8)
        #expect(targetText.hasPrefix("font-size = 12\n") && targetText.hasSuffix(GUIConfigFile.includeDirective + "\n"))
        #expect(f.guiText?.contains("font-size = 16") == true)
    }

    @Test func addIncludeCreatesMissingMainConfig() throws {
        let f = try Fixture(main: nil)
        f.model.addInclude()
        #expect(f.mainText?.hasSuffix(GUIConfigFile.includeDirective + "\n") == true)
        #expect(f.reloads == 1)
    }

    @Test func refreshKeepsUnsavedChanges() throws {
        let f = try Fixture(main: "font-size = 13\n")
        f.model.set(.fontSize, "20")
        try "font-size = 11\n".write(to: f.main, atomically: true, encoding: .utf8)
        f.model.refresh()
        #expect(f.model.value(.fontSize) == "20")
        #expect(f.model.fallbackValue(.fontSize) == "11")
    }
}

@Suite
struct SettingsFormatTests {
    @Test(arguments: [(1.0, "1"), (0.85, "0.85"), (0.851, "0.85"), (13.5, "13.5"), (1000, "1000")])
    func number(value: Double, expected: String) {
        #expect(SettingsFormat.number(value) == expected)
    }

    @Test func percent() {
        #expect(SettingsFormat.percent("10%") == 10)
        #expect(SettingsFormat.percent("-5%") == -5)
        #expect(SettingsFormat.percent("2") == nil)
        #expect(SettingsFormat.percent(nil) == nil)
    }
}

@Suite
struct SettingsModelPhase5Tests {
    @Test func windowKeysRenderInOrderAfterFontKeys() {
        let file = GUIConfigFile(values: [
            .windowPaddingX: "8", .windowWidth: "120", .windowHeight: "36",
            .macosTitlebarStyle: "tabs", .fontSize: "14", .windowPaddingBalance: "equal",
        ])
        #expect(file.render() == GUIConfigFile.header + """
            font-size = 14
            macos-titlebar-style = tabs
            window-width = 120
            window-height = 36
            window-padding-x = 8
            window-padding-balance = equal

            """)
        #expect(GUIConfigFile.parse(file.render()) == file)
    }

    @Test func configErrorsAndReload() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SettingsModelPhase5Tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let main = dir.appendingPathComponent("config.ghostty")
        try "window-padding-x = 2,4\n".write(to: main, atomically: true, encoding: .utf8)

        var errors = ["config.ghostty:1: unknown field"]
        var reloads = 0
        let model = SettingsModel(environment: .init(
            mainConfigURL: { main },
            validate: { _ in [] },
            reload: { reloads += 1 },
            loadThemes: { [] },
            configErrors: { errors }
        ))
        #expect(model.configErrors == ["config.ghostty:1: unknown field"])
        #expect(model.value(.windowPaddingX) == "2,4")
        #expect(model.value(.windowSaveState) == "default")

        errors = []
        model.reloadConfiguration()
        #expect(reloads == 1)
        model.refresh()
        #expect(model.configErrors.isEmpty)
    }
}
