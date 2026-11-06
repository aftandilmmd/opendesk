import Foundation

/// One account signed in on this phone: a person on a server. Each has its own
/// session and refresh token (contracts/native.md "Native sessions"); the app
/// holds several at once, as a browser does (contracts/tokens.md "Several
/// accounts in one browser"), and one of them is open.
struct DeviceAccount: Codable, Hashable, Identifiable, Sendable {
    var instance: Instance
    var userID: String
    var name: String
    var email: String
    var avatarURL: String?
    /// The workspaces the account belongs to, as of its last load: a push names
    /// only its server and workspace, and this tells which account it is for.
    var workspaceIDs: [String]

    var id: String { Self.id(instance: instance, userID: userID) }

    static func id(instance: Instance, userID: String) -> String { instance.storageKey + "|" + userID }

    /// The Keychain item that holds this account's refresh token.
    var tokenKey: String { "refresh." + instance.storageKey + "." + userID }

    var displayName: String { name.isEmpty ? email : name }

    init(instance: Instance, me: Me) {
        self.instance = instance
        userID = me.user.id
        name = me.user.name
        email = me.user.email
        avatarURL = me.user.avatarURL
        workspaceIDs = me.memberships.map(\.id)
    }

    func belongs(to workspaceID: String?) -> Bool {
        guard let workspaceID else { return false }
        return workspaceIDs.contains(workspaceID)
    }
}

/// The accounts on this phone and which one is open, kept in the Keychain next
/// to their tokens (device only, never synced). Names and addresses stay out of
/// `UserDefaults`.
enum AccountKeyring {
    /// As many as a browser holds (contracts/tokens.md).
    static let maxAccounts = 5

    struct Saved: Codable, Sendable {
        var active: String?
        var accounts: [DeviceAccount] = []
    }

    private static let item = "accounts.v1"

    static func load() -> Saved {
        guard let raw = KeychainStore.get(item), let saved = try? JSONDecoder().decode(Saved.self, from: Data(raw.utf8)) else {
            return Saved()
        }
        return saved
    }

    static func save(_ saved: Saved) {
        guard !saved.accounts.isEmpty else {
            KeychainStore.remove(item)
            return
        }
        guard let data = try? JSONEncoder().encode(saved), let raw = String(data: data, encoding: .utf8) else { return }
        KeychainStore.set(raw, for: item)
    }

    /// Where versions with one account kept its refresh token: one item per server.
    static func legacyTokenKey(for instance: Instance) -> String { "refresh." + instance.storageKey }
}
