import Foundation
import Testing
@testable import Ghostty

@Suite
struct RemoteHostStoreTests {
    @Test func templateParses() {
        let state = RemoteHostStore.parse(Data(RemoteHostStore.template.utf8))
        #expect(state == .loaded([
            RemoteHost(name: "堡垒机", sshCommand: "tjump", sftpCommand: "tsftp"),
        ]))
    }

    @Test func unknownKeysAreIgnored() {
        // Lets later versions add fields (user, host, port, ...) without
        // breaking older builds reading the same file.
        let json = #"{"hosts":[{"name":"a","port":22}]}"#
        #expect(RemoteHostStore.parse(Data(json.utf8)) == .loaded([RemoteHost(name: "a")]))
    }

    @Test(arguments: [
        ("{", "不是有效的 JSON"),
        (#"{"hosts":[{"sshCommand":"x"}]}"#, "hosts[0] 缺少字段 name"),
        (#"{"hosts":[{"name":1}]}"#, "字段类型不对：hosts[0].name"),
        (#"{"hosts":[{"name":" "}]}"#, "主机名称不能为空"),
        (#"{"hosts":[{"name":"a"},{"name":"a"}]}"#, "主机名称重复：a"),
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
        #expect(store.hosts.map(\.name) == ["堡垒机"])

        // Calling it again must not overwrite the user's edits.
        let edited = #"{"hosts":[{"name":"dev","sshCommand":"ssh dev"}]}"#
        try Data(edited.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: url.path
        )
        try store.ensureFileExists()
        #expect(store.hosts == [RemoteHost(name: "dev", sshCommand: "ssh dev")])
        #expect(store.host(named: "dev")?.command(for: .sftp) == nil)
    }
}

@Suite
struct RemoteCommandTests {
    @Test func commandIsTrimmedAndEmptyMeansUnset() {
        let host = RemoteHost(name: "x", sshCommand: "  tjump \n", sftpCommand: "")
        #expect(host.command(for: .ssh) == "tjump")
        #expect(host.command(for: .sftp) == nil)
    }

    @Test func quote() {
        #expect(RemoteCommand.quote("tjump") == "'tjump'")
        #expect(RemoteCommand.quote("it's") == #"'it'\''s'"#)
    }

    @Test func runsInLoginShell() {
        #expect(RemoteCommand.loginShell("tjump", shell: "/bin/zsh") == #"'/bin/zsh' -l -c 'exec tjump'"#)
    }

    @Test func tabTitles() {
        let host = RemoteHost(name: "堡垒机")
        #expect(RemoteSessionKind.ssh.tabTitle(for: host) == "🔐 堡垒机")
        #expect(RemoteSessionKind.sftp.tabTitle(for: host) == "📁 SFTP 堡垒机")
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
