import AppKit
import Testing
@testable import Ghostty

@Suite
struct RemoteHostStoreTests {
    @Test func templateParses() {
        let state = RemoteHostStore.parse(Data(RemoteHostStore.template.utf8))
        #expect(state == .loaded([
            RemoteHost(name: "堡垒机", host: "bastion.example.com", user: "jumpserver", port: 60022),
            RemoteHost(name: "堡垒机（脚本）", sshCommand: "tjump", sftpCommand: "tsftp"),
        ]))
    }

    @Test func unknownKeysAreIgnored() {
        // Lets later versions add fields without breaking older builds
        // reading the same file.
        let json = #"{"hosts":[{"name":"a","host":"h","future":1}]}"#
        #expect(RemoteHostStore.parse(Data(json.utf8)) == .loaded([RemoteHost(name: "a", host: "h")]))
    }

    @Test(arguments: [
        ("{", "不是有效的 JSON"),
        (#"{"hosts":[{"sshCommand":"x"}]}"#, "hosts[0] 缺少字段 name"),
        (#"{"hosts":[{"name":1}]}"#, "字段类型不对：hosts[0].name"),
        (#"{"hosts":[{"name":" ","host":"h"}]}"#, "主机名称不能为空"),
        (#"{"hosts":[{"name":"a","host":"h"},{"name":"a","host":"h"}]}"#, "主机名称重复：a"),
        (#"{"hosts":[{"name":"a"}]}"#, "主机「a」需要填写 host，或 sshCommand / sftpCommand"),
        (#"{"hosts":[{"name":"a","host":"-oProxyCommand=x"}]}"#, "主机「a」的 host 不能以 - 开头或包含空白"),
        (#"{"hosts":[{"name":"a","host":"h","user":"a b"}]}"#, "主机「a」的 user 不能以 - 开头或包含空白"),
        (#"{"hosts":[{"name":"a","host":"h","port":70000}]}"#, "主机「a」的 port 必须在 1–65535 之间"),
        (#"{"hosts":[{"name":"a","host":"h","sshClient":"mosh"}]}"#, "主机「a」的 sshClient 只能是 tssh 或 ssh"),
    ])
    func invalidFiles(json: String, message: String) {
        #expect(RemoteHostStore.parse(Data(json.utf8)) == .invalid(message))
    }

    @Test func reloadsWhenFileChanges() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteHostStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ghostty/remote-hosts.json")
        let store = RemoteHostStore(fileURL: url)

        #expect(store.state == .missing)

        try store.ensureFileExists()
        #expect(store.hosts.map(\.name) == ["堡垒机", "堡垒机（脚本）"])

        // Calling it again must not overwrite the user's edits.
        let edited = #"{"hosts":[{"name":"dev","sshCommand":"ssh dev"}]}"#
        try Data(edited.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: url.path
        )
        try store.ensureFileExists()
        #expect(store.hosts == [RemoteHost(name: "dev", sshCommand: "ssh dev")])
        #expect(store.host(named: "dev")?.launch(for: .sftp) == nil)
    }
}

@Suite
struct RemoteHostLaunchTests {
    private func managed(_ host: RemoteHost, _ kind: RemoteSessionKind) -> RemoteManagedSession? {
        if case .managed(let session) = host.launch(for: kind) { return session }
        return nil
    }

    @Test func structuredHostUsesTsshWithZmodemAndReuseByDefault() {
        let host = RemoteHost(name: "堡垒机", host: " bastion ", user: "jumpserver", port: 60022)
        let plan = RemoteMux.plan(destination: "jumpserver@bastion", port: 60022, minutes: 60)
        #expect(managed(host, .ssh) == RemoteManagedSession(
            argv: ["tssh", "--zmodem", "-p", "60022", "-o", "ControlPath=\(plan.controlPath)", "jumpserver@bastion"],
            keychainAccount: "堡垒机",
            autoPassword: true,
            acceptHostKey: false,
            mux: plan
        ))
        #expect(managed(host, .sftp)?.argv
            == ["sftp", "-P", "60022", "-o", "ControlPath=\(plan.controlPath)", "jumpserver@bastion"])
        // Tooltips leave the control socket out.
        #expect(host.displayCommand(for: .ssh) == "tssh --zmodem -p 60022 jumpserver@bastion")
        #expect(host.usesKeychainPassword)
    }

    @Test func clientOptions() {
        var host = RemoteHost(name: "a", host: "h", sshClient: "tssh", zmodem: false, dragFile: true, reuseMinutes: 0)
        #expect(managed(host, .ssh)?.argv == ["tssh", "--dragfile", "h"])

        // tssh-only flags are dropped for plain ssh.
        host.sshClient = "ssh"
        #expect(managed(host, .ssh)?.argv == ["ssh", "h"])

        host.acceptHostKey = true
        host.autoPassword = false
        #expect(managed(host, .sftp)?.acceptHostKey == true)
        #expect(managed(host, .sftp)?.autoPassword == false)
        #expect(!host.usesKeychainPassword)
    }

    @Test func customCommandWinsPerKind() {
        let host = RemoteHost(name: "a", sshCommand: "  tjump \n", sftpCommand: "", host: "h", reuseMinutes: 0)
        #expect(host.launch(for: .ssh) == .custom("tjump"))
        #expect(managed(host, .sftp)?.argv == ["sftp", "h"])
        // Only the SFTP session fills a password.
        #expect(host.usesKeychainPassword)

        let scriptsOnly = RemoteHost(name: "b", sshCommand: "tjump", sftpCommand: "tsftp")
        #expect(!scriptsOnly.usesKeychainPassword)
    }
}

@Suite
struct RemoteCommandTests {
    @Test func quote() {
        #expect(RemoteCommand.quote("tjump") == "'tjump'")
        #expect(RemoteCommand.quote("it's") == #"'it'\''s'"#)
    }

    @Test func runsInLoginShell() {
        #expect(RemoteCommand.loginShell("tjump", shell: "/bin/zsh") == #"'/bin/zsh' -l -c 'exec tjump'"#)
    }

    @Test func customCommandIsUnchangedAndNeedsNoScript() throws {
        let command = try RemoteCommand.command(for: .custom("tjump")) {
            Issue.record("script should not be installed for custom commands")
            return ""
        }
        #expect(command == "tjump")
    }

    @Test func managedCommandRunsTheExpectHelper() {
        let session = RemoteManagedSession(
            argv: ["tssh", "-p", "22", "me@h"],
            keychainAccount: "堡垒机",
            autoPassword: true,
            acceptHostKey: false
        )
        let command = RemoteCommand.command(
            for: .managed(session),
            scriptPath: { "/Library/Application Support/x/ghostty-remote.exp" },
            service: "svc"
        )
        #expect(command == """
            '/usr/bin/expect' '-f' '/Library/Application Support/x/ghostty-remote.exp' \
            'svc' '堡垒机' '1' 'ask' '--' 'tssh' '-p' '22' 'me@h'
            """)
    }

    @Test func tabTitles() {
        let host = RemoteHost(name: "堡垒机")
        #expect(RemoteSessionKind.ssh.tabTitle(for: host) == "🔐 堡垒机")
        #expect(RemoteSessionKind.sftp.tabTitle(for: host) == "📁 SFTP 堡垒机")
    }
}

@Suite
struct RemoteKeychainTests {
    @Test(arguments: [
        ("", "密码不能为空"),
        ("密码", "密码只能包含英文字母、数字、空格和英文符号"),
        ("tab\there", "密码只能包含英文字母、数字、空格和英文符号"),
    ])
    func rejectedPasswords(password: String, message: String) {
        #expect(RemoteKeychain.validationError(for: password) == message)
    }

    @Test func acceptsPrintableASCII() {
        #expect(RemoteKeychain.validationError(for: #"p"a\ss w'o|r#d$x(}~"#) == nil)
    }

    @Test func quoteForSecurityInteractive() {
        #expect(RemoteKeychain.quote(#"a"b\c d"#) == #""a\"b\\c d""#)
    }
}

@Suite
struct RemoteScriptTests {
    @Test func installWritesOnlyWhenChanged() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteScriptTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try RemoteScript.install(in: dir)
        #expect(try String(contentsOf: url, encoding: .utf8) == RemoteScript.source)

        let firstDate = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: url.path
        )
        try RemoteScript.install(in: dir)
        let unchanged = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        #expect(unchanged == Date(timeIntervalSince1970: 0))
        #expect(firstDate != nil)

        // A stale or edited copy is replaced.
        try Data("old".utf8).write(to: url)
        try RemoteScript.install(in: dir)
        #expect(try String(contentsOf: url, encoding: .utf8) == RemoteScript.source)
    }
}

@Suite
struct KeepAwakeTests {
    @Test(arguments: [
        (10.0, "1 分钟"),
        (30 * 60.0, "30 分钟"),
        (60 * 60.0, "1 小时"),
        (65 * 60.0, "1 小时 5 分钟"),
    ])
    func format(seconds: Double, expected: String) {
        #expect(KeepAwake.format(seconds) == expected)
    }

    @Test func offHasNoRemainingTime() {
        let defaults = UserDefaults(suiteName: "KeepAwakeTests-\(UUID().uuidString)")!
        let keepAwake = KeepAwake(defaults: defaults)
        #expect(!keepAwake.isOn)
        #expect(keepAwake.remainingSeconds == nil)
        #expect(keepAwake.remainingText == nil)
    }
}

@Suite
struct ToolShortcutTests {
    @Test(arguments: [
        ("ctrl+cmd+a", "⌃⌘A"),
        ("ctrl+opt+shift+cmd+k", "⌃⌥⇧⌘K"),
        ("opt+1", "⌥1"),
        ("cmd++", "⌘+"),
    ])
    func storageRoundTrip(storage: String, display: String) throws {
        let shortcut = try #require(ToolShortcut(storageValue: storage))
        #expect(shortcut.displayString == display)
        #expect(shortcut.storageValue == storage)
        #expect(ToolShortcut(storageValue: shortcut.storageValue) == shortcut)
    }

    @Test(arguments: ["a", "shift+a", "foo+a", "ctrl+cmd+ab", "", "ctrl+cmd+"])
    func rejectsInvalidStorage(storage: String) {
        #expect(ToolShortcut(storageValue: storage) == nil)
    }

    private func key(_ chars: String, _ modifiers: NSEvent.ModifierFlags, keyCode: UInt16 = 0) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
            context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode
        )!
    }

    @Test func recordsFromEvents() {
        #expect(ToolShortcut(event: key("a", [.control, .command])) == .keepAwakeDefault)
        #expect(ToolShortcut(event: key("K", [.control, .shift, .command]))?.displayString == "⌃⇧⌘K")
        // Needs ⌃, ⌥ or ⌘ so plain typing can't trigger it.
        #expect(ToolShortcut(event: key("a", [])) == nil)
        #expect(ToolShortcut(event: key("a", [.shift])) == nil)
        // Arrows and function keys aren't single printable keys.
        #expect(ToolShortcut(event: key("\u{F700}", [.command])) == nil)
        #expect(ToolShortcut(event: key(" ", [.command])) == nil)
    }

    @Test func matchesExactModifiers() {
        let shortcut = ToolShortcut.keepAwakeDefault
        #expect(shortcut.matches(key("a", [.control, .command])))
        #expect(shortcut.matches(key("a", [.control, .command, .capsLock])))
        #expect(!shortcut.matches(key("A", [.control, .shift, .command])))
        #expect(!shortcut.matches(key("a", [.command])))
    }
}

@Suite
struct ToolsPreferencesTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "ToolsPreferencesTests-\(UUID().uuidString)")!
    }

    @Test func defaultsAndPersistence() {
        let store = defaults()
        let preferences = ToolsPreferences(defaults: store)
        #expect(preferences.keepAwakeShortcut == .keepAwakeDefault)
        #expect(!preferences.keepAwakeOnLaunch)

        preferences.keepAwakeShortcut = ToolShortcut(key: "k", modifiers: [.option, .command])
        preferences.keepAwakeOnLaunch = true
        let reloaded = ToolsPreferences(defaults: store)
        #expect(reloaded.keepAwakeShortcut?.displayString == "⌥⌘K")
        #expect(reloaded.keepAwakeOnLaunch)

        // Removing the shortcut is remembered, not reset to the default.
        reloaded.keepAwakeShortcut = nil
        #expect(ToolsPreferences(defaults: store).keepAwakeShortcut == nil)
    }

    @Test func titlebarButtonsAreShownUnlessTurnedOffSeparately() {
        let store = defaults()
        let preferences = ToolsPreferences(defaults: store)
        #expect(preferences.showsKeepAwakeInTitlebar && preferences.showsRemoteHostsInTitlebar)

        preferences.showsKeepAwakeInTitlebar = false
        let reloaded = ToolsPreferences(defaults: store)
        #expect(!reloaded.showsKeepAwakeInTitlebar)
        #expect(reloaded.showsRemoteHostsInTitlebar)

        reloaded.showsRemoteHostsInTitlebar = false
        #expect(!ToolsPreferences(defaults: store).showsRemoteHostsInTitlebar)
    }

    @Test func garbageFallsBackToDefault() {
        let store = defaults()
        store.set("nonsense", forKey: "KeepAwakeShortcut")
        #expect(ToolsPreferences(defaults: store).keepAwakeShortcut == .keepAwakeDefault)
    }
}

@Suite
struct RemoteHostStoreSaveTests {
    @Test func rendersKeysInFixedOrderAndRoundTrips() {
        let hosts = [
            RemoteHost(name: "堡垒机", host: "bastion", user: "jumpserver", port: 60022, zmodem: false),
            RemoteHost(name: #"q"uote\back"#, sshCommand: "tjump --x 'a b'", sftpCommand: "tsftp"),
        ]
        let text = RemoteHostStore.render(hosts)
        #expect(text == #"""
            {
              "hosts": [
                {
                  "name": "堡垒机",
                  "host": "bastion",
                  "user": "jumpserver",
                  "port": 60022,
                  "zmodem": false
                },
                {
                  "name": "q\"uote\\back",
                  "sshCommand": "tjump --x 'a b'",
                  "sftpCommand": "tsftp"
                }
              ]
            }

            """#)
        #expect(RemoteHostStore.parse(Data(text.utf8)) == .loaded(hosts))
        #expect(RemoteHostStore.render([]) == "{\n  \"hosts\": []\n}\n")
    }

    @Test func saveValidatesAndWrites() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteHostStoreSaveTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RemoteHostStore(fileURL: dir.appendingPathComponent("ghostty/remote-hosts.json"))

        #expect(throws: (any Error).self) { try store.save([RemoteHost(name: "a")]) }
        #expect(store.state == .missing)

        try store.save([RemoteHost(name: "a", host: "h")])
        #expect(store.hosts == [RemoteHost(name: "a", host: "h")])
    }
}

@Suite
struct RemoteHostsModelTests {
    /// An in-memory Keychain.
    final class FakeKeychain {
        var passwords: [String: String] = [:]
        var keychain: RemoteHostsModel.Keychain {
            .init(
                hasPassword: { [unowned self] in passwords[$0] != nil },
                setPassword: { [unowned self] in passwords[$1] = $0 },
                deletePassword: { [unowned self] in passwords[$0] = nil },
                movePassword: { [unowned self] from, to in
                    if let value = passwords.removeValue(forKey: from) { passwords[to] = value }
                }
            )
        }
    }

    private func makeModel(_ json: String? = nil) throws -> (RemoteHostsModel, FakeKeychain, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteHostsModelTests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("remote-hosts.json")
        if let json {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try json.write(to: url, atomically: true, encoding: .utf8)
        }
        let fake = FakeKeychain()
        return (RemoteHostsModel(store: RemoteHostStore(fileURL: url), keychain: fake.keychain), fake, dir)
    }

    @Test func addRenameAndDelete() throws {
        let (model, fake, dir) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(model.save(RemoteHost(name: " 堡垒机 ", host: "h", port: 60022), replacing: nil, password: "pw") == nil)
        #expect(model.hosts.map(\.name) == ["堡垒机"])
        #expect(fake.passwords == ["堡垒机": "pw"])
        #expect(model.savedPasswords == ["堡垒机"])

        // Renaming keeps the password, under the new name.
        var renamed = model.hosts[0]
        renamed.name = "跳板"
        #expect(model.save(renamed, replacing: "堡垒机", password: "") == nil)
        #expect(model.hosts.map(\.name) == ["跳板"])
        #expect(fake.passwords == ["跳板": "pw"])

        #expect(model.delete("跳板") == nil)
        #expect(model.hosts.isEmpty && fake.passwords.isEmpty)
    }

    @Test func rejectsBadInput() throws {
        let (model, fake, dir) = try makeModel(#"{"hosts":[{"name":"a","host":"h"}]}"#)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(model.save(RemoteHost(name: "", host: "h"), replacing: nil, password: "") == "名称不能为空")
        #expect(model.save(RemoteHost(name: "a", host: "x"), replacing: nil, password: "") == "已经有名为「a」的主机")
        #expect(model.save(RemoteHost(name: "b", host: "-x"), replacing: nil, password: "") == "主机「b」的 host 不能以 - 开头或包含空白")
        #expect(model.save(RemoteHost(name: "b", host: "h"), replacing: nil, password: "密码") == "密码只能包含英文字母、数字、空格和英文符号")
        #expect(model.hosts.map(\.name) == ["a"])
        #expect(fake.passwords.isEmpty)
    }

    @Test func neverOverwritesABrokenFile() throws {
        let (model, _, dir) = try makeModel("{ broken")
        defer { try? FileManager.default.removeItem(at: dir) }

        let error = model.save(RemoteHost(name: "a", host: "h"), replacing: nil, password: "")
        #expect(error == "remote-hosts.json 有错误（不是有效的 JSON），请先在编辑器里修正")
        #expect(try String(contentsOf: dir.appendingPathComponent("remote-hosts.json"), encoding: .utf8) == "{ broken")
    }
}

@Suite
struct RemoteMuxTests {
    private let directory = URL(fileURLWithPath: "/tmp/mux")

    @Test func planCommands() {
        let plan = RemoteMux.plan(destination: "me@h", port: 60022, minutes: 90, directory: directory)
        let path = "/tmp/mux/" + RemoteMux.socketName(destination: "me@h", port: 60022)
        #expect(plan.controlPath == path)
        #expect(plan.masterArgv == [
            "ssh", "-f", "-N", "-o", "ControlMaster=yes", "-o", "ControlPath=\(path)",
            "-o", "ControlPersist=90m", "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3",
            "-p", "60022", "me@h",
        ])
        #expect(plan.checkArgv == ["ssh", "-o", "ControlPath=\(path)", "-O", "check", "me@h"])
        #expect(plan.exitArgv == ["ssh", "-o", "ControlPath=\(path)", "-O", "exit", "me@h"])
    }

    @Test func socketNames() {
        let name = RemoteMux.socketName(destination: "jumpserver@bastion.example.com", port: 60022)
        #expect(name.count == 16 && name.allSatisfy(\.isHexDigit))
        #expect(name == RemoteMux.socketName(destination: "jumpserver@bastion.example.com", port: 60022))
        #expect(name != RemoteMux.socketName(destination: "jumpserver@bastion.example.com", port: 22))
        #expect(RemoteMux.socketName(destination: "h", port: nil) == RemoteMux.socketName(destination: "h", port: 22))
        // Unix socket paths are limited to about 104 bytes.
        #expect(RemoteMux.directory.appendingPathComponent(name).path.utf8.count < 100)
    }

    @Test func reuseIsPerHost() {
        #expect(RemoteHost(name: "a", host: "h").muxPlan?.minutes == 60)
        #expect(RemoteHost(name: "a", host: "h", reuseMinutes: 15).muxPlan?.minutes == 15)
        #expect(RemoteHost(name: "a", host: "h", reuseMinutes: 0).muxPlan == nil)
        #expect(RemoteHost(name: "a", sshCommand: "tjump").muxPlan == nil)
        #expect(RemoteHost(name: "a", host: "h", reuseMinutes: 2000).validationError()
            == "主机「a」的 reuseMinutes 必须在 0–1440 之间")
    }

    @Test func scriptLogsInOnceThenExecsTheSession() {
        let plan = RemoteMux.plan(destination: "me@h", port: nil, minutes: 60, directory: directory)
        let session = RemoteManagedSession(
            argv: ["tssh"] + plan.clientOptions + ["me@h"],
            keychainAccount: "堡垒机",
            autoPassword: true,
            acceptHostKey: false,
            mux: plan
        )
        let script = RemoteCommand.script(for: .managed(session), scriptPath: { "/s.exp" }, service: "svc")
        let control = "'-o' 'ControlPath=\(plan.controlPath)'"
        let expect = "'/usr/bin/expect' '-f' '/s.exp' 'svc' '堡垒机' '1' 'ask' '--'"

        #expect(script.hasPrefix("if 'ssh' \(control) '-O' 'check' 'me@h' >/dev/null 2>&1; then "))
        #expect(script.contains("else \(expect) 'ssh' '-f' '-N' '-o' 'ControlMaster=yes' \(control)"))
        #expect(script.contains("|| exit $?; "))
        #expect(script.hasSuffix("fi; exec \(expect) 'tssh' \(control) 'me@h'"))
    }

    @Test func scriptWithoutReuseJustExecs() {
        let session = RemoteManagedSession(argv: ["sftp", "h"], keychainAccount: "a", autoPassword: false, acceptHostKey: true)
        #expect(RemoteCommand.script(for: .managed(session), scriptPath: { "/s.exp" }, service: "svc")
            == "exec '/usr/bin/expect' '-f' '/s.exp' 'svc' 'a' '0' 'accept' '--' 'sftp' 'h'")
        #expect(RemoteCommand.script(for: .custom("tjump"), scriptPath: { "" }) == "exec tjump")
        #expect(RemoteCommand.loginShell(script: "exec tjump", shell: "/bin/zsh") == "'/bin/zsh' -l -c 'exec tjump'")
    }

    @Test func reuseMinutesIsSaved() {
        let hosts = [RemoteHost(name: "a", host: "h", reuseMinutes: 240)]
        let text = RemoteHostStore.render(hosts)
        #expect(text.contains("\"reuseMinutes\": 240"))
        #expect(RemoteHostStore.parse(Data(text.utf8)) == .loaded(hosts))
    }
}
