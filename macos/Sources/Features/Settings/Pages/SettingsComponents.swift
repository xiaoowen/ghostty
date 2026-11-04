import AppKit
import SwiftUI

// MARK: - Terminal colors

/// The colors of the terminal theme in effect. The Settings window is
/// painted with them, the way the command palette takes on the terminal's
/// background, so it reads as part of Ghostty rather than a generic panel.
struct TerminalColors: Equatable {
    var background: ThemeColor
    var foreground: ThemeColor
    var palette: [Int: ThemeColor]

    /// Ghostty's built-in colors (src/config/Config.zig, src/terminal/color.zig).
    static let ghosttyDefault = TerminalColors(
        background: ThemeColor(red: 0x28, green: 0x2C, blue: 0x34),
        foreground: ThemeColor(red: 0xFF, green: 0xFF, blue: 0xFF),
        palette: [
            0: ThemeColor(red: 0x1D, green: 0x1F, blue: 0x21), 1: ThemeColor(red: 0xCC, green: 0x66, blue: 0x66),
            2: ThemeColor(red: 0xB5, green: 0xBD, blue: 0x68), 3: ThemeColor(red: 0xF0, green: 0xC6, blue: 0x74),
            4: ThemeColor(red: 0x81, green: 0xA2, blue: 0xBE), 5: ThemeColor(red: 0xB2, green: 0x94, blue: 0xBB),
            6: ThemeColor(red: 0x8A, green: 0xBE, blue: 0xB7), 7: ThemeColor(red: 0xC5, green: 0xC8, blue: 0xC6),
            8: ThemeColor(red: 0x66, green: 0x66, blue: 0x66), 9: ThemeColor(red: 0xD5, green: 0x4E, blue: 0x53),
            10: ThemeColor(red: 0xB9, green: 0xCA, blue: 0x4A), 11: ThemeColor(red: 0xE7, green: 0xC5, blue: 0x47),
            12: ThemeColor(red: 0x7A, green: 0xA6, blue: 0xDA), 13: ThemeColor(red: 0xC3, green: 0x97, blue: 0xD8),
            14: ThemeColor(red: 0x70, green: 0xC0, blue: 0xB1), 15: ThemeColor(red: 0xEA, green: 0xEA, blue: 0xEA),
        ]
    )

    /// A theme's colors, with anything it doesn't set taken from `fallback`.
    init(theme: ThemeInfo?, fallback: TerminalColors = .ghosttyDefault) {
        background = theme?.background ?? fallback.background
        foreground = theme?.foreground ?? fallback.foreground
        palette = fallback.palette.merging(theme?.palette ?? [:]) { _, new in new }
    }

    init(background: ThemeColor, foreground: ThemeColor, palette: [Int: ThemeColor]) {
        self.background = background
        self.foreground = foreground
        self.palette = palette
    }

    var isLight: Bool { background.isLight }
    var colorScheme: ColorScheme { isLight ? .light : .dark }

    var backgroundColor: Color { Color(themeColor: background) }
    var foregroundColor: Color { Color(themeColor: foreground) }

    func color(_ index: Int) -> Color {
        palette[index].map { Color(themeColor: $0) } ?? foregroundColor
    }
}

private struct TerminalColorsKey: EnvironmentKey {
    static let defaultValue = TerminalColors.ghosttyDefault
}

private struct SystemIsDarkKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var terminalColors: TerminalColors {
        get { self[TerminalColorsKey.self] }
        set { self[TerminalColorsKey.self] = newValue }
    }

    /// The system (app) appearance, which picks the light or dark theme of a
    /// pair. `colorScheme` follows the terminal colors instead.
    var systemIsDark: Bool {
        get { self[SystemIsDarkKey.self] }
        set { self[SystemIsDarkKey.self] = newValue }
    }
}

extension Color {
    init(themeColor color: ThemeColor) {
        self.init(
            .sRGB,
            red: Double(color.red) / 255,
            green: Double(color.green) / 255,
            blue: Double(color.blue) / 255,
            opacity: 1
        )
    }
}

/// Keeps the hosting window's appearance in step with the terminal colors so
/// the titlebar, popovers and sheets match the content.
struct WindowAppearanceSetter: NSViewRepresentable {
    let isDark: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        DispatchQueue.main.async { nsView.window?.appearance = appearance }
    }
}

// MARK: - Building blocks

/// A rounded, colored square with a white symbol, like System Settings.
struct IconTile: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundColor(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
    }
}

/// Title and description at the top of a page.
struct SettingsPageHeader<Trailing: View>: View {
    let page: SettingsPage
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconTile(symbol: page.symbolName, colors: page.tileColors, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title)
                    .font(.system(size: 22, weight: .bold))
                Text(page.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            trailing()
        }
    }
}

extension SettingsPageHeader where Trailing == EmptyView {
    init(page: SettingsPage) {
        self.init(page: page) { EmptyView() }
    }
}

/// A titled group of rows on a rounded card.
struct SettingsSection<Content: View>: View {
    let title: String?
    var footer: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }

            VStack(spacing: 0, content: content)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09))
                )

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The line between two rows of a `SettingsSection`.
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 14)
    }
}

/// A row with a title, an optional note and a control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var note: String?
    var isModified = false
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                    if isModified { ModifiedBadge() }
                }
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 44)
    }
}

/// A row for one config option: marked when this window changed it, with a
/// button that goes back to config.ghostty's value.
struct SettingRow<Control: View>: View {
    @ObservedObject var model: SettingsModel
    let title: String
    let key: SettingKey
    var note: String?
    @ViewBuilder let control: () -> Control

    var body: some View {
        SettingsRow(title: title, note: note, isModified: model.isOverridden(key)) {
            HStack(spacing: 8) {
                control()
                SettingResetButton(model: model, keys: [key])
            }
        }
    }
}

/// "已修改", in the command palette's badge style.
struct ModifiedBadge: View {
    var body: some View {
        Text("已修改")
            .font(.caption2.weight(.medium))
            .foregroundColor(.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
    }
}

struct SettingResetButton: View {
    @ObservedObject var model: SettingsModel
    let keys: [SettingKey]

    private var isOverridden: Bool { keys.contains(where: model.isOverridden) }

    var body: some View {
        let fallback = keys.compactMap { model.fallbackValue($0) }
            .map { $0.isEmpty ? "默认" : $0 }
            .joined(separator: " × ")
        Button {
            keys.forEach(model.reset)
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("恢复为 config.ghostty 中的值：\(fallback.isEmpty ? "未设置" : fallback)")
        // Keep the column aligned when there's nothing to reset.
        .opacity(isOverridden ? 1 : 0)
        .disabled(!isOverridden)
        .accessibilityHidden(!isOverridden)
    }
}

/// A notice card, e.g. that changes aren't in effect yet.
struct SettingsBanner: View {
    let symbol: String
    let tint: Color
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tint)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.regular)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.35)))
    }
}

/// A small capsule label, e.g. "已存密码".
struct CapsuleLabel: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .foregroundColor(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

// MARK: - Theme previews

/// A miniature terminal in a theme's colors, used for theme cards. Its
/// contents scale with the space it's given.
struct ThemeSwatch: View {
    let theme: ThemeInfo?

    var body: some View {
        let colors = TerminalColors(theme: theme)
        GeometryReader { geometry in
            let unit = max(2, min(geometry.size.height / 8, geometry.size.width / 18))
            ZStack(alignment: .topLeading) {
                colors.backgroundColor
                VStack(alignment: .leading, spacing: unit * 0.9) {
                    HStack(spacing: unit * 0.8) {
                        bar(colors.color(2), width: unit * 2.5, unit: unit)
                        bar(colors.color(4), width: unit * 4.5, unit: unit)
                        bar(colors.foregroundColor.opacity(0.85), width: unit * 3.5, unit: unit)
                    }
                    HStack(spacing: unit * 0.8) {
                        bar(colors.color(5), width: unit * 3.5, unit: unit)
                        bar(colors.foregroundColor.opacity(0.6), width: unit * 6, unit: unit)
                    }
                    HStack(spacing: unit * 0.5) {
                        ForEach(1...6, id: \.self) { index in
                            RoundedRectangle(cornerRadius: unit * 0.3)
                                .fill(colors.color(index))
                                .frame(width: unit * 1.3, height: unit * 1.3)
                        }
                    }
                }
                .padding(unit * 1.4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
    }

    private func bar(_ color: Color, width: CGFloat, unit: CGFloat) -> some View {
        Capsule().fill(color).frame(width: width, height: unit * 0.8)
    }
}

/// A searchable list in a popover, used for fonts.
struct SearchableList<Item: Identifiable, Row: View, Header: View>: View {
    let items: [Item]
    let placeholder: String
    let matches: (Item, String) -> Bool
    @ViewBuilder let header: () -> Header
    @ViewBuilder let row: (Item) -> Row

    @State private var query = ""

    var body: some View {
        VStack(spacing: 8) {
            TextField(placeholder, text: $query)
                .textFieldStyle(.roundedBorder)
            header()
            List(items.filter { query.isEmpty || matches($0, query) }) { item in
                row(item)
            }
            .listStyle(.inset)
        }
        .padding(10)
    }
}
