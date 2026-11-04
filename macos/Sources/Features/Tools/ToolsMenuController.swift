import AppKit

/// The 「工具」 menu, starting with keep-awake.
///
/// The same tools are offered in the main menu, the Dock menu and the command
/// palette. All of them are built on demand from `KeepAwake.shared`, so they
/// always show the current state (the checkmark, the remaining time).
final class ToolsMenuController: NSObject, NSMenuDelegate {
    static let shared = ToolsMenuController()

    /// Shortcut for toggling keep-awake (⌃⌘A). Ghostty keybinds still win,
    /// since the terminal only passes unbound key equivalents to the menu.
    static let keepAwakeKeyEquivalent = "a"
    static let keepAwakeModifiers: NSEvent.ModifierFlags = [.control, .command]
    static let keepAwakeSymbols = ["⌃", "⌘", "A"]

    let menu = NSMenu(title: "工具")
    private let keepAwake: KeepAwake

    init(keepAwake: KeepAwake = .shared) {
        self.keepAwake = keepAwake
        super.init()
        menu.delegate = self
    }

    /// Adds the 「工具」 menu to the main menu bar before the Window menu and
    /// starts the menu bar indicator. Safe to call more than once.
    func install() {
        guard let mainMenu = NSApp.mainMenu,
              !mainMenu.items.contains(where: { $0.submenu === menu }) else { return }

        // Populate now so the shortcut works before the menu is first opened.
        rebuild(menu)

        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        let index = mainMenu.items.firstIndex { $0.submenu === NSApp.windowsMenu }
            ?? mainMenu.items.firstIndex { $0.submenu === NSApp.helpMenu }
            ?? mainMenu.items.count
        mainMenu.insertItem(item, at: index)

        KeepAwakeStatusItem.shared.start(observing: keepAwake)
    }

    /// Items to append to the Dock menu.
    func dockMenuItems() -> [NSMenuItem] {
        [.separator()] + makeItems(forDock: true)
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    /// Answers key equivalent lookups without repopulating the menu. Without
    /// this AppKit calls `menuNeedsUpdate` (rebuilding every item) for every
    /// unbound shortcut typed in a terminal. AppKit still
    /// searches the existing items after a `false`; ⌃⌘A is answered here
    /// explicitly so it doesn't depend on that.
    func menuHasKeyEquivalent(
        _ menu: NSMenu,
        for event: NSEvent,
        target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
        action: UnsafeMutablePointer<Selector?>
    ) -> Bool {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        guard menu === self.menu,
              modifiers == Self.keepAwakeModifiers,
              event.charactersIgnoringModifiers?.lowercased() == Self.keepAwakeKeyEquivalent else {
            return false
        }
        target.pointee = self
        action.pointee = #selector(toggleKeepAwake(_:))
        return true
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in makeItems(forDock: false) {
            menu.addItem(item)
        }
    }

    // MARK: Menu items

    private func makeItems(forDock: Bool) -> [NSMenuItem] {
        [keepAwakeToggleItem(withShortcut: !forDock), keepAwakeTimerItem()]
    }

    private func keepAwakeToggleItem(withShortcut: Bool) -> NSMenuItem {
        var title = "防息屏"
        if keepAwake.endDate != nil, let remaining = keepAwake.remainingText {
            title += "（\(remaining)）"
        }

        let item = NSMenuItem(
            title: title,
            action: #selector(toggleKeepAwake(_:)),
            keyEquivalent: withShortcut ? Self.keepAwakeKeyEquivalent : ""
        )
        if withShortcut {
            item.keyEquivalentModifierMask = Self.keepAwakeModifiers
        }
        item.target = self
        item.state = keepAwake.isOn ? .on : .off
        item.toolTip = "用 caffeinate -d 阻止显示器休眠，Ghostty 退出时自动结束"
        item.setImageIfDesired(systemSymbolName: "cup.and.saucer")
        return item
    }

    private func keepAwakeTimerItem() -> NSMenuItem {
        let submenu = NSMenu(title: "定时防息屏")

        for preset in KeepAwake.Preset.allCases where preset.seconds != nil {
            let item = NSMenuItem(
                title: "开启 \(preset.title)",
                action: #selector(startKeepAwakePreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset
            submenu.addItem(item)
        }

        if keepAwake.endDate != nil {
            submenu.addItem(.separator())
            let extend = NSMenuItem(title: "延长 1 小时", action: #selector(extendKeepAwake(_:)), keyEquivalent: "")
            extend.target = self
            submenu.addItem(extend)
        }

        submenu.addItem(.separator())
        let system = NSMenuItem(
            title: "同时阻止系统休眠",
            action: #selector(togglePreventSystemSleep(_:)),
            keyEquivalent: ""
        )
        system.target = self
        system.state = keepAwake.preventSystemSleep ? .on : .off
        system.toolTip = "额外传入 caffeinate -i。合上屏幕仍会休眠。"
        submenu.addItem(system)

        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        item.setImageIfDesired(systemSymbolName: "timer")
        return item
    }

    // MARK: Command palette

    /// Tool commands for the terminal command palette.
    func paletteOptions() -> [CommandOption] {
        var options: [CommandOption] = []
        let keepAwake = keepAwake

        if keepAwake.isOn {
            options.append(CommandOption(
                title: "防息屏：关闭",
                subtitle: keepAwake.remainingText.map { "已开启 · \($0)" },
                symbols: Self.keepAwakeSymbols,
                leadingIcon: "cup.and.saucer.fill"
            ) {
                keepAwake.stop()
            })
            if keepAwake.endDate != nil {
                options.append(CommandOption(title: "防息屏：延长 1 小时", leadingIcon: "timer") {
                    keepAwake.extend(by: 60 * 60)
                })
            }
        } else {
            options.append(CommandOption(
                title: "防息屏：开启",
                subtitle: "直到手动关闭或 Ghostty 退出",
                symbols: Self.keepAwakeSymbols,
                leadingIcon: "cup.and.saucer"
            ) {
                keepAwake.start(.indefinite)
            })
        }

        for preset in KeepAwake.Preset.allCases where preset.seconds != nil {
            options.append(CommandOption(title: "防息屏：开启 \(preset.title)", leadingIcon: "timer") {
                keepAwake.start(preset)
            })
        }

        return options
    }

    // MARK: Actions

    @objc private func toggleKeepAwake(_ sender: Any?) {
        keepAwake.toggle()
    }

    @objc private func startKeepAwakePreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? KeepAwake.Preset else { return }
        keepAwake.start(preset)
    }

    @objc private func extendKeepAwake(_ sender: Any?) {
        keepAwake.extend(by: 60 * 60)
    }

    @objc private func togglePreventSystemSleep(_ sender: Any?) {
        keepAwake.preventSystemSleep.toggle()
    }
}
