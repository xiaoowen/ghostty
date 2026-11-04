import Foundation

/// A remote host the Tools menu can open sessions to.
///
/// For now a host is described by the commands that connect to it, which lets
/// existing wrapper scripts (e.g. expect scripts that log into a bastion host
/// and stop at the MFA prompt) be used unchanged.
struct RemoteHost: Codable, Hashable, Identifiable {
    /// Display name. Also the identifier, so it must be unique.
    var name: String

    /// Command that opens an interactive SSH session, e.g. `tjump`.
    var sshCommand: String?

    /// Command that opens an SFTP session, e.g. `tsftp`.
    var sftpCommand: String?

    var id: String { name }

    /// The trimmed command for a session kind, or nil if not configured.
    func command(for kind: RemoteSessionKind) -> String? {
        let raw = switch kind {
        case .ssh: sshCommand
        case .sftp: sftpCommand
        }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
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
    static let template = """
    {
      "hosts": [
        {
          "name": "堡垒机",
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
