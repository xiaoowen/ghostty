import SwiftUI

/// 窗口: titlebar, initial size, state restoration and padding, with a live
/// preview on top.
struct WindowSettingsPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            TerminalPreview(model: model)

            SettingsSection("窗口") {
                SettingRow(model: model, title: "标题栏样式", key: .macosTitlebarStyle, note: "对之后打开的窗口生效") {
                    Picker("标题栏样式", selection: stringBinding(.macosTitlebarStyle)) {
                        Text("透明").tag("transparent")
                        Text("原生").tag("native")
                        Text("标签页").tag("tabs")
                        Text("隐藏").tag("hidden")
                        extraOption(.macosTitlebarStyle, known: ["transparent", "native", "tabs", "hidden"])
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                WindowSizeRow(model: model)
                SettingsDivider()
                SettingRow(model: model, title: "退出时保存窗口", key: .windowSaveState, note: "下次启动时恢复窗口和标签页") {
                    Picker("退出时保存窗口", selection: stringBinding(.windowSaveState)) {
                        Text("跟随系统设置").tag("default")
                        Text("总是").tag("always")
                        Text("从不").tag("never")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsSection("内边距", footer: "单位是点。只对之后新建的窗口、标签页和分屏生效。") {
                SettingRow(model: model, title: "左右", key: .windowPaddingX, note: paddingNote(.windowPaddingX)) {
                    PaddingControl(model: model, key: .windowPaddingX)
                }
                SettingsDivider()
                SettingRow(model: model, title: "上下", key: .windowPaddingY, note: paddingNote(.windowPaddingY)) {
                    PaddingControl(model: model, key: .windowPaddingY)
                }
                SettingsDivider()
                SettingRow(model: model, title: "平衡", key: .windowPaddingBalance, note: "把放不下一格的剩余空白分到四周") {
                    Picker("平衡", selection: stringBinding(.windowPaddingBalance)) {
                        Text("关闭").tag("false")
                        Text("平衡").tag("true")
                        Text("四边相等").tag("equal")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    private func paddingNote(_ key: SettingKey) -> String? {
        guard let value = model.value(key), value.contains(",") else { return nil }
        return "两侧不同（\(value)），拖动滑块会改成两侧相同"
    }

    private func stringBinding(_ key: SettingKey) -> Binding<String> {
        Binding(get: { model.value(key) ?? "" }, set: { model.set(key, $0) })
    }

    @ViewBuilder
    private func extraOption(_ key: SettingKey, known: [String]) -> some View {
        if let value = model.value(key), !known.contains(value) {
            Text("自定义：\(value)").tag(value)
        }
    }
}

/// A padding in points: a slider plus the value. "2,4" (two sides) shows
/// its first number until changed.
private struct PaddingControl: View {
    @ObservedObject var model: SettingsModel
    let key: SettingKey

    private var points: Double {
        let first = (model.value(key) ?? "2").split(separator: ",").first.map(String.init) ?? "2"
        return Double(first.trimmingCharacters(in: .whitespaces)) ?? 2
    }

    var body: some View {
        Slider(
            value: Binding(get: { points }, set: { model.set(key, SettingsFormat.number($0.rounded())) }),
            in: 0...40,
            step: 1
        )
        .frame(width: 180)
        Text("\(Int(points)) pt")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 44, alignment: .trailing)
    }
}

/// window-width and window-height together: they only work as a pair.
private struct WindowSizeRow: View {
    @ObservedObject var model: SettingsModel

    private var width: Int { Int(model.value(.windowWidth) ?? "0") ?? 0 }
    private var height: Int { Int(model.value(.windowHeight) ?? "0") ?? 0 }
    private var isCustom: Bool { width > 0 && height > 0 }

    var body: some View {
        SettingsRow(
            title: "初始大小",
            note: "以字符格计，只影响新窗口；超出屏幕会被缩小",
            isModified: model.isOverridden(.windowWidth) || model.isOverridden(.windowHeight)
        ) {
            HStack(spacing: 8) {
                Picker("初始大小", selection: customBinding) {
                    Text("自动").tag(false)
                    Text("指定").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                if isCustom {
                    sizeField(value: width, range: 20...500, key: .windowWidth)
                    Text("列").foregroundStyle(.secondary).fixedSize()
                    sizeField(value: height, range: 5...200, key: .windowHeight)
                    Text("行").foregroundStyle(.secondary).fixedSize()
                }

                SettingResetButton(model: model, keys: [.windowWidth, .windowHeight])
            }
        }
    }

    private var customBinding: Binding<Bool> {
        Binding(
            get: { isCustom },
            set: { custom in
                model.set(.windowWidth, custom ? "100" : "0")
                model.set(.windowHeight, custom ? "30" : "0")
            }
        )
    }

    private func sizeField(value: Int, range: ClosedRange<Int>, key: SettingKey) -> some View {
        let binding = Binding<Int>(
            get: { value },
            set: { model.set(key, String(min(max($0, range.lowerBound), range.upperBound))) }
        )
        return HStack(spacing: 2) {
            TextField("", value: binding, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 46)
            Stepper("", value: binding, in: range)
                .labelsHidden()
        }
    }
}
