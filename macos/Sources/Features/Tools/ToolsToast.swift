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

    /// The message on screen, if any.
    private var state: ToolsToastState?

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

        // A replacement takes the place of the message on screen; otherwise
        // the message drops in. SwiftUI animates it inside a panel that stays
        // put, which keeps the glass and the motion in one animation.
        let isReplacing = panel.parent === parent && self.state?.isShown == true
        let state = ToolsToastState(message: message, isShown: isReplacing)
        self.state = state

        let background = Self.backgroundColor
        // Light or dark like the terminal, not the system, so the glass and
        // the text agree with each other and with the window below.
        panel.appearance = NSAppearance(named: background.isLightColor ? .aqua : .darkAqua)
        let host = NSHostingView(rootView: ToolsToastView(state: state, background: background))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host

        // Centered, just below the titlebar (and tab bar, toolbar).
        let contentTop = parent.frame.minY + parent.contentLayoutRect.maxY
        let visibleTop = contentTop - 10
        panel.setFrame(NSRect(
            x: (parent.frame.midX - size.width / 2).rounded(),
            y: (visibleTop + Self.shadowMargin - size.height).rounded(),
            width: size.width,
            height: size.height
        ), display: true)

        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)

        if !isReplacing {
            // After the hidden state has been drawn once.
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { state.isShown = true }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleSeconds) { [weak self] in
            self?.hide(ifStill: shown)
        }
    }

    private func hide(ifStill shown: Int) {
        guard let panel, let state, generation == shown else { return }
        withAnimation(.easeIn(duration: 0.22)) { state.isShown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.generation == shown else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
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

/// The message a toast shows and whether it's on screen, which animates.
private final class ToolsToastState: ObservableObject {
    let message: ToolsToastMessage
    @Published var isShown: Bool

    init(message: ToolsToastMessage, isShown: Bool) {
        self.message = message
        self.isShown = isShown
    }
}

private struct ToolsToastView: View {
    @ObservedObject var state: ToolsToastState
    let background: NSColor

    var body: some View {
        let message = state.message
        HStack(spacing: 8) {
            Image(systemName: message.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(message.tint == nil ? .secondary : .white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(message.tint ?? Color.primary.opacity(0.1)))
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
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .modifier(ToolsToastBackground(color: Color(nsColor: background)))
        // Hidden: a little higher and smaller, so it drops in from under the
        // titlebar.
        .scaleEffect(state.isShown ? 1 : 0.94, anchor: .top)
        .offset(y: state.isShown ? 0 : -6)
        .opacity(state.isShown ? 1 : 0)
        .padding(18)
        .environment(\.colorScheme, background.isLightColor ? .light : .dark)
    }
}

/// A capsule in the terminal's background color: Liquid Glass tinted with it
/// on macOS 26 and later, solid before.
private struct ToolsToastBackground: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(Glass.regular.tint(color.opacity(0.65)), in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        } else {
            solid(content)
        }
        #else
        solid(content)
        #endif
    }

    private func solid(_ content: Content) -> some View {
        content
            .background(Capsule().fill(color))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14)))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}
