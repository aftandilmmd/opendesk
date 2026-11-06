import Foundation
import Observation

/// Settings › Webhooks: the workspace's endpoints and their recent deliveries, shared by the
/// list and a webhook's page (contracts/api.md "Webhooks"). Admins only.
@MainActor
@Observable
final class WebhooksStore {
    static let shared = WebhooksStore()

    private(set) var hooks: [WebhookRecord] = []
    private(set) var loaded = false
    private(set) var error: String?
    /// The last 50 attempts per webhook, newest first.
    private(set) var deliveries: [String: [WebhookDeliveryRecord]] = [:]
    private(set) var deliveriesLoading: Set<String> = []
    @ObservationIgnored private var workspaceID: String?
    @ObservationIgnored private weak var session: SessionStore?

    private var api: APIClient? { session?.api }

    func hook(_ id: String) -> WebhookRecord? { hooks.first { $0.id == id } }

    func health(_ hook: WebhookRecord) -> WebhookHealth {
        WebhookHealth(hook, deliveries: deliveries[hook.id] ?? [])
    }

    func load(_ session: SessionStore) async {
        self.session = session
        if session.workspace?.id != workspaceID {
            workspaceID = session.workspace?.id
            hooks = []
            deliveries = [:]
            loaded = false
            error = nil
        }
        do {
            let page: Page<WebhookRecord> = try await session.api.get("v1/webhooks", query: [URLQueryItem(name: "limit", value: "100")])
            hooks = page.data
            error = nil
        } catch {
            if !error.isCancellation { self.error = error.userMessage }
        }
        loaded = true
    }

    /// The deliveries of the first 25 webhooks, for the list's health and success rate.
    func loadAllDeliveries() async {
        guard let api else { return }
        let ids = hooks.prefix(25).map(\.id)
        let results = await withTaskGroup(of: (String, [WebhookDeliveryRecord]?).self) { group in
            for id in ids {
                group.addTask {
                    let page: Page<WebhookDeliveryRecord>? = try? await api.get("v1/webhooks/\(id)/deliveries", query: [URLQueryItem(name: "limit", value: "50")])
                    return (id, page?.data)
                }
            }
            var out: [(String, [WebhookDeliveryRecord]?)] = []
            for await result in group { out.append(result) }
            return out
        }
        for (id, list) in results { if let list { deliveries[id] = list } }
    }

    func loadDeliveries(_ id: String) async {
        guard let api else { return }
        deliveriesLoading.insert(id)
        defer { deliveriesLoading.remove(id) }
        if let page: Page<WebhookDeliveryRecord> = try? await api.get("v1/webhooks/\(id)/deliveries", query: [URLQueryItem(name: "limit", value: "50")]) {
            deliveries[id] = page.data
        }
    }

    // MARK: Changes

    struct Form: Sendable {
        var url: String
        var description: String
        var events: [String]
        var enabled: Bool
        /// nil keeps the configured headers.
        var headers: [String: String]?
        /// nil keeps the private teams.
        var privateTeamIDs: [String]?

        var body: [String: JSONValue] {
            var body: [String: JSONValue] = [
                "url": .string(url),
                "description": .string(description),
                "events": .array((WebhookEvents.all.allSatisfy(events.contains) ? ["*"] : events).map(JSONValue.string)),
                "enabled": .bool(enabled),
            ]
            if let headers { body["headers"] = .object(headers.mapValues(JSONValue.string)) }
            if let privateTeamIDs { body["private_team_ids"] = .array(privateTeamIDs.map(JSONValue.string)) }
            return body
        }
    }

    func create(_ form: Form) async throws -> CreatedWebhook {
        guard let api else { throw APIError.signedOut }
        let created: CreatedWebhook = try await api.post("v1/webhooks", body: form.body)
        hooks.insert(created.hook, at: 0)
        return created
    }

    @discardableResult
    func update(_ id: String, _ body: [String: JSONValue]) async throws -> WebhookRecord {
        guard let api else { throw APIError.signedOut }
        let hook: WebhookRecord = try await api.patch("v1/webhooks/\(id)", body: body)
        upsert(hook)
        return hook
    }

    /// Pauses or resumes at once, put back when the server refuses.
    func setEnabled(_ id: String, _ enabled: Bool) async throws {
        guard let index = hooks.firstIndex(where: { $0.id == id }) else { return }
        let before = hooks[index]
        hooks[index].enabled = enabled
        do {
            try await update(id, ["enabled": .bool(enabled)])
        } catch {
            if let index = hooks.firstIndex(where: { $0.id == id }) { hooks[index] = before }
            throw error
        }
    }

    func remove(_ id: String) async throws {
        guard let api else { throw APIError.signedOut }
        let before = hooks
        hooks.removeAll { $0.id == id }
        do {
            try await api.delete("v1/webhooks/\(id)")
            deliveries[id] = nil
        } catch {
            hooks = before
            throw error
        }
    }

    /// Sends `webhook.test`; `409 webhook_unverified` before the address is verified.
    func test(_ id: String) async throws {
        guard let api else { throw APIError.signedOut }
        let delivery: WebhookDeliveryRecord = try await api.post("v1/webhooks/\(id)/test")
        if delivery.id.isEmpty {
            await loadDeliveries(id)
        } else {
            deliveries[id] = [delivery] + (deliveries[id] ?? []).filter { $0.id != delivery.id }
        }
    }

    /// With a code: verifies the address with the challenge it received. Without: sends a new challenge.
    func verify(_ id: String, code: String?) async throws -> WebhookRecord {
        guard let api else { throw APIError.signedOut }
        var body: [String: JSONValue] = [:]
        if let code { body["code"] = .string(code) }
        let hook: WebhookRecord = try await api.post("v1/webhooks/\(id)/verify", body: body)
        upsert(hook)
        return hook
    }

    private func upsert(_ hook: WebhookRecord) {
        if let index = hooks.firstIndex(where: { $0.id == hook.id }) { hooks[index] = hook } else { hooks.insert(hook, at: 0) }
    }
}
