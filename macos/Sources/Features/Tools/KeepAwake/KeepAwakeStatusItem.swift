import AppKit
import Combine

/// A ☕ item in the system menu bar, shown only while keep-awake is on.
///
/// It stays visible when Ghostty isn't the frontmost app. Forgetting that
/// keep-awake is on is the costly mistake, so this is the main indicator;
/// the Tools menu checkmark is secondary.
final class KeepAwakeStatusItem: NSObject, NSMenuDelegate {
    static let shared = KeepAwakeStatusItem()

    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?
    private weak var keepAwake: KeepAwake?

    var isVisible: Bool { statusItem != nil }

    func start(observing keepAwake: KeepAwake) {
        guard cancellable == nil else { return }
        self.keepAwake = keepAwake
        cancellable = keepAwake.$isOn
            .removeDuplicates()
            .sink { [weak self] isOn in self?.setVisible(isOn) }
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                button.image = NSImage(
                    systemSymbolName: "cup.and.saucer.fill",
                    accessibilityDescription: "防息屏已开启"
                )
                button.toolTip = "Ghostty 防息屏已开启"
            }
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let keepAwake else { return }

        let status = NSMenuItem(
            title: "Ghostty 防息屏 · \(keepAwake.remainingText ?? "未开启")",
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if keepAwake.endDate != nil {
            let extend = NSMenuItem(title: "延长 1 小时", action: #selector(extend(_:)), keyEquivalent: "")
            extend.target = self
            menu.addItem(extend)
        }

        let off = NSMenuItem(title: "关闭防息屏", action: #selector(turnOff(_:)), keyEquivalent: "")
        off.target = self
        menu.addItem(off)
    }

    @objc private func extend(_ sender: Any?) {
        keepAwake?.extend(by: 60 * 60)
    }

    @objc private func turnOff(_ sender: Any?) {
        keepAwake?.stop()
    }
}
