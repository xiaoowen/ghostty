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

    var symbolName: String {
        switch self {
        case .appearance: "paintpalette"
        // Not "textformat": its localized variant draws "格式" on Chinese systems.
        case .font: "f.cursive"
        case .window: "macwindow"
        case .tools: "wrench.and.screwdriver"
        case .advanced: "gearshape.2"
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

/// The Settings window's content: a sidebar of pages and the selected page.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var navigation: SettingsNavigation
    let tools: ToolsSettingsContext

    init(model: SettingsModel, navigation: SettingsNavigation, tools: ToolsSettingsContext) {
        self.model = model
        self.navigation = navigation
        self.tools = tools
    }

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsPage.allCases, selection: selection) { page in
                Label(page.title, systemImage: page.symbolName)
                    .tag(page)
            }
            .listStyle(.sidebar)
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
    }

    /// The sidebar wants an optional selection; never let it become empty.
    private var selection: Binding<SettingsPage?> {
        Binding(
            get: { navigation.page },
            set: { if let page = $0 { navigation.page = page } }
        )
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
            Divider()
        }

        if let error = model.saveError {
            SettingsBanner(symbol: "xmark.octagon.fill", tint: .red, text: error)
            Divider()
        }
    }
}
