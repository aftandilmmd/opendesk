import Foundation

// The models of Settings › Developers and Admin (contracts/api.md "API keys", "Webhooks",
// "Audit log", "AI clients"). Every field decodes leniently: a server that grows a field,
// or leaves one out, never blanks a page.

// MARK: - Shared

/// A private team a key or webhook sees, with who granted it: the grant lasts while they are on the team.
struct DevTeamGrant: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var grantedBy: UserRef?

    enum CodingKeys: String, CodingKey {
        case id, name
        case grantedBy = "granted_by"
    }

    init(id: String, name: String, grantedBy: UserRef?) {
        self.id = id
        self.name = name
        self.grantedBy = grantedBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, forKey: .id) ?? ""
        name = c.lenient(String.self, forKey: .name) ?? ""
        grantedBy = c.lenient(UserRef.self, forKey: .grantedBy)
    }
}

/// A team as the private-teams field needs it (`GET /v1/teams`).
struct DevTeam: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var color: String
    var isPrivate: Bool
    var memberIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, color, members
        case isPrivate = "private"
        case memberIDs = "member_ids"
    }

    private struct TeamMember: Decodable { var user_id: String? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, forKey: .id) ?? ""
        name = c.lenient(String.self, forKey: .name) ?? ""
        color = c.lenient(String.self, forKey: .color) ?? ""
        isPrivate = c.lenient(Bool.self, forKey: .isPrivate) ?? false
        let members = (c.lenient([TeamMember].self, forKey: .members) ?? []).compactMap(\.user_id)
        memberIDs = c.lenient([String].self, forKey: .memberIDs) ?? members
    }
}

/// A bot a key can speak as (`GET /v1/bots`).
struct DevBot: Decodable, Hashable, Sendable, Identifiable {
    var ref: BotRef
    var role: String

    var id: String { ref.id }
    var name: String { ref.name }

    private enum CodingKeys: String, CodingKey { case role }

    init(from decoder: Decoder) throws {
        ref = try BotRef(from: decoder)
        role = (try? decoder.container(keyedBy: CodingKeys.self).lenient(String.self, forKey: .role)) ?? ""
    }
}

// MARK: - API keys

struct APIKeyRecord: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var prefix: String
    var scopes: [String]
    var lastUsedAt: Date?
    var expiresAt: Date?
    var createdAt: Date?
    var createdBy: UserRef?
    var privateTeamIDs: [String]
    var privateTeams: [DevTeamGrant]
    var recordRequests: Bool
    /// Recorded requests that failed (400 and up) in the last 24 hours; nil when the key does not record.
    var errorCount24h: Int?
    var botID: String?

    enum CodingKeys: String, CodingKey {
        case id, name, prefix, scopes
        case lastUsedAt = "last_used_at"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case createdBy = "created_by"
        case privateTeamIDs = "private_team_ids"
        case privateTeams = "private_teams"
        case recordRequests = "record_requests"
        case errorCount24h = "error_count_24h"
        case botID = "bot_id"
    }

    init(id: String, name: String, prefix: String, scopes: [String], lastUsedAt: Date? = nil, expiresAt: Date? = nil, createdAt: Date? = nil,
         createdBy: UserRef? = nil, privateTeamIDs: [String] = [], privateTeams: [DevTeamGrant] = [], recordRequests: Bool = false,
         errorCount24h: Int? = nil, botID: String? = nil) {
        self.id = id
        self.name = name
        self.prefix = prefix
        self.scopes = scopes
        self.lastUsedAt = lastUsedAt
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.privateTeamIDs = privateTeamIDs
        self.privateTeams = privateTeams
        self.recordRequests = recordRequests
        self.errorCount24h = errorCount24h
        self.botID = botID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, forKey: .id) ?? ""
        name = c.lenient(String.self, forKey: .name) ?? ""
        prefix = c.lenient(String.self, forKey: .prefix) ?? ""
        scopes = c.lenient([String].self, forKey: .scopes) ?? []
        lastUsedAt = c.lenient(Date.self, forKey: .lastUsedAt)
        expiresAt = c.lenient(Date.self, forKey: .expiresAt)
        createdAt = c.lenient(Date.self, forKey: .createdAt)
        createdBy = c.lenient(UserRef.self, forKey: .createdBy)
        privateTeamIDs = c.lenient([String].self, forKey: .privateTeamIDs) ?? []
        privateTeams = c.lenient([DevTeamGrant].self, forKey: .privateTeams) ?? []
        recordRequests = c.lenient(Bool.self, forKey: .recordRequests) ?? false
        errorCount24h = c.lenient(Int.self, forKey: .errorCount24h)
        botID = c.lenient(String.self, forKey: .botID)
    }

    enum State { case active, expiring, expired }

    /// Expired once its date passed; expiring within 14 days, as the web's list counts.
    func state(now: Date = AppClock.now) -> State {
        guard let expiresAt else { return .active }
        if expiresAt < now { return .expired }
        return expiresAt.timeIntervalSince(now) < 14 * 86400 ? .expiring : .active
    }
}

/// A new key's answer: the row and its secret, shown once.
struct CreatedAPIKey: Decodable, Sendable {
    var key: APIKeyRecord
    var secret: String

    private enum CodingKeys: String, CodingKey { case secret }

    init(from decoder: Decoder) throws {
        key = try APIKeyRecord(from: decoder)
        secret = (try? decoder.container(keyedBy: CodingKeys.self).lenient(String.self, forKey: .secret)) ?? ""
    }
}

/// The scopes a key can hold, grouped as the web's checklist lists them.
enum APIKeyScopes {
    struct Scope: Hashable, Sendable {
        var id: String
        var label: String
    }

    struct Group: Hashable, Sendable, Identifiable {
        var resource: String
        var label: String
        var scopes: [Scope]
        var id: String { resource }
    }

    static let groups: [Group] = [
        Group(resource: "tickets", label: "Tickets", scopes: [Scope(id: "tickets:read", label: "Read"), Scope(id: "tickets:write", label: "Write")]),
        Group(resource: "contacts", label: "Contacts", scopes: [Scope(id: "contacts:read", label: "Read"), Scope(id: "contacts:write", label: "Write")]),
        Group(resource: "kb", label: "Knowledge base", scopes: [Scope(id: "kb:read", label: "Read"), Scope(id: "kb:write", label: "Write")]),
        Group(resource: "changelog", label: "Changelog", scopes: [Scope(id: "changelog:read", label: "Read"), Scope(id: "changelog:write", label: "Write")]),
        Group(resource: "wiki", label: "Wiki", scopes: [Scope(id: "wiki:read", label: "Read"), Scope(id: "wiki:write", label: "Write")]),
        Group(resource: "settings", label: "Settings", scopes: [Scope(id: "settings:read", label: "Read"), Scope(id: "settings:write", label: "Write")]),
        Group(resource: "realtime", label: "Realtime", scopes: [Scope(id: "realtime", label: "Subscribe")]),
        // Acts as the key's creator in Collab: reads the mail they see and saves reply drafts, never sends.
        Group(resource: "collab", label: "Collab (as you)", scopes: [Scope(id: "collab:draft", label: "Draft replies")]),
    ]

    /// collab:draft reaches the creator's mail, so no preset includes it: it is chosen by hand.
    static let optIn: Set<String> = ["collab:draft"]
    static let all: [String] = groups.flatMap { $0.scopes.map(\.id) }.filter { !optIn.contains($0) }
    static let read: [String] = all.filter { $0.hasSuffix(":read") }

    /// Every scope but the opt-in ones.
    static func isFull(_ scopes: [String]) -> Bool { all.allSatisfy(scopes.contains) }
    /// Exactly every read scope.
    static func isReadOnly(_ scopes: [String]) -> Bool { scopes.count == read.count && read.allSatisfy(scopes.contains) }
    /// A key speaks as a bot only where it writes: replies and notes on tickets.
    static func canSpeak(_ scopes: [String]) -> Bool { scopes.contains("tickets:write") }

    enum Level: Sendable {
        case write, readWrite, read, subscribe, draft

        var words: String {
            switch self {
            case .readWrite: "read and write"
            case .write: "write only"
            case .read: "read only"
            case .subscribe: "live events (subscribe)"
            case .draft: "drafts replies as you"
            }
        }
    }

    struct Access: Hashable, Sendable, Identifiable {
        var resource: String
        var level: Level
        var id: String { resource }

        /// The list's name for the resource ("Articles" for kb).
        var name: String {
            switch resource {
            case "tickets": "Tickets"
            case "contacts": "Contacts"
            case "kb": "Articles"
            case "changelog": "Changelog"
            case "wiki": "Wiki"
            case "settings": "Settings"
            case "realtime": "Realtime"
            case "collab": "Collab"
            default: resource
            }
        }

        var words: String { "\(name): \(level.words)" }
    }

    /// A key's scopes as one entry per resource, with exactly the permissions it has there.
    static func grouped(_ scopes: [String]) -> [Access] {
        let set = Set(scopes)
        return groups.compactMap { group in
            let r = group.resource
            switch r {
            case "realtime": return set.contains("realtime") ? Access(resource: r, level: .subscribe) : nil
            case "collab": return set.contains("collab:draft") ? Access(resource: r, level: .draft) : nil
            default:
                if set.contains("\(r):write") { return Access(resource: r, level: set.contains("\(r):read") ? .readWrite : .write) }
                if set.contains("\(r):read") { return Access(resource: r, level: .read) }
                return nil
            }
        }
    }
}

/// A request an API key made while recording was on (`GET /v1/api-keys/{id}/requests`).
struct APIKeyRequestRecord: Decodable, Hashable, Sendable, Identifiable {
    struct TicketRef: Codable, Hashable, Sendable {
        var id: String
        var number: Int?
    }

    var id: String
    var createdAt: Date?
    var method: String
    var path: String
    var query: String
    var status: Int
    var durationMS: Int
    var idempotencyKey: String
    var replayed: Bool
    var ticket: TicketRef?
    var ticketRef: String
    var messageID: String?
    var contactID: String?
    // The detail's fields (`GET …/requests/{requestId}`); empty on the list.
    var requestID: String
    var ip: String
    var userAgent: String
    var contentType: String
    var requestSize: Int
    var requestBody: String?
    var requestTruncated: Bool
    var responseBody: String?
    var responseTruncated: Bool

    enum CodingKeys: String, CodingKey {
        case id, method, path, query, status, replayed, ticket, ip
        case createdAt = "created_at"
        case durationMS = "duration_ms"
        case idempotencyKey = "idempotency_key"
        case ticketRef = "ticket_ref"
        case messageID = "message_id"
        case contactID = "contact_id"
        case requestID = "request_id"
        case userAgent = "user_agent"
        case contentType = "content_type"
        case requestSize = "request_size"
        case requestBody = "request_body"
        case requestTruncated = "request_truncated"
        case responseBody = "response_body"
        case responseTruncated = "response_truncated"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, forKey: .id) ?? ""
        createdAt = c.lenient(Date.self, forKey: .createdAt)
        method = c.lenient(String.self, forKey: .method) ?? ""
        path = c.lenient(String.self, forKey: .path) ?? ""
        query = c.lenient(String.self, forKey: .query) ?? ""
        status = c.lenient(Int.self, forKey: .status) ?? 0
        durationMS = c.lenient(Int.self, forKey: .durationMS) ?? 0
        idempotencyKey = c.lenient(String.self, forKey: .idempotencyKey) ?? ""
        replayed = c.lenient(Bool.self, forKey: .replayed) ?? false
        ticket = c.lenient(TicketRef.self, forKey: .ticket)
        ticketRef = c.lenient(String.self, forKey: .ticketRef) ?? ""
        messageID = c.lenient(String.self, forKey: .messageID)
        contactID = c.lenient(String.self, forKey: .contactID)
        requestID = c.lenient(String.self, forKey: .requestID) ?? ""
        ip = c.lenient(String.self, forKey: .ip) ?? ""
        userAgent = c.lenient(String.self, forKey: .userAgent) ?? ""
        contentType = c.lenient(String.self, forKey: .contentType) ?? ""
        requestSize = c.lenient(Int.self, forKey: .requestSize) ?? 0
        requestBody = c.lenient(String.self, forKey: .requestBody)
        requestTruncated = c.lenient(Bool.self, forKey: .requestTruncated) ?? false
        responseBody = c.lenient(String.self, forKey: .responseBody)
        responseTruncated = c.lenient(Bool.self, forKey: .responseTruncated) ?? false
    }
}

// MARK: - Webhooks

struct WebhookRecord: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var url: String
    var description: String
    var events: [String]
    var headerNames: [String]
    var enabled: Bool
    var verified: Bool
    var createdAt: Date?
    var privateTeamIDs: [String]
    var privateTeams: [DevTeamGrant]

    enum CodingKeys: String, CodingKey {
        case id, url, description, events, enabled, verified
        case headerNames = "header_names"
        case createdAt = "created_at"
        case privateTeamIDs = "private_team_ids"
        case privateTeams = "private_teams"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, forKey: .id) ?? ""
        url = c.lenient(String.self, forKey: .url) ?? ""
        description = c.lenient(String.self, forKey: .description) ?? ""
        events = c.lenient([String].self, forKey: .events) ?? []
        headerNames = c.lenient([String].self, forKey: .headerNames) ?? []
        enabled = c.lenient(Bool.self, forKey: .enabled) ?? true
        // Webhooks made before verification existed count as verified.
        verified = c.lenient(Bool.self, forKey: .verified) ?? true
        createdAt = c.lenient(Date.self, forKey: .createdAt)
        privateTeamIDs = c.lenient([String].self, forKey: .privateTeamIDs) ?? []
        privateTeams = c.lenient([DevTeamGrant].self, forKey: .privateTeams) ?? []
    }

    var allEvents: Bool { WebhookEvents.isAll(events) }
}

/// A new webhook's answer: the row and its signing secret, shown once.
struct CreatedWebhook: Decodable, Sendable {
    var hook: WebhookRecord
    var secret: String

    private enum CodingKeys: String, CodingKey { case secret }

    init(from decoder: Decoder) throws {
        hook = try WebhookRecord(from: decoder)
        secret = (try? decoder.container(keyedBy: CodingKeys.self).lenient(String.self, forKey: .secret)) ?? ""
    }
}

struct WebhookDeliveryRecord: Decodable, Hashable, Sendable, Identifiable {
    enum Status: String, LenientEnum {
        case pending, succeeded, failed
        static let fallback: Status = .pending

        var title: String {
            switch self {
            case .succeeded: "Delivered"
            case .failed: "Failed"
            case .pending: "Pending"
            }
        }

        var tone: Tone {
            switch self {
            case .succeeded: .green
            case .failed: .red
            case .pending: .amber
            }
        }
    }

    var id: String
    var eventID: String
    var eventType: String
    var status: Status
    var attempts: Int
    var responseCode: Int?
    var durationMS: Int?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status, attempts
        case eventID = "event_id"
        case eventType = "event_type"
        case responseCode = "response_code"
        case durationMS = "duration_ms"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, forKey: .id) ?? ""
        eventID = c.lenient(String.self, forKey: .eventID) ?? ""
        eventType = c.lenient(String.self, forKey: .eventType) ?? ""
        status = c.lenient(Status.self, forKey: .status) ?? .pending
        attempts = c.lenient(Int.self, forKey: .attempts) ?? 1
        responseCode = c.lenient(Int.self, forKey: .responseCode)
        durationMS = c.lenient(Int.self, forKey: .durationMS)
        createdAt = c.lenient(Date.self, forKey: .createdAt)
    }
}

/// A webhook's health from its latest deliveries, as the web's list reads it.
enum WebhookHealth: Hashable, Sendable {
    case active, failing, paused, unverified

    init(_ hook: WebhookRecord, deliveries: [WebhookDeliveryRecord]) {
        let finished = deliveries.first { $0.status != .pending }
        // A delivery still retrying after an error response counts as failing too.
        let retrying = deliveries.first?.status == .pending && (deliveries.first?.responseCode ?? 0) >= 400
        if !hook.verified { self = .unverified } else if !hook.enabled { self = .paused } else if retrying || finished?.status == .failed { self = .failing } else { self = .active }
    }

    var title: String {
        switch self {
        case .active: "Active"
        case .failing: "Failing"
        case .paused: "Paused"
        case .unverified: "Not verified"
        }
    }

    var tone: Tone {
        switch self {
        case .active: .green
        case .failing: .red
        case .paused: .gray
        case .unverified: .amber
        }
    }

    /// The row's tile: teal while healthy, as the web's list shows it.
    var tileTone: Tone {
        switch self {
        case .active: .teal
        case .failing: .red
        case .paused: .gray
        case .unverified: .amber
        }
    }
}

/// The events catalog (contracts/events.md), grouped by resource.
enum WebhookEvents {
    struct Group: Hashable, Sendable, Identifiable {
        var label: String
        var events: [String]
        var id: String { label }
    }

    static let groups: [Group] = [
        Group(label: "Tickets", events: ["ticket.created", "ticket.updated", "ticket.deleted"]),
        Group(label: "Messages", events: ["message.created", "message.updated", "message.withdrawn"]),
        Group(label: "Activity", events: ["activity.created", "activity.updated"]),
        Group(label: "Contacts", events: ["contact.created", "contact.updated", "contact.deleted"]),
        Group(label: "Companies", events: ["company.created", "company.updated", "company.deleted"]),
        Group(label: "Labels", events: ["tag.created", "tag.updated", "tag.deleted"]),
        Group(label: "Mailboxes", events: ["mailbox.created", "mailbox.updated", "mailbox.deleted"]),
        Group(label: "Members", events: ["member.added", "member.updated", "member.removed"]),
        Group(label: "Knowledge base", events: ["kb_article.created", "kb_article.updated", "kb_article.deleted", "kb_collection.created", "kb_collection.updated", "kb_collection.deleted"]),
        Group(label: "Changelog", events: ["changelog_entry.created", "changelog_entry.updated", "changelog_entry.deleted"]),
        Group(label: "Wiki", events: ["wiki_page.created", "wiki_page.updated", "wiki_page.moved", "wiki_page.deleted"]),
        Group(label: "Saved replies", events: ["saved_reply.created", "saved_reply.updated", "saved_reply.deleted"]),
        Group(label: "Views", events: ["view.created", "view.updated", "view.deleted"]),
        Group(label: "Automations", events: ["automation.created", "automation.updated", "automation.deleted"]),
        Group(label: "SLA policies", events: ["sla_policy.created", "sla_policy.updated", "sla_policy.deleted"]),
        Group(label: "Teams", events: ["team.created", "team.updated", "team.deleted"]),
    ]

    static let all: [String] = groups.flatMap(\.events)

    /// The server stores "every event, including ones added later" as ["*"] (or []).
    static func isAll(_ events: [String]) -> Bool {
        events.isEmpty || events.contains("*") || all.allSatisfy(events.contains)
    }

    static func expand(_ events: [String]) -> [String] {
        isAll(events) ? all : events
    }

    /// The list's line for a webhook's events.
    static func summary(_ events: [String]) -> String {
        if isAll(events) { return "All events" }
        return events.count == 1 ? events[0] : "\(events.count) events"
    }
}

// MARK: - Audit log

struct AuditEntry: Decodable, Hashable, Sendable, Identifiable {
    struct Actor: Decodable, Hashable, Sendable {
        var type: String
        var user: UserRef?
        var apiKeyID: String?

        enum CodingKeys: String, CodingKey {
            case type, user
            case apiKeyID = "api_key_id"
        }

        init(type: String, user: UserRef?, apiKeyID: String?) {
            self.type = type
            self.user = user
            self.apiKeyID = apiKeyID
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = c.lenient(String.self, forKey: .type) ?? "system"
            user = c.lenient(UserRef.self, forKey: .user)
            apiKeyID = c.lenient(String.self, forKey: .apiKeyID)
        }
    }

    var id: String
    var actor: Actor
    var action: String
    var entityType: String
    var entityID: String?
    var data: [String: JSONValue]
    var ip: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, actor, action, data, ip
        case entityType = "entity_type"
        case entityID = "entity_id"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, forKey: .id) ?? UUID().uuidString
        actor = c.lenient(Actor.self, forKey: .actor) ?? Actor(type: "system", user: nil, apiKeyID: nil)
        action = c.lenient(String.self, forKey: .action) ?? ""
        entityType = c.lenient(String.self, forKey: .entityType) ?? ""
        entityID = c.lenient(String.self, forKey: .entityID)
        data = c.lenient([String: JSONValue].self, forKey: .data) ?? [:]
        ip = c.lenient(String.self, forKey: .ip) ?? ""
        createdAt = c.lenient(Date.self, forKey: .createdAt) ?? .distantPast
    }
}

// MARK: - AI clients

struct AIClientTool: Decodable, Hashable, Sendable, Identifiable {
    var name: String
    var title: String
    var description: String
    var scopes: [String]
    var readOnly: Bool
    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, title, description, scopes
        case readOnly = "read_only"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenient(String.self, forKey: .name) ?? ""
        title = c.lenient(String.self, forKey: .title) ?? ""
        description = c.lenient(String.self, forKey: .description) ?? ""
        scopes = c.lenient([String].self, forKey: .scopes) ?? []
        readOnly = c.lenient(Bool.self, forKey: .readOnly) ?? true
    }

    /// Tool descriptions are written for models; the first sentence is enough here.
    var firstSentence: String {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var previous: Character?
        for index in text.indices {
            let character = text[index]
            if let mark = previous, ".!?".contains(mark), character.isWhitespace {
                return String(text[..<text.index(before: index)]) + String(mark)
            }
            previous = character
        }
        return text
    }
}

struct AIClientServerInfo: Decodable, Sendable {
    var url: String
    var tools: [AIClientTool]

    enum CodingKeys: String, CodingKey { case url, tools }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = c.lenient(String.self, forKey: .url) ?? ""
        tools = c.lenient([AIClientTool].self, forKey: .tools) ?? []
    }
}

struct AIClientConnectionRecord: Decodable, Hashable, Sendable, Identifiable {
    struct Client: Decodable, Hashable, Sendable {
        var name: String
        var redirectHost: String
        var local: Bool

        enum CodingKeys: String, CodingKey {
            case name, local
            case redirectHost = "redirect_host"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = c.lenient(String.self, forKey: .name) ?? "AI client"
            redirectHost = c.lenient(String.self, forKey: .redirectHost) ?? ""
            local = c.lenient(Bool.self, forKey: .local) ?? false
        }
    }

    var id: String
    var client: Client
    var user: UserRef?
    var mine: Bool
    var scopes: [String]
    var lastUsedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, client, user, mine, scopes
        case lastUsedAt = "last_used_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, forKey: .id) ?? ""
        client = try c.decode(Client.self, forKey: .client)
        user = c.lenient(UserRef.self, forKey: .user)
        mine = c.lenient(Bool.self, forKey: .mine) ?? false
        scopes = c.lenient([String].self, forKey: .scopes) ?? []
        lastUsedAt = c.lenient(Date.self, forKey: .lastUsedAt)
    }
}

/// The AI clients the setup lists, and what each needs (web `components/aiClients/snippets.ts`).
enum AIClientSetup: String, CaseIterable, Identifiable, Sendable {
    case claude, chatgpt, claudeCode, claudeDesktop, cursor, vscode, other

    var id: String { rawValue }

    static let keyPlaceholder = "od_live_..."
    /// Read scopes for an assistant that only reads; write adds what replying and drafting need.
    static let readScopes = ["tickets:read", "contacts:read", "kb:read", "wiki:read"]
    static let writeScopes = readScopes + ["tickets:write", "contacts:write", "kb:write", "wiki:write"]

    var label: String {
        switch self {
        case .claude: "Claude"
        case .chatgpt: "ChatGPT"
        case .claudeCode: "Claude Code"
        case .claudeDesktop: "Claude Desktop"
        case .cursor: "Cursor"
        case .vscode: "VS Code"
        case .other: "Other"
        }
    }

    /// Signs in with OAuth (only the URL is needed), or sends an API key in a header.
    var oauth: Bool {
        switch self {
        case .claudeDesktop, .cursor, .vscode: false
        default: true
        }
    }

    var usesKey: Bool { !oauth || self == .claudeCode || self == .other }

    var steps: String {
        switch self {
        case .claude: "In Claude, open Settings, then Connectors, and choose Add custom connector. Paste the URL and select Connect. Sign in to opendesk and approve."
        case .chatgpt: "In ChatGPT, add a connector in developer mode with this URL and OAuth authentication. Sign in to opendesk and approve."
        case .claudeCode: "Run this in your terminal. Claude Code opens opendesk to sign in the first time you use the server."
        case .claudeDesktop: "Prefer a connector with sign-in (see Claude). To use an API key, open Settings, then Developer, then Edit config, add this and restart Claude Desktop. It needs Node.js."
        case .cursor: "Add this to ~/.cursor/mcp.json for all projects, or .cursor/mcp.json for one. Then check Cursor Settings, MCP."
        case .vscode: "Add this as .vscode/mcp.json in your workspace. VS Code asks for the key the first time and stores it securely."
        case .other: "Any client that speaks Streamable HTTP works: with OAuth if it supports the MCP authorization spec, otherwise with an API key in the Authorization header."
        }
    }

    /// Copyable snippets, in order. `key` fills them when the person just made one.
    func snippets(url: String, key: String?) -> [String] {
        let k = key ?? Self.keyPlaceholder
        switch self {
        case .claude, .chatgpt: return [url]
        case .claudeCode: return ["claude mcp add --transport http opendesk \(url)"]
        case .claudeDesktop:
            return [Self.json([
                "mcpServers": ["opendesk": [
                    "command": "npx",
                    "args": ["-y", "mcp-remote", url, "--header", "Authorization:${OPENDESK_AUTH}"],
                    "env": ["OPENDESK_AUTH": "Bearer \(k)"],
                ]],
            ])]
        case .cursor:
            return [Self.json(["mcpServers": ["opendesk": ["url": url, "headers": ["Authorization": "Bearer \(k)"]]]])]
        case .vscode:
            return [Self.json([
                "inputs": [["type": "promptString", "id": "opendesk-key", "description": "opendesk API key", "password": true]],
                "servers": ["opendesk": ["type": "http", "url": url, "headers": ["Authorization": "Bearer ${input:opendesk-key}"]]],
            ])]
        case .other: return [url, "Authorization: Bearer \(k)"]
        }
    }

    /// The second way with an API key, under a note (Claude Code).
    func keySnippets(url: String, key: String?) -> [String] {
        guard self == .claudeCode else { return [] }
        return ["claude mcp add --transport http opendesk \(url) \\\n  --header \"Authorization: Bearer \(key ?? Self.keyPlaceholder)\""]
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
