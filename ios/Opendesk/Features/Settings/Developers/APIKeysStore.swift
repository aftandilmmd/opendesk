import Foundation
import Observation

/// Settings › API keys: the workspace's keys, shared by the list and a key's page
/// (contracts/api.md "API keys"). Admins only; every call is a person's, never a key's.
@MainActor
@Observable
final class APIKeysStore {
    static let shared = APIKeysStore()

    private(set) var keys: [APIKeyRecord] = []
    private(set) var loaded = false
    private(set) var error: String?
    @ObservationIgnored private var workspaceID: String?
    @ObservationIgnored private weak var session: SessionStore?

    private var api: APIClient? { session?.api }

    func key(_ id: String) -> APIKeyRecord? { keys.first { $0.id == id } }

    /// Newest first, as the web lists them.
    var sorted: [APIKeyRecord] {
        keys.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    /// The session to call with, forgetting another workspace's keys.
    func attach(_ session: SessionStore) {
        self.session = session
        if session.workspace?.id != workspaceID {
            workspaceID = session.workspace?.id
            keys = []
            loaded = false
            error = nil
        }
    }

    func load(_ session: SessionStore) async {
        attach(session)
        do {
            let list: [APIKeyRecord] = try await session.api.all("v1/api-keys")
            keys = list
            error = nil
        } catch {
            if !error.isCancellation { self.error = error.userMessage }
        }
        loaded = true
    }

    // MARK: Changes

    struct NewKey: Sendable {
        var name: String
        var scopes: [String]
        var expiresAt: Date?
        var privateTeamIDs: [String] = []
        var botID: String?
    }

    /// Needs a recent sign-in (with two-factor when on): `reauth_required` / `mfa_required`.
    func create(_ new: NewKey) async throws -> CreatedAPIKey {
        guard let api else { throw APIError.signedOut }
        var body: [String: JSONValue] = [
            "name": .string(new.name),
            "scopes": .array(new.scopes.map(JSONValue.string)),
            "expires_at": new.expiresAt.map { .string($0.devISO) } ?? .null,
        ]
        if !new.privateTeamIDs.isEmpty { body["private_team_ids"] = .array(new.privateTeamIDs.map(JSONValue.string)) }
        if let bot = new.botID, APIKeyScopes.canSpeak(new.scopes) { body["bot_id"] = .string(bot) }
        let created: CreatedAPIKey = try await api.post("v1/api-keys", body: body)
        keys.insert(created.key, at: 0)
        return created
    }

    /// A PATCH with only the fields given; `null` where a value is cleared (no expiry, no bot).
    @discardableResult
    func update(_ id: String, _ patch: [String: JSONValue]) async throws -> APIKeyRecord {
        guard let api else { throw APIError.signedOut }
        let key: APIKeyRecord = try await api.patch("v1/api-keys/\(id)", body: patch)
        upsert(key)
        return key
    }

    /// Changes shown at once and put back when the server refuses.
    func optimistic(_ id: String, _ patch: [String: JSONValue], apply: (inout APIKeyRecord) -> Void) async throws {
        guard let index = keys.firstIndex(where: { $0.id == id }) else { return }
        let before = keys[index]
        apply(&keys[index])
        do {
            try await update(id, patch)
        } catch {
            if let index = keys.firstIndex(where: { $0.id == id }) { keys[index] = before }
            throw error
        }
    }

    func revoke(_ id: String) async throws {
        guard let api else { throw APIError.signedOut }
        let before = keys
        keys.removeAll { $0.id == id }
        do {
            try await api.delete("v1/api-keys/\(id)")
        } catch {
            keys = before
            throw error
        }
    }

    func upsert(_ key: APIKeyRecord) {
        if let index = keys.firstIndex(where: { $0.id == key.id }) { keys[index] = key } else { keys.insert(key, at: 0) }
    }
}
