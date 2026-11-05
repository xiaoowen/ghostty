import AppKit
import SwiftUI

/// How big the titlebar buttons are.
enum TitlebarToolsSize {
    /// In a titlebar with a toolbar, e.g. tabs in the titlebar: as tall as
    /// the tab bar's tabs and new-tab button.
    case regular
    /// In a plain titlebar: like the update pill.
    case compact

    var height: CGFloat {
        switch self {
        case .regular: 28
        case .compact: 22
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .regular: 13
        case .compact: 11
        }
    }
}

/// Keep-awake and remote host buttons at the right of a terminal window's
/// titlebar, next to Ghostty's update pill. Icons only; the details are in
/// the hover text.
struct TitlebarToolsView: View {
    @ObservedObject var keepAwake: KeepAwake
    @ObservedObject var hosts: RemoteHostsModel
    @ObservedObject var preferences: ToolsPreferences
    var size: TitlebarToolsSize = .compact

    var body: some View {
        HStack(spacing: 8) {
            if preferences.showsKeepAwakeInTitlebar {
                KeepAwakeTitlebarButton(keepAwake: keepAwake, size: size)
            }
            if preferences.showsRemoteHostsInTitlebar {
                RemoteHostsTitlebarButton(hosts: hosts, size: size)
            }
        }
        .fixedSize()
    }
}

// MARK: - Titlebar button background

extension View {
    /// The background of a titlebar button. On macOS 26 and later it's Liquid
    /// Glass, like the tab bar and its new-tab button next to it; before that
    /// a translucent capsule that lightens on hover.
    @ViewBuilder
    func titlebarButtonBackground<S: InsettableShape>(_ shape: S, tint: Color? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(), in: shape)
        } else {
            modifier(TitlebarFallbackBackground(shape: shape, tint: tint))
        }
        #else
        modifier(TitlebarFallbackBackground(shape: shape, tint: tint))
        #endif
    }
}

private struct TitlebarFallbackBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
            .onHover { isHovering = $0 }
    }

    private var fill: Color {
        if let tint { return tint.opacity(isHovering ? 1 : 0.88) }
        return Color.primary.opacity(isHovering ? 0.13 : 0.08)
    }
}

/// The color of a titlebar icon.
private func titlebarIconColor(isActive: Bool) -> Color {
    isActive ? .white : Color.primary.opacity(0.82)
}

// MARK: - Keep-awake

/// A split icon button: the cup turns keep-awake on or off, the chevron
/// opens timers and options. Tinted orange while on.
struct KeepAwakeTitlebarButton: View {
    @ObservedObject var keepAwake: KeepAwake
    var size: TitlebarToolsSize = .compact

    @State private var showOptions = false

    /// The glass tint while on.
    static let onTint = Color(red: 0.98, green: 0.55, blue: 0.16)

    var body: some View {
        // Re-render as time passes so the hover text counts down.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 0) {
                Button {
                    keepAwake.toggle()
                } label: {
                    Image(systemName: keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: size.iconSize, weight: .semibold))
                        .frame(width: size.height + 4, height: size.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(toggleHelp)
                .accessibilityLabel(toggleHelp)

                Rectangle()
                    .fill(titlebarIconColor(isActive: keepAwake.isOn).opacity(0.3))
                    .frame(width: 1, height: size.height * 0.42)

                Button {
                    showOptions.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: size.iconSize * 0.62, weight: .bold))
                        .frame(width: size.height * 0.68, height: size.height)
                        .padding(.trailing, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("防息屏：定时与选项")
                .accessibilityLabel("防息屏：定时与选项")
            }
            .foregroundColor(titlebarIconColor(isActive: keepAwake.isOn))
            .titlebarButtonBackground(Capsule(), tint: keepAwake.isOn ? Self.onTint.opacity(0.78) : nil)
            .animation(.easeOut(duration: 0.2), value: keepAwake.isOn)
            // Outside the styling above: a popover's content inherits the
            // environment where it's attached, and the white icon color
            // made its text unreadable on light glass.
            .popover(isPresented: $showOptions, arrowEdge: .bottom) {
                KeepAwakeOptions(keepAwake: keepAwake)
                    .noInitialFocus()
            }
        }
    }

    private var toggleHelp: String {
        guard keepAwake.isOn else { return "防息屏：已关闭，点击开启（直到关闭或 Ghostty 退出）" }
        guard let remaining = keepAwake.remainingSeconds else { return "防息屏：已开启，点击关闭" }
        return "防息屏：已开启，剩余 \(KeepAwake.format(remaining))，点击关闭"
    }
}

/// The keep-awake popover: switch, timers and options.
struct KeepAwakeOptions: View {
    @ObservedObject var keepAwake: KeepAwake

    private var isOn: Binding<Bool> {
        Binding(
            get: { keepAwake.isOn },
            set: { $0 ? keepAwake.start(.indefinite) : keepAwake.stop() }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ToolsStatusIcon(
                    symbol: keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer",
                    tint: keepAwake.isOn ? KeepAwakeTitlebarButton.onTint : nil
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(keepAwake.isOn ? "防息屏已开启" : "防息屏未开启")
                        .font(.system(size: 13, weight: .semibold))
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 8)
                Toggle("防息屏", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(14)

            ToolsPanelDivider()

            VStack(alignment: .leading, spacing: 8) {
                ToolsPanelHeading(keepAwake.isOn ? "重新计时" : "定时开启")
                HStack(spacing: 6) {
                    ForEach(KeepAwake.Preset.allCases.filter { $0.seconds != nil }) { preset in
                        Button(preset.title) { keepAwake.start(preset) }
                            .buttonStyle(ToolChipButtonStyle())
                    }
                    if keepAwake.endDate != nil {
                        Button {
                            keepAwake.extend(by: 60 * 60)
                        } label: {
                            Label("1 小时", systemImage: "plus")
                        }
                        .buttonStyle(ToolChipButtonStyle(tint: KeepAwakeTitlebarButton.onTint))
                        .help("在剩余时间上再加 1 小时")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            ToolsPanelDivider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("同时阻止系统休眠")
                        .font(.system(size: 13))
                    Text("额外传入 caffeinate -i；合上屏幕仍会休眠")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Toggle("同时阻止系统休眠", isOn: $keepAwake.preventSystemSleep)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(14)
        }
        .frame(width: 310)
    }

    private var detail: String {
        guard keepAwake.isOn else { return "显示器按系统设置休眠" }
        guard let endDate = keepAwake.endDate, let remaining = keepAwake.remainingSeconds else {
            return "不限时，直到关闭或 Ghostty 退出"
        }
        return "剩余 \(KeepAwake.format(remaining)) · \(Self.timeFormatter.string(from: endDate)) 自动关闭"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

// MARK: - Remote hosts

/// An icon that opens a panel listing the remote hosts with SSH/SFTP
/// buttons. A green dot means a host is logged in for reuse.
struct RemoteHostsTitlebarButton: View {
    @ObservedObject var hosts: RemoteHostsModel
    var size: TitlebarToolsSize = .compact

    @State private var showHosts = false

    var body: some View {
        Button {
            hosts.refresh()
            showHosts.toggle()
        } label: {
            Image(systemName: "server.rack")
                .font(.system(size: size.iconSize, weight: .semibold))
                .frame(width: size.height + 2, height: size.height)
                .overlay(alignment: .topTrailing) {
                    if !hosts.loggedIn.isEmpty {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .offset(x: -5, y: 5)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundColor(titlebarIconColor(isActive: false))
        .titlebarButtonBackground(Capsule())
        .help(help)
        .accessibilityLabel(help)
        .popover(isPresented: $showHosts, arrowEdge: .bottom) {
            RemoteHostsPanel(hosts: hosts) { showHosts = false }
                .noInitialFocus()
        }
    }

    private var help: String {
        let names = hosts.hosts.map(\.name).filter(hosts.loggedIn.contains)
        guard !names.isEmpty else { return "远程主机：连接 SSH 或 SFTP" }
        return "远程主机：连接 SSH 或 SFTP（已登录：\(names.joined(separator: "、"))）"
    }
}

/// The remote host panel: one row per host with SSH and SFTP buttons.
struct RemoteHostsPanel: View {
    @ObservedObject var hosts: RemoteHostsModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("远程主机")
                    .font(.system(size: 13, weight: .semibold))
                if !hosts.hosts.isEmpty {
                    Text("\(hosts.hosts.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                Spacer()
                Button {
                    dismiss()
                    SettingsController.shared.show(page: .tools)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ToolIconButtonStyle())
                .help("管理主机（设置 → 工具）")
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 8)

            ToolsPanelDivider()

            if case .invalid(let error) = hosts.state {
                Label("主机列表有误：\(error)", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            } else if hosts.hosts.isEmpty {
                VStack(spacing: 8) {
                    ToolsStatusIcon(symbol: "server.rack", tint: nil)
                    Text("还没有主机")
                        .font(.system(size: 13, weight: .medium))
                    Text("在设置里添加后，可以从这里一键连接 SSH 或 SFTP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("添加主机…") {
                        dismiss()
                        SettingsController.shared.show(page: .tools)
                    }
                    .buttonStyle(ToolChipButtonStyle(tint: .accentColor))
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 14)
            } else {
                VStack(spacing: 2) {
                    ForEach(hosts.hosts) { host in
                        RemoteHostPanelRow(hosts: hosts, host: host, dismiss: dismiss)
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 400)
    }
}

/// One host in the remote host panel; highlighted under the mouse.
private struct RemoteHostPanelRow: View {
    @ObservedObject var hosts: RemoteHostsModel
    let host: RemoteHost
    let dismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        let loggedIn = hosts.loggedIn.contains(host.name)
        let isCustom = RemoteSessionKind.allCases.contains { host.customCommand(for: $0) != nil }
        HStack(spacing: 10) {
            IconTile(
                symbol: isCustom ? "terminal.fill" : "server.rack",
                colors: isCustom
                    ? [Color(red: 0.55, green: 0.55, blue: 0.62), Color(red: 0.36, green: 0.36, blue: 0.44)]
                    : [Color(red: 0.36, green: 0.62, blue: 0.98), Color(red: 0.24, green: 0.38, blue: 0.86)],
                size: 28
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(host.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if loggedIn {
                        CapsuleLabel(text: "已登录", symbol: "link", tint: .green)
                    }
                }
                Text(host.displayCommand(for: .ssh) ?? host.displayCommand(for: .sftp) ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if loggedIn {
                Button {
                    hosts.disconnect(host)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ToolIconButtonStyle())
                .help("断开登录")
            }

            HStack(spacing: 4) {
                ForEach(RemoteSessionKind.allCases, id: \.self) { kind in
                    Button {
                        dismiss()
                        RemoteLauncher.open(host, kind: kind)
                    } label: {
                        Label(kind.label, systemImage: kind.symbolName)
                    }
                    .buttonStyle(ToolChipButtonStyle())
                    .disabled(host.launch(for: kind) == nil)
                    .help(host.displayCommand(for: kind) ?? "")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.07 : 0))
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - Panel building blocks

extension View {
    /// Leaves nothing focused when this view's popover or window first shows.
    /// With keyboard navigation turned on, AppKit would otherwise focus the
    /// first control (e.g. the gear in the host panel) and draw its focus
    /// ring before anything was pressed. Tab still moves into the controls.
    func noInitialFocus() -> some View {
        background(InitialFocusClearer())
    }
}

private struct InitialFocusClearer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ClearingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ClearingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // After AppKit has picked the first key view.
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(nil)
            }
        }
    }
}

/// A round icon for the state of a tool: filled with `tint` when active.
struct ToolsStatusIcon: View {
    let symbol: String
    let tint: Color?
    var size: CGFloat = 34

    var body: some View {
        Circle()
            .fill(tint.map {
                AnyShapeStyle(LinearGradient(colors: [$0.opacity(0.95), $0], startPoint: .top, endPoint: .bottom))
            } ?? AnyShapeStyle(Color.primary.opacity(0.08)))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundColor(tint == nil ? .secondary : .white)
            )
            .frame(width: size, height: size)
            .shadow(color: (tint ?? .clear).opacity(0.35), radius: 4, y: 1)
    }
}

/// A small heading over a group in a tool panel.
struct ToolsPanelHeading: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

/// The line between the groups of a tool panel.
struct ToolsPanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}

/// A capsule button for quick actions, e.g. a timer or "SSH". Lightens under
/// the mouse; `tint` colors it for the action that stands out.
struct ToolChipButtonStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        ToolChip(configuration: configuration, tint: tint)
    }

    private struct ToolChip: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color?

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .labelStyle(ToolChipLabelStyle())
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(tint ?? .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill((tint ?? .primary).opacity(fillOpacity)))
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { isHovering = $0 && isEnabled }
                .animation(.easeOut(duration: 0.12), value: isHovering)
        }

        private var fillOpacity: Double {
            let base = tint == nil ? 0.08 : 0.16
            if configuration.isPressed { return base + 0.12 }
            return isHovering ? base + 0.06 : base
        }
    }
}

/// Icon and title close together, the icon a little smaller.
private struct ToolChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .font(.system(size: 10, weight: .semibold))
            configuration.title
        }
    }
}

/// A borderless icon button that shows a round highlight under the mouse.
struct ToolIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToolIcon(configuration: configuration)
    }

    private struct ToolIcon: View {
        let configuration: ButtonStyleConfiguration

        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.secondary)
                .background(
                    Circle().fill(Color.primary.opacity(
                        configuration.isPressed ? 0.16 : (isHovering ? 0.09 : 0)
                    ))
                )
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
        }
    }
}
