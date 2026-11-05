import AppKit

/// Keeps a SwiftUI window from focusing its first control by itself.
///
/// With keyboard navigation turned on, SwiftUI focuses the first focusable
/// view (in Settings, the 外观 sidebar row) whenever nothing is focused and
/// the window becomes key or is clicked: when it opens, when a font or theme
/// picker button is clicked, when a popover or sheet gives key status back.
/// The focus ring then shows up on a row nobody chose. Such focus is cleared,
/// so a ring appears only once Tab is pressed. Focus moved with Tab, and text
/// fields clicked into, are kept.
final class AutomaticFocusSuppressor {
    private weak var window: NSWindow?
    private var firstResponderObservation: NSKeyValueObservation?
    private var eventMonitor: Any?

    /// Whether the user is moving the focus with the keyboard: set by Tab,
    /// cleared by a click.
    private var isKeyboardFocus = false

    private static let tabKeyCode: UInt16 = 48

    init(window: NSWindow) {
        self.window = window

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.type == .leftMouseDown {
                self.isKeyboardFocus = false
            } else if event.keyCode == Self.tabKeyCode {
                self.isKeyboardFocus = true
            }
            return event
        }

        firstResponderObservation = window.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
            self?.firstResponderDidChange(in: window)
        }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    /// For a window that's being opened: start over without keyboard focus,
    /// whatever was focused when it closed. Call before showing it.
    func reset() {
        isKeyboardFocus = false
    }

    /// Clears automatic focus right away. For just after the window is shown:
    /// SwiftUI focuses the first row while showing it, and the deferred clear
    /// would come after the window's first frame.
    func clearAutomaticFocus() {
        guard let window, let responder = automaticFocus(in: window) else { return }
        if window.firstResponder === responder { window.makeFirstResponder(nil) }
    }

    private func firstResponderDidChange(in window: NSWindow) {
        guard let responder = automaticFocus(in: window) else { return }

        // Not from within AppKit's own first responder change.
        DispatchQueue.main.async { [weak window] in
            guard let window, window.firstResponder === responder else { return }
            window.makeFirstResponder(nil)
        }
    }

    /// The focused control, if SwiftUI focused it rather than the user.
    private func automaticFocus(in window: NSWindow) -> NSResponder? {
        guard !isKeyboardFocus,
              let responder = window.firstResponder,
              responder !== window,
              // The field editor of a text field the user clicked into.
              !(responder is NSText) else { return nil }
        return responder
    }
}
