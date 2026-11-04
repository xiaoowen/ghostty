import Foundation

/// State behind the Settings window.
///
/// Every change is written to `gui.ghostty` shortly after it's made (sliders
/// produce many changes), after libghostty has validated the new file, and
/// then Ghostty reloads its configuration. Use from the main thread only.
final class SettingsModel: ObservableObject {
    /// What the model needs from the app, injectable for tests.
    struct Environment {
        /// The main config file, e.g. `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`.
        var mainConfigURL: () -> URL

        /// Problems libghostty reports for a config file. Empty means valid.
        var validate: (URL) -> [String]

        /// Reloads Ghostty's configuration.
        var reload: () -> Void

        /// Loads the theme list. Called once, off the main thread.
        var loadThemes: () -> [ThemeInfo]

        /// Problems in the configuration Ghostty is currently running with.
        var configErrors: () -> [String] = { [] }
    }

    /// Values in `gui.ghostty`, i.e. set from this window.
    @Published private(set) var overrides: [SettingKey: String] = [:]

    /// Values set in the main config file.
    @Published private(set) var baseline: [SettingKey: String] = [:]

    /// Whether the main config lacks `config-file = ?gui.ghostty`, in which
    /// case saved changes have no effect yet.
    @Published private(set) var includeMissing = false

    /// The last save problem, shown in the window.
    @Published private(set) var saveError: String?

    @Published private(set) var themes: [ThemeInfo] = []

    /// Errors in the loaded configuration, including ones not caused here.
    @Published private(set) var configErrors: [String] = []

    @Published private(set) var mainConfigURL: URL

    var guiConfigURL: URL {
        mainConfigURL.deletingLastPathComponent().appendingPathComponent(GUIConfigFile.fileName)
    }

    private let environment: Environment
    private let saveDelay: TimeInterval
    private var pendingSave: DispatchWorkItem?
    private var themesRequested = false

    init(environment: Environment, saveDelay: TimeInterval = 0.3) {
        self.environment = environment
        self.saveDelay = saveDelay
        self.mainConfigURL = environment.mainConfigURL()
        refresh()
    }

    /// Re-reads both files, e.g. when the window opens or the config changed
    /// elsewhere. Unsaved changes are kept.
    func refresh() {
        mainConfigURL = environment.mainConfigURL()
        let mainText = (try? String(contentsOf: mainConfigURL, encoding: .utf8)) ?? ""
        baseline = ConfigText.values(in: mainText)
        includeMissing = !ConfigText.includesGUIFile(mainText, guiFilePath: guiConfigURL.path)
        configErrors = environment.configErrors()

        if pendingSave == nil {
            let guiText = (try? String(contentsOf: guiConfigURL, encoding: .utf8)) ?? ""
            overrides = GUIConfigFile.parse(guiText).values
        }
    }

    func loadThemesIfNeeded() {
        guard !themesRequested else { return }
        themesRequested = true
        let load = environment.loadThemes
        DispatchQueue.global(qos: .userInitiated).async {
            let themes = load()
            DispatchQueue.main.async { self.themes = themes }
        }
    }

    // MARK: Values

    /// The value in effect: this window's, else the main config's, else
    /// Ghostty's default.
    func value(_ key: SettingKey) -> String? {
        overrides[key] ?? baseline[key] ?? key.defaultValue
    }

    func isOverridden(_ key: SettingKey) -> Bool {
        overrides[key] != nil
    }

    /// What the option falls back to when reset, for tooltips.
    func fallbackValue(_ key: SettingKey) -> String? {
        baseline[key] ?? key.defaultValue
    }

    func set(_ key: SettingKey, _ value: String) {
        guard GUIConfigFile.isWritable(value, for: key) else {
            saveError = "\(key.rawValue) 的值不能包含引号、反斜杠或换行"
            return
        }
        guard overrides[key] != value else { return }
        overrides[key] = value
        scheduleSave()
    }

    /// Removes this window's value so the main config's applies again.
    func reset(_ key: SettingKey) {
        guard overrides[key] != nil else { return }
        overrides[key] = nil
        scheduleSave()
    }

    func resetAll() {
        guard !overrides.isEmpty else { return }
        overrides = [:]
        scheduleSave()
    }

    // MARK: Saving

    private func scheduleSave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: item)
    }

    var hasPendingSave: Bool { pendingSave != nil }

    /// Writes pending changes now, e.g. when the window closes.
    func saveNow() {
        guard let pending = pendingSave else { return }
        pending.cancel()
        pendingSave = nil

        let text = GUIConfigFile(values: overrides).render()

        // Validate a copy first so a bad value never reaches the real file.
        let candidate = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-settings-\(UUID().uuidString).ghostty")
        defer { try? FileManager.default.removeItem(at: candidate) }
        do {
            try text.write(to: candidate, atomically: true, encoding: .utf8)
        } catch {
            saveError = "无法写入临时文件：\(error.localizedDescription)"
            return
        }

        let problems = environment.validate(candidate)
            .map { $0.replacingOccurrences(of: candidate.path, with: GUIConfigFile.fileName) }
        guard problems.isEmpty else {
            saveError = "设置未保存：" + problems.joined(separator: "；")
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: guiConfigURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: guiConfigURL, atomically: true, encoding: .utf8)
        } catch {
            saveError = "无法写入 \(guiConfigURL.path)：\(error.localizedDescription)"
            return
        }

        saveError = nil
        let mainText = (try? String(contentsOf: mainConfigURL, encoding: .utf8)) ?? ""
        includeMissing = !ConfigText.includesGUIFile(mainText, guiFilePath: guiConfigURL.path)
        if !includeMissing { environment.reload() }
    }

    /// Saves pending changes and reloads Ghostty's configuration, e.g. after
    /// editing config.ghostty by hand. `refresh()` follows via the
    /// config-changed notification.
    func reloadConfiguration() {
        saveNow()
        environment.reload()
    }

    /// Appends `config-file = ?gui.ghostty` to the main config and reloads.
    ///
    /// The file is appended to rather than rewritten so comments, formatting
    /// and symlinks (e.g. into a dotfiles repository) are left alone.
    func addInclude() {
        saveNow()

        let fileManager = FileManager.default
        let existing = (try? String(contentsOf: mainConfigURL, encoding: .utf8)) ?? ""
        guard !ConfigText.includesGUIFile(existing, guiFilePath: guiConfigURL.path) else {
            includeMissing = false
            environment.reload()
            return
        }

        let addition = String(ConfigText.addingGUIInclude(to: existing).dropFirst(existing.count))
        do {
            if fileManager.fileExists(atPath: mainConfigURL.path) {
                let handle = try FileHandle(forWritingTo: mainConfigURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(addition.utf8))
            } else {
                try fileManager.createDirectory(
                    at: mainConfigURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try addition.write(to: mainConfigURL, atomically: false, encoding: .utf8)
            }
        } catch {
            saveError = "无法修改 \(mainConfigURL.lastPathComponent)：\(error.localizedDescription)"
            return
        }

        includeMissing = false
        environment.reload()
    }
}

/// Formatting of numbers for config values.
enum SettingsFormat {
    /// "1", "0.85", "13.5" — no trailing zeros.
    static func number(_ value: Double, maxDecimals: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxDecimals
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Parses "10%" into 10. Nil for absolute values like "2".
    static func percent(_ value: String?) -> Double? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), value.hasSuffix("%") else { return nil }
        return Double(value.dropLast())
    }
}
