import SwiftUI

/// A form row for one option, with a reset button when this window has
/// overridden the value from config.ghostty.
struct SettingRow<Control: View>: View {
    @ObservedObject var model: SettingsModel
    let title: String
    let key: SettingKey
    var note: String?
    @ViewBuilder let control: () -> Control

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                control()
                SettingResetButton(model: model, key: key)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct SettingResetButton: View {
    @ObservedObject var model: SettingsModel
    let key: SettingKey

    var body: some View {
        let fallback = model.fallbackValue(key).map { $0.isEmpty ? "默认" : $0 } ?? "未设置"
        Button {
            model.reset(key)
        } label: {
            Image(systemName: "arrow.uturn.backward.circle.fill")
        }
        .buttonStyle(.borderless)
        .help("恢复为 config.ghostty 中的值：\(fallback)")
        // Keep the column aligned when there's nothing to reset.
        .opacity(model.isOverridden(key) ? 1 : 0)
        .disabled(!model.isOverridden(key))
        .accessibilityHidden(!model.isOverridden(key))
    }
}

/// A message across the top of the window.
struct SettingsBanner: View {
    let symbol: String
    let tint: Color
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundColor(tint)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12))
    }
}

/// A small preview of a theme's background and first palette colors.
struct ThemeSwatch: View {
    let theme: ThemeInfo?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(theme?.background.map { Color(themeColor: $0) } ?? Color.gray.opacity(0.2))
            HStack(spacing: 2) {
                ForEach(1...6, id: \.self) { index in
                    Circle()
                        .fill(theme?.palette[index].map { Color(themeColor: $0) } ?? .clear)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.15)))
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

/// A searchable list in a popover, used for themes and fonts.
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
