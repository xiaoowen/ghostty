import AppKit
import SwiftUI

/// A one-line confirmation of what a tool just did, e.g. "防息屏已开启 · 不限时".
struct ToolsToastMessage: Equatable {
    var symbol: String
    var title: String
    var detail: String?
    /// Icon color; nil for the secondary label color.
    var tint: Color?

    init(symbol: String, title: String, detail: String? = nil, tint: Color? = nil) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.tint = tint
    }
}

/// Shows one message at a time at the top of the main window, then fades it
/// out. A new message replaces the current one. Use from the main thread only.
///
/// The message lives in a borderless child panel that ignores the mouse, so
/// it follows the window without touching the terminal's view hierarchy.
final class ToolsToast {
    static let shared = ToolsToast()

    private static let visibleSeconds: TimeInterval = 1.8

    /// Room around the message inside the panel for its shadow.
    private static let shadowMargin: CGFloat = 18

    private var panel: NSPanel?

    /// Bumped by every `show`, so a fade-out that a newer message interrupted
    /// doesn't hide that message when it completes.
    private var generation = 0

    /// Shows `message` in `window`, or in the main window when nil. Does
    /// nothing when Ghostty isn't the active app, since nobody would see it.
    func show(_ message: ToolsToastMessage, in window: NSWindow? = nil) {
        guard let parent = window ?? Self.targetWindow() else { return }

        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        generation += 1
        let shown = generation

        let host = NSHostingView(rootView: ToolsToastView(message: message, background: Self.backgroundColor))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host

        // Centered, just below the titlebar (and tab bar, toolbar).
        let contentTop = parent.frame.minY + parent.contentLayoutRect.maxY
        let visibleTop = contentTop - 8
        panel.setFrame(NSRect(
            x: (parent.frame.midX - size.width / 2).rounded(),
            y: (visibleTop + Self.shadowMargin - size.height).rounded(),
            width: size.width,
            height: size.height
        ), display: true)

        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            panel.alphaValue = 0
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleSeconds) { [weak self] in
            self?.hide(ifStill: shown)
        }
    }

    private func hide(ifStill shown: Int) {
        guard let panel, generation == shown else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == shown else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        })
    }

    /// The main window, or the key one, while Ghostty is active. Popovers and
    /// panels never become main, so a click in the keep-awake popover still
    /// lands in the terminal window it belongs to.
    private static func targetWindow() -> NSWindow? {
        guard NSApp.isActive else { return nil }
        return [NSApp.mainWindow, NSApp.keyWindow]
            .compactMap { $0 }
            .first { $0.isVisible && !($0 is NSPanel) }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        return panel
    }

    /// The terminal theme's background, like the command palette uses.
    private static var backgroundColor: NSColor {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return .windowBackgroundColor }
        return NSColor(appDelegate.ghostty.config.backgroundColor).withAlphaComponent(1)
    }
}

private struct ToolsToastView: View {
    let message: ToolsToastMessage
    let background: NSColor

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(message.tint ?? .secondary)
            Text(message.title)
                .font(.system(size: 13, weight: .semibold))
            if let detail = message.detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: background)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .tertiaryLabelColor).opacity(0.75))
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .padding(18)
        .environment(\.colorScheme, background.isLightColor ? .light : .dark)
    }
}
