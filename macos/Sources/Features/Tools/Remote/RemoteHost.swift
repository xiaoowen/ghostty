import Foundation

/// A remote host the Tools menu can open SSH and SFTP sessions to.
///
/// A host can be described in two ways, chosen per session kind:
///
/// - Custom commands (`sshCommand` / `sftpCommand`) run as-is, so existing
///   wrapper scripts such as `tjump` / `tsftp` keep working unchanged.
/// - Structured fields (`host`, `user`, `port`, …). Ghostty runs the client
///   through its own expect helper (`RemoteScript`), which fills the login
///   password from the Keychain and leaves MFA prompts to the user. One host
///   then provides both SSH and SFTP.
///
/// A custom command wins over the structured fields for its session kind.
struct RemoteHost: Codable, Hashable, Identifiable {
    /// Display name. Also the identifier and the Keychain account, so it must
    /// be unique. Renaming a host means saving its password again.
    var name: String

    /// Command that opens an interactive SSH session, e.g. `tjump`.
    var sshCommand: String?

    /// Command that opens an SFTP session, e.g. `tsftp`.
    var sftpCommand: String?

    /// Host name or address for structured sessions.
    var host: String?

    /// Login user. Omit to let ssh decide (e.g. from ~/.ssh/config).
    var user: String?

    /// SSH port. Omit for the client's default.
    var port: Int?

    /// SSH client: "tssh" (default) or "ssh". SFTP always uses `sftp`.
    var sshClient: String?

    /// tssh only: rz/sz support (`--zmodem`). Defaults to on.
    var zmodem: Bool?

    /// tssh only: drag files into the tab to upload (`--dragfile`). Defaults to off.
    var dragFile: Bool?

    /// Answer "yes" when the server's host key is unknown. Defaults to off,
    /// leaving the decision to the user.
    var acceptHostKey: Bool?

    /// Fill the first password prompt from the Keychain. Defaults to on.
    var autoPassword: Bool?

    var id: String { name }
}

/// How a session for a host is started.
enum RemoteLaunch: Equatable {
    /// A user-provided command, run as-is.
    case custom(String)

    /// A client invocation run through Ghostty's expect helper.
    case managed(RemoteManagedSession)
}

struct RemoteManagedSession: Equatable {
    /// The client and its arguments, e.g. `["tssh", "--zmodem", "-p", "22", "me@host"]`.
    var argv: [String]

    /// Keychain account holding the login password.
    var keychainAccount: String

    var autoPassword: Bool
    var acceptHostKey: Bool
}

extension RemoteHost {
    static let defaultSSHClient = "tssh"
    static let supportedSSHClients = ["tssh", "ssh"]

    /// The trimmed custom command for a session kind, or nil if not set.
    func customCommand(for kind: RemoteSessionKind) -> String? {
        switch kind {
        case .ssh: Self.trimmed(sshCommand)
        case .sftp: Self.trimmed(sftpCommand)
        }
    }

    /// How to start a session of `kind`, or nil if this host can't provide one.
    func launch(for kind: RemoteSessionKind) -> RemoteLaunch? {
        if let custom = customCommand(for: kind) { return .custom(custom) }
        guard let host = Self.trimmed(host) else { return nil }

        var argv: [String]
        switch kind {
        case .ssh:
            let client = Self.trimmed(sshClient) ?? Self.defaultSSHClient
            argv = [client]
            if client == "tssh" {
                if zmodem ?? true { argv.append("--zmodem") }
                if dragFile ?? false { argv.append("--dragfile") }
            }
            if let port { argv += ["-p", String(port)] }

        case .sftp:
            argv = ["sftp"]
            if let port { argv += ["-P", String(port)] }
        }
        argv.append(Self.trimmed(user).map { "\($0)@\(host)" } ?? host)

        return .managed(RemoteManagedSession(
            argv: argv,
            keychainAccount: name,
            autoPassword: autoPassword ?? true,
            acceptHostKey: acceptHostKey ?? false
        ))
    }

    /// What a session runs, for tooltips and the command palette.
    func displayCommand(for kind: RemoteSessionKind) -> String? {
        switch launch(for: kind) {
        case .custom(let command): command
        case .managed(let session): session.argv.joined(separator: " ")
        case nil: nil
        }
    }

    /// Whether any session of this host fills its password from the Keychain,
    /// i.e. whether a saved password would be used.
    var usesKeychainPassword: Bool {
        RemoteSessionKind.allCases.contains { kind in
            if case .managed(let session) = launch(for: kind) { return session.autoPassword }
            return false
        }
    }

    /// A message describing what's wrong with this host, or nil if it's usable.
    func validationError() -> String? {
        let label = "主机「\(name)」"
        let hasCustom = RemoteSessionKind.allCases.contains { customCommand(for: $0) != nil }
        let host = Self.trimmed(self.host)

        if !hasCustom && host == nil {
            return "\(label)需要填写 host，或 sshCommand / sftpCommand"
        }
        if let host, !Self.isPlainArgument(host) {
            return "\(label)的 host 不能以 - 开头或包含空白"
        }
        if let user = Self.trimmed(user), !Self.isPlainArgument(user) {
            return "\(label)的 user 不能以 - 开头或包含空白"
        }
        if let port, !(1...65535).contains(port) {
            return "\(label)的 port 必须在 1–65535 之间"
        }
        if let client = Self.trimmed(sshClient), !Self.supportedSSHClients.contains(client) {
            return "\(label)的 sshClient 只能是 tssh 或 ssh"
        }
        return nil
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    /// Values become client arguments, so they must not look like options.
    private static func isPlainArgument(_ value: String) -> Bool {
        !value.hasPrefix("-") && !value.contains { $0.isWhitespace || $0.isNewline }
    }
}

enum RemoteSessionKind: CaseIterable {
    case ssh
    case sftp

    /// Name used in menus and the command palette.
    var label: String {
        switch self {
        case .ssh: "SSH"
        case .sftp: "SFTP"
        }
    }

    /// Submenu title in the Tools menu.
    var menuTitle: String {
        switch self {
        case .ssh: "远程连接"
        case .sftp: "SFTP"
        }
    }

    var symbolName: String {
        switch self {
        case .ssh: "terminal"
        case .sftp: "folder"
        }
    }

    /// Tab title for a session, e.g. "🔐 堡垒机" or "📁 SFTP 堡垒机".
    func tabTitle(for host: RemoteHost) -> String {
        switch self {
        case .ssh: "🔐 \(host.name)"
        case .sftp: "📁 SFTP \(host.name)"
        }
    }
}

/// Builds the shell command a new surface runs for a remote session.
enum RemoteCommand {
    static let expectPath = "/usr/bin/expect"

    /// The command for `launch`, before `loginShell` wrapping. `scriptPath` is
    /// only called for managed sessions.
    static func command(
        for launch: RemoteLaunch,
        scriptPath: () throws -> String,
        service: String = RemoteKeychain.service
    ) rethrows -> String {
        switch launch {
        case .custom(let command):
            return command

        case .managed(let session):
            let args = [
                expectPath, "-f", try scriptPath(),
                service, session.keychainAccount,
                session.autoPassword ? "1" : "0",
                session.acceptHostKey ? "accept" : "ask",
                "--",
            ] + session.argv
            return args.map(quote).joined(separator: " ")
        }
    }

    /// Wraps `command` so it runs inside the user's login shell.
    ///
    /// Ghostty started from the Dock or Finder only has launchd's minimal PATH,
    /// so `~/.local/bin/tjump` and the Homebrew `tssh` would not be found. A
    /// login shell reads ~/.zprofile (or the equivalent) and gets the same PATH
    /// as a normal tab. `exec` replaces the shell so the session is the
    /// surface's only process.
    static func loginShell(_ command: String, shell: String = userShell) -> String {
        "\(quote(shell)) -l -c \(quote("exec " + command))"
    }

    /// POSIX single-quote escaping.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// The user's login shell from the passwd database, falling back to zsh.
    static var userShell: String {
        if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell {
            let value = String(cString: shell)
            if !value.isEmpty { return value }
        }
        return "/bin/zsh"
    }
}

/// Loads hosts from `remote-hosts.json` in the Ghostty config directory and
/// re-reads it whenever the file changes, so edits show up without a reload.
/// Use from the main thread only.
final class RemoteHostStore {
    static let shared = RemoteHostStore()

    enum State: Equatable {
        case missing
        case loaded([RemoteHost])
        case invalid(String)
    }

    private struct File: Codable {
        var hosts: [RemoteHost]
    }

    /// Written by `ensureFileExists()` when the user first edits the list.
    /// Shows both ways of describing a host.
    static let template = """
    {
      "hosts": [
        {
          "name": "堡垒机",
          "user": "jumpserver",
          "host": "bastion.example.com",
          "port": 60022
        },
        {
          "name": "堡垒机（脚本）",
          "sshCommand": "tjump",
          "sftpCommand": "tsftp"
        }
      ]
    }

    """

    let fileURL: URL
    private var cachedModificationDate: Date?
    private var cachedState: State?

    init(fileURL: URL = RemoteHostStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// `$XDG_CONFIG_HOME/ghostty/remote-hosts.json`, defaulting to ~/.config.
    static var defaultFileURL: URL {
        let base: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
        }
        return base.appendingPathComponent("ghostty/remote-hosts.json")
    }

    var state: State {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modificationDate = attributes?[.modificationDate] as? Date
        if let cachedState, modificationDate == cachedModificationDate {
            return cachedState
        }

        let state = load()
        cachedState = state
        cachedModificationDate = modificationDate
        return state
    }

    var hosts: [RemoteHost] {
        if case .loaded(let hosts) = state { return hosts }
        return []
    }

    func host(named name: String) -> RemoteHost? {
        hosts.first { $0.name == name }
    }

    /// Creates the file from `template` if it doesn't exist and returns its URL.
    @discardableResult
    func ensureFileExists() throws -> URL {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.template.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return fileURL
    }

    private func load() -> State {
        guard let data = try? Data(contentsOf: fileURL) else { return .missing }
        return Self.parse(data)
    }

    static func parse(_ data: Data) -> State {
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: data)
        } catch let error as DecodingError {
            return .invalid(describe(error))
        } catch {
            return .invalid(error.localizedDescription)
        }

        var seen = Set<String>()
        for host in file.hosts {
            let name = host.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { return .invalid("主机名称不能为空") }
            if !seen.insert(name).inserted { return .invalid("主机名称重复：\(name)") }
            if let error = host.validationError() { return .invalid(error) }
        }
        return .loaded(file.hosts)
    }

    private static func describe(_ error: DecodingError) -> String {
        /// e.g. "hosts[0].name"
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.reduce(into: "") { result, key in
                if let index = key.intValue {
                    result += "[\(index)]"
                } else {
                    result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
                }
            }
        }

        switch error {
        case .dataCorrupted:
            return "不是有效的 JSON"
        case .keyNotFound(let key, let context):
            let at = path(context)
            return at.isEmpty ? "缺少字段 \(key.stringValue)" : "\(at) 缺少字段 \(key.stringValue)"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "字段类型不对：\(path(context))"
        @unknown default:
            return "无法解析"
        }
    }
}
