import Foundation

/// How sessions to a host reuse one logged-in connection (OpenSSH
/// ControlMaster).
///
/// The first session logs in through a background OpenSSH master connection:
/// the expect helper fills the password, the user types the MFA code. Later
/// SSH and SFTP sessions to the same host open channels on that connection —
/// `sftp` through OpenSSH, `tssh` through its own implementation of OpenSSH's
/// mux protocol — so they don't log in again. The master stays up while any
/// session uses it and for `minutes` after the last one closes.
struct RemoteMuxPlan: Equatable {
    /// The master's control socket.
    var controlPath: String

    /// How long the master outlives its last session.
    var minutes: Int

    /// `ssh -f -N …`: logs in, then leaves the master running in the background.
    var masterArgv: [String]

    /// `ssh -O check`: exits 0 while the master is up.
    var checkArgv: [String]

    /// `ssh -O exit`: closes the master and every session on it.
    var exitArgv: [String]

    /// Options that make a client use the master.
    var clientOptions: [String] { ["-o", "ControlPath=\(controlPath)"] }
}

enum RemoteMux {
    static let defaultMinutes = 60

    /// Choices offered in the host editor; 0 turns reuse off.
    static let minuteChoices = [0, 15, 60, 240, 480]

    /// `~/.ssh/ghostty-mux`. Kept short: Unix socket paths are limited to
    /// about 104 bytes.
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/ghostty-mux", isDirectory: true)
    }

    static func plan(
        destination: String,
        port: Int?,
        minutes: Int,
        directory: URL = directory
    ) -> RemoteMuxPlan {
        let path = directory.appendingPathComponent(socketName(destination: destination, port: port)).path
        let control = ["-o", "ControlPath=\(path)"]

        var master = ["ssh", "-f", "-N", "-o", "ControlMaster=yes"] + control + [
            "-o", "ControlPersist=\(minutes)m",
            // Keeps an idle master from being dropped by NAT or the bastion.
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
        ]
        if let port { master += ["-p", String(port)] }
        master.append(destination)

        return RemoteMuxPlan(
            controlPath: path,
            minutes: minutes,
            masterArgv: master,
            checkArgv: ["ssh"] + control + ["-O", "check", destination],
            exitArgv: ["ssh"] + control + ["-O", "exit", destination]
        )
    }

    /// A stable 16-character name per destination and port (FNV-1a).
    static func socketName(destination: String, port: Int?) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(destination):\(port ?? 22)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }

    /// Creates the socket directory, readable only by the user.
    static func ensureDirectory(_ directory: URL = directory) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    /// Whether a master is probably up: its socket exists. A stale socket is
    /// harmless — `ssh -O check` fails and the next session logs in again.
    static func isActive(_ plan: RemoteMuxPlan) -> Bool {
        FileManager.default.fileExists(atPath: plan.controlPath)
    }

    /// Closes the master and every session using it.
    static func disconnect(_ plan: RemoteMuxPlan) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = Array(plan.exitArgv.dropFirst())
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()

        // A master that died uncleanly leaves its socket behind; nothing is
        // listening on it, so `-O exit` fails and the file can go.
        if process.terminationStatus != 0 {
            try? FileManager.default.removeItem(atPath: plan.controlPath)
        }
    }
}
