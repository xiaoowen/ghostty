import SwiftUI

/// A mock Ghostty window drawn with the settings in effect: theme colors,
/// font, size, line height, cursor, background opacity, titlebar style and
/// padding. Shown at the top of the appearance, font and window pages so a
/// change can be seen before opening a new terminal.
struct TerminalPreview: View {
    @ObservedObject var model: SettingsModel

    /// The theme in effect for the system appearance, set by `SettingsView`.
    @Environment(\.terminalColors) private var colors

    var height: CGFloat = 220

    // MARK: Values from the model

    private var fontSize: CGFloat {
        CGFloat(min(max(Double(model.value(.fontSize) ?? "13") ?? 13, 8), 22))
    }

    private var font: Font {
        let family = model.value(.fontFamily) ?? ""
        if !family.isEmpty, FontCatalog.isInstalled(family) {
            return .custom(family, size: fontSize)
        }
        // Ghostty embeds JetBrains Mono; use the installed copy if there is one.
        if FontCatalog.isInstalled("JetBrains Mono") {
            return .custom("JetBrains Mono", size: fontSize)
        }
        return .system(size: fontSize, design: .monospaced)
    }

    private var lineSpacing: CGFloat {
        let percent = SettingsFormat.percent(model.value(.adjustCellHeight)) ?? 0
        return max(0, fontSize * 0.25 + fontSize * CGFloat(percent) / 100)
    }

    private var opacity: Double {
        min(max(Double(model.value(.backgroundOpacity) ?? "1") ?? 1, 0.3), 1)
    }

    private func padding(_ key: SettingKey) -> CGFloat {
        let first = (model.value(key) ?? "2").split(separator: ",").first.map(String.init) ?? "2"
        return CGFloat(Double(first.trimmingCharacters(in: .whitespaces)) ?? 2)
    }

    private var titlebarStyle: String { model.value(.macosTitlebarStyle) ?? "transparent" }
    private var cursorStyle: String { model.value(.cursorStyle) ?? "block" }

    // MARK: Body

    var body: some View {
        ZStack {
            // A "desktop" behind the window so transparency is visible.
            LinearGradient(
                colors: [Color(red: 0.36, green: 0.42, blue: 0.85), Color(red: 0.78, green: 0.42, blue: 0.70)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 220)
                .offset(x: 180, y: -70)

            window
                .padding(.horizontal, 26)
                .padding(.top, 22)
                .padding(.bottom, -12)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .accessibilityLabel("终端预览")
    }

    private var window: some View {
        VStack(spacing: 0) {
            titlebar
            content
                .padding(.horizontal, 10 + padding(.windowPaddingX))
                .padding(.vertical, 6 + padding(.windowPaddingY))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(colors.backgroundColor.opacity(opacity))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.black.opacity(0.25))
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        // The window chrome follows the theme, like the real window.
        .environment(\.colorScheme, colors.colorScheme)
    }

    // MARK: Titlebar

    @ViewBuilder
    private var titlebar: some View {
        switch titlebarStyle {
        case "hidden":
            EmptyView()

        case "tabs":
            HStack(spacing: 0) {
                trafficLights.padding(.horizontal, 10)
                tab("~/ghostty", active: true)
                tab("ssh 堡垒机", active: false)
                Spacer()
            }
            .frame(height: 28)
            .background(Color.black.opacity(colors.isLight ? 0.06 : 0.22))

        case "native":
            ZStack {
                Text("~/ghostty — zsh")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack { trafficLights; Spacer() }.padding(.horizontal, 10)
            }
            .frame(height: 28)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.2)).frame(height: 1) }

        default: // transparent
            ZStack {
                Text("~/ghostty — zsh")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colors.foregroundColor.opacity(0.55))
                HStack { trafficLights; Spacer() }.padding(.horizontal, 10)
            }
            .frame(height: 28)
        }
    }

    private var trafficLights: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34))
            Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18))
            Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
        }
        .frame(width: 48, height: 10)
    }

    private func tab(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 11, weight: active ? .semibold : .regular))
            .foregroundColor(colors.foregroundColor.opacity(active ? 0.85 : 0.5))
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(active ? colors.backgroundColor.opacity(opacity) : Color.clear)
    }

    // MARK: Terminal content

    private var content: some View {
        VStack(alignment: .leading, spacing: lineSpacing) {
            prompt(command: "ls")
            HStack(spacing: 0) {
                Text("macos  ").foregroundColor(colors.color(4)).bold()
                Text("src  ").foregroundColor(colors.color(4)).bold()
                Text("build.zig  ").foregroundColor(colors.foregroundColor)
                Text("README.md").foregroundColor(colors.foregroundColor)
            }
            Text("中文对齐：你好，世界！=> != 0O 1lI")
                .foregroundColor(colors.foregroundColor)
            HStack(spacing: 0) {
                prompt(command: "")
                cursor
            }
        }
        .font(font)
        .lineLimit(1)
    }

    private func prompt(command: String) -> some View {
        HStack(spacing: 0) {
            Text("~/ghostty ").foregroundColor(colors.color(6))
            Text("main ").foregroundColor(colors.color(5))
            Text("❯ ").foregroundColor(colors.color(2))
            if !command.isEmpty {
                Text(command).foregroundColor(colors.foregroundColor)
            }
        }
    }

    /// The cursor in the configured style (block, bar, underline, hollow).
    private var cursor: some View {
        let width = fontSize * 0.6
        let height = fontSize * 1.2
        return ZStack(alignment: .bottomLeading) {
            switch cursorStyle {
            case "bar":
                Rectangle().fill(colors.foregroundColor).frame(width: 2, height: height)
            case "underline":
                Rectangle().fill(colors.foregroundColor).frame(width: width, height: 2)
            case "block_hollow":
                Rectangle().strokeBorder(colors.foregroundColor, lineWidth: 1).frame(width: width, height: height)
            default:
                Rectangle().fill(colors.foregroundColor.opacity(0.85)).frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height, alignment: .bottomLeading)
    }
}
