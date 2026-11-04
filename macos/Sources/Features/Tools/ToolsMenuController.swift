import AppKit

/// The 「工具」 menu: keep-awake and remote host sessions.
///
/// The same tools are offered in the main menu, the Dock menu and the command
/// palette. All three are built on demand from `KeepAwake.shared` and
/// `RemoteHostStore.shared`, so they always show the current state (the
/// checkmark, the remaining time, the host list as it is on disk).
final class ToolsMenuController: NSObject, NSMenuDelegate {
    static let shared = ToolsMenuController()

    /// Shortcut for toggling keep-awake (⌃⌘A). Ghostty keybinds still win,
    /// since the terminal only passes unbound key equivalents to the menu.
    static let keepAwakeKeyEquivalent = "a"
    static let keepAwakeModifiers: NSEvent.ModifierFlags = [.control, .command]
    static let keepAwakeSymbols = ["⌃", "⌘", "A"]

    let menu = NSMenu(title: "工具")
    private let keepAwake: KeepAwake
    private let hosts: RemoteHostStore

    /// Whether a Keychain password is saved for a host name.
    private let passwordSaved: (String) -> Bool

    /// Shows the dialog that saves a host's password.
    private let promptForPassword: (RemoteHost) -> Void

    init(
        keepAwake: KeepAwake = .shared,
        hosts: RemoteHostStore = .shared,
        passwordSaved: @escaping (String) -> Bool = { RemoteKeychain.hasPassword(account: $0) },
        promptForPassword: @escaping (RemoteHost) -> Void = RemotePasswordPrompt.run(for:)
    ) {
        self.keepAwake = keepAwake
        self.hosts = hosts
        self.passwordSaved = passwordSaved
        self.promptForPassword = promptForPassword
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
    /// this AppKit calls `menuNeedsUpdate` (re-reading the hosts file and the
    /// Keychain) for every unbound shortcut typed in a terminal. AppKit still
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
        var items = [keepAwakeToggleItem(withShortcut: !forDock), keepAwakeTimerItem()]
        items.append(.separator())
        items += RemoteSessionKind.allCases.map(remoteItem)
        if !forDock {
            items.append(editHostsItem())
            items.append(passwordsItem())
        }
        return items
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

    private func remoteItem(_ kind: RemoteSessionKind) -> NSMenuItem {
        let submenu = NSMenu(title: kind.menuTitle)

        switch hosts.state {
        case .missing:
            submenu.addItem(Self.disabledItem("尚未配置主机"))
        case .invalid(let message):
            submenu.addItem(Self.disabledItem("主机列表有误：\(message)"))
        case .loaded(let list):
            let usable = list.filter { $0.launch(for: kind) != nil }
            if usable.isEmpty {
                submenu.addItem(Self.disabledItem("没有可用于 \(kind.label) 的主机"))
            }
            for host in usable {
                let item = NSMenuItem(title: host.name, action: #selector(openRemote(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = RemoteMenuTarget(host: host, kind: kind)
                item.toolTip = host.displayCommand(for: kind)
                submenu.addItem(item)
            }
        }

        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        item.setImageIfDesired(systemSymbolName: kind.symbolName)
        return item
    }

    private func editHostsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "编辑主机列表…", action: #selector(editHosts(_:)), keyEquivalent: "")
        item.target = self
        item.toolTip = hosts.fileURL.path
        item.setImageIfDesired(systemSymbolName: "pencil")
        return item
    }

    /// Hosts whose sessions fill the password from the Keychain, with whether
    /// one is saved. Selecting a host opens the save/replace/delete dialog.
    private func passwordsItem() -> NSMenuItem {
        let submenu = NSMenu(title: "主机密码")
        let hostsWithPasswords = hosts.hosts.filter(\.usesKeychainPassword)
        if hostsWithPasswords.isEmpty {
            submenu.addItem(Self.disabledItem("没有需要自动填密码的主机"))
        }
        for host in hostsWithPasswords {
            let saved = passwordSaved(host.name)
            let item = NSMenuItem(
                title: "\(host.name)\(saved ? "" : "（未保存）")…",
                action: #selector(editPassword(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.state = saved ? .on : .off
            item.representedObject = host
            submenu.addItem(item)
        }

        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        item.toolTip = "保存在登录钥匙串中，服务名 \(RemoteKeychain.service)"
        item.setImageIfDesired(systemSymbolName: "key")
        return item
    }

    private static func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
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

        for host in hosts.hosts {
            for kind in RemoteSessionKind.allCases {
                guard let command = host.displayCommand(for: kind) else { continue }
                options.append(CommandOption(
                    title: "\(kind.label)：\(host.name)",
                    subtitle: command,
                    leadingIcon: kind.symbolName
                ) {
                    RemoteLauncher.open(host, kind: kind)
                })
            }

            if host.usesKeychainPassword {
                let promptForPassword = promptForPassword
                options.append(CommandOption(
                    title: "主机密码：\(host.name)",
                    subtitle: passwordSaved(host.name) ? "已保存在钥匙串" : "未保存",
                    leadingIcon: "key"
                ) {
                    promptForPassword(host)
                })
            }
        }

        options.append(CommandOption(
            title: "远程主机：编辑列表",
            subtitle: (hosts.fileURL.path as NSString).abbreviatingWithTildeInPath,
            leadingIcon: "pencil"
        ) { [weak self] in
            self?.editHostList()
        })

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

    @objc private func openRemote(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? RemoteMenuTarget else { return }
        RemoteLauncher.open(target.host, kind: target.kind)
    }

    @objc private func editPassword(_ sender: NSMenuItem) {
        guard let host = sender.representedObject as? RemoteHost else { return }
        promptForPassword(host)
    }

    @objc private func editHosts(_ sender: Any?) {
        editHostList()
    }

    /// Opens `remote-hosts.json` in an editor, creating it from a template
    /// the first time.
    func editHostList() {
        let url: URL
        do {
            url = try hosts.ensureFileExists()
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法创建主机列表"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }

        NSWorkspace.shared.openInTextEditor(url)
    }
}

private struct RemoteMenuTarget {
    let host: RemoteHost
    let kind: RemoteSessionKind
}
