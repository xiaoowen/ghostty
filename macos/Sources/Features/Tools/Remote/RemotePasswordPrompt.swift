import AppKit

/// Asks for a host's login password and saves it to the Keychain.
enum RemotePasswordPrompt {
    static func run(for host: RemoteHost) {
        let saved = RemoteKeychain.hasPassword(account: host.name)

        let alert = NSAlert()
        alert.messageText = saved
            ? "更新「\(host.name)」的登录密码"
            : "保存「\(host.name)」的登录密码"
        alert.informativeText = """
            密码保存在登录钥匙串中（服务名 \(RemoteKeychain.service)），\
            连接时自动填入第一个密码提示。MFA 验证码仍需手动输入。
            """

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = saved ? "新密码" : "密码"
        alert.accessoryView = field

        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        if saved {
            alert.addButton(withTitle: "删除已保存的密码")
        }

        alert.layout()
        alert.window.initialFirstResponder = field

        do {
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                if let message = RemoteKeychain.validationError(for: field.stringValue) {
                    showError(message)
                    run(for: host)
                    return
                }
                try RemoteKeychain.setPassword(field.stringValue, account: host.name)

            case .alertThirdButtonReturn:
                try RemoteKeychain.deletePassword(account: host.name)

            default:
                break
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法保存密码"
        alert.informativeText = message
        alert.runModal()
    }
}
