import SwiftUI

/// 字体: family, size, rendering and line height, with a live preview on top.
struct FontSettingsPage: View {
    @ObservedObject var model: SettingsModel

    private var family: String { model.value(.fontFamily) ?? "" }
    private var size: Double { Double(model.value(.fontSize) ?? "13") ?? 13 }
    private var cellHeightPercent: Double? { SettingsFormat.percent(model.value(.adjustCellHeight)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            TerminalPreview(model: model)

            SettingsSection("字体") {
                SettingRow(model: model, title: "字体", key: .fontFamily, note: familyNote) {
                    FontPickerButton(selected: family) { model.set(.fontFamily, $0) }
                }
                SettingsDivider()
                SettingRow(model: model, title: "字号", key: .fontSize) {
                    TextField("字号", value: sizeBinding, format: .number)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 52)
                    Stepper("字号", value: sizeBinding, in: 6...72, step: 1)
                        .labelsHidden()
                    Text("pt").foregroundStyle(.secondary)
                }
                SettingsDivider()
                SettingRow(model: model, title: "加粗渲染", key: .fontThicken, note: "font-thicken，让细字体在屏幕上更清楚") {
                    Toggle("加粗渲染", isOn: thickenBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsDivider()
                SettingRow(model: model, title: "行高", key: .adjustCellHeight, note: cellHeightNote) {
                    Slider(value: cellHeightBinding, in: -20...60, step: 5)
                        .frame(width: 180)
                        .disabled(cellHeightPercent == nil)
                    Text(cellHeightLabel)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .trailing)
                }
            }
        }
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

/// Shows the selected family in its own face; opens a searchable font list.
struct FontPickerButton: View {
    let selected: String
    let onSelect: (String) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                if selected.isEmpty {
                    Text("内置（JetBrains Mono）")
                } else {
                    Text(selected).font(.custom(selected, size: 13))
                }
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
            .frame(width: 380, height: 460)
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
                    HStack(spacing: 8) {
                        if family.name.isEmpty {
                            Text("内置（JetBrains Mono）")
                        } else {
                            Text(family.name).font(.custom(family.name, size: 13))
                            Spacer(minLength: 8)
                            Text("0O 1lI {}")
                                .font(.custom(family.name, size: 12))
                                .foregroundStyle(.secondary)
                        }
                        if family.name.isEmpty { Spacer() }
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
