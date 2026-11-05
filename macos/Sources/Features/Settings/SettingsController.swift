import AppKit
import SwiftUI
import GhosttyKit

/// The Settings window (设置), opened with Ghostty → Preferences… (⌘,).
///
/// Changes are stored in `gui.ghostty` next to the main config; see
/// `GUIConfigFile` and `SettingsModel`.
final class SettingsController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsController()

    let model: SettingsModel
    let navigation = SettingsNavigation()
    private var configObserver: NSObjectProtocol?

    /// Keeps SwiftUI from focusing the 外观 sidebar row by itself.
    private var focusSuppressor: AutomaticFocusSuppressor?

    private init() {
        model = SettingsModel(environment: .live)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        // The content (painted in the terminal theme's colors) runs under a
        // transparent titlebar, like the terminal windows themselves.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 780, height: 540)
        window.contentView = NSHostingView(rootView: SettingsView(
            model: model,
            navigation: navigation,
            tools: .live
        ))
        window.center()
        window.setFrameAutosaveName("GhosttySettingsWindow")

        super.init(window: window)
        window.delegate = self
        focusSuppressor = AutomaticFocusSuppressor(window: window)

        // Pick up edits made to config.ghostty by hand (Reload Configuration).
        configObserver = NotificationCenter.default.addObserver(
            forName: .ghosttyConfigDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.model.refresh()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    /// Shows the window, switching to `page` if given.
    func show(page: SettingsPage? = nil) {
        // Opens with nothing focused, however it's opened (⌘, or the gear
        // in the host panel) and whatever was focused when it closed.
        let isOpening = !(window?.isVisible ?? false)
        if isOpening { focusSuppressor?.reset() }
        if let page { navigation.page = page }
        model.refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if isOpening { focusSuppressor?.clearAutomaticFocus() }
    }

    func windowWillClose(_ notification: Notification) {
        // Don't lose a change made just before closing.
        model.saveNow()
    }

    // MARK: Menu

    /// Points Preferences… (and so its ⌘, shortcut) at this window and adds
    /// "打开配置文件…" after it for the previous behaviour.
    static func installMenuItems(preferences: NSMenuItem?) {
        guard let preferences, let menu = preferences.menu else { return }
        preferences.target = SettingsMenuTarget.shared
        preferences.action = #selector(SettingsMenuTarget.openSettings(_:))

        let openConfig = #selector(AppDelegate.openConfig(_:))
        guard !menu.items.contains(where: { $0.action == openConfig }) else { return }
        let item = NSMenuItem(title: "打开配置文件…", action: openConfig, keyEquivalent: "")
        item.setImageIfDesired(systemSymbolName: "doc.text")
        menu.insertItem(item, at: menu.index(of: preferences) + 1)
    }
}

/// Menu target that creates the window only when it's first needed.
private final class SettingsMenuTarget: NSObject {
    static let shared = SettingsMenuTarget()

    @objc func openSettings(_ sender: Any?) {
        SettingsController.shared.show()
    }
}

extension SettingsModel.Environment {
    static var live: Self {
        Self(
            mainConfigURL: {
                #if DEBUG
                // Debug builds can load an alternative config; edit that one.
                if let path = ProcessInfo.processInfo.environment["GHOSTTY_CONFIG_PATH"], !path.isEmpty {
                    return URL(fileURLWithPath: path)
                }
                #endif
                // The file Ghostty itself opens for editing (created if missing).
                let path = Ghostty.AllocatedString(ghostty_config_open_path()).string
                if !path.isEmpty { return URL(fileURLWithPath: path) }
                return FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".config/ghostty/config.ghostty")
            },
            validate: GhosttyConfigValidator.diagnostics(forFileAt:),
            reload: {
                (NSApp.delegate as? AppDelegate)?.ghostty.reloadConfig()
            },
            loadThemes: {
                ThemeCatalog.load(from: ThemeCatalog.directories())
            },
            configErrors: {
                (NSApp.delegate as? AppDelegate)?.ghostty.config.errors ?? []
            },
            configColors: {
                guard let config = (NSApp.delegate as? AppDelegate)?.ghostty.config.config,
                      let background = configColor(config, "background"),
                      let foreground = configColor(config, "foreground") else { return nil }
                return (background, foreground)
            }
        )
    }
}

/// A color option of the running configuration.
private func configColor(_ config: ghostty_config_t, _ key: String) -> ThemeColor? {
    var color = ghostty_config_color_s()
    guard ghostty_config_get(config, &color, key, UInt(key.lengthOfBytes(using: .utf8))) else { return nil }
    return ThemeColor(red: color.r, green: color.g, blue: color.b)
}

/// Checks a config file with libghostty's own parser.
enum GhosttyConfigValidator {
    static func diagnostics(forFileAt url: URL) -> [String] {
        guard let config = ghostty_config_new() else { return ["无法创建配置对象"] }
        defer { ghostty_config_free(config) }

        ghostty_config_load_file(config, url.path)
        ghostty_config_finalize(config)

        let count = ghostty_config_diagnostics_count(config)
        return (0..<count).map { index in
            String(cString: ghostty_config_get_diagnostic(config, index).message)
        }
    }
}
