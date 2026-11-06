import Foundation
import Observation

/// A named thing a rule can point at: a brand, a chat widget, a phone line, a procedure.
struct AutomationLookup: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var brandID: String?
    var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, number
        case brandID = "brand_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let name = c.lenient(String.self, forKey: .name) ?? ""
        self.name = name.isEmpty ? (c.lenient(String.self, forKey: .number) ?? id) : name
        brandID = c.lenient(String.self, forKey: .brandID)
        enabled = c.lenient(Bool.self, forKey: .enabled) ?? true
    }
}

/// Settings › Automations: the rules, in order, and what their editors pick from.
@MainActor
@Observable
final class AutomationsStore {
    private(set) var automations: [AutomationRule] = []
    private(set) var load: InboxLoad = .loading
    private(set) var mailboxes: [InboxMailboxRef] = []
    private(set) var brands: [AutomationLookup] = []
    private(set) var widgets: [AutomationLookup] = []
    private(set) var lines: [AutomationLookup] = []
    private(set) var procedures: [AutomationLookup] = []
    private(set) var hasPhone = false
    private(set) var severityEnabled = true

    @ObservationIgnored private var api: APIClient?
    @ObservationIgnored private var lookupsLoaded = false

    func start(api: APIClient, lookups: Bool) async {
        self.api = api
        await reload()
        if lookups && !lookupsLoaded { await loadLookups() }
    }

    func reload() async {
        guard let api else { return }
        do {
            async let page: Page<AutomationRule> = api.get("v1/automations")
            async let flags: InboxWorkspaceFlags? = try? api.get("v1/workspace")
            automations = try await page.data.sorted { $0.position < $1.position }
            if let value = await flags { severityEnabled = value.severityEnabled }
            load = .ready
        } catch {
            if error.isCancellation { return }
            if load != .ready { load = .failed(error.userMessage) }
        }
    }

    /// What the editor's pickers offer. Each is optional: a missing one leaves its picker empty.
    func loadLookups() async {
        guard let api else { return }
        lookupsLoaded = true
        async let mailboxes: Page<InboxMailboxRef>? = try? api.get("v1/mailboxes")
        async let brands: Page<AutomationLookup>? = try? api.get("v1/brands")
        async let widgets: Page<AutomationLookup>? = try? api.get("v1/widgets")
        async let phones: Page<AutomationLookup>? = try? api.get("v1/phone/connections")
        async let lines: Page<AutomationLookup>? = try? api.get("v1/phone/lines")
        async let procedures: Page<AutomationLookup>? = try? api.get("v1/ai/procedures")
        if let page = await mailboxes { self.mailboxes = page.data }
        if let page = await brands { self.brands = page.data }
        if let page = await widgets { self.widgets = page.data }
        if let page = await phones { hasPhone = !page.data.isEmpty }
        if let page = await lines { self.lines = page.data }
        if let page = await procedures { self.procedures = page.data }
    }

    func rule(_ id: String) -> AutomationRule? { automations.first { $0.id == id } }

    // MARK: Writes

    struct Draft: Equatable, Sendable {
        var name = ""
        var trigger: AutomationTrigger = .ticketCreated
        var conditions: [AutomationCondition] = [AutomationCondition(field: "subject", op: "contains", value: "")]
        var actions: [AutomationAction] = [AutomationAction(type: "add_tag")]
        var enabled = true

        init() {}

        init(_ rule: AutomationRule) {
            name = rule.name
            trigger = rule.trigger
            conditions = rule.conditions
            actions = rule.actions
            enabled = rule.enabled
        }
    }

    private struct Body: Encodable, Sendable {
        var name: String
        var trigger: String
        var conditions: [AutomationCondition]
        var actions: [AutomationAction]
        var enabled: Bool
        var position: Int
    }

    func save(_ draft: Draft, existing: AutomationRule?) async throws -> AutomationRule {
        guard let api else { throw APIError.signedOut }
        let body = Body(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            trigger: draft.trigger.rawValue,
            conditions: draft.conditions,
            actions: draft.actions,
            enabled: draft.enabled,
            position: existing?.position ?? automations.count
        )
        let saved: AutomationRule
        if let existing {
            saved = try await api.patch("v1/automations/\(existing.id)", body: body)
        } else {
            saved = try await api.post("v1/automations", body: body)
        }
        upsert(saved)
        return saved
    }

    func setEnabled(_ rule: AutomationRule, _ enabled: Bool) async throws {
        guard let api else { return }
        let before = automations
        if let index = automations.firstIndex(where: { $0.id == rule.id }) { automations[index].enabled = enabled }
        do {
            let saved: AutomationRule = try await api.patch("v1/automations/\(rule.id)", body: ["enabled": enabled])
            upsert(saved)
        } catch {
            automations = before
            throw error
        }
    }

    func delete(_ rule: AutomationRule) async throws {
        guard let api else { return }
        try await api.delete("v1/automations/\(rule.id)")
        automations.removeAll { $0.id == rule.id }
    }

    /// Positions follow the new order; only the rules that moved are written, as on the web.
    func reorder(_ ids: [String]) async throws {
        guard let api else { return }
        let before = automations
        var next: [AutomationRule] = ids.compactMap { id in automations.first { $0.id == id } }
        for index in next.indices { next[index].position = index }
        let changed = next.filter { moved in before.first { $0.id == moved.id }?.position != moved.position }
        automations = next
        do {
            for rule in changed {
                let _: AutomationRule = try await api.patch("v1/automations/\(rule.id)", body: ["position": rule.position])
            }
        } catch {
            automations = before
            throw error
        }
    }

    private func upsert(_ rule: AutomationRule) {
        if let index = automations.firstIndex(where: { $0.id == rule.id }) { automations[index] = rule } else { automations.append(rule) }
        automations.sort { $0.position < $1.position }
    }
}
