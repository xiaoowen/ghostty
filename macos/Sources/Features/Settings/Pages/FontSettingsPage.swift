import SwiftUI

/// 字体: family, size, rendering and line height, with a preview.
struct FontSettingsPage: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.colorScheme) private var colorScheme

    private var family: String { model.value(.fontFamily) ?? "" }
    private var size: Double { Double(model.value(.fontSize) ?? "13") ?? 13 }
    private var cellHeightPercent: Double? { SettingsFormat.percent(model.value(.adjustCellHeight)) }

    var body: some View {
        Form {
            Section("字体") {
                SettingRow(model: model, title: "字体", key: .fontFamily, note: familyNote) {
                    FontPickerButton(selected: family) { model.set(.fontFamily, $0) }
                }

                SettingRow(model: model, title: "字号", key: .fontSize) {
                    TextField("字号", value: sizeBinding, format: .number)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                    Stepper("字号", value: sizeBinding, in: 6...72, step: 1)
                        .labelsHidden()
                    Text("pt").foregroundStyle(.secondary)
                }

                SettingRow(
                    model: model,
                    title: "加粗渲染",
                    key: .fontThicken,
                    note: "font-thicken：让细字体在屏幕上更清楚"
                ) {
                    Toggle("加粗渲染", isOn: thickenBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingRow(model: model, title: "行高", key: .adjustCellHeight, note: cellHeightNote) {
                    Slider(value: cellHeightBinding, in: -20...60, step: 5)
                        .frame(width: 200)
                        .disabled(cellHeightPercent == nil)
                    Text(cellHeightLabel)
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
            }

            Section("预览") {
                FontPreview(
                    family: family,
                    size: size,
                    extraLineSpacing: size * (cellHeightPercent ?? 0) / 100,
                    theme: previewTheme
                )
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Derived text

    private var familyNote: String? {
        if family.isEmpty { return "Ghostty 内置 JetBrains Mono" }
        if !FontCatalog.isInstalled(family) { return "「\(family)」没有安装，Ghostty 会改用内置字体" }
        return nil
    }

    private var cellHeightLabel: String {
        guard let percent = cellHeightPercent else {
            return model.value(.adjustCellHeight) ?? "0%"
        }
        return percent > 0 ? "+\(SettingsFormat.number(percent))%" : "\(SettingsFormat.number(percent))%"
    }

    private var cellHeightNote: String? {
        guard cellHeightPercent == nil, let value = model.value(.adjustCellHeight), value != "0%" else {
            return "在字体自带行高的基础上增减"
        }
        return "config.ghostty 用的是绝对值 \(value)，恢复后才能用滑块调整"
    }

    /// The theme in effect for the current appearance, for preview colors.
    private var previewTheme: ThemeInfo? {
        let name = ThemeSelection(configValue: model.value(.theme)).name(dark: colorScheme == .dark)
        return model.themes.first { $0.name == name }
    }

    // MARK: Bindings

    private var sizeBinding: Binding<Double> {
        Binding(
            get: { size },
            set: { model.set(.fontSize, SettingsFormat.number(min(max($0, 6), 72), maxDecimals: 1)) }
        )
    }

    private var thickenBinding: Binding<Bool> {
        Binding(
            get: { model.value(.fontThicken) == "true" },
            set: { model.set(.fontThicken, $0 ? "true" : "false") }
        )
    }

    private var cellHeightBinding: Binding<Double> {
        Binding(
            get: { cellHeightPercent ?? 0 },
            set: { model.set(.adjustCellHeight, "\(SettingsFormat.number($0))%") }
        )
    }
}

/// A button showing the selected family that opens a searchable font list.
struct FontPickerButton: View {
    let selected: String
    let onSelect: (String) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                Text(selected.isEmpty ? "内置（JetBrains Mono）" : selected)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            FontListView(selected: selected) { family in
                onSelect(family)
                isPresented = false
            }
            .frame(width: 340, height: 440)
        }
    }
}

struct FontListView: View {
    struct Family: Identifiable, Hashable {
        /// "" is Ghostty's built-in font.
        let name: String
        var id: String { name }
    }

    let selected: String
    let onSelect: (String) -> Void

    @State private var monospacedOnly = true
    @State private var families: [Family] = []

    var body: some View {
        SearchableList(
            items: [Family(name: "")] + families,
            placeholder: "搜索字体",
            matches: { $0.name.localizedCaseInsensitiveContains($1) },
            header: {
                Toggle("只显示等宽字体", isOn: $monospacedOnly)
                    .frame(maxWidth: .infinity, alignment: .leading)
            },
            row: { family in
                Button {
                    onSelect(family.name)
                } label: {
                    HStack {
                        if family.name.isEmpty {
                            Text("内置（JetBrains Mono）")
                        } else {
                            Text(family.name).font(.custom(family.name, size: 13))
                        }
                        Spacer()
                        if family.name == selected {
                            Image(systemName: "checkmark").foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        )
        .onAppear(perform: reload)
        .onChange(of: monospacedOnly) { _ in reload() }
    }

    private func reload() {
        let names = monospacedOnly ? FontCatalog.monospacedFamilies() : FontCatalog.allFamilies()
        families = names.map(Family.init(name:))
    }
}

/// Sample terminal text in the chosen font, size and theme colors.
struct FontPreview: View {
    let family: String
    let size: Double
    let extraLineSpacing: Double
    let theme: ThemeInfo?

    private var font: Font {
        if !family.isEmpty, FontCatalog.isInstalled(family) {
            return .custom(family, size: size)
        }
        // Ghostty embeds JetBrains Mono; use the installed copy if there is one.
        if FontCatalog.isInstalled("JetBrains Mono") {
            return .custom("JetBrains Mono", size: size)
        }
        return .system(size: size, design: .monospaced)
    }

    private func color(_ index: Int) -> Color {
        theme?.palette[index].map { Color(themeColor: $0) } ?? .primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: max(0, extraLineSpacing)) {
            (Text("~/ghostty ").foregroundColor(color(4)) + Text("main ").foregroundColor(color(2)) + Text("$ ls -la"))
            Text("drwxr-xr-x  12 me  staff   384 Nov  4 15:07 macos")
            Text("中文对齐：你好，世界！终端里的汉字占两格")
            Text("=> != -> >= <= 0O 1lI {} [] () #include")
            HStack(spacing: 0) {
                ForEach(1...6, id: \.self) { index in
                    Text("■ ").foregroundColor(color(index))
                }
            }
        }
        .font(font)
        .foregroundColor(theme?.foreground.map { Color(themeColor: $0) } ?? .primary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme?.background.map { Color(themeColor: $0) } ?? Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .textSelection(.enabled)
    }
}
