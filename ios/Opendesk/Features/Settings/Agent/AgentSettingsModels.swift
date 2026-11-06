import Foundation

// Shapes of the AI agent's settings (contracts/agent.md, contracts/ai.md, contracts/bots.md and
// contracts/ai.md "Asking a teammate"), read leniently: a missing or odd value takes its default,
// so a newer or older server never blanks a page. Request bodies are built as `JSONValue`.

/// A coding key from any string, so models read the API's snake_case names directly.
struct AgentKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Decoder {
    /// The object's members by their API names.
    func agentFields() throws -> KeyedDecodingContainer<AgentKey> { try container(keyedBy: AgentKey.self) }
}

extension KeyedDecodingContainer where Key == AgentKey {
    /// The member, or `fallback` when it is missing, null or of another shape.
    func v<T: Decodable>(_ key: String, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: AgentKey(key))) ?? fallback
    }

    /// The member when present and readable.
    func o<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        (try? decodeIfPresent(T.self, forKey: AgentKey(key))) ?? nil
    }
}

// MARK: - Settings and models

/// The widget agent's settings (`AISettings` widget_*), with the contract's defaults.
struct AgentBehaviour: Hashable, Sendable {
    var widgetAnswers = false
    var widgetModel = ""
    var widgetMaxReplies = 20
    var widgetBlockedTopics: [String] = []
    var widgetMonthlyCapUSD: Double = 0
    var widgetCollectEmail = true

    var json: JSONValue {
        .object([
            "widget_answers": .bool(widgetAnswers),
            "widget_model": .string(widgetModel),
            "widget_max_replies": .number(Double(widgetMaxReplies)),
            "widget_blocked_topics": .array(widgetBlockedTopics.map(JSONValue.string)),
            "widget_monthly_cap_usd": .number(widgetMonthlyCapUSD),
            "widget_collect_email": .bool(widgetCollectEmail),
        ])
    }

    /// Only the members that differ from `base`, for a PATCH.
    func patch(from base: AgentBehaviour) -> [String: JSONValue] {
        let mine = json.object ?? [:]
        let theirs = base.json.object ?? [:]
        return mine.filter { theirs[$0.key] != $0.value }
    }

    /// What the playground and a test run try from these edits.
    var playgroundJSON: [String: JSONValue] {
        ["widget_model": .string(widgetModel), "widget_blocked_topics": .array(widgetBlockedTopics.map(JSONValue.string))]
    }
}

extension AgentBehaviour: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        widgetAnswers = c.v("widget_answers", false)
        widgetModel = c.v("widget_model", "")
        widgetMaxReplies = c.v("widget_max_replies", 20)
        widgetBlockedTopics = c.v("widget_blocked_topics", [String]())
        widgetMonthlyCapUSD = c.v("widget_monthly_cap_usd", 0.0)
        widgetCollectEmail = c.v("widget_collect_email", true)
    }
}

/// `GET /v1/ai/config`, as the agent pages read it.
struct AgentConfig: Decodable, Sendable {
    var enabled: Bool
    var assistantName: String
    var behaviour: AgentBehaviour
    /// The workspace's main model ("" is the instance default).
    var model: String
    var defaultModel: String
    var playgroundCost: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        enabled = c.v("enabled", false)
        assistantName = c.o("assistant_name", as: String.self).flatMap { $0.isEmpty ? nil : $0 } ?? "Ollie"
        behaviour = c.o("features", as: AgentBehaviour.self) ?? AgentBehaviour()
        let features = c.o("features", as: JSONValue.self)
        model = features?["model"]?.string ?? ""
        defaultModel = c.o("models", as: JSONValue.self)?["default"]?.string ?? ""
        playgroundCost = c.o("costs", as: JSONValue.self)?["playground"]?.double
    }
}

/// A model the instance offers (`GET /v1/ai/models`).
struct AgentModel: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var vendor: String
    var contextLength: Int?
    var typicalReplyUSD: Double?
    var inputUSD: Double?
    var outputUSD: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        id = c.v("id", "")
        name = c.v("name", "")
        vendor = c.v("vendor", "")
        contextLength = c.o("context_length")
        typicalReplyUSD = c.o("typical_reply_usd")
        let price = c.o("usd_per_mtok", as: JSONValue.self)
        inputUSD = price?["input"]?.double
        outputUSD = price?["output"]?.double
    }
}

struct AgentModels: Decodable, Sendable {
    var data: [AgentModel]
    var defaultID: String

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        data = c.v("data", [AgentModel]())
        defaultID = c.v("default", "")
    }
}

// MARK: - Overview

struct AgentReport: Decodable, Sendable {
    struct Day: Decodable, Hashable, Sendable, Identifiable {
        var date: String
        var conversations: Int
        var replies: Int
        var resolved: Int
        var handoffs: Int
        var id: String { date }

        init(from decoder: Decoder) throws {
            let c = try decoder.agentFields()
            date = c.v("date", "")
            conversations = c.v("conversations", 0)
            replies = c.v("replies", 0)
            resolved = c.v("resolved", 0)
            handoffs = c.v("handoffs", 0)
        }
    }

    struct ToolStat: Decodable, Hashable, Sendable, Identifiable {
        var tool: String
        var calls: Int
        var errors: Int
        var id: String { tool }

        init(from decoder: Decoder) throws {
            let c = try decoder.agentFields()
            tool = c.v("tool", "")
            calls = c.v("calls", 0)
            errors = c.v("errors", 0)
        }
    }

    struct Gap: Decodable, Hashable, Sendable {
        var question: String
        var count: Int

        init(from decoder: Decoder) throws {
            let c = try decoder.agentFields()
            question = c.v("question", "")
            count = c.v("count", 1)
        }
    }

    var conversations: Int
    var replies: Int
    var resolved: Int
    var handoffs: Int
    var ratingsUp: Int
    var ratingsDown: Int
    var usd: Double
    var byDay: [Day]
    var tools: [ToolStat]
    var gaps: [Gap]

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        conversations = c.v("conversations", 0)
        replies = c.v("replies", 0)
        resolved = c.v("resolved", 0)
        handoffs = c.v("handoffs", 0)
        let ratings = c.o("ratings", as: JSONValue.self)
        ratingsUp = ratings?["up"]?.int ?? 0
        ratingsDown = ratings?["down"]?.int ?? 0
        usd = c.v("usd", 0.0)
        byDay = c.v("by_day", [Day]())
        tools = c.v("tools", [ToolStat]())
        gaps = c.v("gaps", [Gap]())
    }
}

/// `GET /v1/ai/agent/setup`.
struct AgentSetup: Decodable, Sendable {
    struct Step: Decodable, Hashable, Sendable, Identifiable {
        var id: String
        var title: String
        var description: String
        var done: Bool
        var optional: Bool
        var href: String

        init(from decoder: Decoder) throws {
            let c = try decoder.agentFields()
            id = c.v("id", "")
            title = c.v("title", "")
            description = c.v("description", "")
            done = c.v("done", false)
            optional = c.v("optional", false)
            href = c.v("href", "")
        }
    }

    var steps: [Step]

    init(from decoder: Decoder) throws {
        steps = try decoder.agentFields().v("steps", [Step]())
    }

    private static let needsAI: Set<String> = ["playground", "answers_on", "email_answers"]

    var required: [Step] { steps.filter { !$0.optional } }
    var done: Int { required.filter(\.done).count }
    var total: Int { required.count }
    var complete: Bool { done == total }

    /// The step that has to come first, when this one can't be done yet.
    func blocked(_ step: Step) -> Bool {
        guard !step.done, Self.needsAI.contains(step.id) else { return false }
        return steps.first { $0.id == "ai_on" }.map { !$0.done } ?? false
    }

    /// The first open required step that can be done now, else the first open optional one.
    var next: Step? {
        let open = steps.filter { !$0.done && !blocked($0) }
        return open.first { !$0.optional } ?? open.first { $0.optional }
    }
}

/// "Needs review" on the overview (contracts/agent.md "Review queue").
struct AgentReviewItem: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var ticketID: String
    var ticketNumber: Int
    var ratedDown: Bool
    var question: String
    var answer: String
    var contactName: String
    var createdAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        id = c.v("id", "")
        ticketID = c.v("ticket_id", "")
        ticketNumber = c.v("ticket_number", 0)
        ratedDown = c.v("reason", "handoff") == "rated_down"
        question = c.v("question", "")
        answer = c.v("answer", "")
        contactName = c.v("contact_name", "")
        createdAt = c.o("created_at")
    }
}

// MARK: - Bots

struct BotPersonality: Hashable, Sendable {
    var tone = "friendly"
    var customTone = ""
    var instructions = ""
    var replyLength = "medium"
    var emoji = "some"
    var greeting = ""
    var handoffMessage = ""
    var blockedTopics: [String] = []
    var signOff = ""

    var json: JSONValue {
        .object([
            "tone": .string(tone), "custom_tone": .string(customTone), "instructions": .string(instructions),
            "reply_length": .string(replyLength), "emoji": .string(emoji), "greeting": .string(greeting),
            "handoff_message": .string(handoffMessage), "blocked_topics": .array(blockedTopics.map(JSONValue.string)),
            "sign_off": .string(signOff),
        ])
    }

    /// The members that differ from `base`.
    func patch(from base: BotPersonality) -> [String: JSONValue] {
        let mine = json.object ?? [:]
        let theirs = base.json.object ?? [:]
        return mine.filter { theirs[$0.key] != $0.value }
    }
}

extension BotPersonality: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        tone = c.v("tone", "friendly")
        customTone = c.v("custom_tone", "")
        instructions = c.v("instructions", "")
        replyLength = c.v("reply_length", "medium")
        emoji = c.v("emoji", "some")
        greeting = c.v("greeting", "")
        handoffMessage = c.v("handoff_message", "")
        blockedTopics = c.v("blocked_topics", [String]())
        signOff = c.v("sign_off", "")
    }
}

/// A customer-facing bot (contracts/bots.md).
struct AgentBot: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var role: String
    var language: String
    var look: BotLook
    var imageURL: String?
    var personality: BotPersonality
    var isDefault: Bool
    var position: Int
    /// Where it answers: widget names, mailbox addresses and API keys, in that order.
    var usage: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        id = c.v("id", "")
        name = c.v("name", "")
        role = c.v("role", "")
        language = c.v("language", "")
        look = BotLook.read(c.o("look", as: JSONValue.self))
        imageURL = c.o("image_url", as: String.self).flatMap { $0.isEmpty ? nil : $0 }
        personality = c.o("personality", as: BotPersonality.self) ?? BotPersonality()
        isDefault = c.v("is_default", false)
        position = c.v("position", 0)
        let usage = c.o("usage", as: JSONValue.self)
        let widgets = usage?["widgets"]?.array?.compactMap { $0["name"]?.string } ?? []
        let mailboxes = usage?["mailboxes"]?.array?.compactMap { $0["email"]?.string } ?? []
        let keys = usage?["api_keys"]?.array?.compactMap { $0["name"]?.string }.map { "\($0) (API key)" } ?? []
        self.usage = widgets + mailboxes + keys
    }

    /// "Answers on Marketing site, Docs and 1 more", or that it answers nowhere yet.
    var usageLine: String {
        guard !usage.isEmpty else {
            return isDefault ? "Answers everywhere no other bot is picked" : "Not used yet. Pick it on a widget or an address."
        }
        let shown = usage.prefix(2)
        let more = usage.count - shown.count
        if more > 0 { return "Answers on \(shown.joined(separator: ", ")) and \(more) more" }
        return "Answers on " + shown.joined(separator: " and ")
    }
}

// MARK: - Knowledge

struct KnowledgeSource: Decodable, Hashable, Sendable, Identifiable {
    struct Website: Hashable, Sendable {
        var url = ""
        var maxPages = 100
        var include: [String] = []
        var exclude: [String] = []
        var weekly = true
    }

    var id: String
    var kind: String
    var name: String
    var status: String
    var error: String?
    var enabled: Bool
    var website: Website?
    var filename: String?
    var contentType: String?
    var sizeBytes: Int?
    var question: String?
    var answer: String?
    var docCount: Int
    var charCount: Int
    var lastSyncedAt: Date?
    var createdAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        id = c.v("id", "")
        kind = c.v("kind", "website")
        name = c.v("name", "")
        status = c.v("status", "ready")
        error = c.o("error", as: String.self).flatMap { $0.isEmpty ? nil : $0 }
        enabled = c.v("enabled", true)
        if let w = c.o("website", as: JSONValue.self), w.object != nil {
            website = Website(
                url: w["url"]?.string ?? "",
                maxPages: w["max_pages"]?.int ?? 100,
                include: w["include"]?.array?.compactMap(\.string) ?? [],
                exclude: w["exclude"]?.array?.compactMap(\.string) ?? [],
                weekly: (w["recrawl"]?.string ?? "weekly") == "weekly"
            )
        }
        let file = c.o("file", as: JSONValue.self)
        filename = file?["filename"]?.string
        contentType = file?["content_type"]?.string
        sizeBytes = file?["size_bytes"]?.int
        let snippet = c.o("snippet", as: JSONValue.self)
        question = snippet?["question"]?.string
        answer = snippet?["answer"]?.string
        docCount = c.v("doc_count", 0)
        charCount = c.v("char_count", 0)
        lastSyncedAt = c.o("last_synced_at")
        createdAt = c.o("created_at")
    }

    var moving: Bool { status == "syncing" || status == "pending" }

    /// The line under a source's name: its address, file or question.
    var detail: String {
        switch kind {
        case "website": website?.url ?? ""
        case "file": [filename, sizeBytes.map(Format.bytes)].compactMap { $0 }.joined(separator: " · ")
        default: question ?? ""
        }
    }
}

struct KnowledgeDoc: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var url: String?
    var chars: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        id = c.v("id", "")
        title = c.v("title", "")
        url = c.o("url", as: String.self).flatMap { $0.isEmpty ? nil : $0 }
        chars = c.v("chars", 0)
    }
}

// MARK: - Procedures

struct AgentProcedure: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var when: String
    var instructions: String
    var enabled: Bool
    var channels: [String]
    var botIDs: [String]
    var updatedAt: Date?
    var updatedBy: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        id = c.v("id", "")
        name = c.v("name", "")
        when = c.v("when", "")
        instructions = c.v("instructions", "")
        enabled = c.v("enabled", true)
        channels = c.v("channels", [String]())
        botIDs = c.v("bot_ids", [String]())
        updatedAt = c.o("updated_at")
        updatedBy = c.o("updated_by", as: JSONValue.self)?["name"]?.string
    }

    /// "Chat, Email", "Automations only".
    var channelsText: String {
        channels.isEmpty ? "Automations only" : channels.map { $0 == "chat" ? "Chat" : "Email" }.joined(separator: ", ")
    }
}

// MARK: - Tools

struct McpTool: Decodable, Hashable, Sendable, Identifiable {
    var name: String
    var title: String?
    var description: String
    var inputSchema: JSONValue
    var readOnly: Bool
    var destructive: Bool
    var enabled: Bool
    var policy: String
    var verifiedOnly: Bool
    var id: String { name }
    var shownName: String { (title?.isEmpty == false ? title : nil) ?? name }

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        name = c.v("name", "")
        title = c.o("title", as: String.self)
        description = c.v("description", "")
        inputSchema = c.v("input_schema", JSONValue.object([:]))
        readOnly = c.v("read_only", false)
        destructive = c.v("destructive", false)
        enabled = c.v("enabled", false)
        policy = c.v("policy", "confirm")
        verifiedOnly = c.v("verified_only", false)
    }
}

struct McpServer: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var slug: String
    var url: String
    var enabled: Bool
    var authKind: String
    var headerName: String
    var hasSecret: Bool
    var oauthConnected: Bool
    var oauthScopes: [String]
    var status: String
    var error: String?
    var serverInfo: String?
    var tools: [McpTool]
    var lastSyncedAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        id = c.v("id", "")
        name = c.v("name", "")
        slug = c.v("slug", "")
        url = c.v("url", "")
        enabled = c.v("enabled", true)
        let auth = c.o("auth", as: JSONValue.self)
        authKind = auth?["kind"]?.string ?? "none"
        headerName = auth?["header_name"]?.string ?? ""
        hasSecret = auth?["has_secret"]?.bool ?? false
        oauthConnected = auth?["oauth"]?["connected"]?.bool ?? false
        oauthScopes = auth?["oauth"]?["scopes"]?.array?.compactMap(\.string) ?? []
        status = c.v("status", "connected")
        error = c.o("error", as: String.self).flatMap { $0.isEmpty ? nil : $0 }
        let info = c.o("server_info", as: JSONValue.self)
        serverInfo = info.flatMap { i in i["name"]?.string.map { "\($0) \(i["version"]?.string ?? "")".trimmingCharacters(in: .whitespaces) } }
        tools = c.v("tools", [McpTool]())
        lastSyncedAt = c.o("last_synced_at")
    }

    var toolsOn: Int { tools.filter(\.enabled).count }

    var authText: String {
        switch authKind {
        case "oauth": oauthConnected ? "Signed in with OAuth" : "OAuth, not signed in"
        case "bearer": "Bearer token"
        case "header": "Header \(headerName)"
        default: "No authentication"
        }
    }

    /// Tool keys as the agent names them: `<server_slug>__<tool>` (contracts/agent.md).
    func key(_ tool: McpTool) -> String {
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "[^a-zA-Z0-9_-]+", with: "_", options: .regularExpression)
        }
        let joined = String((clean(slug) + "__" + clean(tool.name)).prefix(64))
        return joined.trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
    }
}

struct McpToolResult: Decodable, Sendable {
    var content: String
    var isError: Bool
    var ms: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        content = c.v("content", "")
        isError = c.v("is_error", false)
        ms = c.v("ms", 0)
    }
}

// MARK: - Playground and tests

/// A source an answer cited.
struct AgentSource: Decodable, Hashable, Sendable {
    var kind: String
    var id: String
    var title: String
    var url: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        kind = c.v("kind", "article")
        id = c.v("id", "")
        title = c.v("title", "")
        url = c.o("url", as: String.self).flatMap { $0.isEmpty ? nil : $0 }
    }

    var symbol: String {
        switch kind {
        case "page": "globe"
        case "file": "doc.text"
        case "snippet": "text.quote"
        default: "book"
        }
    }
}

struct AgentProcedureRef: Decodable, Hashable, Sendable {
    var id: String
    var name: String

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        id = c.v("id", "")
        name = c.v("name", "")
    }
}

/// A change the agent would ask the visitor to confirm.
struct AgentAction: Decodable, Hashable, Sendable {
    var tool: String
    var title: String
    var summary: String

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        tool = c.v("tool", "")
        title = c.v("title", "")
        summary = c.v("summary", "")
    }
}

/// One message of a test conversation or a playground history.
struct AgentLine: Codable, Hashable, Sendable {
    var role: String
    var text: String

    init(role: String, text: String) {
        self.role = role
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        role = c.v("role", "visitor") == "agent" ? "agent" : "visitor"
        text = c.v("text", "")
    }

    var json: JSONValue { .object(["role": .string(role), "text": .string(text)]) }
}

struct AgentExpectation: Hashable, Sendable {
    var kind: String
    var value: String

    static let kinds = ["mentions", "not_mentions", "handoff", "no_handoff", "uses_tool", "uses_procedure", "cites_knowledge"]

    static func title(_ kind: String) -> String {
        switch kind {
        case "mentions": "Mentions"
        case "not_mentions": "Doesn't mention"
        case "handoff": "Hands off to the team"
        case "no_handoff": "Doesn't hand off"
        case "uses_tool": "Uses a tool"
        case "uses_procedure": "Follows a procedure"
        case "cites_knowledge": "Cites the knowledge base"
        default: kind
        }
    }

    static func hint(_ kind: String) -> String {
        switch kind {
        case "mentions": "What the answer must say"
        case "not_mentions": "What the answer must not say"
        case "handoff": "Ollie passes the conversation to a person"
        case "no_handoff": "Ollie answers without passing it on"
        case "uses_tool": "Ollie calls this tool"
        case "uses_procedure": "Ollie reads this procedure"
        case "cites_knowledge": "The answer cites at least one source"
        default: ""
        }
    }

    static func picked(_ kind: String) -> Bool { kind == "uses_tool" || kind == "uses_procedure" }
    static func needsValue(_ kind: String) -> Bool { kind == "mentions" || kind == "not_mentions" || picked(kind) }

    var json: JSONValue {
        Self.needsValue(kind) ? .object(["kind": .string(kind), "value": .string(value)]) : .object(["kind": .string(kind)])
    }
}

extension AgentExpectation: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        kind = c.v("kind", "mentions")
        value = c.v("value", "")
    }
}

struct AgentTestCheck: Decodable, Hashable, Sendable {
    var kind: String
    var value: String
    var passed: Bool
    var reason: String

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        kind = c.v("kind", "mentions")
        value = c.v("value", "")
        passed = c.v("passed", false)
        reason = c.v("reason", "")
    }
}

struct AgentTestResult: Decodable, Hashable, Sendable {
    var runID: String
    var testID: String
    var status: String
    var answerHTML: String
    var handoff: Bool
    var tools: [String]
    var sources: [AgentSource]
    var procedures: [AgentProcedureRef]
    var action: AgentAction?
    var checks: [AgentTestCheck]
    var error: String?
    var usd: Double
    var draft: Bool
    var previousStatus: String?
    var finishedAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        runID = c.v("run_id", "")
        testID = c.v("test_id", "")
        status = c.v("status", "pending")
        answerHTML = c.v("answer_html", "")
        handoff = c.v("handoff", false)
        tools = c.v("tools", [String]())
        sources = c.v("sources", [AgentSource]())
        procedures = c.v("procedures", [AgentProcedureRef]())
        action = c.o("action")
        checks = c.v("checks", [AgentTestCheck]())
        error = c.o("error", as: String.self).flatMap { $0.isEmpty ? nil : $0 }
        usd = c.v("usd", 0.0)
        draft = c.v("draft", false)
        previousStatus = c.o("previous_status")
        finishedAt = c.o("finished_at")
    }

    var final: Bool { status == "passed" || status == "failed" || status == "error" }
    /// Passed before and fails now.
    var newlyFailing: Bool { (status == "failed" || status == "error") && previousStatus == "passed" }
}

struct AgentTestVisitor: Hashable, Sendable {
    var verified = false
    var email = ""
    var userID = ""
}

struct AgentTest: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var messages: [AgentLine]
    var expectations: [AgentExpectation]
    var visitor: AgentTestVisitor
    var lastResult: AgentTestResult?

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        id = c.v("id", "")
        name = c.v("name", "")
        messages = c.v("messages", [AgentLine]())
        expectations = c.v("expectations", [AgentExpectation]())
        let v = c.o("visitor", as: JSONValue.self)
        visitor = AgentTestVisitor(verified: v?["verified"]?.bool ?? false, email: v?["email"]?.string ?? "", userID: v?["user_id"]?.string ?? "")
        lastResult = c.o("last_result")
    }

    var firstVisitorLine: String { messages.first { $0.role == "visitor" }?.text ?? "" }
}

struct AgentTestRun: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var status: String
    var draft: Bool
    var testIDs: [String]
    var total: Int
    var passed: Int
    var failed: Int
    var errored: Int
    var usd: Double
    var error: String?
    var createdAt: Date?
    var finishedAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        id = c.v("id", "")
        status = c.v("status", "queued")
        draft = c.v("draft", false)
        testIDs = c.v("test_ids", [String]())
        total = c.v("total", 0)
        passed = c.v("passed", 0)
        failed = c.v("failed", 0)
        errored = c.v("errored", 0)
        usd = c.v("usd", 0.0)
        error = c.o("error", as: String.self).flatMap { $0.isEmpty ? nil : $0 }
        createdAt = c.o("created_at")
        finishedAt = c.o("finished_at")
    }

    var active: Bool { status == "queued" || status == "running" }
    var done: Int { passed + failed + errored }
    var progress: Double { total > 0 ? Double(done) / Double(total) : 0 }
}

/// Where a test stands in the list: its latest result, or queued in the active run.
enum AgentTestState: String, CaseIterable, Sendable {
    case passed, failed, error, queued, never

    var title: String {
        switch self {
        case .passed: "Passing"
        case .failed: "Failing"
        case .error: "Error"
        case .queued: "Queued"
        case .never: "Not run"
        }
    }

    var tone: Tone {
        switch self {
        case .passed: .green
        case .failed: .red
        case .error: .amber
        case .queued: .violet
        case .never: .gray
        }
    }

    var symbol: String {
        switch self {
        case .passed: "checkmark.circle"
        case .failed: "xmark.circle"
        case .error: "exclamationmark.circle"
        case .queued: "clock"
        case .never: "circle.dashed"
        }
    }

    static func of(_ test: AgentTest, run: AgentTestRun?) -> AgentTestState {
        if let run, run.testIDs.contains(test.id), test.lastResult?.runID != run.id { return .queued }
        return AgentTestState(rawValue: test.lastResult?.status ?? "") ?? .never
    }
}

// MARK: - Mailboxes (Behaviour's Email section)

struct AgentMailbox: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var email: String
    var aiAnswers: Bool
    var sends: Bool
    var outsideHours: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        id = c.v("id", "")
        name = c.v("name", "")
        email = c.v("email", "")
        aiAnswers = c.v("ai_answers", false)
        sends = c.v("ai_answers_mode", "draft") == "send"
        outsideHours = c.v("ai_answers_outside_hours", false)
    }
}

// MARK: - Agent-to-agent

struct PeerPerson: Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var email: String
    var avatarURL: String?

    var json: JSONValue { .object(["id": .string(id), "name": .string(name), "email": .string(email)]) }
}

extension PeerPerson: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        id = c.v("id", "")
        name = c.v("name", "")
        email = c.v("email", "")
        avatarURL = c.o("avatar_url")
    }
}

struct PeerAccount: Hashable, Sendable, Identifiable {
    var id: String
    var email: String
    var name: String
    var provider: String
    var mode: String
    var chosen: Bool
}

extension PeerAccount: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        id = c.v("id", "")
        email = c.v("email", "")
        name = c.v("name", "")
        provider = c.v("provider", "imap")
        mode = c.v("mode", "none")
        chosen = c.v("chosen", false)
    }
}

/// `GET /v1/me/assistant-peer`: the caller's own sharing in this workspace.
struct PeerSettings: Decodable, Hashable, Sendable {
    struct TeamRef: Hashable, Sendable, Identifiable {
        var id: String
        var name: String
    }

    static let modes = ["verbatim", "summary", "none"]
    static let rulesMax = 2000

    var available: Bool
    var enabled: Bool
    var shareWith: String
    var users: [PeerPerson]
    var teams: [TeamRef]
    var allAccounts: Bool
    var defaultMode: String
    var accounts: [PeerAccount]
    var rules: String

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        available = c.v("available", false)
        enabled = c.v("enabled", false)
        shareWith = c.v("share_with", "everyone")
        let audience = c.o("audience", as: JSONValue.self)
        users = (audience?["users"]).flatMap { try? $0.decode([PeerPerson].self) } ?? []
        teams = audience?["teams"]?.array?.compactMap { t in t["id"]?.string.map { TeamRef(id: $0, name: t["name"]?.string ?? "") } } ?? []
        allAccounts = c.v("all_accounts", true)
        defaultMode = c.v("default_mode", "summary")
        accounts = c.v("accounts", [PeerAccount]())
        rules = c.v("rules", "")
    }

    static func modeTitle(_ mode: String) -> String {
        switch mode {
        case "verbatim": "Verbatim"
        case "summary": "Summaries only"
        default: "Nothing"
        }
    }

    /// The PUT body that keeps everything the page shows.
    var input: JSONValue {
        .object([
            "enabled": .bool(enabled),
            "share_with": .string(shareWith),
            "audience": .object(["user_ids": .array(users.map { .string($0.id) }), "team_ids": .array(teams.map { .string($0.id) })]),
            "all_accounts": .bool(allAccounts),
            "default_mode": .string(defaultMode),
            "accounts": .array(accounts.filter(\.chosen).map { .object(["id": .string($0.id), "mode": .string($0.mode)]) }),
            "rules": .string(rules),
        ])
    }

    /// Accounts without their own choice follow the scope and the default.
    mutating func remode() {
        for index in accounts.indices where !accounts[index].chosen {
            accounts[index].mode = allAccounts ? defaultMode : "none"
        }
    }
}

struct PeerAsk: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var asker: PeerPerson
    var question: String
    var answer: String
    var result: String
    var sources: Int
    var createdAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.agentFields()
        id = c.v("id", "")
        asker = c.o("asker", as: PeerPerson.self) ?? PeerPerson(id: "", name: "", email: "")
        question = c.v("question", "")
        answer = c.v("answer", "")
        result = c.v("result", "answered")
        sources = c.v("sources", 0)
        createdAt = c.o("created_at")
    }

    var resultTitle: String {
        switch result {
        case "answered": sources == 0 ? "Answered" : sources == 1 ? "Answered from 1 conversation" : "Answered from \(sources) conversations"
        case "declined": "Declined"
        case "not_shared": "Not shared"
        default: "Could not answer"
        }
    }

    var resultTone: Tone {
        switch result {
        case "answered": .green
        case "declined": .amber
        case "not_shared": .gray
        default: .red
        }
    }
}
