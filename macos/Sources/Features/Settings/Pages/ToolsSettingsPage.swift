import AppKit
import SwiftUI

/// What the Tools page works with, injectable for previews and tests.
struct ToolsSettingsContext {
    var keepAwake: KeepAwake
    var preferences: ToolsPreferences
    var hosts: RemoteHostsModel

    static var live: Self {
        Self(keepAwake: .shared, preferences: .shared, hosts: RemoteHostsModel(store: .shared))
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
        Form {
            keepAwakeSection
            hostsSection
        }
        .formStyle(.grouped)
        .onAppear { hosts.refresh() }
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
        Section {
            LabeledContent("状态") {
                HStack(spacing: 10) {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text(keepAwake.isOn ? "已开启 · \(keepAwake.remainingText ?? "")" : "未开启")
                            .foregroundStyle(.secondary)
                    }
                    Button(keepAwake.isOn ? "关闭" : "开启") { keepAwake.toggle() }
                }
            }

            Toggle("启动 Ghostty 时自动开启", isOn: $preferences.keepAwakeOnLaunch)
                .toggleStyle(.switch)

            Toggle(isOn: $keepAwake.preventSystemSleep) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("同时阻止系统休眠")
                    Text("额外传入 caffeinate -i；合上屏幕仍会休眠")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            LabeledContent {
                ShortcutRecorder(shortcut: $preferences.keepAwakeShortcut, defaultShortcut: .keepAwakeDefault)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("快捷键")
                    Text("和 Ghostty 的 keybind 冲突时以 keybind 为准")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("防息屏")
        }
    }

    // MARK: Hosts

    private var hostsSection: some View {
        Section {
            if case .invalid(let error) = hosts.state {
                Label("主机列表有误：\(error)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            } else if hosts.hosts.isEmpty {
                Text("还没有主机。")
                    .foregroundStyle(.secondary)
            }

            ForEach(hosts.hosts) { host in
                HostRow(
                    host: host,
                    passwordSaved: hosts.savedPasswords.contains(host.name),
                    onEdit: { editing = EditingHost(host: host, original: host.name) },
                    onDelete: { deleting = host }
                )
            }

            if let message {
                Text(message).foregroundColor(.red)
            }

            HStack {
                Button("添加主机…") {
                    editing = EditingHost(host: RemoteHost(name: ""), original: nil)
                }
                .disabled({ if case .invalid = hosts.state { return true } else { return false } }())
                Spacer()
                Button("编辑 \(hosts.store.fileURL.lastPathComponent)…") {
                    _ = try? hosts.store.ensureFileExists()
                    NSWorkspace.shared.openInTextEditor(hosts.store.fileURL)
                }
                .buttonStyle(.link)
            }
        } header: {
            Text("远程主机")
        } footer: {
            Text("也可以从菜单栏「工具」、命令面板和 Dock 菜单连接。密码保存在登录钥匙串（服务名 \(RemoteKeychain.service)）。")
                .font(.caption)
                .foregroundStyle(.secondary)
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
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name).fontWeight(.medium)
                Text(host.displayCommand(for: .ssh) ?? host.displayCommand(for: .sftp) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if host.usesKeychainPassword {
                Label(passwordSaved ? "已存密码" : "未存密码", systemImage: passwordSaved ? "key.fill" : "key")
                    .font(.caption)
                    .foregroundColor(passwordSaved ? .secondary : .orange)
            }

            ForEach(RemoteSessionKind.allCases, id: \.self) { kind in
                Button(kind.label) { RemoteLauncher.open(host, kind: kind) }
                    .disabled(host.launch(for: kind) == nil)
                    .help(host.displayCommand(for: kind) ?? "")
            }

            Button(action: onEdit) { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help("编辑")
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("删除")
        }
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
            Text("SSH 和 SFTP 都用这些信息；MFA 验证码仍需在终端里手动输入。")
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
