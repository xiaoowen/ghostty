import Foundation
import Security

/// Login passwords for remote hosts, stored as generic passwords in the
/// login Keychain under `service`, one item per host (account = host name).
///
/// Items are written with `/usr/bin/security` rather than the Security
/// framework because the expect helper reads them with that same tool: the
/// creating application is always allowed to read an item, so connecting
/// never triggers a Keychain access prompt. The password is passed on
/// `security -i`'s standard input, never in its arguments, so it doesn't show
/// up in `ps`.
enum RemoteKeychain {
    static let service = "ghostty.remote"

    enum KeychainError: LocalizedError {
        case invalidPassword(String)
        case securityFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidPassword(let message): message
            case .securityFailed(let output): "钥匙串操作失败：\(output)"
            }
        }
    }

    /// Why `password` can't be stored, or nil if it can.
    ///
    /// Only printable ASCII is accepted: `security -w` prints anything else as
    /// hex, which the expect helper couldn't tell apart from a real password.
    static func validationError(for password: String) -> String? {
        if password.isEmpty { return "密码不能为空" }
        let printableASCII = password.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }
        if !printableASCII { return "密码只能包含英文字母、数字、空格和英文符号" }
        return nil
    }

    /// Whether a password is saved for `account`. Only reads attributes, so
    /// it never prompts.
    static func hasPassword(account: String, service: String = service) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Saves or replaces the password for `account`.
    static func setPassword(_ password: String, account: String, service: String = service) throws {
        if let message = validationError(for: password) {
            throw KeychainError.invalidPassword(message)
        }

        let command = [
            "add-generic-password", "-U",
            "-s", quote(service),
            "-a", quote(account),
            "-l", quote("Ghostty 远程主机：\(account)"),
            "-w", quote(password),
        ].joined(separator: " ")
        let output = try runSecurityInteractive(command)

        // `security -i` exits 0 even when a command fails, so check the result.
        guard hasPassword(account: account, service: service) else {
            throw KeychainError.securityFailed(output.isEmpty ? "未知错误" : output)
        }
    }

    /// Deletes the saved password for `account`, if any.
    static func deletePassword(account: String, service: String = service) throws {
        guard hasPassword(account: account, service: service) else { return }
        let command = ["delete-generic-password", "-s", quote(service), "-a", quote(account)]
            .joined(separator: " ")
        let output = try runSecurityInteractive(command)
        if hasPassword(account: account, service: service) {
            throw KeychainError.securityFailed(output.isEmpty ? "未知错误" : output)
        }
    }

    /// Quoting for `security -i`'s command parser: double quotes, with `\`
    /// and `"` escaped by a backslash.
    static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Runs one command in `security -i` and returns its trimmed output.
    private static func runSecurityInteractive(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["-i"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        try process.run()
        input.fileHandleForWriting.write(Data((command + "\n").utf8))
        try input.fileHandleForWriting.close()
        // Read before waiting so a chatty process can't fill the pipe and block.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
