import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance
    case font

    var id: Self { self }

    var title: String {
        switch self {
        case .appearance: "外观"
        case .font: "字体"
        }
    }

    var symbolName: String {
        switch self {
        case .appearance: "paintpalette"
        // Not "textformat": its localized variant draws "格式" on Chinese systems.
        case .font: "f.cursive"
        }
    }
}

/// The Settings window's content: a sidebar of pages and the selected page.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    @State private var page: SettingsPage?
    @State private var confirmingResetAll = false

    init(model: SettingsModel, page: SettingsPage = .appearance) {
        self.model = model
        _page = State(initialValue: page)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)

            Divider()

            VStack(spacing: 0) {
                banners
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.loadThemesIfNeeded() }
        .alert("恢复全部设置？", isPresented: $confirmingResetAll) {
            Button("全部恢复", role: .destructive) { model.resetAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空 gui.ghostty 中由设置页写入的全部修改，恢复为 config.ghostty 中的值。")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(SettingsPage.allCases, selection: $page) { page in
                Label(page.title, systemImage: page.symbolName)
                    .tag(page)
            }
            .listStyle(.sidebar)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Button("打开 \(model.mainConfigURL.lastPathComponent)…") {
                    NSWorkspace.shared.openInTextEditor(model.mainConfigURL)
                }
                Button("打开 \(GUIConfigFile.fileName)…") {
                    NSWorkspace.shared.openInTextEditor(model.guiConfigURL)
                }
                .disabled(!FileManager.default.fileExists(atPath: model.guiConfigURL.path))
                Button("全部恢复…") { confirmingResetAll = true }
                    .disabled(model.overrides.isEmpty)
            }
            .buttonStyle(.link)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch page ?? .appearance {
        case .appearance:
            AppearanceSettingsPage(model: model)
        case .font:
            FontSettingsPage(model: model)
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
            Divider()
        }

        if let error = model.saveError {
            SettingsBanner(symbol: "xmark.octagon.fill", tint: .red, text: error)
            Divider()
        }
    }
}
