import Foundation
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

    @Test func structuredHostUsesTsshWithZmodemByDefault() {
        let host = RemoteHost(name: "堡垒机", host: " bastion ", user: "jumpserver", port: 60022)
        #expect(managed(host, .ssh) == RemoteManagedSession(
            argv: ["tssh", "--zmodem", "-p", "60022", "jumpserver@bastion"],
            keychainAccount: "堡垒机",
            autoPassword: true,
            acceptHostKey: false
        ))
        #expect(managed(host, .sftp)?.argv == ["sftp", "-P", "60022", "jumpserver@bastion"])
        #expect(host.displayCommand(for: .ssh) == "tssh --zmodem -p 60022 jumpserver@bastion")
        #expect(host.usesKeychainPassword)
    }

    @Test func clientOptions() {
        var host = RemoteHost(name: "a", host: "h", sshClient: "tssh", zmodem: false, dragFile: true)
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
        let host = RemoteHost(name: "a", sshCommand: "  tjump \n", sftpCommand: "", host: "h")
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
