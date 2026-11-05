import Foundation

/// The expect helper that runs managed SSH/SFTP sessions.
///
/// It generalizes wrapper scripts like `tjump`/`tsftp`: run the client, type
/// the login password, then hand the session to the user (who types the MFA
/// code). Differences from those scripts:
///
/// - The password is read from the Keychain with `/usr/bin/security` instead
///   of being stored in the script.
/// - It uses `interact` with output patterns from the start, so the user's
///   keystrokes always reach the client. Key-based logins, MFA prompts and
///   host key questions never get stuck waiting for a pattern.
/// - The password is typed at most once and only during the first minute, so
///   a later `passwd` or similar prompt is never answered by accident.
/// - Host keys are only accepted automatically when the host opts in.
///
/// The script is embedded here and written to Application Support on use,
/// which keeps the Xcode resource setup untouched.
enum RemoteScript {
    static let fileName = "ghostty-remote.exp"

    static let source = #"""
    # Written by Ghostty (macos/Sources/Features/Tools/Remote/RemoteScript.swift).
    # Ghostty rewrites this file when it changes, so local edits are lost.
    #
    # Usage: expect -f ghostty-remote.exp SERVICE ACCOUNT AUTOFILL HOSTKEY -- COMMAND...
    #
    # Runs COMMAND (an ssh, tssh or sftp invocation). During the first minute:
    #   * when AUTOFILL is 1, types the password stored in the Keychain item
    #     SERVICE/ACCOUNT into the first password prompt;
    #   * when HOSTKEY is "accept", answers "yes" to an unknown host key prompt.
    # Everything else, including MFA prompts, is left to the user. Once those
    # prompts are answered (or the minute is up), the session runs untouched.

    if {[llength $argv] < 6 || [lindex $argv 4] ne "--"} {
        send_user "usage: ghostty-remote.exp SERVICE ACCOUNT AUTOFILL HOSTKEY -- COMMAND...\n"
        exit 2
    }
    lassign $argv service account autofill hostkey
    set command [lrange $argv 5 end]

    set password ""
    if {$autofill} {
        if {[catch {exec /usr/bin/security find-generic-password -s $service -a $account -w} result]} {
            send_user "\[Ghostty\] 钥匙串里没有「$account」的密码，请手动输入。可在 工具 → 主机密码 中保存。\n"
        } else {
            set password $result
        }
    }

    set timeout -1
    if {[catch {spawn -noecho {*}$command} err]} {
        send_user "\[Ghostty\] 无法启动 [lindex $command 0]：$err\n"
        exit 127
    }

    # Pass terminal size changes on to the client.
    trap {
        set rows [stty rows]
        set cols [stty columns]
        stty rows $rows columns $cols < $spawn_out(slave,name)
    } WINCH

    set deadline [expr {[clock seconds] + 60}]

    # Watch the output only for prompts we can still answer, and stop at the
    # first one we answer for good: the password, or the host key when there
    # is no password to fill. -nobuffer passes output on as it arrives;
    # without it Expect holds back text that could start a prompt ("p", "(")
    # until more output comes, which leaves full-screen programs such as a
    # bastion's host menu half drawn while they wait for a key.
    set prompts {}
    if {$password ne ""} {
        lappend prompts -nobuffer -re {(?i)password:} {
            if {[clock seconds] < $deadline} {
                send -- "$password\r"
            }
            return
        }
    }
    if {$hostkey eq "accept"} {
        lappend prompts -nobuffer -re {\(yes/no[^)]*\)\?} {
            if {[clock seconds] < $deadline} {
                send -- "yes\r"
            }
            if {$password eq "" || [clock seconds] >= $deadline} {
                return
            }
        }
    }

    # Then pass everything through untouched, like running COMMAND directly.
    set ended 0
    if {[llength $prompts] > 0} {
        interact -o {*}$prompts eof {
            set ended 1
            return
        }
    }
    if {!$ended} {
        interact
    }

    # Exit with the client's status so the tab shows why it ended.
    catch {wait} status
    exit [lindex $status 3]

    """#

    /// `~/Library/Application Support/<bundle id>/remote`.
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty"
        return base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("remote", isDirectory: true)
    }

    /// Writes the script into `directory` unless it is already up to date, and
    /// returns its path.
    @discardableResult
    static func install(in directory: URL = defaultDirectory) throws -> URL {
        let url = directory.appendingPathComponent(fileName)
        let data = Data(source.utf8)
        if (try? Data(contentsOf: url)) == data { return url }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: url, options: .atomic)
        return url
    }
}
