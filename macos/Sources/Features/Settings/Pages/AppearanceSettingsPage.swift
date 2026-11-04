import SwiftUI

/// 外观: theme, background and cursor.
struct AppearanceSettingsPage: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.colorScheme) private var colorScheme

    private enum ThemeMode: Hashable {
        case none
        case single
        case pair
    }

    private var selection: ThemeSelection {
        ThemeSelection(configValue: model.value(.theme))
    }

    var body: some View {
        Form {
            Section("主题") {
                SettingRow(model: model, title: "配色", key: .theme) {
                    Picker("配色", selection: themeMode) {
                        Text("跟随系统外观").tag(ThemeMode.pair)
                        Text("固定一个主题").tag(ThemeMode.single)
                        Text("不使用主题").tag(ThemeMode.none)
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                switch selection {
                case .pair(let light, let dark):
                    LabeledContent("浅色外观时") {
                        ThemePickerButton(model: model, selected: light, prefersDark: false) {
                            model.set(.theme, ThemeSelection.pair(light: $0, dark: dark).configValue)
                        }
                    }
                    LabeledContent("深色外观时") {
                        ThemePickerButton(model: model, selected: dark, prefersDark: true) {
                            model.set(.theme, ThemeSelection.pair(light: light, dark: $0).configValue)
                        }
                    }

                case .single(let name):
                    LabeledContent("主题") {
                        ThemePickerButton(model: model, selected: name, prefersDark: colorScheme == .dark) {
                            model.set(.theme, ThemeSelection.single($0).configValue)
                        }
                    }

                case .none:
                    EmptyView()
                }
            }

            Section("背景") {
                SettingRow(
                    model: model,
                    title: "不透明度",
                    key: .backgroundOpacity,
                    note: "macOS 上需要完全退出并重新打开 Ghostty 才会生效"
                ) {
                    Slider(value: opacity, in: 0.3...1, step: 0.05)
                        .frame(width: 200)
                    Text("\(Int((opacity.wrappedValue * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }

                SettingRow(
                    model: model,
                    title: "模糊",
                    key: .backgroundBlur,
                    note: "不透明度低于 100% 时才看得出来；玻璃效果需要 macOS 26 或更高"
                ) {
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

            Section("光标") {
                SettingRow(model: model, title: "样式", key: .cursorStyle) {
                    Picker("样式", selection: stringBinding(.cursorStyle)) {
                        Text("方块").tag("block")
                        Text("竖线").tag("bar")
                        Text("下划线").tag("underline")
                        Text("空心方块").tag("block_hollow")
                        extraOption(.cursorStyle, known: ["block", "bar", "underline", "block_hollow"])
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                SettingRow(
                    model: model,
                    title: "闪烁",
                    key: .cursorStyleBlink,
                    note: "运行中的程序仍可以改变光标样式和闪烁"
                ) {
                    Picker("闪烁", selection: stringBinding(.cursorStyleBlink)) {
                        Text("由程序决定").tag("")
                        Text("闪烁").tag("true")
                        Text("不闪烁").tag("false")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Bindings

    private func stringBinding(_ key: SettingKey) -> Binding<String> {
        Binding(
            get: { model.value(key) ?? "" },
            set: { model.set(key, $0) }
        )
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
                let current = selection.name(dark: colorScheme == .dark)
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

/// A button showing the selected theme that opens a searchable theme list.
struct ThemePickerButton: View {
    @ObservedObject var model: SettingsModel
    let selected: String
    let prefersDark: Bool
    let onSelect: (String) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                ThemeSwatch(theme: model.themes.first { $0.name == selected })
                    .frame(width: 34, height: 20)
                Text(selected)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ThemeListView(
                themes: model.themes,
                selected: selected,
                filter: prefersDark ? .dark : .light
            ) { name in
                onSelect(name)
                isPresented = false
            }
            .frame(width: 360, height: 440)
        }
    }
}

struct ThemeListView: View {
    enum Filter: Hashable {
        case all
        case light
        case dark
    }

    let themes: [ThemeInfo]
    let selected: String
    let onSelect: (String) -> Void

    @State private var filter: Filter

    init(themes: [ThemeInfo], selected: String, filter: Filter, onSelect: @escaping (String) -> Void) {
        self.themes = themes
        self.selected = selected
        self.onSelect = onSelect
        _filter = State(initialValue: filter)
    }

    var body: some View {
        SearchableList(
            items: themes.filter { theme in
                switch filter {
                case .all: true
                case .light: !theme.isDark
                case .dark: theme.isDark
                }
            },
            placeholder: themes.isEmpty ? "正在载入主题…" : "搜索 \(themes.count) 个主题",
            matches: { $0.name.localizedCaseInsensitiveContains($1) },
            header: {
                Picker("筛选", selection: $filter) {
                    Text("浅色").tag(Filter.light)
                    Text("深色").tag(Filter.dark)
                    Text("全部").tag(Filter.all)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            },
            row: { theme in
                Button {
                    onSelect(theme.name)
                } label: {
                    HStack(spacing: 10) {
                        ThemeSwatch(theme: theme).frame(width: 44, height: 24)
                        Text(theme.name)
                        Spacer()
                        if theme.name == selected {
                            Image(systemName: "checkmark").foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        )
    }
}
