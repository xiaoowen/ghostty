import SwiftUI

/// 外观: theme, background and cursor, with a live preview on top.
struct AppearanceSettingsPage: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.systemIsDark) private var systemIsDark

    private enum ThemeMode: Hashable {
        case none
        case single
        case pair
    }

    private var selection: ThemeSelection {
        ThemeSelection(configValue: model.value(.theme))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            TerminalPreview(model: model)

            SettingsSection("主题") {
                SettingRow(model: model, title: "配色", key: .theme, note: modeNote) {
                    Picker("配色", selection: themeMode) {
                        Text("跟随系统").tag(ThemeMode.pair)
                        Text("固定").tag(ThemeMode.single)
                        Text("不使用").tag(ThemeMode.none)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                switch selection {
                case .pair(let light, let dark):
                    SettingsDivider()
                    HStack(spacing: 12) {
                        ThemeSlotCard(model: model, label: "浅色外观", symbol: "sun.max.fill", selected: light, prefersDark: false) {
                            model.set(.theme, ThemeSelection.pair(light: $0, dark: dark).configValue)
                        }
                        ThemeSlotCard(model: model, label: "深色外观", symbol: "moon.fill", selected: dark, prefersDark: true) {
                            model.set(.theme, ThemeSelection.pair(light: light, dark: $0).configValue)
                        }
                    }
                    .padding(14)

                case .single(let name):
                    SettingsDivider()
                    ThemeSlotCard(model: model, label: "主题", symbol: "paintpalette", selected: name, prefersDark: systemIsDark) {
                        model.set(.theme, ThemeSelection.single($0).configValue)
                    }
                    .frame(maxWidth: 280, alignment: .leading)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)

                case .none:
                    EmptyView()
                }
            }

            SettingsSection("背景", footer: "macOS 上修改不透明度需要完全退出并重新打开 Ghostty 才会生效。") {
                SettingRow(model: model, title: "不透明度", key: .backgroundOpacity) {
                    Slider(value: opacity, in: 0.3...1, step: 0.05)
                        .frame(width: 180)
                    Text("\(Int((opacity.wrappedValue * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                SettingsDivider()
                SettingRow(model: model, title: "模糊", key: .backgroundBlur, note: "不透明度低于 100% 时可见；玻璃效果需要 macOS 26 或更高") {
                    Picker("模糊", selection: stringBinding(.backgroundBlur)) {
                        Text("关闭").tag("false")
                        Text("模糊").tag("true")
                        Text("玻璃（常规）").tag("macos-glass-regular")
                        Text("玻璃（清透）").tag("macos-glass-clear")
                        extraOption(.backgroundBlur, known: ["false", "true", "macos-glass-regular", "macos-glass-clear"])
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsSection("光标", footer: "运行中的程序仍可以改变光标的样式和闪烁。") {
                SettingRow(model: model, title: "样式", key: .cursorStyle) {
                    Picker("样式", selection: stringBinding(.cursorStyle)) {
                        Text("方块").tag("block")
                        Text("竖线").tag("bar")
                        Text("下划线").tag("underline")
                        Text("空心").tag("block_hollow")
                        extraOption(.cursorStyle, known: ["block", "bar", "underline", "block_hollow"])
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingRow(model: model, title: "闪烁", key: .cursorStyleBlink) {
                    Picker("闪烁", selection: stringBinding(.cursorStyleBlink)) {
                        Text("由程序决定").tag("")
                        Text("闪烁").tag("true")
                        Text("不闪烁").tag("false")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    private var modeNote: String? {
        switch selection {
        case .pair: "随系统的浅色/深色外观自动切换"
        case .single: nil
        case .none: "使用 Ghostty 默认配色"
        }
    }

    // MARK: Bindings

    private func stringBinding(_ key: SettingKey) -> Binding<String> {
        Binding(get: { model.value(key) ?? "" }, set: { model.set(key, $0) })
    }

    /// Keeps a value set by hand in config.ghostty selectable in a picker.
    @ViewBuilder
    private func extraOption(_ key: SettingKey, known: [String]) -> some View {
        if let value = model.value(key), !known.contains(value) {
            Text("自定义：\(value)").tag(value)
        }
    }

    private var opacity: Binding<Double> {
        Binding(
            get: { Double(model.value(.backgroundOpacity) ?? "1") ?? 1 },
            set: { model.set(.backgroundOpacity, SettingsFormat.number($0)) }
        )
    }

    private var themeMode: Binding<ThemeMode> {
        Binding(
            get: {
                switch selection {
                case .none: .none
                case .single: .single
                case .pair: .pair
                }
            },
            set: { mode in
                // Start from what's shown now so switching modes keeps the look.
                let current = selection.name(dark: systemIsDark)
                let currentInfo = model.themes.first { $0.name == current }
                let firstLight = model.themes.first { !$0.isDark }?.name
                let firstDark = model.themes.first { $0.isDark }?.name

                let next: ThemeSelection?
                switch mode {
                case .none:
                    next = ThemeSelection.none
                case .single:
                    next = (current ?? model.themes.first?.name).map(ThemeSelection.single)
                case .pair:
                    let light = currentInfo.map { $0.isDark ? firstLight : $0.name } ?? firstLight
                    let dark = currentInfo.map { $0.isDark ? $0.name : firstDark } ?? firstDark
                    if let light, let dark {
                        next = .pair(light: light, dark: dark)
                    } else {
                        next = nil
                    }
                }
                if let next { model.set(.theme, next.configValue) }
            }
        )
    }
}

/// A card showing one theme slot; opens the theme gallery.
private struct ThemeSlotCard: View {
    @ObservedObject var model: SettingsModel
    let label: String
    let symbol: String
    let selected: String
    let prefersDark: Bool
    let onSelect: (String) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ThemeSwatch(theme: model.themes.first { $0.name == selected })
                    .frame(height: 58)
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selected)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ThemeGallery(
                themes: model.themes,
                selected: selected,
                filter: prefersDark ? .dark : .light
            ) { name in
                onSelect(name)
                isPresented = false
            }
            .frame(width: 580, height: 480)
        }
    }
}

/// A searchable grid of theme cards.
struct ThemeGallery: View {
    enum Filter: Hashable {
        case all
        case light
        case dark
    }

    let themes: [ThemeInfo]
    let selected: String
    let onSelect: (String) -> Void

    @State private var filter: Filter
    @State private var query = ""

    init(themes: [ThemeInfo], selected: String, filter: Filter, onSelect: @escaping (String) -> Void) {
        self.themes = themes
        self.selected = selected
        self.onSelect = onSelect
        _filter = State(initialValue: filter)
    }

    private var filtered: [ThemeInfo] {
        themes.filter { theme in
            let kind = switch filter {
            case .all: true
            case .light: !theme.isDark
            case .dark: theme.isDark
            }
            return kind && (query.isEmpty || theme.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                TextField(themes.isEmpty ? "正在载入主题…" : "搜索 \(themes.count) 个主题", text: $query)
                    .textFieldStyle(.roundedBorder)
                Picker("筛选", selection: $filter) {
                    Text("浅色").tag(Filter.light)
                    Text("深色").tag(Filter.dark)
                    Text("全部").tag(Filter.all)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 12)], spacing: 14) {
                        ForEach(filtered) { theme in
                            card(theme).id(theme.name)
                        }
                    }
                    .padding(4)
                }
                .onAppear { proxy.scrollTo(selected, anchor: .center) }
            }

            if filtered.isEmpty && !themes.isEmpty {
                Text("没有匹配的主题")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private func card(_ theme: ThemeInfo) -> some View {
        let isSelected = theme.name == selected
        return Button {
            onSelect(theme.name)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ThemeSwatch(theme: theme)
                    .frame(height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2.5 : 0)
                    )
                HStack(spacing: 4) {
                    Text(theme.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(theme.name)
    }
}
