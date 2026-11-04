import Foundation

/// Editing of `remote-hosts.json` and the hosts' Keychain passwords for the
/// Tools page of the Settings window. Use from the main thread only.
final class RemoteHostsModel: ObservableObject {
    /// Keychain operations, injectable for tests.
    struct Keychain {
        var hasPassword: (String) -> Bool
        var setPassword: (String, String) throws -> Void
        var deletePassword: (String) throws -> Void
        var movePassword: (String, String) throws -> Void

        static let live = Keychain(
            hasPassword: { RemoteKeychain.hasPassword(account: $0) },
            setPassword: { try RemoteKeychain.setPassword($0, account: $1) },
            deletePassword: { try RemoteKeychain.deletePassword(account: $0) },
            movePassword: { try RemoteKeychain.movePassword(from: $0, to: $1) }
        )
    }

    @Published private(set) var state: RemoteHostStore.State = .missing

    /// Names of hosts with a saved password.
    @Published private(set) var savedPasswords: Set<String> = []

    /// Names of hosts whose reusable logged-in connection is up.
    @Published private(set) var loggedIn: Set<String> = []

    let store: RemoteHostStore
    private let keychain: Keychain

    init(store: RemoteHostStore, keychain: Keychain = .live) {
        self.store = store
        self.keychain = keychain
        refresh()
    }

    var hosts: [RemoteHost] {
        if case .loaded(let hosts) = state { return hosts }
        return []
    }

    func refresh() {
        state = store.state
        savedPasswords = Set(hosts.filter(\.usesKeychainPassword).map(\.name).filter(keychain.hasPassword))
        loggedIn = Set(hosts.filter { $0.muxPlan.map(RemoteMux.isActive) ?? false }.map(\.name))
    }

    /// Closes a host's reusable connection and the sessions using it.
    func disconnect(_ host: RemoteHost) {
        if let plan = host.muxPlan { RemoteMux.disconnect(plan) }
        refresh()
    }

    /// Saves `host`, replacing the host named `original` (nil adds a new
    /// one). A non-empty `password` is saved to the Keychain. Returns a
    /// message describing why nothing (or not everything) was saved.
    func save(_ host: RemoteHost, replacing original: String?, password: String) -> String? {
        var host = host
        host.name = host.name.trimmingCharacters(in: .whitespacesAndNewlines)

        let current: [RemoteHost]
        switch store.state {
        case .missing: current = []
        case .loaded(let hosts): current = hosts
        case .invalid(let message):
            // Never overwrite a file the user is in the middle of fixing.
            return "\(store.fileURL.lastPathComponent) 有错误（\(message)），请先在编辑器里修正"
        }

        if host.name.isEmpty { return "名称不能为空" }
        if host.name != original && current.contains(where: { $0.name == host.name }) {
            return "已经有名为「\(host.name)」的主机"
        }
        if let message = host.validationError() { return message }
        if !password.isEmpty, let message = RemoteKeychain.validationError(for: password) { return message }

        var updated = current
        if let original, let index = updated.firstIndex(where: { $0.name == original }) {
            updated[index] = host
        } else {
            updated.append(host)
        }

        do {
            try store.save(updated)
        } catch {
            return error.localizedDescription
        }

        defer { refresh() }
        do {
            // The Keychain account is the host name.
            if let original, original != host.name {
                try keychain.movePassword(original, host.name)
            }
            if !password.isEmpty {
                try keychain.setPassword(password, host.name)
            }
        } catch {
            return "主机已保存，但密码没有保存：\(error.localizedDescription)"
        }
        return nil
    }

    /// Removes a host and its saved password.
    func delete(_ name: String) -> String? {
        guard case .loaded(let current) = store.state else { return "主机列表有错误，无法删除" }
        do {
            try store.save(current.filter { $0.name != name })
        } catch {
            return error.localizedDescription
        }
        defer { refresh() }
        do {
            try keychain.deletePassword(name)
        } catch {
            return "主机已删除，但钥匙串里的密码没有删除：\(error.localizedDescription)"
        }
        return nil
    }
}
