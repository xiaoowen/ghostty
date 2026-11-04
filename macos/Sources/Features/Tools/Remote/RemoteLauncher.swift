import AppKit

/// Opens SSH/SFTP sessions for remote hosts in new terminal tabs.
enum RemoteLauncher {
    static func open(_ host: RemoteHost, kind: RemoteSessionKind) {
        guard let command = host.command(for: kind) else { return }
        guard let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty else { return }

        var config = Ghostty.SurfaceConfiguration()
        config.command = RemoteCommand.loginShell(command)

        // Keep the tab around after the session ends so a failed login or a
        // dropped connection can still be read. (Setting a command already
        // implies this in libghostty; it's explicit here because we rely on it.)
        config.waitAfterCommand = true

        let controller = TerminalController.newTab(
            ghostty,
            from: TerminalController.preferredParent?.window,
            withBaseConfig: config
        )

        // A fixed title so remote shells changing it via OSC 0/2 don't make
        // the tab hard to find.
        controller?.titleOverride = kind.tabTitle(for: host)
    }
}
