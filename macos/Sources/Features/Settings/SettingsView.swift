import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance
    case font
    case window
    case tools
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .appearance: "外观"
        case .font: "字体"
        case .window: "窗口"
        case .tools: "工具"
        case .advanced: "高级"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: "主题配色、背景透明度和光标"
        case .font: "终端字体、字号与行高"
        case .window: "标题栏、初始大小、内边距和窗口恢复"
        case .tools: "防息屏、远程主机与快捷键"
        case .advanced: "配置文件、配置错误与恢复"
        }
    }

    var symbolName: String {
        switch self {
        case .appearance: "paintpalette.fill"
        // Not "textformat": its localized variant draws "格式" on Chinese systems.
        case .font: "f.cursive"
        case .window: "macwindow"
        case .tools: "wrench.and.screwdriver.fill"
        case .advanced: "gearshape.2.fill"
        }
    }

    var tileColors: [Color] {
        switch self {
        case .appearance: [Color(red: 0.98, green: 0.46, blue: 0.64), Color(red: 0.82, green: 0.27, blue: 0.56)]
        case .font: [Color(red: 0.38, green: 0.64, blue: 1.0), Color(red: 0.18, green: 0.42, blue: 0.95)]
        case .window: [Color(red: 0.30, green: 0.82, blue: 0.76), Color(red: 0.11, green: 0.58, blue: 0.62)]
        case .tools: [Color(red: 1.0, green: 0.69, blue: 0.26), Color(red: 0.96, green: 0.46, blue: 0.12)]
        case .advanced: [Color(white: 0.64), Color(white: 0.42)]
        }
    }

    /// Options on this page, for the sidebar's count of changes.
    var keys: [SettingKey] {
        switch self {
        case .appearance: [.theme, .backgroundOpacity, .backgroundBlur, .cursorStyle, .cursorStyleBlink]
        case .font: [.fontFamily, .fontSize, .fontThicken, .adjustCellHeight]
        case .window: [.macosTitlebarStyle, .windowWidth, .windowHeight, .windowSaveState,
                       .windowPaddingX, .windowPaddingY, .windowPaddingBalance]
        case .tools, .advanced: []
        }
    }
}

/// Which page the Settings window shows; lets other code open a page.
final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage

    init(page: SettingsPage = .appearance) {
        self.page = page
    }
}

/// The Settings window's content.
///
/// The window is painted with the terminal theme's background, the way the
/// command palette is, and its light/dark look follows that background.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var navigation: SettingsNavigation
    let tools: ToolsSettingsContext

    /// Overrides the system appearance; for previews and screenshots.
    var systemIsDarkOverride: Bool?

    init(
        model: SettingsModel,
        navigation: SettingsNavigation,
        tools: ToolsSettingsContext,
        systemIsDarkOverride: Bool? = nil
    ) {
        self.model = model
        self.navigation = navigation
        self.tools = tools
        self.systemIsDarkOverride = systemIsDarkOverride
    }

    /// The appearance Ghostty reports to the terminal, which picks the light
    /// or dark half of a theme pair.
    private var systemIsDark: Bool {
        systemIsDarkOverride ?? (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }

    private var colors: TerminalColors {
        let fallback = model.configColors.map {
            TerminalColors(
                background: $0.background,
                foreground: $0.foreground,
                palette: TerminalColors.ghosttyDefault.palette
            )
        } ?? .ghosttyDefault
        let name = ThemeSelection(configValue: model.value(.theme)).name(dark: systemIsDark)
        return TerminalColors(theme: model.themes.first { $0.name == name }, fallback: fallback)
    }

    var body: some View {
        let colors = colors
        HStack(spacing: 0) {
            SettingsSidebar(model: model, navigation: navigation)
                .frame(width: 216)
                .background(colors.backgroundColor.overlay(Color.black.opacity(colors.isLight ? 0.05 : 0.22)))

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SettingsPageHeader(page: navigation.page) {
                        let changed = navigation.page.keys.filter(model.isOverridden)
                        if !changed.isEmpty {
                            Button("恢复本页") { changed.forEach(model.reset) }
                                .help("恢复本页 \(changed.count) 项修改为 config.ghostty 中的值")
                        }
                    }
                    banners
                    detail
                }
                .padding(.horizontal, 30)
                .padding(.top, 38)
                .padding(.bottom, 30)
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(colors.backgroundColor)
        }
        // Under the translucent divider and anything else not painted.
        .background(colors.backgroundColor)
        // The titlebar is transparent; the content runs underneath it.
        .ignoresSafeArea()
        .frame(minWidth: 780, minHeight: 540)
        .environment(\.terminalColors, colors)
        .environment(\.systemIsDark, systemIsDark)
        .environment(\.colorScheme, colors.colorScheme)
        .background(WindowAppearanceSetter(isDark: !colors.isLight))
        .onAppear { model.loadThemesIfNeeded() }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.page {
        case .appearance:
            AppearanceSettingsPage(model: model)
        case .font:
            FontSettingsPage(model: model)
        case .window:
            WindowSettingsPage(model: model)
        case .tools:
            ToolsSettingsPage(
                keepAwake: tools.keepAwake,
                preferences: tools.preferences,
                hosts: tools.hosts
            )
        case .advanced:
            AdvancedSettingsPage(model: model)
        }
    }

    @ViewBuilder
    private var banners: some View {
        if model.includeMissing && !model.overrides.isEmpty {
            SettingsBanner(
                symbol: "exclamationmark.triangle.fill",
                tint: .orange,
                text: "修改已保存到 \(GUIConfigFile.fileName)，但 \(model.mainConfigURL.lastPathComponent) "
                    + "还没有引用它，所以暂未生效。添加后会在该文件末尾追加一行 "
                    + GUIConfigFile.includeDirective + "。",
                actionTitle: "添加引用",
                action: { model.addInclude() }
            )
        }

        if let error = model.saveError {
            SettingsBanner(symbol: "xmark.octagon.fill", tint: .red, text: error)
        }
    }
}

/// The page list, with the app's identity on top and whether changes are in
/// effect at the bottom.
private struct SettingsSidebar: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ghostty")
                        .font(.system(size: 14, weight: .bold))
                    Text("设置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 18)
            // Clears the traffic lights of the transparent titlebar.
            .padding(.top, 48)
            .padding(.bottom, 18)

            VStack(spacing: 2) {
                ForEach(SettingsPage.allCases) { page in
                    row(page)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 16)

            status
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
        }
    }

    private func row(_ page: SettingsPage) -> some View {
        let selected = navigation.page == page
        let changes = page.keys.filter(model.isOverridden).count
        return Button {
            navigation.page = page
        } label: {
            HStack(spacing: 9) {
                IconTile(symbol: page.symbolName, colors: page.tileColors)
                Text(page.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer(minLength: 4)
                if changes > 0 {
                    Text("\(changes)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .help("本页有 \(changes) 项修改")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var status: some View {
        let (color, text): (Color, String) = if model.overrides.isEmpty {
            (.secondary, "设置页没有修改任何选项")
        } else if model.includeMissing {
            (.orange, "修改尚未生效")
        } else {
            (.green, "修改已生效 · \(model.overrides.count) 项")
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                NSWorkspace.shared.openInTextEditor(model.mainConfigURL)
            } label: {
                Label("打开 \(model.mainConfigURL.lastPathComponent)", systemImage: "doc.text")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
    }
}
