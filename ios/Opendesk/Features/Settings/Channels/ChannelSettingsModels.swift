import Foundation

// The shapes the Channels settings pages read (contracts/api.md, contracts/phone.md,
// contracts/support-channels.md, contracts/collab.md, contracts/teams.md). Every member is
// decoded leniently: a server that grows or trims a field never fails a page.

/// A JSON key by name, so lenient decoders read `c.or("display_name", "")`.
struct ChannelKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension KeyedDecodingContainer where Key == ChannelKey {
    func or<T: Decodable>(_ key: String, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: ChannelKey(key))) ?? nil) ?? fallback
    }

    func opt<T: Decodable>(_ key: String) -> T? {
        (try? decodeIfPresent(T.self, forKey: ChannelKey(key))) ?? nil
    }

    func id(_ key: String = "id") throws -> String {
        try decode(String.self, forKey: ChannelKey(key))
    }
}

extension Decoder {
    func channel() throws -> KeyedDecodingContainer<ChannelKey> { try container(keyedBy: ChannelKey.self) }
}

/// `{data: [...]}`, or a bare array.
struct ChannelList<T: Decodable & Sendable>: Decodable, Sendable {
    var data: [T]
    var nextCursor: String?

    init(from decoder: Decoder) throws {
        if let c = try? decoder.channel(), c.contains(ChannelKey("data")) {
            data = c.or("data", [T]())
            nextCursor = c.opt("next_cursor")
        } else {
            data = (try? [T](from: decoder)) ?? []
        }
    }
}

/// A JSON body built key by key, for patches that send only what changed.
typealias ChannelBody = [String: JSONValue]

extension JSONValue {
    static func chString(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }
    static func chInt(_ value: Int) -> JSONValue { .number(Double(value)) }
    static func chStrings(_ values: [String]) -> JSONValue { .array(values.map(JSONValue.string)) }
}

// MARK: - Conditions

/// One condition of a routing rule or a support channel destination.
struct ChannelCondition: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var field: String
    var op: String
    var value: String
    var question: String?

    enum CodingKeys: String, CodingKey { case field, op, value, question }

    init(field: String, op: String, value: String = "", question: String? = nil) {
        self.field = field
        self.op = op
        self.value = value
        self.question = question
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        field = c.lenient(String.self, forKey: .field) ?? ""
        op = c.lenient(String.self, forKey: .op) ?? "equals"
        if let text = c.lenient(String.self, forKey: .value) {
            value = text
        } else if let number = c.lenient(Double.self, forKey: .value) {
            value = number.rounded() == number ? String(Int(number)) : String(number)
        } else {
            value = ""
        }
        question = c.lenient(String.self, forKey: .question)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(field, forKey: .field)
        try c.encode(op, forKey: .op)
        try c.encode(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .value)
        if field == "ai_decide" { try c.encode((question ?? "").trimmingCharacters(in: .whitespacesAndNewlines), forKey: .question) }
    }

    /// The same condition, ignoring the local id.
    func same(as other: ChannelCondition) -> Bool {
        field == other.field && op == other.op && value == other.value && (question ?? "") == (other.question ?? "")
    }
}

extension [ChannelCondition] {
    func same(as other: [ChannelCondition]) -> Bool {
        count == other.count && zip(self, other).allSatisfy { $0.same(as: $1) }
    }
}

// MARK: - Mailboxes

struct MailboxConfig: Hashable, Sendable, Decodable {
    var imapHost = ""
    var imapPort = 993
    var imapUsername = ""
    var imapTLS = "tls"
    var smtpHost = ""
    var smtpPort = 587
    var smtpUsername = ""
    var smtpTLS = "starttls"
    var oauthEmail = ""
    var oauthGrant = ""
    var oauthClient = ""
    var mailHost = ""
    var syncStart = ""
    var providerMarkRead = false
    var providerArchiveOnSolve = false
    var providerLabel = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        imapHost = c.or("imap_host", "")
        imapPort = c.or("imap_port", 993)
        imapUsername = c.or("imap_username", "")
        imapTLS = c.or("imap_tls", "tls")
        smtpHost = c.or("smtp_host", "")
        smtpPort = c.or("smtp_port", 587)
        smtpUsername = c.or("smtp_username", "")
        smtpTLS = c.or("smtp_tls", "starttls")
        oauthEmail = c.or("oauth_email", "")
        oauthGrant = c.or("oauth_grant", "")
        oauthClient = c.or("oauth_client", "")
        mailHost = c.or("mail_host", "")
        syncStart = c.or("sync_start", "")
        providerMarkRead = c.or("provider_mark_read", false)
        providerArchiveOnSolve = c.or("provider_archive_on_solve", false)
        providerLabel = c.or("provider_label", false)
    }
}

struct MailboxAliasSettings: Hashable, Sendable, Decodable {
    var displayName = ""
    var signatureHTML = ""
    var brandID: String?
    var sendAs = "unknown"
    var sendAsBy = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        displayName = c.or("display_name", "")
        signatureHTML = c.or("signature_html", "")
        brandID = c.opt("brand_id")
        sendAs = c.or("send_as", "unknown")
        sendAsBy = c.or("send_as_by", "")
    }
}

struct MailboxSendAs: Hashable, Sendable, Decodable {
    struct Address: Hashable, Sendable, Decodable {
        var email: String
        var displayName: String
        var verified: Bool

        init(from decoder: Decoder) throws {
            let c = try decoder.channel()
            email = c.or("email", "")
            displayName = c.or("display_name", "")
            verified = c.or("verified", false)
        }
    }

    var readable: Bool
    var checkedAt: Date?
    var addresses: [Address]

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        readable = c.or("readable", false)
        checkedAt = c.opt("checked_at")
        addresses = c.or("addresses", [Address]())
    }
}

struct MailboxPersonalReplies: Hashable, Sendable, Decodable {
    var enabled: Bool?
    var replyTo: String?
    var accounts = "any"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        enabled = c.opt("enabled")
        replyTo = c.opt("reply_to")
        accounts = c.or("accounts", "any")
    }

    var json: JSONValue {
        .object(["enabled": enabled.map(JSONValue.bool) ?? .null, "reply_to": .chString(replyTo), "accounts": .string(accounts)])
    }
}

/// A mailbox as settings read it (`GET /v1/mailboxes/{id}`).
struct SettingsMailbox: Hashable, Sendable, Identifiable, Decodable {
    var id: String
    var name = ""
    var email = ""
    var displayName = ""
    var inboundKind = "forwarding"
    var outboundKind = "smtp"
    var forwardingAddress = ""
    var config = MailboxConfig()
    var teamID: String?
    var brandID: String?
    var aliases: [String] = []
    var aliasTeams: [String: String] = [:]
    var aliasSettings: [String: MailboxAliasSettings] = [:]
    var providerSendAs: MailboxSendAs?
    var fromNameFormat = ""
    var trustedFormSenders: [String] = []
    var botID: String?
    var isPrivate = false
    var personalReplies = MailboxPersonalReplies()
    var receiving = "ok"
    var sending = "ok"
    var signatureHTML = ""
    var autoReplyEnabled = false
    var autoReplySubject = ""
    var autoReplyHTML = ""
    var aiAnswers = false
    var aiAnswersMode = "draft"
    var aiAnswersOutsideHours = false
    var status = "active"
    var lastError = ""
    var lastSyncedAt: Date?
    var lastReceivedAt: Date?
    var createdAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        id = try c.id()
        name = c.or("name", "")
        email = c.or("email", "")
        displayName = c.or("display_name", "")
        inboundKind = c.or("inbound_kind", "forwarding")
        outboundKind = c.or("outbound_kind", "smtp")
        forwardingAddress = c.or("forwarding_address", "")
        config = c.or("config", MailboxConfig())
        teamID = c.opt("team_id")
        brandID = c.opt("brand_id")
        aliases = c.or("aliases", [String]())
        aliasTeams = c.or("alias_teams", [String: String]())
        aliasSettings = c.or("alias_settings", [String: MailboxAliasSettings]())
        providerSendAs = c.opt("provider_send_as")
        fromNameFormat = c.or("from_name_format", "")
        trustedFormSenders = c.or("trusted_form_senders", [String]())
        botID = c.opt("bot_id")
        isPrivate = c.or("private", false)
        personalReplies = c.or("personal_replies", MailboxPersonalReplies())
        receiving = c.or("receiving", "ok")
        sending = c.or("sending", "ok")
        signatureHTML = c.or("signature_html", "")
        autoReplyEnabled = c.or("auto_reply_enabled", false)
        autoReplySubject = c.or("auto_reply_subject", "")
        autoReplyHTML = c.or("auto_reply_html", "")
        aiAnswers = c.or("ai_answers", false)
        aiAnswersMode = c.or("ai_answers_mode", "draft")
        aiAnswersOutsideHours = c.or("ai_answers_outside_hours", false)
        status = c.or("status", "active")
        lastError = c.or("last_error", "")
        lastSyncedAt = c.opt("last_synced_at")
        lastReceivedAt = c.opt("last_received_at")
        createdAt = c.opt("created_at")
    }

    var label: String { name.isEmpty ? email : name }
    var disabled: Bool { status == "disabled" }
    var imapOff: Bool { receiving == "imap_off" && !disabled }
    var systemOff: Bool { sending == "system_off" && !disabled }
    var needsAttention: Bool { status == "error" || imapOff || systemOff }

    /// Signed in to Google or Microsoft only to send: mail arrives by forwarding.
    var sendOnly: Bool { inboundKind == "forwarding" && (outboundKind == "google" || outboundKind == "microsoft") }
    /// Reads its Google or Microsoft inbox through the provider's API rather than IMAP.
    var readsDirectly: Bool { (inboundKind == "google" || inboundKind == "microsoft") && config.oauthGrant == "api" }
    /// The provider it is signed in to, to sync or only to send.
    var signedInProvider: String? {
        if inboundKind == "google" || inboundKind == "microsoft" { return inboundKind }
        if outboundKind == "google" || outboundKind == "microsoft" { return outboundKind }
        return nil
    }

    var providerName: String? { signedInProvider.map(MailboxKinds.providerName) }

    /// "Gmail · App password", "Forwarding · Sends with Google".
    var connectionLabel: String {
        if sendOnly { return "Forwarding · Sends with \(MailboxKinds.providerName(outboundKind))" }
        let how: String
        if readsDirectly {
            how = "Reads the inbox directly through \(MailboxKinds.providerName(inboundKind))"
        } else if inboundKind == "google" || inboundKind == "microsoft" {
            how = "Sign-in"
        } else if inboundKind == "forwarding" {
            how = "Forwarding"
        } else {
            how = MailboxKinds.passwordAuth(config.mailHost) == "app_password" ? "App password" : "Password"
        }
        let host = MailboxKinds.hostLabel(config.mailHost)
        if !host.isEmpty, config.mailHost != "other" { return "\(host) · \(how)" }
        return inboundKind == "imap" ? "IMAP and SMTP · \(how)" : how
    }

    /// Days since mail last arrived when that is long enough to look wrong.
    func quietDays(now: Date) -> Int? {
        guard status == "active", receiving == "ok" else { return nil }
        if let last = lastReceivedAt {
            let days = Int(now.timeIntervalSince(last) / 86400)
            return days >= 7 ? days : nil
        }
        if let created = createdAt, now.timeIntervalSince(created) > 86400 { return 0 }
        return nil
    }
}

enum MailboxKinds {
    static func providerName(_ kind: String) -> String { kind == "microsoft" ? "Microsoft" : "Google" }

    static func symbol(_ mailbox: SettingsMailbox) -> String {
        switch mailbox.inboundKind {
        case "google": "envelope"
        case "microsoft": "envelope.badge"
        case "imap": "server.rack"
        default: "arrowshape.turn.up.right"
        }
    }

    static func tone(_ mailbox: SettingsMailbox) -> Tone {
        switch mailbox.inboundKind {
        case "google": .blue
        case "microsoft": .cyan
        case "imap": .indigo
        default: .teal
        }
    }

    static let hostLabels: [String: String] = [
        "google_workspace": "Google Workspace", "gmail": "Gmail", "microsoft365": "Microsoft 365", "outlook": "Outlook.com",
        "zoho": "Zoho Mail", "yahoo": "Yahoo Mail", "aol": "AOL Mail", "icloud": "iCloud Mail", "fastmail": "Fastmail",
        "godaddy": "GoDaddy", "namecheap": "Namecheap Private Email", "ionos": "IONOS", "hostinger": "Hostinger", "ovh": "OVHcloud",
        "migadu": "Migadu", "purelymail": "Purelymail", "rackspace": "Rackspace Email", "yandex": "Yandex Mail", "gmx": "GMX",
        "proton": "Proton Mail", "other": "Other provider",
    ]

    static func hostLabel(_ host: String) -> String { hostLabels[host] ?? "" }
    static func isGoogle(_ host: String) -> Bool { host == "gmail" || host == "google_workspace" }
    static func isMicrosoft(_ host: String) -> Bool { host == "microsoft365" || host == "outlook" }

    /// How a password signs in on a host (mailhost.PasswordAuthFor).
    static func passwordAuth(_ host: String) -> String {
        switch host {
        case "google_workspace", "gmail", "yahoo", "aol", "icloud", "fastmail", "yandex": "app_password"
        case "microsoft365", "outlook": "oauth_only"
        case "proton": "unsupported"
        default: "password"
        }
    }
}

struct MailboxTestResult: Hashable, Sendable, Decodable {
    struct Leg: Hashable, Sendable, Decodable {
        var ok: Bool
        var error: String
        var detail: String

        init(from decoder: Decoder) throws {
            let c = try decoder.channel()
            ok = c.or("ok", false)
            error = c.or("error", "")
            detail = c.or("detail", "")
        }
    }

    struct Cause: Hashable, Sendable, Decodable {
        var title: String
        var fix: String

        init(from decoder: Decoder) throws {
            let c = try decoder.channel()
            title = c.or("title", "")
            fix = c.or("fix", "")
        }
    }

    var inbound: Leg?
    var outbound: Leg?
    var cause: Cause?

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        inbound = c.opt("inbound")
        outbound = c.opt("outbound")
        cause = c.opt("cause")
    }

    var failed: Bool { inbound?.ok == false || outbound?.ok == false }
}

struct MailboxConnectOptions: Hashable, Sendable, Decodable {
    struct Provider: Hashable, Sendable, Decodable {
        var configured = false
        var oauth = false
        var apiSync = false

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.channel()
            configured = c.or("configured", false)
            oauth = c.or("oauth", false)
            apiSync = c.or("api_sync", false)
        }
    }

    var google = Provider()
    var microsoft = Provider()
    var forwarding = true
    var mailboxIMAP = true
    var instanceIMAP = true
    var systemSend = false
    var systemSender = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        google = c.or("google", Provider())
        microsoft = c.or("microsoft", Provider())
        let fwd: JSONValue? = c.opt("forwarding")
        forwarding = fwd?["enabled"]?.bool ?? true
        mailboxIMAP = c.or("mailbox_imap", true)
        instanceIMAP = c.or("instance_imap", true)
        systemSend = c.or("system_send", false)
        systemSender = c.or("system_sender", "")
    }
}

struct MailboxDetection: Hashable, Sendable, Decodable {
    struct Server: Hashable, Sendable, Decodable {
        var host: String
        var port: Int
        var security: String

        init(from decoder: Decoder) throws {
            let c = try decoder.channel()
            host = c.or("host", "")
            port = c.or("port", 0)
            security = c.or("security", "tls")
        }
    }

    var domain = ""
    var host = ""
    var label = ""
    var source = "none"
    var imap: Server?
    var smtp: Server?
    var passwordAuth = "password"
    var appPasswordURL = ""
    var oauth: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        domain = c.or("domain", "")
        host = c.or("host", "")
        label = c.or("label", "")
        source = c.or("source", "none")
        let settings: JSONValue? = c.opt("settings")
        imap = try? settings?["imap"]?.decode(Server.self)
        smtp = try? settings?["smtp"]?.decode(Server.self)
        passwordAuth = c.or("password_auth", "password")
        appPasswordURL = c.or("app_password_url", "")
        oauth = c.opt("oauth")
    }
}

struct MailboxUsage: Sendable, Decodable {
    var tickets: Int
    var open: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        tickets = c.or("tickets", 0)
        open = c.or("open", 0)
    }
}

/// A bot the mailbox or a widget may answer with (`GET /v1/bots`).
struct ChannelBotOption: Hashable, Sendable, Identifiable, Decodable {
    var id: String
    var name: String

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        id = try c.id()
        name = c.or("name", "Bot")
    }
}

// MARK: - Phone

struct PhoneProvider: Hashable, Sendable, Identifiable, Decodable {
    struct Field: Hashable, Sendable, Decodable {
        var name: String
        var label: String
        var secret: Bool

        init(from decoder: Decoder) throws {
            let c = try decoder.channel()
            name = c.or("name", "")
            label = c.or("label", "")
            secret = c.or("secret", false)
        }
    }

    var key: String
    var name: String
    var fields: [Field]
    var manualWebhook: Bool
    var insightCards: Bool
    var id: String { key }

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        key = c.or("key", "")
        name = c.or("name", "")
        fields = c.or("fields", [Field]())
        manualWebhook = c.or("manual_webhook", false)
        insightCards = c.or("insight_cards", false)
    }
}

struct PhoneConnection: Hashable, Sendable, Identifiable, Decodable {
    var id: String
    var provider: String
    var name: String
    var accountName: String
    var status: String
    var lastError: String
    var healthStatus: String
    var healthCode: String
    var healthDetail: String
    var reuseDays: Int
    var assignAnswered: Bool
    var insightCards: Bool
    var lastEventAt: Date?
    var webhookURL: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        id = try c.id()
        provider = c.or("provider", "")
        name = c.or("name", "")
        accountName = c.or("account_name", "")
        status = c.or("status", "connected")
        lastError = c.or("last_error", "")
        healthStatus = c.or("health_status", "unknown")
        healthCode = c.or("health_code", "")
        healthDetail = c.or("health_detail", "")
        reuseDays = c.or("reuse_days", 7)
        assignAnswered = c.or("assign_answered", false)
        insightCards = c.or("insight_cards", false)
        lastEventAt = c.opt("last_event_at")
        webhookURL = c.opt("webhook_url")
    }
}

// MARK: - Support channels

struct SupportProvider: Hashable, Sendable, Identifiable, Decodable {
    struct Field: Hashable, Sendable, Decodable {
        var name: String
        var label: String
        var secret: Bool
        var generated: Bool
        var discovered: Bool
        var help: String

        init(from decoder: Decoder) throws {
            let c = try decoder.channel()
            name = c.or("name", "")
            label = c.or("label", "")
            secret = c.or("secret", false)
            generated = c.or("generated", false)
            discovered = c.or("discovered", false)
            help = c.or("help", "")
        }
    }

    var key: String
    var name: String
    var description: String
    var configures: Bool
    var fields: [Field]
    var id: String { key }

    /// The fields a person types (the rest are made or found by opendesk).
    var typed: [Field] { fields.filter { !$0.generated && !$0.discovered } }
    var discovered: Field? { fields.first(where: \.discovered) }

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        key = c.or("key", "")
        name = c.or("name", "")
        description = c.or("description", "")
        configures = c.or("configures", false)
        fields = c.or("fields", [Field]())
    }
}

struct SupportConnection: Hashable, Sendable, Identifiable, Decodable {
    var id: String
    var provider: String
    var name: String
    var externalAccountID: String
    var externalAccountName: String
    var externalAccountHandle: String
    var status: String
    var lastError: String
    var healthStatus: String
    var healthDetail: String
    var webhookURL: String

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        id = try c.id()
        provider = c.or("provider", "")
        name = c.or("name", "")
        externalAccountID = c.or("external_account_id", "")
        externalAccountName = c.or("external_account_name", "")
        externalAccountHandle = c.or("external_account_handle", "")
        status = c.or("status", "connected")
        lastError = c.or("last_error", "")
        healthStatus = c.or("health_status", "unknown")
        healthDetail = c.or("health_detail", "")
        webhookURL = c.or("webhook_url", "")
    }
}

struct SupportDestination: Hashable, Sendable, Identifiable, Decodable {
    var id: String
    var connectionID: String
    var teamID: String?
    var priority: String?
    var channelID: String
    var channelName: String
    var enabled: Bool
    var includeNotes: Bool
    var messageLimit: Int
    var mode: String
    var conditions: [ChannelCondition]
    var mirror: [String]
    var ollieSummary: Bool
    var ollieWarnings: Bool
    var olliePersonality: String
    var ollieLength: String

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        id = try c.id()
        connectionID = c.or("connection_id", "")
        teamID = c.opt("team_id")
        priority = c.opt("priority")
        channelID = c.or("external_channel_id", "")
        channelName = c.or("external_channel_name", "")
        enabled = c.or("enabled", true)
        includeNotes = c.or("include_notes", false)
        messageLimit = c.or("message_limit", 3500)
        mode = c.or("mode", "route")
        conditions = c.or("conditions", [ChannelCondition]())
        mirror = c.or("mirror", ["customer_replies", "agent_replies"])
        ollieSummary = c.or("ollie_summary", true)
        ollieWarnings = c.or("ollie_warnings", true)
        olliePersonality = c.or("ollie_personality", "")
        ollieLength = c.or("ollie_length", "standard")
    }

    var label: String { channelName.isEmpty ? channelID : channelName }
}

struct SupportOption: Hashable, Sendable, Identifiable, Decodable {
    var id: String
    var name: String
    var available: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        id = c.or("id", "")
        name = c.or("name", "")
        available = c.or("available", true)
    }
}

struct SupportDelivery: Hashable, Sendable, Identifiable, Decodable {
    var eventSeq: Int
    var eventType: String
    var ticketNumber: Int?
    var status: String
    var attempts: Int
    var lastError: String
    var updatedAt: Date?
    var id: Int { eventSeq }

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        eventSeq = c.or("event_seq", 0)
        eventType = c.or("event_type", "")
        ticketNumber = c.opt("ticket_number")
        status = c.or("status", "queued")
        attempts = c.or("attempts", 0)
        lastError = c.or("last_error", "")
        updatedAt = c.opt("updated_at")
    }
}

struct SupportOperations: Hashable, Sendable, Decodable {
    var total = 0, healthy = 0, unhealthy = 0, alerted = 0
    var queued = 0, retrying = 0, delivered = 0, failed = 0
    var averageLatencyMS = 0.0, maximumLatencyMS = 0.0
    var oldestPendingAt: Date?
    var rejected = 0, duplicates = 0

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        let connections: JSONValue = c.or("connections", .null)
        let deliveries: JSONValue = c.or("deliveries", .null)
        let webhooks: JSONValue = c.or("webhooks", .null)
        total = connections["total"]?.int ?? 0
        healthy = connections["healthy"]?.int ?? 0
        unhealthy = connections["unhealthy"]?.int ?? 0
        alerted = connections["alerted"]?.int ?? 0
        queued = deliveries["queued"]?.int ?? 0
        retrying = deliveries["retrying"]?.int ?? 0
        delivered = deliveries["delivered"]?.int ?? 0
        failed = deliveries["failed"]?.int ?? 0
        averageLatencyMS = deliveries["average_latency_ms"]?.double ?? 0
        maximumLatencyMS = deliveries["maximum_latency_ms"]?.double ?? 0
        oldestPendingAt = try? deliveries["oldest_pending_at"]?.decode(Date.self)
        rejected = webhooks["rejected"]?.int ?? 0
        duplicates = webhooks["duplicates_suppressed"]?.int ?? 0
    }
}

// MARK: - Collab

/// `GET /v1/collab`, with the providers the connect choices need.
struct CollabSettingsStatus: Hashable, Sendable, Decodable {
    var enabled = false
    var reason: String?
    var google = false
    var microsoft = false
    var imap = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        enabled = c.or("enabled", false)
        reason = c.opt("reason")
        let providers: JSONValue = c.or("providers", .null)
        google = providers["google"]?.bool ?? false
        microsoft = providers["microsoft"]?.bool ?? false
        imap = providers["imap"]?.bool ?? false
    }
}

struct MailImapSettings: Hashable, Sendable, Decodable {
    var imapHost = ""
    var imapPort = 993
    var imapTLS = "tls"
    var imapUsername = ""
    var smtpHost = ""
    var smtpPort = 465
    var smtpTLS = "tls"
    var smtpUsername = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        imapHost = c.or("imap_host", "")
        imapPort = c.or("imap_port", 993)
        imapTLS = c.or("imap_tls", "tls")
        imapUsername = c.or("imap_username", "")
        smtpHost = c.or("smtp_host", "")
        smtpPort = c.or("smtp_port", 465)
        smtpTLS = c.or("smtp_tls", "tls")
        smtpUsername = c.or("smtp_username", "")
    }
}

/// A Collab account as its settings read it: the Mail area's model plus what only settings show.
struct SettingsMailAccount: Hashable, Sendable, Identifiable, Decodable {
    var account: MailAccount
    var imap: MailImapSettings?
    var signatureSync = ""
    var displayNameSync = ""
    var categoriesAI = true
    var categoriesTeam: String?
    var ownCategories: [MailCategory] = []
    /// Gmail sync's progress (`refreshing`, `pending`, `failed`, `ready`); "" for local categories.
    var categoriesSyncStatus = ""
    var historyStatus = ""
    var historyDetail: MailHistoryDetail?
    var createdAt: Date?

    var id: String { account.id }

    init(from decoder: Decoder) throws {
        account = try MailAccount(from: decoder)
        let c = try decoder.channel()
        imap = c.opt("imap")
        signatureSync = c.or("signature_sync", "")
        displayNameSync = c.or("display_name_sync", "")
        let categories: JSONValue = c.or("categories", .null)
        categoriesAI = categories["ai"]?.bool ?? true
        categoriesTeam = categories["team"]?["name"]?.string
        ownCategories = (try? categories["own"]?.decode([MailCategory].self)) ?? []
        categoriesSyncStatus = categories["sync_status"]?.string ?? ""
        historyStatus = account.history?.status ?? ""
        historyDetail = c.opt("history")
        createdAt = c.opt("created_at")
    }
}

/// The latest import of older mail, as its settings show it (contracts/collab.md "History").
struct MailHistoryDetail: Hashable, Sendable, Decodable {
    var status: String
    var since: Date?
    var includeSpamTrash: Bool
    var requestedBy: String?
    var startedAt: Date?
    var finishedAt: Date?
    var reached: Date?
    var imported: Int
    var present: Int
    var tooLarge: Int
    var unreadable: Int
    var total: Int?
    var lastError: String

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        status = c.or("status", "")
        since = c.opt("since")
        includeSpamTrash = c.or("include_spam_trash", false)
        let by: JSONValue? = c.opt("requested_by")
        requestedBy = by?["name"]?.string
        startedAt = c.opt("started_at")
        finishedAt = c.opt("finished_at")
        reached = c.opt("reached")
        imported = c.or("imported", 0)
        present = c.or("present", 0)
        tooLarge = c.or("too_large", 0)
        unreadable = c.or("unreadable", 0)
        total = c.opt("total")
        lastError = c.or("last_error", "")
    }

    var active: Bool { status == "running" || status == "paused" || status == "limited" }
}

struct MailCategorySet: Hashable, Sendable, Decodable {
    var enabled: Bool
    var categories: [MailCategory]
    var locked: Bool
    var teamID: String?
    var teamName: String
    var position: Int
    var updatedAt: Date?
    var updatedBy: String?

    /// A team's set before it is saved.
    init(teamID: String, teamName: String, categories: [MailCategory]) {
        enabled = true
        self.categories = categories
        locked = false
        self.teamID = teamID
        self.teamName = teamName
        position = 0
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        enabled = c.or("enabled", false)
        categories = c.or("categories", [MailCategory]())
        locked = c.or("locked", false)
        teamID = c.opt("team_id")
        teamName = c.or("team_name", "")
        position = c.or("position", 0)
        updatedAt = c.opt("updated_at")
        let by: JSONValue? = c.opt("updated_by")
        updatedBy = by?["name"]?.string
    }
}

struct MailCategorySettings: Hashable, Sendable, Decodable {
    var workspace: MailCategorySet?
    var teams: [MailCategorySet] = []
    var presets: [MailCategory] = []
    var gmailCategories: [MailCategory] = []
    var sorting = "rules"
    var suggest = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        workspace = c.opt("workspace")
        teams = c.or("teams", [MailCategorySet]())
        presets = c.or("presets", [MailCategory]())
        gmailCategories = c.or("gmail_categories", [MailCategory]())
        sorting = c.or("sorting", "rules")
        suggest = c.or("suggest", false)
    }
}

struct MailCategoryRule: Hashable, Sendable, Identifiable, Decodable {
    var id: String
    var sender: String
    var category: String

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        id = c.or("id", UUID().uuidString)
        sender = c.or("sender", "")
        category = c.or("category", "")
    }
}

extension MailCategory {
    /// The body form the API takes.
    var json: JSONValue {
        .object(["key": .string(key), "name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)), "description": .string(description.trimmingCharacters(in: .whitespacesAndNewlines)), "color": .string(color)])
    }
}

// MARK: - Routing

struct RoutingRule: Hashable, Sendable, Identifiable, Decodable {
    var id: String
    var name: String
    var enabled: Bool
    var position: Int
    var runCount: Int
    var match: String
    var conditions: [ChannelCondition]
    var teamID: String?
    var skillIDs: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        id = try c.id()
        name = c.or("name", "")
        enabled = c.or("enabled", true)
        position = c.or("position", 0)
        runCount = c.or("run_count", 0)
        match = c.or("match", "all")
        conditions = c.or("conditions", [ChannelCondition]())
        teamID = c.opt("team_id")
        skillIDs = c.or("skill_ids", [String]())
    }
}

struct RoutingSkill: Hashable, Sendable, Identifiable, Decodable {
    var id: String
    var name: String
    var archived: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        id = try c.id()
        name = c.or("name", "")
        archived = c.or("archived", false)
    }
}

struct RoutingTestResult: Hashable, Sendable, Decodable {
    struct Step: Hashable, Sendable, Decodable, Identifiable {
        var ruleID: String
        var name: String
        /// "true", "false" or "unknown".
        var matched: String
        var id: String { ruleID }

        init(from decoder: Decoder) throws {
            let c = try decoder.channel()
            ruleID = c.or("rule_id", UUID().uuidString)
            name = c.or("name", "")
            if let flag: Bool = c.opt("matched") { matched = flag ? "true" : "false" } else { matched = c.or("matched", "false") }
        }
    }

    var teamID: String?
    var brandID: String?
    var mailboxID: String?
    var via: String?
    var ruleName: String?
    var topicLabel: String?
    var steps: [Step]
    var skills: [String]
    var assignMode: String

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        teamID = c.opt("team_id")
        brandID = c.opt("brand_id")
        mailboxID = c.opt("mailbox_id")
        let routed: JSONValue? = c.opt("routed")
        via = routed?["via"]?.string
        ruleName = routed?["rule_name"]?.string
        topicLabel = routed?["topic_label"]?.string
        steps = c.or("steps", [Step]())
        let required: JSONValue? = c.opt("required_skills")
        skills = required?.array?.compactMap { $0["name"]?.string } ?? []
        assignMode = c.or("assign_mode", "none")
    }
}

// MARK: - Brands and widgets

struct BrandHelpDomain: Hashable, Sendable, Decodable {
    struct Record: Hashable, Sendable, Decodable {
        var type: String
        var name: String
        var value: String
        var ok: Bool

        init(from decoder: Decoder) throws {
            let c = try decoder.channel()
            type = c.or("type", "")
            name = c.or("name", "")
            value = c.or("value", "")
            ok = c.or("ok", false)
        }
    }

    var hostname: String
    var status: String
    var problem: String
    var records: [Record]
    var checkedAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        hostname = c.or("hostname", "")
        status = c.or("status", "pending")
        problem = c.or("problem", "")
        records = c.or("records", [Record]())
        checkedAt = c.opt("checked_at")
    }
}

struct SettingsBrand: Hashable, Sendable, Identifiable, Decodable {
    var id: String
    var name: String
    var slug: String
    var isDefault: Bool
    var color: String
    var locale: String
    var helpEnabled: Bool
    var helpTitle: String
    var helpURL: String
    var helpDefaultURL: String
    var domain: BrandHelpDomain?
    var logo: String?
    var defaultMailboxID: String?
    var mailboxCount: Int
    var widgetCount: Int
    var position: Int
    var updatedAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        id = try c.id()
        name = c.or("name", "")
        slug = c.or("slug", "")
        isDefault = c.or("is_default", false)
        color = c.or("color", "")
        locale = c.or("locale", "")
        let help: JSONValue = c.or("help_center", .null)
        helpEnabled = help["enabled"]?.bool ?? false
        helpTitle = help["title"]?.string ?? ""
        helpURL = help["url"]?.string ?? ""
        helpDefaultURL = help["default_url"]?.string ?? helpURL
        domain = help["domain"].flatMap { $0.isNull ? nil : try? $0.decode(BrandHelpDomain.self) }
        let images: JSONValue = c.or("images", .null)
        logo = images["logo"]?.string
        defaultMailboxID = c.opt("default_mailbox_id")
        mailboxCount = c.or("mailbox_count", 0)
        widgetCount = c.or("widget_count", 0)
        position = c.or("position", 0)
        updatedAt = c.opt("updated_at")
    }

    var shortURL: String {
        helpURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    }
}

struct WidgetTopic: Hashable, Sendable, Identifiable, Decodable {
    var id: String
    var label: String
    var teamID: String?
    /// Topics made here have no server id yet.
    var isNew = false

    init(label: String, teamID: String?) {
        id = UUID().uuidString
        self.label = label
        self.teamID = teamID
        isNew = true
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        id = c.or("id", UUID().uuidString)
        label = c.or("label", "")
        teamID = c.opt("team_id")
    }

    var json: JSONValue {
        var object: ChannelBody = ["label": .string(label.trimmingCharacters(in: .whitespacesAndNewlines)), "team_id": .chString(teamID)]
        if !isNew { object["id"] = .string(id) }
        return .object(object)
    }
}

/// A widget's settings: the keys `PATCH /v1/widgets/{id}` merges.
struct WidgetSettings: Hashable, Sendable, Decodable {
    var enabled = true
    var greeting = ""
    var intro = ""
    var chatWelcome = true
    var requireEmail = false
    var allowedOrigins: [String] = []
    var color = ""
    var theme = "auto"
    var position = "right"
    var offsetX = 20
    var offsetY = 20
    var launcher = "icon"
    var launcherLabel = ""
    var radius = "soft"
    var title = ""
    var subtitle = ""
    var showTeam = true
    var suggestions: [String] = []
    var sound = false
    var topics: [WidgetTopic] = []
    var offlineMessage = ""
    var emailFollowUp = true
    var attachments = true
    var attachmentTypes: [String] = []
    var voiceMessages = false
    var voiceMaxSeconds = 60

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        enabled = c.or("enabled", true)
        greeting = c.or("greeting", "")
        intro = c.or("intro", "")
        chatWelcome = c.or("chat_welcome", true)
        requireEmail = c.or("require_email", false)
        allowedOrigins = c.or("allowed_origins", [String]())
        color = c.or("color", "")
        theme = c.or("theme", "auto")
        position = c.or("position", "right")
        offsetX = c.or("offset_x", 20)
        offsetY = c.or("offset_y", 20)
        launcher = c.or("launcher", "icon")
        launcherLabel = c.or("launcher_label", "")
        radius = c.or("radius", "soft")
        title = c.or("title", "")
        subtitle = c.or("subtitle", "")
        showTeam = c.or("show_team", true)
        suggestions = c.or("suggestions", [String]())
        sound = c.or("sound", false)
        topics = c.or("topics", [WidgetTopic]())
        offlineMessage = c.or("offline_message", "")
        emailFollowUp = c.or("email_follow_up", true)
        attachments = c.or("attachments", true)
        attachmentTypes = c.or("attachment_types", [String]())
        voiceMessages = c.or("voice_messages", false)
        voiceMaxSeconds = c.or("voice_max_seconds", 60)
    }

    var json: ChannelBody {
        [
            "enabled": .bool(enabled), "greeting": .string(greeting), "intro": .string(intro), "chat_welcome": .bool(chatWelcome),
            "require_email": .bool(requireEmail), "allowed_origins": .chStrings(allowedOrigins), "color": .string(color),
            "theme": .string(theme), "position": .string(position), "offset_x": .chInt(offsetX), "offset_y": .chInt(offsetY),
            "launcher": .string(launcher), "launcher_label": .string(launcherLabel), "radius": .string(radius),
            "title": .string(title), "subtitle": .string(subtitle), "show_team": .bool(showTeam), "suggestions": .chStrings(suggestions),
            "sound": .bool(sound), "topics": .array(topics.map(\.json)), "offline_message": .string(offlineMessage),
            "email_follow_up": .bool(emailFollowUp), "attachments": .bool(attachments), "attachment_types": .chStrings(attachmentTypes),
            "voice_messages": .bool(voiceMessages), "voice_max_seconds": .chInt(voiceMaxSeconds),
        ]
    }

    /// The keys whose values differ from `old`.
    func changes(from old: WidgetSettings) -> ChannelBody {
        let before = old.json
        return json.filter { before[$0.key] != $0.value }
    }
}

struct ChatWidget: Hashable, Sendable, Identifiable, Decodable {
    var id: String
    var brandID: String
    var name: String
    var key: String
    var teamID: String?
    var botID: String?
    var settings: WidgetSettings
    var snippet: String
    var seenAt: Date?
    var secret: String?
    var secretAvailable: Bool
    var position: Int
    var avatarURL: String?
    var launcherURL: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.channel()
        id = try c.id()
        brandID = c.or("brand_id", "")
        name = c.or("name", "")
        key = c.or("key", "")
        teamID = c.opt("team_id")
        botID = c.opt("bot_id")
        settings = c.or("settings", WidgetSettings())
        let install: JSONValue = c.or("install", .null)
        snippet = install["snippet"]?.string ?? ""
        seenAt = c.opt("seen_at")
        secret = c.opt("secret")
        secretAvailable = c.or("secret_available", false)
        position = c.or("position", 0)
        let images: JSONValue = c.or("images", .null)
        avatarURL = images["avatar"]?.string
        launcherURL = images["launcher"]?.string
    }

    var statusText: String { seenAt == nil ? "Not installed" : (settings.enabled ? "Live" : "Hidden") }
    var statusTone: Tone { seenAt == nil ? .gray : (settings.enabled ? .green : .gray) }
}
