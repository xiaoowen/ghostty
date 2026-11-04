import SwiftUI

/// Keep-awake and remote host buttons at the right of a terminal window's
/// titlebar, next to Ghostty's update pill. Icons only; the details are in
/// the hover text.
struct TitlebarToolsView: View {
    @ObservedObject var keepAwake: KeepAwake
    @ObservedObject var hosts: RemoteHostsModel
    @ObservedObject var preferences: ToolsPreferences

    var body: some View {
        HStack(spacing: 5) {
            if preferences.showsKeepAwakeInTitlebar {
                KeepAwakeTitlebarButton(keepAwake: keepAwake)
            }
            if preferences.showsRemoteHostsInTitlebar {
                RemoteHostsTitlebarButton(hosts: hosts)
            }
        }
        .fixedSize()
    }
}

/// The capsule behind a titlebar icon, in the update pill's style.
private struct TitlebarCapsule: ViewModifier {
    let isActive: Bool
    let tint: Color

    func body(content: Content) -> some View {
        content
            .foregroundColor(isActive ? tint : .secondary)
            .background(Capsule().fill(isActive ? tint.opacity(0.22) : Color.primary.opacity(0.08)))
    }
}

// MARK: - Keep-awake

/// A split icon button: the cup turns keep-awake on or off, the chevron
/// opens timers and options.
struct KeepAwakeTitlebarButton: View {
    @ObservedObject var keepAwake: KeepAwake

    @State private var showOptions = false

    var body: some View {
        // Re-render as time passes so the hover text counts down.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 0) {
                Button {
                    keepAwake.toggle()
                } label: {
                    Image(systemName: keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(toggleHelp)
                .accessibilityLabel(toggleHelp)

                Rectangle()
                    .fill((keepAwake.isOn ? Color.orange : Color.secondary).opacity(0.35))
                    .frame(width: 1, height: 10)

                Button {
                    showOptions.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .frame(width: 15, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("防息屏：定时与选项")
                .accessibilityLabel("防息屏：定时与选项")
                .popover(isPresented: $showOptions, arrowEdge: .bottom) {
                    KeepAwakeOptions(keepAwake: keepAwake)
                }
            }
            .modifier(TitlebarCapsule(isActive: keepAwake.isOn, tint: .orange))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 20))
                    .foregroundColor(keepAwake.isOn ? .orange : .secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(keepAwake.isOn ? "防息屏已开启" : "防息屏未开启")
                        .font(.headline)
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Toggle("防息屏", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("定时开启")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(KeepAwake.Preset.allCases.filter { $0.seconds != nil }) { preset in
                        Button(preset.title) { keepAwake.start(preset) }
                    }
                    if keepAwake.endDate != nil {
                        Button("延长 1 小时") { keepAwake.extend(by: 60 * 60) }
                    }
                }
                .controlSize(.small)
            }

            Toggle("同时阻止系统休眠", isOn: $keepAwake.preventSystemSleep)
                .toggleStyle(.checkbox)
                .help("额外传入 caffeinate -i；合上屏幕仍会休眠")
        }
        .padding(14)
        .frame(width: 300)
    }

    private var detail: String {
        guard keepAwake.isOn else { return "显示器按系统设置休眠" }
        guard let remaining = keepAwake.remainingSeconds else { return "直到关闭或 Ghostty 退出" }
        return "剩余 \(KeepAwake.format(remaining))"
    }
}

// MARK: - Remote hosts

/// An icon that opens a panel listing the remote hosts with SSH/SFTP
/// buttons. A green dot means a host is logged in for reuse.
struct RemoteHostsTitlebarButton: View {
    @ObservedObject var hosts: RemoteHostsModel

    @State private var showHosts = false

    var body: some View {
        Button {
            hosts.refresh()
            showHosts.toggle()
        } label: {
            Image(systemName: "server.rack")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 20)
                .overlay(alignment: .topTrailing) {
                    if !hosts.loggedIn.isEmpty {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .offset(x: -3, y: 3)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(TitlebarCapsule(isActive: false, tint: .accentColor))
        .help(help)
        .accessibilityLabel(help)
        .popover(isPresented: $showHosts, arrowEdge: .bottom) {
            RemoteHostsPanel(hosts: hosts) { showHosts = false }
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
            Text("远程主机")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if case .invalid(let error) = hosts.state {
                Label("主机列表有误：\(error)", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            } else if hosts.hosts.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("还没有主机")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            ForEach(hosts.hosts) { host in
                Divider().padding(.leading, 14)
                row(host)
            }

            Divider()
            HStack {
                Button(hosts.hosts.isEmpty ? "添加主机…" : "管理主机…") {
                    dismiss()
                    SettingsController.shared.show(page: .tools)
                }
                .buttonStyle(.link)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 380)
    }

    private func row(_ host: RemoteHost) -> some View {
        let loggedIn = hosts.loggedIn.contains(host.name)
        let isCustom = RemoteSessionKind.allCases.contains { host.customCommand(for: $0) != nil }
        return HStack(spacing: 10) {
            IconTile(
                symbol: isCustom ? "terminal.fill" : "server.rack",
                colors: isCustom
                    ? [Color(red: 0.55, green: 0.55, blue: 0.62), Color(red: 0.36, green: 0.36, blue: 0.44)]
                    : [Color(red: 0.36, green: 0.62, blue: 0.98), Color(red: 0.24, green: 0.38, blue: 0.86)],
                size: 26
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(host.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if loggedIn {
                        CapsuleLabel(text: "已登录", symbol: "link", tint: .accentColor)
                    }
                }
                Text(host.displayCommand(for: .ssh) ?? host.displayCommand(for: .sftp) ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if loggedIn {
                Button {
                    hosts.disconnect(host)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("断开登录")
            }

            ForEach(RemoteSessionKind.allCases, id: \.self) { kind in
                Button(kind.label) {
                    dismiss()
                    RemoteLauncher.open(host, kind: kind)
                }
                .controlSize(.small)
                .disabled(host.launch(for: kind) == nil)
                .help(host.displayCommand(for: kind) ?? "")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
