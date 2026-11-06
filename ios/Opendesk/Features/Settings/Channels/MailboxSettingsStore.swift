import Foundation
import Observation

/// Settings › Mailboxes: the workspace's mailboxes and what adding and editing one needs.
@MainActor
@Observable
final class MailboxSettingsStore {
    private(set) var mailboxes: [SettingsMailbox] = []
    private(set) var loaded = false
    private(set) var error: String?
    /// Viewers can't read mailbox settings at all.
    private(set) var forbidden = false
    private(set) var options = MailboxConnectOptions()
    private(set) var brands: [SettingsBrand] = []
    private(set) var bots: [ChannelBotOption] = []

    @ObservationIgnored private var api: APIClient?

    func attach(_ api: APIClient) { self.api = api }

    /// Needs attention first, then active, then disabled; by name within each.
    var sorted: [SettingsMailbox] {
        mailboxes.sorted { a, b in
            let ra = a.needsAttention ? 0 : (a.disabled ? 2 : 1)
            let rb = b.needsAttention ? 0 : (b.disabled ? 2 : 1)
            return ra != rb ? ra < rb : a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
        }
    }

    func load() async {
        guard let api else { return }
        do {
            let page: ChannelList<SettingsMailbox> = try await api.get("v1/mailboxes", query: [URLQueryItem(name: "limit", value: "100")])
            mailboxes = page.data
            error = nil
            forbidden = false
        } catch let failure as APIError where failure.status == 403 {
            forbidden = true
        } catch {
            if !error.isCancellation { self.error = error.userMessage }
        }
        loaded = true
    }

    /// Brands, bots and the instance's connect options, for the editors (each optional).
    func loadExtras(admin: Bool) async {
        guard let api else { return }
        async let brands: ChannelList<SettingsBrand>? = try? api.get("v1/brands", query: [URLQueryItem(name: "limit", value: "100")])
        async let bots: ChannelList<ChannelBotOption>? = try? api.get("v1/bots")
        if admin, let options: MailboxConnectOptions = try? await api.get("v1/mailboxes/connect-options") { self.options = options }
        if let page = await brands { self.brands = page.data.sorted { $0.isDefault != $1.isDefault ? $0.isDefault : $0.position < $1.position } }
        if let page = await bots { self.bots = page.data }
    }

    func mailbox(_ id: String) -> SettingsMailbox? { mailboxes.first { $0.id == id } }

    func fetch(_ id: String) async throws -> SettingsMailbox {
        guard let api else { throw CancellationError() }
        let mailbox: SettingsMailbox = try await api.get("v1/mailboxes/\(id)")
        upsert(mailbox)
        return mailbox
    }

    func upsert(_ mailbox: SettingsMailbox) {
        if let index = mailboxes.firstIndex(where: { $0.id == mailbox.id }) { mailboxes[index] = mailbox } else { mailboxes.append(mailbox) }
    }

    func test(_ id: String) async throws -> MailboxTestResult {
        guard let api else { throw CancellationError() }
        return try await api.post("v1/mailboxes/\(id)/test")
    }

    @discardableResult
    func patch(_ id: String, _ body: ChannelBody) async throws -> SettingsMailbox {
        guard let api else { throw CancellationError() }
        let mailbox: SettingsMailbox = try await api.patch("v1/mailboxes/\(id)", body: body)
        upsert(mailbox)
        return mailbox
    }

    func create(_ body: ChannelBody) async throws -> SettingsMailbox {
        guard let api else { throw CancellationError() }
        let mailbox: SettingsMailbox = try await api.post("v1/mailboxes", body: body, idempotencyKey: UUID().uuidString)
        upsert(mailbox)
        return mailbox
    }

    /// Turns a mailbox on or off at once, as the list and the danger zone do.
    func setEnabled(_ mailbox: SettingsMailbox, _ on: Bool) async throws {
        try await patch(mailbox.id, ["status": .string(on ? "active" : "disabled")])
    }

    func usage(_ id: String) async -> MailboxUsage? {
        guard let api else { return nil }
        return try? await api.get("v1/mailboxes/\(id)/usage")
    }

    func remove(_ id: String) async throws {
        guard let api else { return }
        try await api.delete("v1/mailboxes/\(id)")
        mailboxes.removeAll { $0.id == id }
    }

    func detect(_ email: String) async -> MailboxDetection? {
        guard let api else { return nil }
        return try? await api.post("v1/mailboxes/detect", body: ["email": email])
    }

    func checkSendAs(_ id: String) async throws {
        guard let api else { return }
        let mailbox: SettingsMailbox = try await api.post("v1/mailboxes/\(id)/send-as/check")
        upsert(mailbox)
    }

    /// What removing a mailbox does, from its usage.
    static func removeMessage(_ mailbox: SettingsMailbox, usage: MailboxUsage?) -> String {
        guard let usage, usage.tickets > 0 else {
            return "Mail sent to \(mailbox.email) stops arriving in opendesk. Existing tickets stay."
        }
        if usage.tickets == 1 {
            return "Mail sent to \(mailbox.email) stops arriving in opendesk. The ticket that replies from it stays (\(usage.open) open), but its replies will no longer go out from \(mailbox.email)."
        }
        return "Mail sent to \(mailbox.email) stops arriving in opendesk. The \(usage.tickets) tickets that reply from it stay (\(usage.open) open), but their replies will no longer go out from \(mailbox.email)."
    }
}
