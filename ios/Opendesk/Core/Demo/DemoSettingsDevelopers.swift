#if DEBUG
import Foundation

// The demo's Developers and Admin settings (`Features/Settings/Developers`): Margin's API keys
// with their request logs, its webhooks with deliveries, its audit log, and the AI clients
// connected over MCP. Lumen Labs, where Maya is an agent, has none (the pages say admins only).
//
//   Keys      Zapier sync (records requests, 3 failures today), Data warehouse export (read only),
//             Support autopilot (speaks as Ollie, expires in 9 days), Status page (never used),
//             Staging smoke tests (expired)
//   Webhooks  hooks.margin.app (healthy, a custom header), api.copperleaf.dev (failing),
//             n8n.margin.app (paused, every event), staging.margin.app (not verified yet)
//
// The first new key, added permission or later expiry of a run asks for a fresh sign-in, as a
// session older than 12 hours would; "Confirm it's you" then lets it through.

struct DemoDeveloperSettings: Sendable {
    var keys: [APIKeyRecord] = []
    var requests: [String: [DemoKeyRequest]] = [:]
    var webhooks: [DemoWebhook] = []
    var deliveries: [String: [DemoDelivery]] = [:]
    var audit: [DemoAuditEntry] = []
    var connections: [DemoAIConnection] = []
    /// Set once the run asked for a fresh sign-in.
    var signedInAgain = false

    static func id(_ n: Int) -> String { demoKBID(0x40, n) }

    static func seed(_ ws: DemoWorkspace) -> DemoDeveloperSettings {
        guard ws.id == DemoSeed.marginID else { return DemoDeveloperSettings() }
        var out = DemoDeveloperSettings()
        out.keys = keys()
        out.requests = [id(1): zapierRequests(), id(3): autopilotRequests()]
        out.webhooks = webhooks()
        out.deliveries = deliveries()
        out.audit = audit()
        out.connections = connections()
        return out
    }

    // MARK: Keys

    private static func keys() -> [APIKeyRecord] {
        [
            APIKeyRecord(
                id: id(1), name: "Zapier sync", prefix: "od_live_zp4k9q2m", scopes: ["tickets:read", "tickets:write", "contacts:read"],
                lastUsedAt: DemoSeed.ago(3), expiresAt: DemoSeed.ahead(60 * 1440), createdAt: DemoSeed.ago(120 * 1440),
                createdBy: DemoPerson.jonas.ref, recordRequests: true
            ),
            APIKeyRecord(
                id: id(2), name: "Data warehouse export", prefix: "od_live_dw7h1x0c", scopes: APIKeyScopes.read,
                lastUsedAt: DemoSeed.ago(130), expiresAt: nil, createdAt: DemoSeed.ago(200 * 1440), createdBy: DemoPerson.maya.ref
            ),
            APIKeyRecord(
                id: id(3), name: "Support autopilot", prefix: "od_live_ap2b8n5t", scopes: ["tickets:read", "tickets:write", "kb:read", "realtime"],
                lastUsedAt: DemoSeed.ago(0.5), expiresAt: DemoSeed.ahead(9 * 1440), createdAt: DemoSeed.ago(81 * 1440),
                createdBy: DemoPerson.maya.ref, recordRequests: true, botID: DemoSeed.ollie.id
            ),
            APIKeyRecord(
                id: id(4), name: "Status page", prefix: "od_live_st0r6w3e", scopes: ["kb:read", "changelog:read", "changelog:write"],
                lastUsedAt: nil, expiresAt: DemoSeed.ahead(300 * 1440), createdAt: DemoSeed.ago(6 * 1440), createdBy: DemoPerson.sam.ref
            ),
            APIKeyRecord(
                id: id(5), name: "Staging smoke tests", prefix: "od_live_sg9y5u1i", scopes: APIKeyScopes.all,
                lastUsedAt: DemoSeed.ago(25 * 1440), expiresAt: DemoSeed.ago(20 * 1440), createdAt: DemoSeed.ago(400 * 1440), createdBy: DemoPerson.priya.ref
            ),
        ]
    }

    private static func zapierRequests() -> [DemoKeyRequest] {
        let ticket = DemoSeed.ticketID(1072)
        let shapes: [(String, String, String, Int, Int?)] = [
            ("GET", "/v1/tickets", "status=open&limit=50", 200, nil),
            ("POST", "/v1/tickets/\(ticket)/messages", "", 201, 1072),
            ("GET", "/v1/contacts", "email=z***%40copperleaf.dev", 200, nil),
            ("PATCH", "/v1/tickets/1065", "", 200, 1065),
            ("POST", "/v1/tickets", "", 422, nil),
            ("GET", "/v1/tickets/1071", "", 200, 1071),
            ("POST", "/v1/tickets/1064/messages", "", 429, 1064),
            ("GET", "/v1/tickets/9999", "", 404, nil),
            ("GET", "/v1/tickets", "updated_since=2026-06-15T00%3A00%3A00Z", 200, nil),
            ("PATCH", "/v1/tickets/1033", "", 500, 1033),
        ]
        var out: [DemoKeyRequest] = []
        for n in 0 ..< 64 {
            let shape = shapes[(n * 7 + n / 3) % shapes.count]
            // Today's failures sit in the last day; older ones are spread over the week.
            let minutes = n < 20 ? Double(3 + n * 61) : Double(1300 + (n - 20) * 197)
            out.append(request(n: n, key: 1, shape: shape, minutes: minutes, agent: "Zapier/1.0 (+https://zapier.com)", ip: "54.86.50.\(140 + n % 9)"))
        }
        return out
    }

    private static func autopilotRequests() -> [DemoKeyRequest] {
        let shapes: [(String, String, String, Int, Int?)] = [
            ("GET", "/v1/tickets", "status=open&assignee=none", 200, nil),
            ("GET", "/v1/kb/articles", "q=sso%20login%20loop", 200, nil),
            ("POST", "/v1/tickets/1086/messages", "", 201, 1086),
            ("POST", "/v1/tickets/1069/messages", "", 201, 1069),
            ("GET", "/v1/tickets/1086", "", 200, 1086),
        ]
        return (0 ..< 14).map { n in
            request(n: n, key: 3, shape: shapes[n % shapes.count], minutes: 0.5 + Double(n) * 47, agent: "margin-autopilot/2.3 node-fetch", ip: "10.24.3.18")
        }
    }

    private static func request(n: Int, key: Int, shape: (String, String, String, Int, Int?), minutes: Double, agent: String, ip: String) -> DemoKeyRequest {
        let (method, path, query, status, number) = shape
        let write = method != "GET"
        let ticketID = number.map { DemoSeed.ticketID($0) }
        var body: String?
        if write {
            if path.hasSuffix("/messages") {
                body = #"{"kind":"reply","body_html":"<p>Thanks for the details. We pushed a fix for the login loop and it is live now.</p>","to":["z***@copperleaf.dev"]}"#
            } else if method == "PATCH" {
                body = #"{"status":"pending","priority":"high","tags":["api"]}"#
            } else {
                body = #"{"subject":"Import failed for workspace 4411","contact":{"email":"i***@northwind.io"}}"#
            }
        }
        var answer: String?
        switch status {
        case 422: answer = #"{"status":422,"code":"validation_failed","detail":"mailbox_id is required when the workspace has more than one mailbox.","request_id":"req_7Hq2"}"#
        case 429: answer = #"{"status":429,"code":"rate_limited","detail":"Too many requests for this key. Retry after 12 seconds."}"#
        case 404: answer = #"{"status":404,"code":"not_found","detail":"That ticket isn't here any more."}"#
        case 500: answer = #"{"status":500,"code":"internal","detail":"Something went wrong on our side. Quote the request id if you contact support.","request_id":"req_9Lp4"}"#
        default: answer = nil
        }
        return DemoKeyRequest(
            id: demoKBID(0x41 + key, n + 1), createdAt: DemoSeed.ago(minutes), method: method, path: path, query: query, status: status,
            durationMS: status >= 500 ? 2140 : 38 + (n * 37) % 260, idempotencyKey: write && status < 300 ? "zap-\(4100 + n)" : "",
            replayed: write && n % 11 == 4, ticket: ticketID.map { APIKeyRequestRecord.TicketRef(id: $0, number: number) },
            ticketRef: number.map(String.init) ?? "", messageID: path.hasSuffix("/messages") && status < 300 ? demoID(.message, 9000 + n) : nil,
            contactID: path.hasPrefix("/v1/contacts") ? demoID(.contact, 3) : nil, requestID: "req_\(String(format: "%06x", 0x3a9f00 + n * 977))",
            ip: ip, userAgent: agent, contentType: write ? "application/json" : "", requestSize: write ? 420 + n * 13 : 0,
            requestBody: body, requestTruncated: false, responseBody: answer, responseTruncated: false
        )
    }

    // MARK: Webhooks

    private static func webhooks() -> [DemoWebhook] {
        [
            DemoWebhook(
                id: id(11), url: "https://hooks.margin.app/opendesk/tickets", description: "Sync tickets to the data warehouse",
                events: ["ticket.created", "ticket.updated", "ticket.deleted", "message.created"], headerNames: ["Authorization"],
                enabled: true, verified: true, createdAt: DemoSeed.ago(180 * 1440)
            ),
            DemoWebhook(
                id: id(12), url: "https://api.copperleaf.dev/webhooks/opendesk", description: "Copperleaf CRM contacts",
                events: ["contact.created", "contact.updated", "contact.deleted", "company.created", "company.updated", "company.deleted"],
                enabled: true, verified: true, createdAt: DemoSeed.ago(64 * 1440)
            ),
            DemoWebhook(
                id: id(13), url: "https://n8n.margin.app/webhook/help-center", description: "Post help center updates to Slack",
                events: ["*"], enabled: false, verified: true, createdAt: DemoSeed.ago(32 * 1440)
            ),
            DemoWebhook(
                id: id(14), url: "https://staging.margin.app/hooks/opendesk", description: "",
                events: ["ticket.created", "ticket.updated"], enabled: true, verified: false, createdAt: DemoSeed.ago(55), challenge: "whv_demo_7f3k2q"
            ),
        ]
    }

    private static func deliveries() -> [String: [DemoDelivery]] {
        let ticketEvents = ["ticket.updated", "message.created", "ticket.created", "ticket.updated", "message.created"]
        var healthy: [DemoDelivery] = []
        for n in 0 ..< 36 {
            let failed = n == 17 || n == 18
            let attempts: Int = failed ? 8 : (n % 13 == 6 ? 2 : 1)
            let duration: Int = failed ? 10_000 : 84 + (n * 53) % 310
            let minutes = 4 + Double(n) * 41
            healthy.append(DemoDelivery(
                id: demoKBID(0x45, n + 1), eventID: demoKBID(0x46, n + 1), eventType: ticketEvents[n % ticketEvents.count],
                status: failed ? "failed" : "succeeded", attempts: attempts, responseCode: failed ? 503 : 200,
                durationMS: duration, createdAt: DemoSeed.ago(minutes)
            ))
        }
        let contactEvents = ["contact.updated", "company.updated", "contact.created"]
        var failing: [DemoDelivery] = [
            DemoDelivery(id: demoKBID(0x47, 1), eventID: demoKBID(0x48, 1), eventType: "contact.updated", status: "pending", attempts: 3, responseCode: 500, durationMS: 1840, createdAt: DemoSeed.ago(9)),
            DemoDelivery(id: demoKBID(0x47, 2), eventID: demoKBID(0x48, 2), eventType: "company.updated", status: "failed", attempts: 8, responseCode: 500, durationMS: 2010, createdAt: DemoSeed.ago(95)),
        ]
        for n in 3 ..< 22 {
            let down = n < 6
            let duration: Int = down ? 30_000 : 120 + (n * 31) % 200
            let minutes = Double(n) * 180
            failing.append(DemoDelivery(
                id: demoKBID(0x47, n), eventID: demoKBID(0x48, n), eventType: contactEvents[n % contactEvents.count],
                status: down ? "failed" : "succeeded", attempts: down ? 8 : 1, responseCode: down ? 502 : 200,
                durationMS: duration, createdAt: DemoSeed.ago(minutes)
            ))
        }
        let kbEvents = ["kb_article.updated", "changelog_entry.created", "kb_article.created"]
        var paused: [DemoDelivery] = []
        for n in 0 ..< 6 {
            let minutes = Double(33 + n) * 1440
            paused.append(DemoDelivery(
                id: demoKBID(0x49, n + 1), eventID: demoKBID(0x4a, n + 1), eventType: kbEvents[n % 3],
                status: "succeeded", attempts: 1, responseCode: 200, durationMS: 210 + n * 17, createdAt: DemoSeed.ago(minutes)
            ))
        }
        return [id(11): healthy, id(12): failing, id(13): paused, id(14): []]
    }

    // MARK: Audit log

    private static func audit() -> [DemoAuditEntry] {
        let maya = DemoPerson.maya.ref, jonas = DemoPerson.jonas.ref, priya = DemoPerson.priya.ref, sam = DemoPerson.sam.ref, lea = DemoPerson.lea.ref
        typealias Spec = (UserRef?, String, String, [String: JSONValue], String)
        let office = "84.153.12.7", home = "91.64.201.33", vpn = "185.220.101.4"
        let specs: [Spec] = [
            (maya, "login.succeeded", "user", [:], office),
            (jonas, "api_key.scopes_changed", "api_key", ["name": .string("Zapier sync"), "added": .array([.string("tickets:write")]), "removed": .array([])], office),
            (nil, "login.failed", "user", ["email": .string("jonas@margin.app"), "reason": .string("invalid_password")], vpn),
            (priya, "login.succeeded", "user", [:], home),
            (maya, "webhook.created", "webhook", ["url": .string("https://staging.margin.app/hooks/opendesk")], office),
            (sam, "api_key.created", "api_key", ["name": .string("Status page"), "scopes": .array([.string("kb:read"), .string("changelog:read"), .string("changelog:write")])], office),
            (maya, "member.role_changed", "member", ["email": .string("jonas@margin.app"), "from": .string("agent"), "to": .string("admin")], office),
            (lea, "totp.enabled", "user", [:], home),
            (jonas, "mailbox.connected", "mailbox", ["email": .string("billing@margin.app"), "provider": .string("google")], office),
            (maya, "ai.settings_updated", "workspace", ["triage": .bool(true)], office),
            (jonas, "logout", "user", [:], office),
            (maya, "invitation.created", "invitation", ["email": .string("theo@margin.app"), "role": .string("viewer")], office),
            (priya, "session.revoked", "session", ["device": .string("Chrome on Windows")], home),
            (maya, "api_key.expiry_changed", "api_key", ["name": .string("Support autopilot"), "from": .null, "to": .string("2026-06-25T23:59:00Z")], office),
            (nil, "billing.updated", "workspace", ["plan": .string("growth"), "seats": .number(8)], ""),
            (jonas, "webhook.updated", "webhook", ["url": .string("https://n8n.margin.app/webhook/help-center"), "enabled": .bool(false)], office),
            (maya, "workspace.updated", "workspace", ["name": .string("Margin"), "timezone": .string("Europe/Berlin")], office),
            (sam, "login.succeeded", "user", [:], "62.214.8.90"),
            (maya, "oauth.grant_revoked", "oauth_grant", ["name": .string("Raycast")], office),
            (jonas, "team.updated", "team", ["name": .string("Billing")], office),
        ]
        return (0 ..< 74).map { n in
            let spec = specs[n % specs.count]
            let isKey = spec.1.hasPrefix("api_key") && n % 5 == 0
            return DemoAuditEntry(
                id: demoKBID(0x4c, n + 1),
                actor: .init(type: spec.0 == nil ? (spec.1 == "login.failed" ? "user" : "system") : (isKey ? "api_key" : "user"), user: isKey ? nil : spec.0, apiKeyID: isKey ? id(1) : nil),
                action: spec.1, entityType: spec.2, entityID: spec.2 == "workspace" ? DemoSeed.marginID : demoKBID(0x4d, n % 9 + 1),
                data: spec.3, ip: spec.4, createdAt: DemoSeed.ago(6 + Double(n) * 173 + Double(n % 4) * 11)
            )
        }
    }

    // MARK: AI clients

    private static func connections() -> [DemoAIConnection] {
        [
            DemoAIConnection(
                id: id(21), client: .init(name: "Claude", uri: "https://claude.ai", redirectHost: "claude.ai", local: false), user: DemoPerson.maya.ref,
                mine: true, scopes: AIClientSetup.writeScopes, createdAt: DemoSeed.ago(14 * 1440), lastUsedAt: DemoSeed.ago(12)
            ),
            DemoAIConnection(
                id: id(22), client: .init(name: "Cursor", uri: "https://cursor.com", redirectHost: "127.0.0.1", local: true), user: DemoPerson.jonas.ref,
                mine: false, scopes: AIClientSetup.readScopes, createdAt: DemoSeed.ago(40 * 1440), lastUsedAt: DemoSeed.ago(2 * 1440)
            ),
        ]
    }
}

// MARK: - Wire shapes

struct DemoKeyRequest: Encodable, Sendable {
    var id: String
    var createdAt: Date
    var method: String
    var path: String
    var query: String
    var status: Int
    var durationMS: Int
    var idempotencyKey: String
    var replayed: Bool
    var ticket: APIKeyRequestRecord.TicketRef?
    var ticketRef: String
    var messageID: String?
    var contactID: String?
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
}

struct DemoWebhook: Encodable, Sendable {
    var id: String
    var url: String
    var description: String
    var events: [String]
    var headerNames: [String] = []
    var enabled: Bool
    var verified: Bool
    var createdAt: Date
    var privateTeamIDs: [String] = []
    /// The challenge the address was sent; never on the wire.
    var challenge = ""

    enum CodingKeys: String, CodingKey {
        case id, url, description, events, enabled, verified
        case headerNames = "header_names"
        case createdAt = "created_at"
        case privateTeamIDs = "private_team_ids"
    }
}

struct DemoDelivery: Encodable, Sendable {
    var id: String
    var eventID: String
    var eventType: String
    var status: String
    var attempts: Int
    var responseCode: Int?
    var durationMS: Int?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, attempts
        case eventID = "event_id"
        case eventType = "event_type"
        case responseCode = "response_code"
        case durationMS = "duration_ms"
        case createdAt = "created_at"
    }
}

struct DemoAuditEntry: Encodable, Sendable {
    struct Actor: Encodable, Sendable {
        var type: String
        var user: UserRef?
        var apiKeyID: String?

        enum CodingKeys: String, CodingKey {
            case type, user
            case apiKeyID = "api_key_id"
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
}

struct DemoAIConnection: Encodable, Sendable {
    struct Client: Encodable, Sendable {
        var name: String
        var uri: String
        var redirectHost: String
        var local: Bool

        enum CodingKeys: String, CodingKey {
            case name, uri, local
            case redirectHost = "redirect_host"
        }
    }

    var id: String
    var client: Client
    var user: UserRef
    var mine: Bool
    var scopes: [String]
    var createdAt: Date
    var lastUsedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, client, user, mine, scopes
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }
}

// MARK: - Routes

extension DemoBackend {
    func developerSettingsRoutes(_ call: Call, in ws: inout DemoWorkspace) throws -> Data?? {
        switch call.path.first {
        case "api-keys": return try apiKeyCall(call, in: &ws)
        case "webhooks": return try webhookCall(call, in: &ws)
        case "audit-logs":
            guard call.method == "GET" else { return nil }
            var list = ws.settings.developers.audit
            if let action = call.query["action"], !action.isEmpty { list = list.filter { $0.action == action } }
            if let type = call.query["entity_type"], !type.isEmpty { list = list.filter { $0.entityType == type } }
            return .some(page(list, call))
        case "ai-clients": return try aiClientCall(call, in: &ws)
        case "bots":
            // The Agent group's routes answer bots first; this is the list a key picks from otherwise.
            guard call.match("GET", "bots") != nil else { return nil }
            let bots: [JSONValue] = [
                .object(["id": .string(DemoSeed.ollie.id), "name": .string("Ollie"), "role": .string("Support assistant"), "avatar_url": .string(""), "look": .object(["kind": .string("built")]), "is_default": .bool(true)]),
                .object(["id": .string(DemoDeveloperSettings.id(31)), "name": .string("Juniper"), "role": .string("Billing questions"), "avatar_url": .string(""), "look": .object(["kind": .string("emoji"), "emoji": .string("🌿")]), "is_default": .bool(false)]),
            ]
            return .some(encode(JSONValue.object(["data": .array(bots), "next_cursor": .null])))
        default: return nil
        }
    }

    // MARK: Paging

    /// A cursor page of `list` (the cursor is the offset), `limit` from the query.
    private func page<T: Encodable>(_ list: [T], _ call: Call) -> Data {
        let limit = max(1, min(Int(call.query["limit"] ?? "") ?? 50, 200))
        let start = min(Int(call.query["cursor"] ?? "") ?? 0, list.count)
        let end = min(start + limit, list.count)
        return encode(ListBody(data: Array(list[start ..< end]), nextCursor: end < list.count ? String(end) : nil))
    }

    // MARK: Fresh sign-in

    /// The first sensitive change of a run asks for a recent sign-in, as a 12-hour-old session would.
    private func freshSignIn(_ ws: inout DemoWorkspace) throws {
        guard !ws.settings.developers.signedInAgain else { return }
        ws.settings.developers.signedInAgain = true
        throw Failure(status: 403, code: "reauth_required", detail: "This needs a sign-in from the last 12 hours. Sign in again to confirm it's you.")
    }

    private func audit(_ action: String, _ type: String, _ entity: String, _ data: [String: JSONValue], in ws: inout DemoWorkspace) {
        let entry = DemoAuditEntry(id: made(), actor: .init(type: "user", user: me, apiKeyID: nil), action: action, entityType: type, entityID: entity, data: data, ip: "84.153.12.7", createdAt: now())
        ws.settings.developers.audit.insert(entry, at: 0)
    }

    private static func token(_ length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0 ..< length).map { _ in alphabet.randomElement()! })
    }

    // MARK: API keys

    /// A key as the list shows it, with its failures of the last day counted from its log.
    private func keyJSON(_ key: APIKeyRecord, in ws: DemoWorkspace) -> APIKeyRecord {
        var key = key
        if key.recordRequests {
            let since = DemoMode.anchor.addingTimeInterval(-86400)
            key.errorCount24h = (ws.settings.developers.requests[key.id] ?? []).filter { $0.status >= 400 && $0.createdAt >= since }.count
        } else {
            key.errorCount24h = nil
        }
        return key
    }

    private func apiKeyCall(_ call: Call, in ws: inout DemoWorkspace) throws -> Data?? {
        let dev = ws.settings.developers
        if call.match("GET", "api-keys") != nil {
            return .some(page(dev.keys.map { keyJSON($0, in: ws) }, call))
        }
        if call.match("POST", "api-keys") != nil {
            let name = (call.string("name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let scopes = call.body["scopes"]?.array?.compactMap(\.string) ?? []
            guard !name.isEmpty else { throw Failure(status: 422, code: "validation_failed", detail: "Name the key so you know what uses it.") }
            guard !scopes.isEmpty else { throw Failure(status: 422, code: "validation_failed", detail: "Choose at least one scope.") }
            let expires = try call.body["expires_at"].flatMap { $0.isNull ? nil : try $0.decode(Date.self) }
            if let expires, expires <= DemoMode.anchor { throw Failure(status: 422, code: "validation_failed", detail: "Pick an expiry in the future.") }
            let bot = call.string("bot_id")
            if bot != nil, !scopes.contains("tickets:write") { throw Failure(status: 422, code: "validation_failed", detail: "Only a key that writes tickets can speak as a bot.") }
            try freshSignIn(&ws)
            let key = APIKeyRecord(
                id: made(), name: name, prefix: "od_live_" + Self.token(8), scopes: scopes, expiresAt: expires, createdAt: now(), createdBy: me,
                privateTeamIDs: call.body["private_team_ids"]?.array?.compactMap(\.string) ?? [], recordRequests: call.body["record_requests"]?.bool ?? false, botID: bot
            )
            ws.settings.developers.keys.insert(key, at: 0)
            audit("api_key.created", "api_key", key.id, ["name": .string(name), "scopes": .array(scopes.map(JSONValue.string))], in: &ws)
            var body = DemoSeed.json(keyJSON(key, in: ws)).object ?? [:]
            body["secret"] = .string(key.prefix + Self.token(32))
            return .some(encode(JSONValue.object(body)))
        }
        if let id = call.match("PATCH", "api-keys/*")?.first {
            guard let index = dev.keys.firstIndex(where: { $0.id == id }) else { throw notFound("key") }
            var key = dev.keys[index]
            if let name = call.string("name") {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw Failure(status: 422, code: "validation_failed", detail: "Name the key so you know what uses it.") }
                key.name = trimmed
            }
            var needsSignIn = false
            var logs: [(String, [String: JSONValue])] = []
            if let scopes = call.body["scopes"]?.array?.compactMap(\.string) {
                guard !scopes.isEmpty else { throw Failure(status: 422, code: "validation_failed", detail: "Choose at least one scope.") }
                let added = scopes.filter { !key.scopes.contains($0) }
                if added.contains("collab:draft"), key.createdBy?.id != me.id {
                    throw Failure(status: 403, code: "forbidden", detail: "Only the person who made this key can let it draft replies as them.")
                }
                if !added.isEmpty { needsSignIn = true }
                let removed = key.scopes.filter { !scopes.contains($0) }
                if !added.isEmpty || !removed.isEmpty {
                    logs.append(("api_key.scopes_changed", ["name": .string(key.name), "added": .array(added.map(JSONValue.string)), "removed": .array(removed.map(JSONValue.string))]))
                }
                key.scopes = scopes
                if !APIKeyScopes.canSpeak(scopes) { key.botID = nil }
            }
            if let value = call.body["expires_at"] {
                if let current = key.expiresAt, current < DemoMode.anchor { throw Failure(status: 422, code: "validation_failed", detail: "An expired key can't be brought back. Make a new one.") }
                let next = value.isNull ? nil : try value.decode(Date.self)
                if let next, next <= DemoMode.anchor { throw Failure(status: 422, code: "validation_failed", detail: "Pick a day after today.") }
                let widens = next == nil ? key.expiresAt != nil : key.expiresAt.map { next! > $0 } ?? false
                if widens { needsSignIn = true }
                logs.append(("api_key.expiry_changed", ["name": .string(key.name), "from": key.expiresAt.map { .string($0.devISO) } ?? .null, "to": next.map { .string($0.devISO) } ?? .null]))
                key.expiresAt = next
            }
            if let record = call.body["record_requests"]?.bool { key.recordRequests = record }
            if let bot = call.body["bot_id"] {
                if !bot.isNull, !APIKeyScopes.canSpeak(key.scopes) { throw Failure(status: 422, code: "validation_failed", detail: "Only a key that writes tickets can speak as a bot.") }
                key.botID = bot.string
            }
            if let teams = call.body["private_team_ids"]?.array { key.privateTeamIDs = teams.compactMap(\.string) }
            if needsSignIn { try freshSignIn(&ws) }
            ws.settings.developers.keys[index] = key
            for (action, data) in logs { audit(action, "api_key", key.id, data, in: &ws) }
            return .some(encode(keyJSON(key, in: ws)))
        }
        if let id = call.match("DELETE", "api-keys/*")?.first {
            guard let key = dev.keys.first(where: { $0.id == id }) else { throw notFound("key") }
            ws.settings.developers.keys.removeAll { $0.id == id }
            audit("api_key.revoked", "api_key", id, ["name": .string(key.name)], in: &ws)
            return .some(nil)
        }
        if let id = call.match("GET", "api-keys/*/requests")?.first {
            guard dev.keys.contains(where: { $0.id == id }) else { throw notFound("key") }
            var list = dev.requests[id] ?? []
            switch call.query["status"] ?? "" {
            case "2xx": list = list.filter { (200 ..< 300).contains($0.status) }
            case "3xx": list = list.filter { (300 ..< 400).contains($0.status) }
            case "4xx": list = list.filter { (400 ..< 500).contains($0.status) }
            case "5xx": list = list.filter { $0.status >= 500 }
            case "errors": list = list.filter { $0.status >= 400 }
            default: break
            }
            if let method = call.query["method"], !method.isEmpty { list = list.filter { $0.method == method.uppercased() } }
            if let raw = call.query["since"], let since = try? JSONValue.string(raw).decode(Date.self) { list = list.filter { $0.createdAt >= since } }
            if let ticket = call.query["ticket"]?.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), !ticket.isEmpty {
                list = list.filter { $0.ticket?.id == ticket || $0.ticket?.number.map(String.init) == ticket || $0.ticketRef == ticket }
            }
            return .some(page(list, call))
        }
        if let ids = call.match("GET", "api-keys/*/requests/*") {
            guard let request = dev.requests[ids[0]]?.first(where: { $0.id == ids[1] }) else { throw notFound("request") }
            return .some(encode(request))
        }
        return nil
    }

    // MARK: Webhooks

    private func webhookCall(_ call: Call, in ws: inout DemoWorkspace) throws -> Data?? {
        let dev = ws.settings.developers
        if call.match("GET", "webhooks") != nil { return .some(page(dev.webhooks, call)) }
        if call.match("POST", "webhooks") != nil {
            let url = try webhookURL(call.string("url"))
            let hook = DemoWebhook(
                id: made(), url: url, description: call.string("description") ?? "", events: call.body["events"]?.array?.compactMap(\.string) ?? ["*"],
                headerNames: call.body["headers"]?.object.map { Array($0.keys).sorted() } ?? [], enabled: call.body["enabled"]?.bool ?? true,
                verified: false, createdAt: now(), privateTeamIDs: call.body["private_team_ids"]?.array?.compactMap(\.string) ?? [], challenge: "whv_" + Self.token(12)
            )
            ws.settings.developers.webhooks.insert(hook, at: 0)
            ws.settings.developers.deliveries[hook.id] = []
            audit("webhook.created", "webhook", hook.id, ["url": .string(url)], in: &ws)
            var body = DemoSeed.json(hook).object ?? [:]
            body["secret"] = .string("whsec_" + Self.token(32))
            return .some(encode(JSONValue.object(body)))
        }
        if let id = call.match("PATCH", "webhooks/*")?.first {
            guard let index = dev.webhooks.firstIndex(where: { $0.id == id }) else { throw notFound("webhook") }
            var hook = dev.webhooks[index]
            if call.body["url"] != nil {
                let url = try webhookURL(call.string("url"))
                // A new address answers a new challenge before it gets events.
                if url != hook.url {
                    hook.url = url
                    hook.verified = false
                    hook.challenge = "whv_" + Self.token(12)
                }
            }
            if let description = call.string("description") { hook.description = description }
            if let events = call.body["events"]?.array?.compactMap(\.string) { hook.events = events }
            if let enabled = call.body["enabled"]?.bool { hook.enabled = enabled }
            if let headers = call.body["headers"]?.object { hook.headerNames = Array(headers.keys).sorted() }
            if let teams = call.body["private_team_ids"]?.array { hook.privateTeamIDs = teams.compactMap(\.string) }
            ws.settings.developers.webhooks[index] = hook
            audit("webhook.updated", "webhook", id, ["url": .string(hook.url), "enabled": .bool(hook.enabled)], in: &ws)
            return .some(encode(hook))
        }
        if let id = call.match("DELETE", "webhooks/*")?.first {
            guard let hook = dev.webhooks.first(where: { $0.id == id }) else { throw notFound("webhook") }
            ws.settings.developers.webhooks.removeAll { $0.id == id }
            ws.settings.developers.deliveries[id] = nil
            audit("webhook.deleted", "webhook", id, ["url": .string(hook.url)], in: &ws)
            return .some(nil)
        }
        if let id = call.match("GET", "webhooks/*/deliveries")?.first {
            guard dev.webhooks.contains(where: { $0.id == id }) else { throw notFound("webhook") }
            return .some(page(dev.deliveries[id] ?? [], call))
        }
        if let id = call.match("POST", "webhooks/*/test")?.first {
            guard let hook = dev.webhooks.first(where: { $0.id == id }) else { throw notFound("webhook") }
            guard hook.verified else { throw Failure(status: 409, code: "webhook_unverified", detail: "Verify the address before sending events to it.") }
            // The CRM endpoint is down: its test is retried like any failing delivery.
            let failing = hook.url.contains("copperleaf")
            let delivery = DemoDelivery(
                id: made(), eventID: made(), eventType: "webhook.test", status: failing ? "pending" : "succeeded", attempts: 1,
                responseCode: failing ? 500 : 200, durationMS: failing ? 1920 : 143, createdAt: now()
            )
            ws.settings.developers.deliveries[id, default: []].insert(delivery, at: 0)
            return .some(encode(delivery))
        }
        if let id = call.match("POST", "webhooks/*/verify")?.first {
            guard let index = dev.webhooks.firstIndex(where: { $0.id == id }) else { throw notFound("webhook") }
            if let code = call.string("code")?.trimmingCharacters(in: .whitespaces), !code.isEmpty {
                // The demo receiver never echoes, so any challenge it could have got verifies it.
                guard code == dev.webhooks[index].challenge || (code.hasPrefix("whv_") && code.count >= 8) else {
                    throw Failure(status: 422, code: "invalid_code", detail: "That challenge doesn't match. Send a new one and enter it within 24 hours.")
                }
                ws.settings.developers.webhooks[index].verified = true
            } else {
                ws.settings.developers.webhooks[index].challenge = "whv_" + Self.token(12)
            }
            return .some(encode(ws.settings.developers.webhooks[index]))
        }
        return nil
    }

    private func webhookURL(_ raw: String?) throws -> String {
        let url = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: url), parsed.scheme?.lowercased() == "https", let host = parsed.host(), !host.isEmpty else {
            throw Failure(status: 422, code: "validation_failed", detail: "Use an https:// URL.")
        }
        if host == "localhost" || host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("169.254.") {
            throw Failure(status: 422, code: "validation_failed", detail: "Webhooks can't go to private or local addresses.")
        }
        return url
    }

    // MARK: AI clients

    private func aiClientCall(_ call: Call, in ws: inout DemoWorkspace) throws -> Data?? {
        if call.match("GET", "ai-clients/server") != nil {
            func tool(_ name: String, _ title: String, _ description: String, _ scopes: [String], readOnly: Bool) -> JSONValue {
                .object([
                    "name": .string(name), "title": .string(title), "description": .string(description),
                    "scopes": .array(scopes.map(JSONValue.string)), "read_only": .bool(readOnly), "destructive": .bool(false),
                ])
            }
            let tools: [JSONValue] = [
                tool("search_tickets", "Search tickets", "Finds tickets by text, status, assignee, team or label. Returns the newest first with their numbers.", ["tickets:read"], readOnly: true),
                tool("get_ticket", "Read a ticket", "Reads one ticket with its messages, notes and fields. Use the number or the id.", ["tickets:read"], readOnly: true),
                tool("reply_to_ticket", "Reply to a ticket", "Sends a reply to the customer from the ticket's mailbox. Drafts first when asked to.", ["tickets:write"], readOnly: false),
                tool("add_note", "Add an internal note", "Adds a note only the team sees. Mentions notify teammates.", ["tickets:write"], readOnly: false),
                tool("update_ticket", "Update a ticket", "Changes status, priority, assignee, team or labels.", ["tickets:write"], readOnly: false),
                tool("search_contacts", "Search contacts", "Finds contacts by name, email or company.", ["contacts:read"], readOnly: true),
                tool("search_articles", "Search help articles", "Searches the knowledge base, published and drafts. Returns titles and excerpts.", ["kb:read"], readOnly: true),
                tool("draft_article", "Draft a help article", "Writes a draft article in a collection. It is never published by the tool.", ["kb:write"], readOnly: false),
                tool("search_wiki", "Search the wiki", "Searches the team's internal wiki pages.", ["wiki:read"], readOnly: true),
            ]
            return .some(encode(JSONValue.object([
                "url": .string(DemoMode.instance.apiURL.appendingPathComponent("mcp").absoluteString),
                "resource_metadata": .string(DemoMode.instance.apiURL.appendingPathComponent(".well-known/oauth-protected-resource").absoluteString),
                "authorization_server": .string(DemoMode.instance.apiURL.absoluteString),
                "scopes": .array((AIClientSetup.writeScopes).map(JSONValue.string)),
                "tools": .array(tools),
            ])))
        }
        if call.match("GET", "ai-clients/connections") != nil {
            // Admins see everyone's clients; members only their own.
            let list = ws.role.isAdmin ? ws.settings.developers.connections : ws.settings.developers.connections.filter(\.mine)
            return .some(encode(ListBody(data: list)))
        }
        if let id = call.match("DELETE", "ai-clients/connections/*")?.first {
            guard let connection = ws.settings.developers.connections.first(where: { $0.id == id }) else { throw notFound("client") }
            ws.settings.developers.connections.removeAll { $0.id == id }
            audit("oauth.grant_revoked", "oauth_grant", id, ["name": .string(connection.client.name)], in: &ws)
            return .some(nil)
        }
        return nil
    }
}
#endif
