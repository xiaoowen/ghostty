import AppKit
import SwiftUI

/// What the Tools page works with, injectable for previews and tests.
struct ToolsSettingsContext {
    var keepAwake: KeepAwake
    var preferences: ToolsPreferences
    var hosts: RemoteHostsModel

    static var live: Self {
        Self(keepAwake: .shared, preferences: .shared, hosts: .shared)
    }
}

/// 工具: keep-awake options and the remote host list.
struct ToolsSettingsPage: View {
    @ObservedObject var keepAwake: KeepAwake
    @ObservedObject var preferences: ToolsPreferences
    @ObservedObject var hosts: RemoteHostsModel

    @State private var editing: EditingHost?
    @State private var deleting: RemoteHost?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            keepAwakeSection
            hostsSection
        }
        .onAppear { hosts.refresh() }
        // Logged-in connections expire on their own; keep the labels current.
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in hosts.refresh() }
        .sheet(item: $editing) { item in
            HostEditor(
                host: item.host,
                original: item.original,
                passwordSaved: item.original.map { hosts.savedPasswords.contains($0) } ?? false,
                onSave: { host, password in
                    let error = hosts.save(host, replacing: item.original, password: password)
                    if error == nil { editing = nil }
                    return error
                },
                onCancel: { editing = nil }
            )
        }
        .confirmationDialog(
            "删除主机「\(deleting?.name ?? "")」？",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { host in
            Button("删除", role: .destructive) {
                message = hosts.delete(host.name)
            }
        } message: { _ in
            Text("同时删除钥匙串中保存的密码。")
        }
    }

    // MARK: Keep-awake

    private var keepAwakeSection: some View {
        SettingsSection("防息屏") {
            HStack(spacing: 12) {
                IconTile(
                    symbol: keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer",
                    colors: keepAwake.isOn ? SettingsPage.tools.tileColors : [Color(white: 0.6), Color(white: 0.45)],
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(keepAwake.isOn ? "防息屏已开启" : "防息屏未开启")
                        .font(.system(size: 14, weight: .semibold))
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text(statusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                Button(keepAwake.isOn ? "关闭" : "开启") { keepAwake.toggle() }
                    .controlSize(.large)
            }
            .padding(14)

            SettingsDivider()
            titlebarRow(isOn: $preferences.showsKeepAwakeInTitlebar, note: "点图标开关防息屏，旁边的箭头打开定时与选项")
            SettingsDivider()
            SettingsRow(title: "启动 Ghostty 时自动开启") {
                Toggle("启动 Ghostty 时自动开启", isOn: $preferences.keepAwakeOnLaunch)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsDivider()
            SettingsRow(title: "同时阻止系统休眠", note: "额外传入 caffeinate -i；合上屏幕仍会休眠") {
                Toggle("同时阻止系统休眠", isOn: $keepAwake.preventSystemSleep)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsDivider()
            SettingsRow(title: "快捷键", note: "和 Ghostty 的 keybind 冲突时以 keybind 为准") {
                ShortcutRecorder(shortcut: $preferences.keepAwakeShortcut, defaultShortcut: .keepAwakeDefault)
            }
        }
    }

    /// "在窗口顶部栏显示", shared by the keep-awake and remote host sections.
    private func titlebarRow(isOn: Binding<Bool>, note: String) -> some View {
        SettingsRow(
            title: "在窗口顶部栏显示",
            note: note + "。标题栏样式为「隐藏」时没有顶部栏，不显示；macOS 15 及更早版本的「标签页」样式也不显示"
        ) {
            Toggle("在窗口顶部栏显示", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private var statusDetail: String {
        guard keepAwake.isOn else { return "显示器按系统设置休眠" }
        if let remaining = keepAwake.remainingText, keepAwake.endDate != nil {
            return "\(remaining) · caffeinate -d\(keepAwake.preventSystemSleep ? " -i" : "")"
        }
        return "直到关闭或 Ghostty 退出 · caffeinate -d\(keepAwake.preventSystemSleep ? " -i" : "")"
    }

    // MARK: Hosts

    private var isListBroken: Bool {
        if case .invalid = hosts.state { return true }
        return false
    }

    private var hostsSection: some View {
        SettingsSection(
            "远程主机",
            footer: "也可以从菜单栏「工具」、命令面板和 Dock 菜单连接。密码保存在登录钥匙串（服务名 \(RemoteKeychain.service)）。"
                + "开启复用登录的主机，登录一次后，新开的 SSH/SFTP 会复用这条连接，不再要求密码和 MFA。"
        ) {
            titlebarRow(isOn: $preferences.showsRemoteHostsInTitlebar, note: "点图标打开主机列表，直接连接 SSH 或 SFTP")
            SettingsDivider()

            if case .invalid(let error) = hosts.state {
                SettingsBanner(symbol: "exclamationmark.triangle.fill", tint: .orange, text: "主机列表有误：\(error)")
                    .padding(12)
                SettingsDivider()
            } else if hosts.hosts.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text("还没有主机")
                        .font(.system(size: 13, weight: .medium))
                    Text("添加堡垒机后，可以一键打开 SSH 或 SFTP 标签页")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                SettingsDivider()
            }

            ForEach(hosts.hosts) { host in
                HostRow(
                    host: host,
                    passwordSaved: hosts.savedPasswords.contains(host.name),
                    loggedIn: hosts.loggedIn.contains(host.name),
                    onEdit: { editing = EditingHost(host: host, original: host.name) },
                    onDisconnect: { hosts.disconnect(host) },
                    onDelete: { deleting = host }
                )
                SettingsDivider()
            }

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundColor(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                SettingsDivider()
            }

            HStack {
                Button {
                    editing = EditingHost(host: RemoteHost(name: ""), original: nil)
                } label: {
                    Label("添加主机…", systemImage: "plus")
                }
                .disabled(isListBroken)
                Spacer()
                Button("编辑 \(hosts.store.fileURL.lastPathComponent)…") {
                    _ = try? hosts.store.ensureFileExists()
                    NSWorkspace.shared.openInTextEditor(hosts.store.fileURL)
                }
                .buttonStyle(.link)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

private struct EditingHost: Identifiable {
    let id = UUID()
    var host: RemoteHost
    /// Nil when adding.
    var original: String?
}

private struct HostRow: View {
    let host: RemoteHost
    let passwordSaved: Bool
    let loggedIn: Bool
    let onEdit: () -> Void
    let onDisconnect: () -> Void
    let onDelete: () -> Void

    private var isCustom: Bool {
        RemoteSessionKind.allCases.contains { host.customCommand(for: $0) != nil }
    }

    var body: some View {
        HStack(spacing: 12) {
            IconTile(
                symbol: isCustom ? "terminal.fill" : "server.rack",
                colors: isCustom
                    ? [Color(red: 0.55, green: 0.55, blue: 0.62), Color(red: 0.36, green: 0.36, blue: 0.44)]
                    : [Color(red: 0.36, green: 0.62, blue: 0.98), Color(red: 0.24, green: 0.38, blue: 0.86)],
                size: 30
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(host.name).font(.system(size: 13, weight: .semibold))
                    if host.usesKeychainPassword {
                        CapsuleLabel(
                            text: passwordSaved ? "已存密码" : "未存密码",
                            symbol: passwordSaved ? "key.fill" : "key",
                            tint: passwordSaved ? .green : .orange
                        )
                    }
                    if loggedIn {
                        CapsuleLabel(text: "已登录", symbol: "link", tint: .accentColor)
                            .help("新开的 SSH/SFTP 会复用这条连接，不用再验证")
                    }
                    if isCustom {
                        CapsuleLabel(text: "自定义命令")
                    }
                }
                Text(host.displayCommand(for: .ssh) ?? host.displayCommand(for: .sftp) ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            ForEach(RemoteSessionKind.allCases, id: \.self) { kind in
                Button {
                    RemoteLauncher.open(host, kind: kind)
                } label: {
                    Label(kind.label, systemImage: kind.symbolName)
                }
                .disabled(host.launch(for: kind) == nil)
                .help(host.displayCommand(for: kind) ?? "")
            }

            Menu {
                Button("编辑…", action: onEdit)
                if loggedIn {
                    Button("断开登录", action: onDisconnect)
                }
                Divider()
                Button("删除…", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Add/edit form for one host, shown as a sheet.
struct HostEditor: View {
    private enum Mode: Hashable {
        case structured
        case custom
    }

    let original: String?
    let passwordSaved: Bool
    let onSave: (RemoteHost, String) -> String?
    let onCancel: () -> Void

    @State private var draft: RemoteHost
    @State private var mode: Mode
    @State private var portText: String
    @State private var password = ""
    @State private var error: String?

    init(
        host: RemoteHost,
        original: String?,
        passwordSaved: Bool,
        onSave: @escaping (RemoteHost, String) -> String?,
        onCancel: @escaping () -> Void
    ) {
        self.original = original
        self.passwordSaved = passwordSaved
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: host)
        let hasCustom = RemoteSessionKind.allCases.contains { host.customCommand(for: $0) != nil }
        _mode = State(initialValue: hasCustom ? .custom : .structured)
        _portText = State(initialValue: host.port.map(String.init) ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("名称", text: $draft.name, prompt: Text("例如 堡垒机"))
                    Picker("连接方式", selection: $mode) {
                        Text("填写主机信息").tag(Mode.structured)
                        Text("运行自定义命令").tag(Mode.custom)
                    }
                } header: {
                    Text(original == nil ? "添加主机" : "编辑「\(original ?? "")」")
                }

                switch mode {
                case .structured: structuredSection
                case .custom: customSection
                }

                if let error {
                    Text(error).foregroundColor(.red)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 460)
    }

    private var structuredSection: some View {
        Section {
            TextField("主机", text: text(\.host), prompt: Text("bastion.example.com"))
            TextField("用户", text: text(\.user), prompt: Text("留空则由 ssh 决定"))
            TextField("端口", text: $portText, prompt: Text("22"))
            Picker("SSH 客户端", selection: client) {
                Text("tssh（支持 trz/tsz）").tag("tssh")
                Text("ssh").tag("ssh")
            }
            if client.wrappedValue == "tssh" {
                Toggle("rz/sz 传文件（--zmodem）", isOn: flag(\.zmodem, default: true))
                Toggle("拖文件到窗口上传（--dragfile）", isOn: flag(\.dragFile, default: false))
            }
            Picker("复用登录", selection: reuse) {
                Text("关闭").tag(0)
                Text("15 分钟").tag(15)
                Text("1 小时").tag(60)
                Text("4 小时").tag(240)
                Text("8 小时").tag(480)
                if !RemoteMux.minuteChoices.contains(reuse.wrappedValue) {
                    Text("\(reuse.wrappedValue) 分钟").tag(reuse.wrappedValue)
                }
            }
            Toggle("自动接受新的主机指纹", isOn: flag(\.acceptHostKey, default: false))
            Toggle("自动填写密码", isOn: flag(\.autoPassword, default: true))
            if draft.autoPassword ?? true {
                SecureField(
                    "密码",
                    text: $password,
                    prompt: Text(passwordSaved ? "已保存，留空则不修改" : "保存到钥匙串")
                )
            }
        } header: {
            Text("连接")
        } footer: {
            Text("SSH 和 SFTP 共用这些信息，MFA 验证码在终端里手动输入。复用登录：登录一次后，所选时间内新开的 SSH/SFTP 不再验证。阿里云等部分堡垒机每条连接只允许一个会话，会话结束就断开整条连接，不支持复用，请保持关闭。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var customSection: some View {
        Section {
            TextField("SSH 命令", text: text(\.sshCommand), prompt: Text("例如 tjump"))
            TextField("SFTP 命令", text: text(\.sftpCommand), prompt: Text("例如 tsftp"))
        } header: {
            Text("命令")
        } footer: {
            Text("在登录 shell 里运行，可以用 PATH 里的脚本。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Bindings

    /// Empty text means the field is unset.
    private func text(_ keyPath: WritableKeyPath<RemoteHost, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    /// Stores nil for the default so the JSON stays short.
    private func flag(_ keyPath: WritableKeyPath<RemoteHost, Bool?>, default value: Bool) -> Binding<Bool> {
        Binding(
            get: { draft[keyPath: keyPath] ?? value },
            set: { draft[keyPath: keyPath] = $0 == value ? nil : $0 }
        )
    }

    /// Stores nil for the default (off) so the JSON stays short.
    private var reuse: Binding<Int> {
        Binding(
            get: { draft.reuseMinutes ?? RemoteMux.defaultMinutes },
            set: { draft.reuseMinutes = $0 == RemoteMux.defaultMinutes ? nil : $0 }
        )
    }

    private var client: Binding<String> {
        Binding(
            get: { draft.sshClient ?? RemoteHost.defaultSSHClient },
            set: { draft.sshClient = $0 == RemoteHost.defaultSSHClient ? nil : $0 }
        )
    }

    private func save() {
        var host = draft
        switch mode {
        case .structured:
            // Custom commands would win over the fields, so drop them.
            host.sshCommand = nil
            host.sftpCommand = nil
            let port = portText.trimmingCharacters(in: .whitespaces)
            if port.isEmpty {
                host.port = nil
            } else if let value = Int(port) {
                host.port = value
            } else {
                error = "端口必须是数字"
                return
            }
        case .custom:
            // Fields are kept: a custom command only replaces its own kind.
            break
        }

        error = onSave(host, mode == .structured && (host.autoPassword ?? true) ? password : "")
    }
}

/// Click, then press a shortcut. Esc cancels, Delete removes it.
struct ShortcutRecorder: View {
    @Binding var shortcut: ToolShortcut?
    let defaultShortcut: ToolShortcut

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(isRecording ? "请按快捷键…" : (shortcut?.displayString ?? "无"))
                    .frame(minWidth: 90)
            }

            if shortcut != defaultShortcut {
                Button("恢复默认") { shortcut = defaultShortcut }
                    .buttonStyle(.link)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53: // Esc
                stop()
            case 51, 117: // Delete, Forward Delete
                shortcut = nil
                stop()
            default:
                if let recorded = ToolShortcut(event: event) {
                    shortcut = recorded
                    stop()
                } else {
                    NSSound.beep()
                }
            }
            // Swallow the key so it doesn't also trigger a menu item.
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
