#if DEBUG
import Foundation

// The demo's AI agent settings (`Features/Settings/Agent`): Margin's bots, knowledge, procedures,
// tools, tests and test runs, the overview's report and review queue, and each member's own
// agent-to-agent sharing. Rows are kept as JSON objects in the shapes of contracts/agent.md,
// contracts/bots.md and contracts/collab.md, so the pages decode them with their real models.
// Test runs and crawls move on their own and publish the events a server would.

struct DemoAgentSettings: Sendable {
    typealias Object = [String: JSONValue]

    var aiOn = true
    var behaviour: Object = [:]
    var playgroundUsed = false
    var bots: [Object] = []
    var knowledge: [Object] = []
    var docs: [String: [Object]] = [:]
    var procedures: [Object] = []
    var servers: [Object] = []
    var tests: [Object] = []
    var runs: [Object] = []
    var review: [Object] = []
    var peer: Object = [:]
    var asks: [Object] = []

    static let models: [Object] = [
        obj(["id": "claude-haiku-4-5", "name": "Claude Haiku 4.5", "vendor": "Anthropic", "context_length": 200_000, "typical_reply_usd": 0.004, "usd_per_mtok": ["input": 1, "output": 5]]),
        obj(["id": "claude-sonnet-4-5", "name": "Claude Sonnet 4.5", "vendor": "Anthropic", "context_length": 200_000, "typical_reply_usd": 0.012, "usd_per_mtok": ["input": 3, "output": 15]]),
        obj(["id": "claude-opus-4-5", "name": "Claude Opus 4.5", "vendor": "Anthropic", "context_length": 200_000, "typical_reply_usd": 0.02, "usd_per_mtok": ["input": 5, "output": 25]]),
    ]
    static let defaultModel = "claude-haiku-4-5"

    static func seed(_ ws: DemoWorkspace) -> DemoAgentSettings {
        var s = DemoAgentSettings()
        s.behaviour = [
            "widget_answers": .bool(true), "widget_model": .string(""), "widget_max_replies": .number(20),
            "widget_blocked_topics": jv(["Legal advice", "Medical questions"]), "widget_monthly_cap_usd": .number(50),
            "widget_collect_email": .bool(true),
        ]
        let lumen = ws.workspace.slug == "lumen"
        s.bots = [bot(1, "Ollie", role: "Support assistant", look: BotLook.ollie.json, isDefault: true, position: 0,
                      personality: ["tone": "friendly", "instructions": lumen ? "" : "Margin is a note-taking app for teams. Keep answers short and link the help center article you used.", "greeting": "Hi! I'm Ollie. Ask me anything about Margin.", "sign_off": ""],
                      usage: ["widgets": [["name": "Website"]], "mailboxes": lumen ? [] : [["email": "support@margin.app"]], "api_keys": []])]
        s.peer = obj(["available": !lumen, "enabled": false, "share_with": "everyone", "user_ids": [Any](), "team_ids": [Any](),
                  "all_accounts": true, "default_mode": "summary", "rules": "",
                  "accounts": lumen ? [Any]() : jv([
                      ["id": agentID(301), "email": "maya@margin.app", "name": "Maya Chen", "provider": "gmail", "mode": "summary", "chosen": false],
                      ["id": agentID(302), "email": "maya.chen@fastmail.com", "name": "Personal", "provider": "imap", "mode": "summary", "chosen": false],
                  ])])
        guard !lumen else { return s }

        var nova = BotLook()
        nova.shape = "rounded"
        nova.color = "#9ee6d0"
        nova.to = "#0c9488"
        nova.eyes = "happy"
        nova.mouth = "smile"
        nova.accessory = "headphones"
        nova.accent = "#f59e0b"
        nova.background = "soft"
        s.bots.append(bot(2, "Nova", role: "Billing helper", look: nova.json, isDefault: false, position: 1,
                          personality: ["tone": "professional", "reply_length": "short", "emoji": "none", "instructions": "Only billing and plans. Hand anything about refunds over 200 dollars to the billing team.", "greeting": "Hello, I'm Nova. I can help with plans, invoices and payments.", "handoff_message": "I've passed this to our billing team. They usually reply within a few hours."],
                          usage: ["widgets": [], "mailboxes": [["email": "billing@margin.app"]], "api_keys": []]))

        s.knowledge = [
            source(11, "website", "Margin docs", status: "ready", docs: 64, chars: 412_300, synced: 260,
                   extra: ["website": ["url": "https://margin.app/docs", "max_pages": 100, "include": ["/docs"], "exclude": ["/docs/changelog"], "recrawl": "weekly"]]),
            source(12, "website", "Pricing page", status: "ready", docs: 3, chars: 9_840, synced: 1500,
                   extra: ["website": ["url": "https://margin.app/pricing", "max_pages": 5, "include": [], "exclude": [], "recrawl": "weekly"]]),
            source(13, "file", "", status: "ready", docs: 1, chars: 38_200, synced: 4300,
                   extra: ["file": ["filename": "Security overview 2026.pdf", "content_type": "application/pdf", "size_bytes": 1_284_000]]),
            source(14, "snippet", "Education discount", status: "ready", docs: 1, chars: 214, synced: 9000,
                   extra: ["snippet": ["question": "Do you offer student discounts?", "answer": "Students and teachers get **40% off** Margin Pro with a school email address. Apply from Settings, Billing."]]),
        ]
        let pages = ["Getting started", "Notebooks and pages", "Sharing a notebook", "Exporting your notes", "Offline mode", "Sync troubleshooting", "Single sign-on (SAML)", "Two-factor authentication", "Plans and pricing", "Refunds and cancellations", "Importing from Notion", "Keyboard shortcuts"]
        s.docs[agentID(11)] = pages.enumerated().map { index, title in
            ["id": .string(agentID(1100 + index)), "title": .string(title), "url": .string("https://margin.app/docs/" + title.lowercased().replacingOccurrences(of: " ", with: "-").filter { $0.isLetter || $0 == "-" }), "chars": .number(Double(3_200 + index * 517 % 4_000))]
        }
        s.docs[agentID(12)] = [
            ["id": .string(agentID(1201)), "title": .string("Pricing"), "url": .string("https://margin.app/pricing"), "chars": .number(4_210)],
            ["id": .string(agentID(1202)), "title": .string("Pricing for teams"), "url": .string("https://margin.app/pricing/teams"), "chars": .number(3_380)],
            ["id": .string(agentID(1203)), "title": .string("Pricing FAQ"), "url": .string("https://margin.app/pricing/faq"), "chars": .number(2_250)],
        ]
        s.docs[agentID(13)] = [["id": .string(agentID(1301)), "title": .string("Security overview 2026.pdf"), "url": .null, "chars": .number(38_200)]]
        s.docs[agentID(14)] = [["id": .string(agentID(1401)), "title": .string("Do you offer student discounts?"), "url": .null, "chars": .number(214)]]

        s.procedures = [
            procedure(21, "Refund requests", when: "A customer asks for a refund or says they were charged twice.",
                      steps: "1. Look up the customer's invoices with list_invoices.\n2. If the charge is a duplicate, say a refund takes 5 to 10 business days and hand off to billing.\n3. If it is over 200 dollars, never promise a refund. Hand off to billing with the invoice number.",
                      channels: ["chat", "email"], minutes: 2880),
            procedure(22, "Sync troubleshooting", when: "Notes don't sync, or a device shows an old version.",
                      steps: "1. Ask which devices and app versions they use.\n2. Have them sign out and in on the device that is behind.\n3. If that doesn't help, ask for the sync log from Settings, Help, and hand off to support.",
                      channels: ["chat"], minutes: 9000),
            procedure(23, "Cancel a subscription", when: "A customer wants to cancel or downgrade.",
                      steps: "1. Ask what made them want to leave, once.\n2. Offer to pause for up to three months.\n3. If they still want to cancel, hand off to billing. Never cancel yourself.",
                      channels: ["chat", "email"], minutes: 20000, enabled: false),
        ]

        s.servers = [[
            "id": .string(agentID(31)), "name": .string("Margin admin"), "slug": .string("margin"), "url": .string("https://admin.margin.app/mcp"), "enabled": .bool(true),
            "auth": jv(["kind": "bearer", "header_name": "", "has_secret": true, "oauth": ["connected": false, "scopes": []]]),
            "status": .string("connected"), "error": .null, "server_info": jv(["name": "margin-admin", "version": "2.4.1"]),
            "tools": jv([
                tool("get_account", "Look up a customer's workspace, plan and seats by email.", readOnly: true, enabled: true, policy: "auto", verifiedOnly: true, schema: ["email": "The customer's email"]),
                tool("list_invoices", "The customer's last invoices with amounts and status.", readOnly: true, enabled: true, policy: "auto", verifiedOnly: true, schema: ["email": "The customer's email"]),
                tool("resend_invoice", "Email an invoice to the customer again.", readOnly: false, enabled: true, policy: "confirm", verifiedOnly: true, schema: ["invoice_id": "The invoice number"]),
                tool("reset_sync", "Clear a device's sync state so it downloads everything again.", readOnly: false, enabled: false, policy: "confirm", verifiedOnly: true, schema: ["device_id": "The device to reset"]),
                tool("cancel_subscription", "Cancel the customer's subscription at the end of the period.", readOnly: false, destructive: true, enabled: false, policy: "confirm", verifiedOnly: true, schema: ["email": "The customer's email"]),
            ]),
            "last_synced_at": ago(180),
        ]]

        let tests: [(Int, String, [Object], [Object], Object?)] = [
            (41, "Refund timing", [line("How long does a refund take?")], [expect("mentions", "5 to 10 business days"), expect("cites_knowledge"), expect("no_handoff")], nil),
            (42, "Student discount", [line("Do you offer student discounts?")], [expect("mentions", "50% off Margin Pro")], nil),
            (43, "Asks for a person", [line("Can I talk to a real person?")], [expect("handoff")], nil),
            (44, "Export to PDF", [line("Can I export a notebook as a PDF?")], [expect("mentions", "File, Export"), expect("cites_knowledge")], nil),
            (45, "Pricing for teams", [line("How much is Pro?"), line("Margin Pro is $8 per member per month, billed yearly.", agent: true), line("And for a team of 30?")], [expect("mentions", "volume pricing"), expect("not_mentions", "lifetime plan")], nil),
            (46, "Invoice lookup", [line("Where can I find my latest invoice?")], [expect("uses_tool", "margin__list_invoices"), expect("no_handoff")], ["verified": .bool(true), "email": .string("ines@northwind.example"), "user_id": .string("u_4821")]),
            (47, "Sync stuck", [line("My notes won't sync on my phone")], [expect("uses_procedure", agentID(22))], nil),
            (48, "", [line("Please cancel my subscription")], [expect("handoff")], nil),
        ]
        s.tests = tests.map { n, name, messages, expectations, visitor in
            ["id": .string(agentID(n)), "name": .string(name.isEmpty ? (messages.first?["text"]?.string ?? "") : name), "messages": jv(messages), "expectations": jv(expectations),
             "visitor": visitor.map { .object($0) } ?? .object([:]), "last_result": .null, "created_at": ago(Double(9000 - n * 10))]
        }
        // Two finished runs: everything passed three days ago; yesterday the discount test broke.
        let older = agentID(51), latest = agentID(52)
        s.runs = [
            ["id": .string(latest), "status": .string("done"), "draft": .bool(false), "test_ids": jv(s.tests.prefix(7).compactMap { $0["id"]?.string }), "total": .number(7), "passed": .number(6), "failed": .number(1), "errored": .number(0), "usd": .number(0.091), "error": .null, "created_at": ago(1442), "finished_at": ago(1440)],
            ["id": .string(older), "status": .string("done"), "draft": .bool(true), "test_ids": jv(s.tests.prefix(7).compactMap { $0["id"]?.string }), "total": .number(7), "passed": .number(7), "failed": .number(0), "errored": .number(0), "usd": .number(0.087), "error": .null, "created_at": ago(4322), "finished_at": ago(4320)],
        ]
        for index in s.tests.indices.prefix(7) {
            var result = s.grade(s.tests[index], run: latest, draft: false, blocked: [])
            result["previous_status"] = .string("passed")
            result["finished_at"] = ago(1440)
            if s.tests[index]["id"]?.string == agentID(42) {
                result["checks"] = jv([["kind": "mentions", "value": "50% off Margin Pro", "passed": false, "reason": "The answer offers 40% off, not 50%."]])
            }
            s.tests[index]["last_result"] = .object(result)
        }

        func ticketID(_ number: Int) -> String? { ws.tickets.first { $0.number == number }?.id }
        if let pricing = ticketID(1086) {
            s.review.append(["id": .string(agentID(61)), "ticket_id": .string(pricing), "ticket_number": .number(1086), "reason": .string("handoff"),
                             "question": .string("Is there a discount if we pay for 40 seats up front for two years?"),
                             "answer": .string("I'm not sure about multi-year pricing, so I've passed this to our team."), "contact_name": .string("Yusuf Moreau"), "created_at": ago(42)])
        }
        if let chat = ticketID(1061) {
            s.review.append(["id": .string(agentID(62)), "ticket_id": .string(chat), "ticket_number": .number(1061), "reason": .string("rated_down"),
                             "question": .string("How do I move a page to another notebook?"),
                             "answer": .string("You can copy the page's text and paste it into a new page in the other notebook."), "contact_name": .string("Hana Sato"), "created_at": ago(1260)])
        }

        let people = ws.members.filter { $0.id != DemoPerson.maya.id }
        let questions: [(String, String, String, Int, Double)] = [
            ("When did Northwind last confirm the renewal date?", "Northwind confirmed renewal for March 1 in an email on October 28.", "answered", 1, 95),
            ("Did Acme send the signed DPA back yet?", "Not that Maya's mail shows. The last message from Acme asks for one more change to section 4.", "answered", 2, 1500),
            ("What's the contract value for Globex?", "Maya's rules don't allow sharing prices or contracts.", "declined", 0, 4200),
        ]
        s.asks = questions.enumerated().map { index, q in
            let person = people.isEmpty ? nil : people[index % people.count]
            return ["id": .string(agentID(71 + index)), "question": .string(q.0), "answer": .string(q.1), "result": .string(q.2), "sources": .number(Double(q.3)), "created_at": ago(q.4),
                    "asker": person.map { jv(["id": $0.id, "name": $0.user.name, "email": $0.user.email ?? ""]) } ?? .null]
        }
        return s
    }

    // MARK: Building rows

    static func agentID(_ n: Int) -> String { String(format: "0197a0c0-%04x-7000-8000-%012d", 0xa1, n) }

    static func ago(_ minutes: Double) -> JSONValue { .string(DemoSeed.stamp(DemoMode.anchor.addingTimeInterval(-minutes * 60))) }

    static func bot(_ n: Int, _ name: String, role: String, look: JSONValue, isDefault: Bool, position: Int, personality: [String: Any], usage: [String: Any]) -> Object {
        var p: Object = ["tone": .string("friendly"), "custom_tone": .string(""), "instructions": .string(""), "reply_length": .string("medium"), "emoji": .string("some"), "greeting": .string(""), "handoff_message": .string(""), "blocked_topics": .array([]), "sign_off": .string("")]
        for (key, value) in personality { p[key] = jv(value) }
        return ["id": .string(agentID(n)), "name": .string(name), "role": .string(role), "language": .string(""), "look": look, "image_url": .null,
                "personality": .object(p), "is_default": .bool(isDefault), "position": .number(Double(position)), "usage": jv(usage)]
    }

    static func source(_ n: Int, _ kind: String, _ name: String, status: String, docs: Int, chars: Int, synced: Double, extra: [String: Any]) -> Object {
        var row: Object = ["id": .string(agentID(n)), "kind": .string(kind), "name": .string(name), "status": .string(status), "error": .null, "enabled": .bool(true),
                           "doc_count": .number(Double(docs)), "char_count": .number(Double(chars)), "last_synced_at": ago(synced), "created_at": ago(synced + 20000)]
        for (key, value) in extra { row[key] = jv(value) }
        return row
    }

    static func procedure(_ n: Int, _ name: String, when: String, steps: String, channels: [String], minutes: Double, enabled: Bool = true) -> Object {
        ["id": .string(agentID(n)), "name": .string(name), "when": .string(when), "instructions": .string(steps), "enabled": .bool(enabled),
         "channels": jv(channels), "bot_ids": .array([]), "updated_at": ago(minutes), "updated_by": jv(["name": DemoPerson.jonas.name])]
    }

    static func tool(_ name: String, _ description: String, readOnly: Bool, destructive: Bool = false, enabled: Bool, policy: String, verifiedOnly: Bool, schema: [String: String]) -> [String: Any] {
        let properties = schema.mapValues { ["type": "string", "description": $0] as [String: Any] }
        return ["name": name, "title": NSNull(), "description": description, "read_only": readOnly, "destructive": destructive, "enabled": enabled, "policy": policy, "verified_only": verifiedOnly,
                "input_schema": ["type": "object", "properties": properties, "required": Array(schema.keys)] as [String: Any]]
    }

    static func line(_ text: String, agent: Bool = false) -> Object { ["role": .string(agent ? "agent" : "visitor"), "text": .string(text)] }

    static func expect(_ kind: String, _ value: String = "") -> Object { ["kind": .string(kind), "value": .string(value)] }

    // MARK: The agent's answers

    struct Reply {
        var text: String
        var handoff = false
        var sources: [JSONValue] = []
        var procedures: [JSONValue] = []
        var tools: [(name: String, summary: String)] = []
    }

    private func article(_ title: String) -> JSONValue {
        let doc = docs[Self.agentID(11)]?.first { $0["title"]?.string == title }
        return jv(["kind": "knowledge", "id": doc?["id"]?.string ?? Self.agentID(11), "title": title, "url": doc?["url"]?.string ?? "https://margin.app/docs"])
    }

    private func procedureRef(_ n: Int) -> JSONValue? {
        guard let p = procedures.first(where: { $0["id"]?.string == Self.agentID(n) }), p["enabled"]?.bool != false else { return nil }
        return jv(["id": p["id"]?.string ?? "", "name": p["name"]?.string ?? ""])
    }

    private func toolOn(_ name: String) -> Bool {
        servers.contains { server in
            server["enabled"]?.bool != false && (server["tools"]?.array ?? []).contains { $0["name"]?.string == name && $0["enabled"]?.bool == true }
        }
    }

    /// What the agent answers to the last visitor message, scripted from Margin's docs.
    func reply(to messages: [Object], blocked: [String], verified: Bool) -> Reply {
        let text = (messages.last { $0["role"]?.string != "agent" }?["text"]?.string ?? "").lowercased()
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        let words = Set(text.split { !$0.isLetter }.map(String.init).filter { $0.count > 3 })
        if let topic = blocked.first(where: { topic in topic.lowercased().split { !$0.isLetter }.map(String.init).contains { $0.count > 3 && words.contains($0) } }) {
            return Reply(text: "That's not something I can help with here (\(topic.lowercased())). I've asked a person from our team to take a look.", handoff: true)
        }
        if has("person", "human", "real ", "someone", "agent") {
            return Reply(text: "Of course. I've passed this to our support team, and someone will reply right here. If you step away, we'll email you too.", handoff: true)
        }
        if has("cancel", "downgrade") {
            var r = Reply(text: "I'm sorry to hear you want to go. I can't cancel a subscription myself, so I've passed this to our billing team. They'll confirm by email, usually within a few hours.", handoff: true)
            if let p = procedureRef(23) { r.procedures = [p] }
            return r
        }
        if has("refund", "money back", "charged twice", "duplicate") {
            var r = Reply(text: "Refunds go back to the original payment method and take **5 to 10 business days** to show up on your statement. If you were charged twice, let me know the invoice number and I'll pass it to billing.", sources: [article("Refunds and cancellations")])
            if let p = procedureRef(21) { r.procedures = [p] }
            return r
        }
        if has("invoice", "receipt", "billing history") {
            if verified, toolOn("list_invoices") {
                return Reply(text: "Your latest invoice is **INV-2026-10-0412** for $96.00, paid on October 1. You'll find every invoice in Settings, Billing, Invoices, and I can email this one again if you like.", tools: [("list_invoices", "3 invoices")])
            }
            return Reply(text: "Every invoice is in **Settings, Billing, Invoices**, where you can download it as a PDF. Sign in on our site if you'd like me to look one up for you.", sources: [article("Plans and pricing")])
        }
        if has("export", "pdf", "markdown", "download") {
            return Reply(text: "Yes. Open the notebook, then choose **File, Export** and pick PDF, Markdown or HTML. Exports keep your headings, images and links, and a whole notebook comes as one file.", sources: [article("Exporting your notes")])
        }
        if has("student", "teacher", "education", "school", "discount") {
            return Reply(text: "Yes! Students and teachers get **40% off** Margin Pro with a school email address. You can apply from Settings, Billing.", sources: [jv(["kind": "snippet", "id": Self.agentID(14), "title": "Education discount", "url": NSNull()])])
        }
        if has("team of", "seats", "volume", "for a team") {
            return Reply(text: "For teams of 20 or more we offer **volume pricing**, which starts at $6 per member per month on a yearly plan. I can connect you with our sales team for a quote.", sources: [jv(["kind": "website", "id": Self.agentID(12), "title": "Pricing for teams", "url": "https://margin.app/pricing/teams"])])
        }
        if has("price", "pricing", "cost", "how much", "plan") {
            return Reply(text: "Margin Pro is **$8 per member per month**, billed yearly, or $10 billed monthly. The Free plan includes 3 notebooks and syncs across two devices.", sources: [jv(["kind": "website", "id": Self.agentID(12), "title": "Pricing", "url": "https://margin.app/pricing"])])
        }
        if has("sync", "offline", "won't update", "old version") {
            var r = Reply(text: "Sorry about that. Let's get your phone caught up:\n\n1. Check that both devices run the latest version of Margin.\n2. On your phone, sign out and back in from Settings, Account.\n3. Keep the app open for a minute on Wi-Fi.\n\nIf it's still behind, tell me and I'll ask for your sync log.", sources: [article("Sync troubleshooting")])
            if let p = procedureRef(22) { r.procedures = [p] }
            return r
        }
        if has("sso", "saml", "okta", "single sign") {
            var r = Reply(text: "Single sign-on with SAML is part of the Business plan. An owner turns it on in **Settings, Security, Single sign-on**, and Okta, Microsoft Entra and Google Workspace all work.", sources: [article("Single sign-on (SAML)")])
            if verified, toolOn("get_account") {
                r.tools = [("get_account", "Business plan, 42 seats")]
                r.text += " Your workspace is already on Business, so you can set it up now."
            }
            return r
        }
        if has("notion", "import") {
            return Reply(text: "You can bring your Notion pages over from **File, Import, Notion**. Margin keeps page nesting, tables and images. Large workspaces take a few minutes.", sources: [article("Importing from Notion")])
        }
        if has("hello", "hi ", "hey") || text == "hi" {
            return Reply(text: "Hi there! I can help with Margin's features, plans and billing. What would you like to know?")
        }
        return Reply(text: "I couldn't find that in our help center, so I've passed your question to the team. Someone will reply here soon.", handoff: true)
    }

    /// A test's result as the grader writes it: each expectation checked against the scripted reply.
    func grade(_ test: Object, run: String, draft: Bool, blocked: [String]) -> Object {
        let messages = (test["messages"]?.array ?? []).compactMap(\.object)
        let verified = test["visitor"]?["verified"]?.bool ?? false
        let r = reply(to: messages, blocked: blocked, verified: verified)
        let answer = r.text.lowercased()
        let toolKeys = r.tools.map { "margin__" + $0.name }
        var checks: [JSONValue] = []
        for e in (test["expectations"]?.array ?? []).compactMap(\.object) {
            let kind = e["kind"]?.string ?? "mentions"
            let value = e["value"]?.string ?? ""
            let passed: Bool
            var reason: String
            switch kind {
            case "mentions":
                passed = Self.mentions(answer, value)
                reason = passed ? "The answer says this." : "The answer doesn't say this."
            case "not_mentions":
                passed = !Self.mentions(answer, value)
                reason = passed ? "The answer leaves this out." : "The answer mentions this."
            case "handoff":
                passed = r.handoff
                reason = passed ? "Handed off to the team." : "Answered without handing off."
            case "no_handoff":
                passed = !r.handoff
                reason = passed ? "Answered without handing off." : "Handed off to the team."
            case "uses_tool":
                passed = toolKeys.contains(value)
                reason = passed ? "Called the tool." : r.tools.isEmpty ? "Called no tools." : "Called other tools."
            case "uses_procedure":
                passed = r.procedures.contains { $0["id"]?.string == value }
                reason = passed ? "Read the procedure." : "Didn't follow this procedure."
            default:
                passed = !r.sources.isEmpty
                reason = passed ? "Cited \(r.sources.count == 1 ? "1 source" : "\(r.sources.count) sources")." : "Cited no sources."
            }
            checks.append(jv(["kind": kind, "value": value, "passed": passed, "reason": reason]))
        }
        let ok = checks.allSatisfy { $0["passed"]?.bool == true }
        return ["run_id": .string(run), "test_id": test["id"] ?? .null, "status": .string(ok ? "passed" : "failed"),
                "answer_html": .string(KBMarkdown.html(from: r.text)), "handoff": .bool(r.handoff), "tools": jv(toolKeys),
                "sources": .array(r.sources), "procedures": .array(r.procedures), "action": .null, "checks": .array(checks),
                "error": .null, "usd": .number(0.013), "draft": .bool(draft), "previous_status": test["last_result"]?["status"] ?? .null]
    }

    /// A lenient "says this": every number exactly, and most of the longer words.
    static func mentions(_ answer: String, _ value: String) -> Bool {
        let tokens = value.lowercased().split { $0.isWhitespace || $0 == "," || $0 == "." }.map(String.init)
        let numbers = tokens.filter { $0.contains(where: \.isNumber) }
        guard numbers.allSatisfy({ answer.contains($0) }) else { return false }
        let words = tokens.filter { !$0.contains(where: \.isNumber) && $0.count > 3 }
        guard !words.isEmpty else { return !numbers.isEmpty || answer.contains(value.lowercased()) }
        return Double(words.filter { answer.contains($0) }.count) / Double(words.count) >= 0.6
    }
}

/// A JSON object from Swift literals.
private func obj(_ d: [String: Any]) -> [String: JSONValue] { d.mapValues { jv($0) } }

/// A JSON value from Swift literals: strings, numbers, booleans, arrays, dictionaries and nil.
private func jv(_ value: Any?) -> JSONValue {
    switch value {
    case nil, is NSNull: .null
    case let v as JSONValue: v
    case let v as Bool: .bool(v)
    case let v as Int: .number(Double(v))
    case let v as Double: .number(v)
    case let v as String: .string(v)
    case let v as [String: JSONValue]: .object(v)
    case let v as [String: Any]: .object(v.mapValues { jv($0) })
    case let v as [Any]: .array(v.map { jv($0) })
    default: .null
    }
}

extension DemoBackend {
    func agentSettingsRoutes(_ call: Call, in ws: inout DemoWorkspace) throws -> Data?? {
        guard let first = call.path.first, first == "ai" || first == "bots" || (first == "me" && call.path.dropFirst().first == "assistant-peer") else { return nil }
        if first == "me" { return try peerRoutes(call, in: &ws) }
        if call.method != "GET", !ws.role.isAdmin {
            throw Failure(status: 403, code: "forbidden", detail: "Only owners and admins can change the AI agent.")
        }
        if first == "bots" { return try botRoutes(call, in: &ws) }
        switch call.path.dropFirst().first {
        case "config", "settings", "models": return try agentConfigRoutes(call, in: &ws)
        case "knowledge": return try knowledgeRoutes(call, in: &ws)
        case "procedures": return try procedureRoutes(call, in: &ws)
        case "mcp-servers": return try mcpRoutes(call, in: &ws)
        case "agent": return try agentQualityRoutes(call, in: &ws)
        default: return nil
        }
    }

    // MARK: Config, models, report and setup

    private func agentConfig(_ ws: DemoWorkspace) -> JSONValue {
        let a = ws.settings.agent
        var features = a.behaviour
        features["enabled"] = .bool(a.aiOn)
        features["assistant"] = .bool(true)
        features["auto_triage"] = .bool(true)
        features["model"] = .string(DemoAgentSettings.defaultModel)
        return .object([
            "enabled": .bool(a.aiOn), "assistant_name": .string("Ollie"), "features": .object(features),
            "models": .object(["default": .string(DemoAgentSettings.defaultModel)]), "costs": .object(["playground": .number(0.004)]),
        ])
    }

    private func agentConfigRoutes(_ call: Call, in ws: inout DemoWorkspace) throws -> Data?? {
        if call.match("GET", "ai/config") != nil { return .some(encode(agentConfig(ws))) }
        if call.match("GET", "ai/models") != nil {
            return .some(encode(JSONValue.object(["data": jv(DemoAgentSettings.models), "default": .string(DemoAgentSettings.defaultModel)])))
        }
        if call.match("PATCH", "ai/settings") != nil {
            let patch = call.body.object ?? [:]
            guard patch.keys.contains(where: { $0.hasPrefix("widget_") }) else { return nil }
            for (key, value) in patch where key.hasPrefix("widget_") {
                if key == "widget_max_replies", let n = value.int, !(1 ... 100).contains(n) {
                    throw Failure(status: 422, code: "validation_failed", detail: "Replies per conversation must be 1 to 100.")
                }
                ws.settings.agent.behaviour[key] = value
            }
            publish("workspace.updated", ["changes": .array([.string("ai")])], in: &ws)
            return .some(encode(agentConfig(ws)))
        }
        return nil
    }

    private func agentReport(_ call: Call, in ws: DemoWorkspace) -> JSONValue {
        let parse = Date.ISO8601FormatStyle().year().month().day()
        let to = call.query["to"].flatMap { try? parse.parse($0) } ?? DemoMode.anchor
        let from = call.query["from"].flatMap { try? parse.parse($0) } ?? to.addingTimeInterval(-29 * 86400)
        let days = max(1, min(366, Int((to.timeIntervalSince(from) / 86400).rounded()) + 1))
        var byDay: [JSONValue] = []
        var totals = (0, 0, 0, 0)
        for offset in 0 ..< days {
            let date = from.addingTimeInterval(Double(offset) * 86400)
            let n = Int(date.timeIntervalSince1970 / 86400)
            let weekend = [3, 4].contains(n % 7)
            let conversations = (weekend ? 5 : 14) + (n * 7 % 9)
            let replies = conversations * 2 + n % 5
            let resolved = conversations * 62 / 100
            let handoffs = conversations * 24 / 100
            totals = (totals.0 + conversations, totals.1 + replies, totals.2 + resolved, totals.3 + handoffs)
            byDay.append(jv(["date": date.formatted(parse), "conversations": conversations, "replies": replies, "resolved": resolved, "handoffs": handoffs]))
        }
        let scale = Double(totals.0) / 400
        return jv([
            "conversations": totals.0, "replies": totals.1, "resolved": totals.2, "handoffs": totals.3,
            "ratings": ["up": Int(38 * scale), "down": Int(6 * scale)], "usd": Double(totals.1) * 0.0042,
            "by_day": byDay,
            "tools": [["tool": "margin__get_account", "calls": Int(54 * scale), "errors": 0], ["tool": "margin__list_invoices", "calls": Int(31 * scale), "errors": Int(2 * scale)], ["tool": "margin__resend_invoice", "calls": Int(6 * scale), "errors": 0]],
            "gaps": [["question": "Can I password-protect a single notebook?", "count": 7], ["question": "Is there a Linux app?", "count": 5], ["question": "How do I merge two workspaces?", "count": 3]],
        ] as [String: Any])
    }

    private func agentSetup(_ ws: DemoWorkspace) -> JSONValue {
        let a = ws.settings.agent
        let defaultBot = a.bots.first { $0["is_default"]?.bool == true }
        let identity = a.bots.count > 1 || defaultBot?["name"]?.string != "Ollie" || !(defaultBot?["personality"]?["instructions"]?.string ?? "").isEmpty
        let knowledge = !ws.kb.articles.isEmpty || a.knowledge.contains { $0["enabled"]?.bool != false && $0["status"]?.string == "ready" }
        let tools = a.servers.contains { $0["enabled"]?.bool != false && $0["status"]?.string == "connected" }
        let answers = a.behaviour["widget_answers"]?.bool ?? false
        func step(_ id: String, _ title: String, _ done: Bool, optional: Bool = false, href: String) -> [String: Any] {
            ["id": id, "title": title, "description": "", "done": done, "optional": optional, "href": href]
        }
        let steps = [
            step("ai_on", "Turn on AI", a.aiOn, href: "/settings/ai"),
            step("identity", "Name your agent", identity, href: "/settings/ai/bots"),
            step("knowledge", "Give it something to know", knowledge, href: "/settings/ai/knowledge"),
            step("tools", "Connect tools", tools, optional: true, href: "/settings/ai/tools"),
            step("playground", "Test it in the playground", a.playgroundUsed || ws.workspace.slug != "lumen", href: "/settings/ai/playground"),
            step("widget", "Install the chat widget", true, href: "/settings/widget"),
            step("answers_on", "Let Ollie answer chats", answers, href: "/settings/ai/behaviour"),
        ]
        let required = steps.filter { $0["optional"] as? Bool != true }
        let done = required.filter { $0["done"] as? Bool == true }.count
        return jv(["steps": steps, "done_count": done, "total": required.count, "complete": done == required.count] as [String: Any])
    }

    // MARK: Bots

    private func botIndex(_ id: String, in ws: DemoWorkspace) throws -> Int {
        guard let index = ws.settings.agent.bots.firstIndex(where: { $0["id"]?.string == id }) else { throw notFound("bot") }
        return index
    }

    private func botsSorted(_ ws: DemoWorkspace) -> [DemoAgentSettings.Object] {
        ws.settings.agent.bots.sorted { ($0["position"]?.int ?? 0) < ($1["position"]?.int ?? 0) }
    }

    private func botChanged(_ bot: DemoAgentSettings.Object, _ type: String = "bot.updated", in ws: inout DemoWorkspace) {
        publish(type, ["bot": .object(bot)], in: &ws)
    }

    private func botRoutes(_ call: Call, in ws: inout DemoWorkspace) throws -> Data?? {
        if call.match("GET", "bots") != nil { return .some(encode(JSONValue.object(["data": jv(botsSorted(ws)), "next_cursor": .null]))) }
        if let id = call.match("GET", "bots/*")?.first { return .some(encode(JSONValue.object(ws.settings.agent.bots[try botIndex(id, in: ws)]))) }
        if call.match("POST", "bots") != nil {
            let name = displayName(call.string("name"), fallback: "New bot")
            var bot = DemoAgentSettings.bot(0, name, role: "", look: call.body["look"] ?? BotLook.ollie.json, isDefault: false, position: ws.settings.agent.bots.count, personality: [:], usage: ["widgets": [], "mailboxes": [], "api_keys": []])
            bot["id"] = .string(made())
            ws.settings.agent.bots.append(bot)
            botChanged(bot, "bot.created", in: &ws)
            return .some(encode(JSONValue.object(bot)))
        }
        if call.match("POST", "bots/reorder") != nil {
            let ids = call.body["ids"]?.array?.compactMap(\.string) ?? []
            for index in ws.settings.agent.bots.indices {
                let id = ws.settings.agent.bots[index]["id"]?.string ?? ""
                ws.settings.agent.bots[index]["position"] = .number(Double(ids.firstIndex(of: id) ?? ids.count + index))
            }
            publish("bot.updated", [:], in: &ws)
            return .some(encode(JSONValue.object(["data": jv(botsSorted(ws))])))
        }
        if let id = call.match("POST", "bots/*/default")?.first {
            let target = try botIndex(id, in: ws)
            for index in ws.settings.agent.bots.indices { ws.settings.agent.bots[index]["is_default"] = .bool(index == target) }
            botChanged(ws.settings.agent.bots[target], in: &ws)
            return .some(encode(JSONValue.object(ws.settings.agent.bots[target])))
        }
        if let id = call.match("POST", "bots/*/duplicate")?.first {
            var copy = ws.settings.agent.bots[try botIndex(id, in: ws)]
            let base = copy["name"]?.string ?? "Bot"
            let taken = Set(ws.settings.agent.bots.compactMap { $0["name"]?.string })
            copy["name"] = .string((2 ... 50).lazy.map { "\(base) \($0)" }.first { !taken.contains($0) } ?? "\(base) copy")
            copy["id"] = .string(made())
            copy["is_default"] = .bool(false)
            copy["position"] = .number(Double(ws.settings.agent.bots.count))
            copy["usage"] = jv(["widgets": [], "mailboxes": [], "api_keys": []] as [String: Any])
            ws.settings.agent.bots.append(copy)
            botChanged(copy, "bot.created", in: &ws)
            return .some(encode(JSONValue.object(copy)))
        }
        if let id = call.match("PATCH", "bots/*")?.first {
            let index = try botIndex(id, in: ws)
            var bot = ws.settings.agent.bots[index]
            for (key, value) in call.body.object ?? [:] {
                switch key {
                case "name": bot["name"] = .string(displayName(value.string, fallback: bot["name"]?.string ?? "Bot"))
                case "role", "language", "look": bot[key] = value
                case "personality":
                    var p = bot["personality"]?.object ?? [:]
                    for (field, v) in value.object ?? [:] { p[field] = v }
                    bot["personality"] = .object(p)
                default: break
                }
            }
            ws.settings.agent.bots[index] = bot
            botChanged(bot, in: &ws)
            return .some(encode(JSONValue.object(bot)))
        }
        if let id = call.match("DELETE", "bots/*")?.first {
            let index = try botIndex(id, in: ws)
            let bot = ws.settings.agent.bots[index]
            if bot["is_default"]?.bool == true {
                throw Failure(status: 409, code: "bot_is_default", detail: "Make another bot the default before you delete this one.")
            }
            if let usage = bot["usage"]?.object, usage.values.contains(where: { !($0.array ?? []).isEmpty }) {
                throw Failure(status: 409, code: "bot_in_use", detail: "A widget, mailbox or API key still answers as this bot.")
            }
            ws.settings.agent.bots.remove(at: index)
            publish("bot.deleted", ["bot_id": .string(id)], in: &ws)
            return .some(nil)
        }
        if let id = call.match("PUT", "bots/*/image")?.first {
            let index = try botIndex(id, in: ws)
            guard let image = Self.filePart(call.raw), !image.data.isEmpty else {
                throw Failure(status: 422, code: "validation_failed", detail: "Choose a PNG, JPEG or WebP picture.")
            }
            ws.settings.agent.bots[index]["image_url"] = .string("data:\(image.type);base64," + image.data.base64EncodedString())
            var look = ws.settings.agent.bots[index]["look"]?.object ?? [:]
            look["kind"] = .string("image")
            ws.settings.agent.bots[index]["look"] = .object(look)
            botChanged(ws.settings.agent.bots[index], in: &ws)
            return .some(encode(JSONValue.object(ws.settings.agent.bots[index])))
        }
        if let id = call.match("DELETE", "bots/*/image")?.first {
            let index = try botIndex(id, in: ws)
            ws.settings.agent.bots[index]["image_url"] = .null
            var look = ws.settings.agent.bots[index]["look"]?.object ?? [:]
            if look["kind"]?.string == "image" { look["kind"] = .string("built") }
            ws.settings.agent.bots[index]["look"] = .object(look)
            botChanged(ws.settings.agent.bots[index], in: &ws)
            return .some(encode(JSONValue.object(ws.settings.agent.bots[index])))
        }
        return nil
    }

    private func displayName(_ raw: String?, fallback: String) -> String {
        let name = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? fallback : String(name.prefix(60))
    }

    /// The first file of a multipart body: its bytes, type and name.
    static func filePart(_ raw: Data) -> (data: Data, type: String, name: String)? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = raw.range(of: separator) else { return nil }
        let header = String(decoding: raw[raw.startIndex ..< headerEnd.lowerBound], as: UTF8.self)
        var body = raw[headerEnd.upperBound...]
        if let close = body.range(of: Data("\r\n--".utf8), options: .backwards) { body = body[body.startIndex ..< close.lowerBound] }
        let type = header.split(separator: "\r\n").first { $0.lowercased().hasPrefix("content-type:") }
            .map { $0.dropFirst("content-type:".count).trimmingCharacters(in: .whitespaces) } ?? "application/octet-stream"
        let name = header.range(of: #"filename="([^"]*)""#, options: .regularExpression)
            .map { String(header[$0].dropFirst("filename=\"".count).dropLast()) } ?? "file"
        return (Data(body), type, name)
    }

    // MARK: Knowledge

    private func sourceIndex(_ id: String, in ws: DemoWorkspace) throws -> Int {
        guard let index = ws.settings.agent.knowledge.firstIndex(where: { $0["id"]?.string == id }) else { throw notFound("source") }
        return index
    }

    private func sourceChanged(_ source: DemoAgentSettings.Object, _ type: String = "ai_knowledge.updated", in ws: inout DemoWorkspace) {
        publish(type, ["source": .object(source)], in: &ws)
    }

    private func knowledgeRoutes(_ call: Call, in ws: inout DemoWorkspace) throws -> Data?? {
        let a = ws.settings.agent
        if call.match("GET", "ai/knowledge") != nil { return .some(encode(JSONValue.object(["data": jv(a.knowledge), "next_cursor": .null]))) }
        if let id = call.match("GET", "ai/knowledge/*")?.first { return .some(encode(JSONValue.object(a.knowledge[try sourceIndex(id, in: ws)]))) }
        if let id = call.match("GET", "ai/knowledge/*/docs")?.first {
            _ = try sourceIndex(id, in: ws)
            let all = a.docs[id] ?? []
            let offset = Int(call.query["cursor"] ?? "") ?? 0
            let limit = max(1, min(100, Int(call.query["limit"] ?? "") ?? 50))
            let slice = Array(all.dropFirst(offset).prefix(limit))
            let next: JSONValue = offset + slice.count < all.count ? .string(String(offset + slice.count)) : .null
            return .some(encode(JSONValue.object(["data": jv(slice), "next_cursor": next])))
        }
        if call.match("POST", "ai/knowledge") != nil {
            guard a.knowledge.count < 50 else { throw Failure(status: 409, code: "limit_reached", detail: "A workspace can have up to 50 knowledge sources.") }
            let kind = call.string("kind") ?? "website"
            var source = DemoAgentSettings.source(0, kind, call.string("name") ?? "", status: kind == "snippet" ? "ready" : "pending", docs: kind == "snippet" ? 1 : 0, chars: 0, synced: 0, extra: [:])
            let id = made()
            source["id"] = .string(id)
            source["created_at"] = .string(DemoSeed.stamp(now()))
            source["last_synced_at"] = .null
            if kind == "snippet" {
                let snippet = call.body["snippet"] ?? .object([:])
                source["snippet"] = snippet
                source["char_count"] = .number(Double((snippet["answer"]?.string ?? "").count))
                source["last_synced_at"] = .string(DemoSeed.stamp(now()))
                ws.settings.agent.docs[id] = [["id": .string(made()), "title": snippet["question"] ?? .string(""), "url": .null, "chars": source["char_count"] ?? .number(0)]]
            } else {
                guard let url = call.body["website"]?["url"]?.string, url.hasPrefix("https://") || url.hasPrefix("http://") else {
                    throw Failure(status: 422, code: "validation_failed", detail: "Enter the website's address, like https://docs.example.com.")
                }
                source["website"] = call.body["website"]
                if (source["name"]?.string ?? "").isEmpty { source["name"] = .string(URL(string: url)?.host ?? url) }
            }
            ws.settings.agent.knowledge.insert(source, at: 0)
            sourceChanged(source, "ai_knowledge.created", in: &ws)
            if kind == "website" { syncSoon(id, in: ws.id) }
            return .some(encode(JSONValue.object(source)))
        }
        if call.match("POST", "ai/knowledge/files") != nil {
            guard let file = Self.filePart(call.raw) else { throw Failure(status: 422, code: "validation_failed", detail: "Choose a file to upload.") }
            var source = DemoAgentSettings.source(0, "file", "", status: "pending", docs: 0, chars: 0, synced: 0, extra: ["file": ["filename": file.name, "content_type": file.type, "size_bytes": file.data.count]])
            let id = made()
            source["id"] = .string(id)
            source["created_at"] = .string(DemoSeed.stamp(now()))
            source["last_synced_at"] = .null
            ws.settings.agent.knowledge.insert(source, at: 0)
            sourceChanged(source, "ai_knowledge.created", in: &ws)
            syncSoon(id, in: ws.id)
            return .some(encode(JSONValue.object(source)))
        }
        if let id = call.match("POST", "ai/knowledge/*/sync")?.first {
            let index = try sourceIndex(id, in: ws)
            if ["pending", "syncing"].contains(ws.settings.agent.knowledge[index]["status"]?.string ?? "") {
                throw Failure(status: 409, code: "conflict", detail: "This source is already syncing.")
            }
            ws.settings.agent.knowledge[index]["status"] = .string("pending")
            sourceChanged(ws.settings.agent.knowledge[index], in: &ws)
            syncSoon(id, in: ws.id)
            return .some(encode(JSONValue.object(ws.settings.agent.knowledge[index])))
        }
        if let id = call.match("PATCH", "ai/knowledge/*")?.first {
            let index = try sourceIndex(id, in: ws)
            for (key, value) in call.body.object ?? [:] where ["name", "enabled", "website", "snippet"].contains(key) {
                ws.settings.agent.knowledge[index][key] = value
            }
            sourceChanged(ws.settings.agent.knowledge[index], in: &ws)
            return .some(encode(JSONValue.object(ws.settings.agent.knowledge[index])))
        }
        if let captured = call.match("DELETE", "ai/knowledge/*/docs/*") {
            let index = try sourceIndex(captured[0], in: ws)
            ws.settings.agent.docs[captured[0]]?.removeAll { $0["id"]?.string == captured[1] }
            let docs = ws.settings.agent.docs[captured[0]] ?? []
            ws.settings.agent.knowledge[index]["doc_count"] = .number(Double(docs.count))
            ws.settings.agent.knowledge[index]["char_count"] = .number(Double(docs.reduce(0) { $0 + ($1["chars"]?.int ?? 0) }))
            sourceChanged(ws.settings.agent.knowledge[index], in: &ws)
            return .some(nil)
        }
        if let id = call.match("DELETE", "ai/knowledge/*")?.first {
            ws.settings.agent.knowledge.remove(at: try sourceIndex(id, in: ws))
            ws.settings.agent.docs[id] = nil
            publish("ai_knowledge.deleted", ["source_id": .string(id)], in: &ws)
            return .some(nil)
        }
        return nil
    }

    /// A crawl or file read: pending, syncing, then ready with its documents, each step published.
    private func syncSoon(_ id: String, in wid: String) {
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            agentMutate(wid) { ws in
                guard let index = ws.settings.agent.knowledge.firstIndex(where: { $0["id"]?.string == id }) else { return }
                ws.settings.agent.knowledge[index]["status"] = .string("syncing")
                sourceChanged(ws.settings.agent.knowledge[index], in: &ws)
            }
            try? await Task.sleep(for: .milliseconds(2200))
            agentMutate(wid) { ws in
                guard let index = ws.settings.agent.knowledge.firstIndex(where: { $0["id"]?.string == id }) else { return }
                var source = ws.settings.agent.knowledge[index]
                if (ws.settings.agent.docs[id] ?? []).isEmpty {
                    let base = source["website"]?["url"]?.string ?? ""
                    let titles = source["kind"]?.string == "file" ? [source["file"]?["filename"]?.string ?? "Document"] : ["Home", "Getting started", "Pricing", "FAQ", "Contact"]
                    ws.settings.agent.docs[id] = titles.enumerated().map { n, title in
                        ["id": .string(made()), "title": .string(title), "url": base.isEmpty ? .null : .string(n == 0 ? base : base + "/" + title.lowercased().replacingOccurrences(of: " ", with: "-")), "chars": .number(Double(2_400 + n * 1_310))]
                    }
                }
                let docs = ws.settings.agent.docs[id] ?? []
                source["status"] = .string("ready")
                source["doc_count"] = .number(Double(docs.count))
                source["char_count"] = .number(Double(docs.reduce(0) { $0 + ($1["chars"]?.int ?? 0) }))
                source["last_synced_at"] = .string(DemoSeed.stamp(now()))
                ws.settings.agent.knowledge[index] = source
                sourceChanged(source, in: &ws)
            }
        }
    }

    /// Changes a workspace outside a request, then hands its events to realtime.
    private func agentMutate(_ wid: String, _ change: (inout DemoWorkspace) -> Void) {
        guard let index = world.workspaces.firstIndex(where: { $0.id == wid }) else { return }
        var ws = world.workspaces[index]
        change(&ws)
        world.workspaces[index] = ws
        flush()
    }

    // MARK: Procedures

    private func procedureRoutes(_ call: Call, in ws: inout DemoWorkspace) throws -> Data?? {
        func index(_ id: String) throws -> Int {
            guard let i = ws.settings.agent.procedures.firstIndex(where: { $0["id"]?.string == id }) else { throw notFound("procedure") }
            return i
        }
        func validate(_ p: DemoAgentSettings.Object) throws {
            if (p["name"]?.string ?? "").trimmingCharacters(in: .whitespaces).isEmpty { throw Failure(status: 422, code: "validation_failed", detail: "Give the procedure a name.") }
            if (p["instructions"]?.string ?? "").trimmingCharacters(in: .whitespaces).isEmpty { throw Failure(status: 422, code: "validation_failed", detail: "Write the steps the agent follows.") }
        }
        if call.match("GET", "ai/procedures") != nil { return .some(encode(JSONValue.object(["data": jv(ws.settings.agent.procedures), "next_cursor": .null]))) }
        if call.match("POST", "ai/procedures") != nil {
            var p = DemoAgentSettings.procedure(0, "", when: "", steps: "", channels: ["chat", "email"], minutes: 0)
            for (key, value) in call.body.object ?? [:] where ["name", "when", "instructions", "enabled", "channels", "bot_ids"].contains(key) { p[key] = value }
            try validate(p)
            p["id"] = .string(made())
            p["updated_at"] = .string(DemoSeed.stamp(now()))
            p["updated_by"] = jv(["name": world.user.name])
            ws.settings.agent.procedures.insert(p, at: 0)
            publish("ai_procedure.created", ["procedure": .object(p)], in: &ws)
            return .some(encode(JSONValue.object(p)))
        }
        if let id = call.match("PATCH", "ai/procedures/*")?.first {
            let i = try index(id)
            var p = ws.settings.agent.procedures[i]
            for (key, value) in call.body.object ?? [:] where ["name", "when", "instructions", "enabled", "channels", "bot_ids"].contains(key) { p[key] = value }
            try validate(p)
            p["updated_at"] = .string(DemoSeed.stamp(now()))
            p["updated_by"] = jv(["name": world.user.name])
            ws.settings.agent.procedures[i] = p
            publish("ai_procedure.updated", ["procedure": .object(p)], in: &ws)
            return .some(encode(JSONValue.object(p)))
        }
        if let id = call.match("DELETE", "ai/procedures/*")?.first {
            ws.settings.agent.procedures.remove(at: try index(id))
            publish("ai_procedure.deleted", ["procedure_id": .string(id)], in: &ws)
            return .some(nil)
        }
        return nil
    }

    // MARK: Tools (MCP)

    private func mcpRoutes(_ call: Call, in ws: inout DemoWorkspace) throws -> Data?? {
        func index(_ id: String) throws -> Int {
            guard let i = ws.settings.agent.servers.firstIndex(where: { $0["id"]?.string == id }) else { throw notFound("connection") }
            return i
        }
        func changed(_ i: Int, _ type: String = "ai_mcp_server.updated") -> Data?? {
            let server = ws.settings.agent.servers[i]
            publish(type, ["mcp_server": .object(server)], in: &ws)
            return .some(encode(JSONValue.object(server)))
        }
        func auth(_ body: JSONValue?, keeping old: JSONValue?) -> JSONValue {
            let kind = body?["kind"]?.string ?? "none"
            let secret = body?["token"]?.string ?? body?["header_value"]?.string
            return jv(["kind": kind, "header_name": body?["header_name"]?.string ?? "", "has_secret": secret != nil || (old?["kind"]?.string == kind && old?["has_secret"]?.bool == true),
                       "oauth": ["connected": false, "scopes": []]] as [String: Any])
        }
        if call.match("GET", "ai/mcp-servers") != nil { return .some(encode(JSONValue.object(["data": jv(ws.settings.agent.servers), "next_cursor": .null]))) }
        if call.match("POST", "ai/mcp-servers") != nil {
            guard let url = call.string("url"), url.hasPrefix("https://") else { throw Failure(status: 422, code: "validation_failed", detail: "The address must start with https://.") }
            let name = displayName(call.string("name"), fallback: URL(string: url)?.host ?? "Tools")
            let a = auth(call.body["auth"], keeping: nil)
            let oauth = a["kind"]?.string == "oauth"
            let slug = String(name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }.prefix(24))
            let server: DemoAgentSettings.Object = [
                "id": .string(made()), "name": .string(name), "slug": .string(slug), "url": .string(url), "enabled": .bool(true), "auth": a,
                "status": .string(oauth ? "needs_auth" : "connected"), "error": .null, "server_info": oauth ? .null : jv(["name": slug, "version": "1.0.0"]),
                "tools": oauth ? .array([]) : jv([
                    DemoAgentSettings.tool("search_orders", "Find a customer's orders by email or order number.", readOnly: true, enabled: false, policy: "auto", verifiedOnly: true, schema: ["query": "An email or order number"]),
                    DemoAgentSettings.tool("refund_order", "Refund an order in full or in part.", readOnly: false, destructive: true, enabled: false, policy: "confirm", verifiedOnly: true, schema: ["order_id": "The order", "amount": "How much to refund"]),
                ]),
                "last_synced_at": .string(DemoSeed.stamp(now())),
            ]
            ws.settings.agent.servers.append(server)
            return changed(ws.settings.agent.servers.count - 1, "ai_mcp_server.created")
        }
        if let id = call.match("POST", "ai/mcp-servers/*/sync")?.first {
            let i = try index(id)
            ws.settings.agent.servers[i]["last_synced_at"] = .string(DemoSeed.stamp(now()))
            return changed(i)
        }
        if let id = call.match("POST", "ai/mcp-servers/*/oauth/start")?.first {
            // The demo has no provider to sign in to: the connection counts as signed in at once.
            let i = try index(id)
            var a = ws.settings.agent.servers[i]["auth"]?.object ?? [:]
            a["oauth"] = jv(["connected": true, "scopes": ["read"]])
            ws.settings.agent.servers[i]["auth"] = .object(a)
            ws.settings.agent.servers[i]["status"] = .string("connected")
            _ = changed(i)
            return .some(encode(JSONValue.object(["url": .string(ws.settings.agent.servers[i]["url"]?.string ?? "https://opendesk.sh")])))
        }
        if let captured = call.match("POST", "ai/mcp-servers/*/tools/*/test") {
            let server = ws.settings.agent.servers[try index(captured[0])]
            guard (server["tools"]?.array ?? []).contains(where: { $0["name"]?.string == captured[1] }) else { throw notFound("tool") }
            let args = call.body["arguments"]?.object ?? [:]
            let content: String
            switch captured[1] {
            case "get_account": content = #"{"workspace":"Northwind Traders","plan":"business","seats":42,"owner":"ines@northwind.example"}"#
            case "list_invoices": content = #"[{"id":"INV-2026-10-0412","amount":"96.00","status":"paid","date":"2026-10-01"},{"id":"INV-2026-09-0398","amount":"96.00","status":"paid","date":"2026-09-01"}]"#
            default: content = "Not run: this tool changes things, so the demo answers without calling it. Arguments: " + (String(data: encode(JSONValue.object(args)), encoding: .utf8) ?? "{}")
            }
            return .some(encode(JSONValue.object(["content": .string(content), "is_error": .bool(false), "ms": .number(Double(180 + content.count % 220))])))
        }
        if let id = call.match("PATCH", "ai/mcp-servers/*")?.first {
            let i = try index(id)
            var server = ws.settings.agent.servers[i]
            let body = call.body.object ?? [:]
            for key in ["name", "url", "enabled"] { if let v = body[key] { server[key] = v } }
            if let a = body["auth"] { server["auth"] = auth(a, keeping: server["auth"]) }
            if let changes = body["tools"]?.object {
                server["tools"] = .array((server["tools"]?.array ?? []).map { tool in
                    guard var t = tool.object, let name = t["name"]?.string, let change = changes[name]?.object else { return tool }
                    for key in ["enabled", "policy", "verified_only"] { if let v = change[key] { t[key] = v } }
                    return .object(t)
                })
            }
            ws.settings.agent.servers[i] = server
            return changed(i)
        }
        if let id = call.match("DELETE", "ai/mcp-servers/*")?.first {
            ws.settings.agent.servers.remove(at: try index(id))
            publish("ai_mcp_server.deleted", ["mcp_server_id": .string(id)], in: &ws)
            return .some(nil)
        }
        return nil
    }

    // MARK: Overview, tests and test runs

    private func agentQualityRoutes(_ call: Call, in ws: inout DemoWorkspace) throws -> Data?? {
        if call.match("GET", "ai/agent/report") != nil { return .some(encode(agentReport(call, in: ws))) }
        if call.match("GET", "ai/agent/setup") != nil { return .some(encode(agentSetup(ws))) }
        if call.match("GET", "ai/agent/review") != nil { return .some(encode(JSONValue.object(["data": jv(ws.settings.agent.review), "next_cursor": .null]))) }
        if let id = call.match("POST", "ai/agent/review/*/dismiss")?.first {
            ws.settings.agent.review.removeAll { $0["id"]?.string == id }
            publish("ai_agent_review.updated", [:], in: &ws)
            return .some(nil)
        }
        if call.match("POST", "ai/agent/improve") != nil { return .some(encode(improve(call, in: &ws))) }
        if call.match("GET", "ai/agent/tests") != nil { return .some(encode(JSONValue.object(["data": jv(ws.settings.agent.tests), "next_cursor": .null]))) }
        if call.match("POST", "ai/agent/tests") != nil {
            guard ws.settings.agent.tests.count < 200 else { throw Failure(status: 409, code: "limit_reached", detail: "A workspace can have up to 200 tests.") }
            var test = try testBody(call.body, onto: ["visitor": .object([:]), "last_result": .null])
            test["id"] = .string(made())
            test["created_at"] = .string(DemoSeed.stamp(now()))
            ws.settings.agent.tests.insert(test, at: 0)
            publish("ai_agent_test.created", ["test": .object(test)], in: &ws)
            return .some(encode(JSONValue.object(test)))
        }
        if let id = call.match("PATCH", "ai/agent/tests/*")?.first {
            guard let i = ws.settings.agent.tests.firstIndex(where: { $0["id"]?.string == id }) else { throw notFound("test") }
            let test = try testBody(call.body, onto: ws.settings.agent.tests[i])
            ws.settings.agent.tests[i] = test
            publish("ai_agent_test.updated", ["test": .object(test)], in: &ws)
            return .some(encode(JSONValue.object(test)))
        }
        if let id = call.match("DELETE", "ai/agent/tests/*")?.first {
            guard let i = ws.settings.agent.tests.firstIndex(where: { $0["id"]?.string == id }) else { throw notFound("test") }
            ws.settings.agent.tests.remove(at: i)
            publish("ai_agent_test.deleted", ["test_id": .string(id)], in: &ws)
            return .some(nil)
        }
        if call.match("GET", "ai/agent/test-runs") != nil { return .some(encode(JSONValue.object(["data": jv(ws.settings.agent.runs), "next_cursor": .null]))) }
        if call.match("POST", "ai/agent/test-runs") != nil {
            if ws.settings.agent.runs.contains(where: { ["queued", "running"].contains($0["status"]?.string ?? "") }) {
                throw Failure(status: 409, code: "run_in_progress", detail: "A test run is already going. Wait for it or stop it first.")
            }
            let all = ws.settings.agent.tests.compactMap { $0["id"]?.string }
            let ids = call.body["test_ids"]?.array?.compactMap(\.string).filter(all.contains) ?? all
            guard !ids.isEmpty else { throw Failure(status: 422, code: "validation_failed", detail: "There are no tests to run.") }
            let settings = call.body["settings"]?.object
            let run: DemoAgentSettings.Object = [
                "id": .string(made()), "status": .string("queued"), "draft": .bool(settings != nil), "test_ids": jv(ids), "total": .number(Double(ids.count)),
                "passed": .number(0), "failed": .number(0), "errored": .number(0), "usd": .number(0), "error": .null, "created_at": .string(DemoSeed.stamp(now())), "finished_at": .null,
            ]
            ws.settings.agent.runs.insert(run, at: 0)
            publish("ai_agent_test_run.created", ["run": .object(run)], in: &ws)
            let blocked = (settings?["widget_blocked_topics"] ?? ws.settings.agent.behaviour["widget_blocked_topics"])?.array?.compactMap(\.string) ?? []
            advanceRun(run["id"]?.string ?? "", ids: ids, blocked: blocked, in: ws.id)
            return .some(encode(JSONValue.object(run)))
        }
        if let id = call.match("POST", "ai/agent/test-runs/*/cancel")?.first {
            guard let i = ws.settings.agent.runs.firstIndex(where: { $0["id"]?.string == id }) else { throw notFound("run") }
            if ["queued", "running"].contains(ws.settings.agent.runs[i]["status"]?.string ?? "") {
                ws.settings.agent.runs[i]["status"] = .string("cancelled")
                ws.settings.agent.runs[i]["finished_at"] = .string(DemoSeed.stamp(now()))
                publish("ai_agent_test_run.updated", ["run": .object(ws.settings.agent.runs[i])], in: &ws)
            }
            return .some(encode(JSONValue.object(ws.settings.agent.runs[i])))
        }
        return nil
    }

    private func testBody(_ body: JSONValue, onto base: DemoAgentSettings.Object) throws -> DemoAgentSettings.Object {
        var test = base
        if let messages = body["messages"]?.array {
            let lines = messages.compactMap(\.object)
            guard !lines.isEmpty, lines.count <= 6, lines.last?["role"]?.string != "agent" else {
                throw Failure(status: 422, code: "validation_failed", detail: "Up to 6 messages, ending with the visitor's.")
            }
            test["messages"] = .array(messages)
        }
        if let expectations = body["expectations"]?.array {
            guard !expectations.isEmpty, expectations.count <= 10 else { throw Failure(status: 422, code: "validation_failed", detail: "Add 1 to 10 checks.") }
            test["expectations"] = .array(expectations)
        }
        if let visitor = body["visitor"] { test["visitor"] = visitor }
        let first = (test["messages"]?.array ?? []).first { $0["role"]?.string != "agent" }?["text"]?.string ?? "Test"
        if let name = body["name"]?.string {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            test["name"] = .string(trimmed.isEmpty ? String(first.prefix(80)) : String(trimmed.prefix(120)))
        } else if (test["name"]?.string ?? "").isEmpty {
            test["name"] = .string(String(first.prefix(80)))
        }
        return test
    }

    /// Answers and grades one test at a time, publishing each result and the run's progress.
    private func advanceRun(_ runID: String, ids: [String], blocked: [String], in wid: String) {
        Task {
            func running() -> Bool {
                let ws = world.workspaces.first { $0.id == wid }
                return ws?.settings.agent.runs.first { $0["id"]?.string == runID }.map { ["queued", "running"].contains($0["status"]?.string ?? "") } ?? false
            }
            try? await Task.sleep(for: .milliseconds(700))
            guard running() else { return }
            agentMutate(wid) { ws in
                guard let r = ws.settings.agent.runs.firstIndex(where: { $0["id"]?.string == runID }) else { return }
                ws.settings.agent.runs[r]["status"] = .string("running")
                publish("ai_agent_test_run.updated", ["run": .object(ws.settings.agent.runs[r])], in: &ws)
            }
            for id in ids {
                try? await Task.sleep(for: .milliseconds(850))
                guard running() else { return }
                agentMutate(wid) { ws in
                    guard let r = ws.settings.agent.runs.firstIndex(where: { $0["id"]?.string == runID }),
                          let t = ws.settings.agent.tests.firstIndex(where: { $0["id"]?.string == id }) else { return }
                    let draft = ws.settings.agent.runs[r]["draft"]?.bool ?? false
                    var result = ws.settings.agent.grade(ws.settings.agent.tests[t], run: runID, draft: draft, blocked: blocked)
                    result["finished_at"] = .string(DemoSeed.stamp(now()))
                    ws.settings.agent.tests[t]["last_result"] = .object(result)
                    var run = ws.settings.agent.runs[r]
                    let key = result["status"]?.string == "passed" ? "passed" : "failed"
                    run[key] = .number(Double((run[key]?.int ?? 0) + 1))
                    run["usd"] = .number((run["usd"]?.double ?? 0) + (result["usd"]?.double ?? 0))
                    ws.settings.agent.runs[r] = run
                    publish("ai_agent_test_result.updated", ["result": .object(result)], in: &ws)
                    publish("ai_agent_test_run.updated", ["run": .object(run)], in: &ws)
                }
            }
            agentMutate(wid) { ws in
                guard let r = ws.settings.agent.runs.firstIndex(where: { $0["id"]?.string == runID }), ws.settings.agent.runs[r]["status"]?.string == "running" else { return }
                ws.settings.agent.runs[r]["status"] = .string("done")
                ws.settings.agent.runs[r]["finished_at"] = .string(DemoSeed.stamp(now()))
                publish("ai_agent_test_run.updated", ["run": .object(ws.settings.agent.runs[r])], in: &ws)
            }
        }
    }

    /// "Improve answer": a Q&A snippet the agent answers from at once, and perhaps a test that checks it.
    private func improve(_ call: Call, in ws: inout DemoWorkspace) -> JSONValue {
        let question = (call.string("question") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = (call.string("answer") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = String(question.prefix(300))
        var source = DemoAgentSettings.source(0, "snippet", String(cut.prefix(80)), status: "ready", docs: 1, chars: answer.count, synced: 0, extra: ["snippet": ["question": cut, "answer": answer]])
        let sourceID = made()
        source["id"] = .string(sourceID)
        source["created_at"] = .string(DemoSeed.stamp(now()))
        source["last_synced_at"] = source["created_at"]
        ws.settings.agent.knowledge.insert(source, at: 0)
        ws.settings.agent.docs[sourceID] = [["id": .string(made()), "title": .string(cut), "url": .null, "chars": .number(Double(answer.count))]]
        sourceChanged(source, "ai_knowledge.created", in: &ws)
        var test: JSONValue = .null
        if call.body["save_test"]?.bool == true {
            let plain = HTMLText.plain(from: KBMarkdown.html(from: answer)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let row: DemoAgentSettings.Object = [
                "id": .string(made()), "name": .string(String(cut.prefix(80))), "messages": jv([["role": "visitor", "text": cut]]),
                "expectations": jv([["kind": "mentions", "value": String(plain.prefix(1000))]]), "visitor": .object([:]), "last_result": .null,
                "created_at": .string(DemoSeed.stamp(now())),
            ]
            ws.settings.agent.tests.insert(row, at: 0)
            publish("ai_agent_test.created", ["test": .object(row)], in: &ws)
            test = .object(row)
        }
        if let id = call.string("message_id") {
            ws.settings.agent.review.removeAll { $0["id"]?.string == id }
            publish("ai_agent_review.updated", [:], in: &ws)
        }
        return .object(["source": jv(["id": sourceID, "kind": "snippet", "name": String(cut.prefix(80))]), "test": test])
    }

    // MARK: Agent-to-agent (Your settings)

    private func peerOut(_ ws: DemoWorkspace) -> JSONValue {
        var p = ws.settings.agent.peer
        let userIDs = p["user_ids"]?.array?.compactMap(\.string) ?? []
        let teamIDs = p["team_ids"]?.array?.compactMap(\.string) ?? []
        let users: [JSONValue] = userIDs.compactMap { id in
            ws.members.first { $0.id == id }.map { jv(["id": $0.id, "name": $0.user.name, "email": $0.user.email ?? ""]) }
        }
        let teams: [JSONValue] = teamIDs.compactMap { id in ws.teams.first { $0.id == id }.map { jv(["id": $0.id, "name": $0.name]) } }
        p["user_ids"] = nil
        p["team_ids"] = nil
        p["audience"] = .object(["users": .array(users), "teams": .array(teams)])
        return .object(p)
    }

    private func peerRoutes(_ call: Call, in ws: inout DemoWorkspace) throws -> Data?? {
        if call.match("GET", "me/assistant-peer") != nil { return .some(encode(peerOut(ws))) }
        if call.match("PUT", "me/assistant-peer") != nil {
            guard ws.settings.agent.peer["available"]?.bool == true else {
                throw Failure(status: 403, code: "assistant_peer_off", detail: "Your workspace has not turned on agent-to-agent.")
            }
            let body = call.body
            let rules = (body["rules"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard rules.count <= 2000 else { throw Failure(status: 422, code: "validation_failed", detail: "Rules can be at most 2,000 characters.") }
            var p = ws.settings.agent.peer
            for key in ["enabled", "all_accounts"] { if let v = body[key]?.bool { p[key] = .bool(v) } }
            if let v = body["share_with"]?.string, ["everyone", "chosen"].contains(v) { p["share_with"] = .string(v) }
            if let v = body["default_mode"]?.string, ["verbatim", "summary", "none"].contains(v) { p["default_mode"] = .string(v) }
            p["rules"] = .string(rules)
            let memberIDs = Set(ws.members.map(\.id))
            let teamIDs = Set(ws.teams.map(\.id))
            p["user_ids"] = .array((body["audience"]?["user_ids"]?.array ?? []).filter { memberIDs.contains($0.string ?? "") && $0.string != world.user.id })
            p["team_ids"] = .array((body["audience"]?["team_ids"]?.array ?? []).filter { teamIDs.contains($0.string ?? "") })
            let chosen = Dictionary((body["accounts"]?.array ?? []).compactMap { a in a["id"]?.string.map { ($0, a["mode"]?.string ?? "none") } }, uniquingKeysWith: { _, last in last })
            let all = p["all_accounts"]?.bool ?? true
            let fallback = all ? (p["default_mode"]?.string ?? "summary") : "none"
            p["accounts"] = .array((p["accounts"]?.array ?? []).map { account in
                guard var a = account.object, let id = a["id"]?.string else { return account }
                a["chosen"] = .bool(chosen[id] != nil)
                a["mode"] = .string(chosen[id] ?? fallback)
                return .object(a)
            })
            ws.settings.agent.peer = p
            return .some(encode(peerOut(ws)))
        }
        if call.match("GET", "me/assistant-peer/asks") != nil {
            let all = ws.settings.agent.asks
            let offset = Int(call.query["cursor"] ?? "") ?? 0
            let limit = max(1, min(50, Int(call.query["limit"] ?? "") ?? 20))
            let slice = Array(all.dropFirst(offset).prefix(limit))
            let next: JSONValue = offset + slice.count < all.count ? .string(String(offset + slice.count)) : .null
            return .some(encode(JSONValue.object(["data": jv(slice), "next_cursor": next])))
        }
        return nil
    }

    // MARK: The playground's stream

    /// `POST /v1/ai/agent/playground`, streamed as `tool`, `delta`, `sources` and `done`; nil when not that.
    func agentStreamRoutes(_ call: Call) throws -> [Beat]? {
        guard call.match("POST", "ai/agent/playground") != nil else { return nil }
        guard let wid = call.workspace, let index = world.workspaces.firstIndex(where: { $0.id == wid }) else { return nil }
        let a = world.workspaces[index].settings.agent
        guard a.aiOn else { throw Failure(status: 409, code: "ai_disabled", detail: "AI is off for this workspace.") }
        let messages = (call.body["messages"]?.array ?? []).compactMap(\.object)
        let settings = call.body["settings"]
        let blocked = (settings?["widget_blocked_topics"] ?? a.behaviour["widget_blocked_topics"])?.array?.compactMap(\.string) ?? []
        let verified = call.body["visitor"]?["verified"]?.bool ?? false
        let reply = a.reply(to: messages, blocked: blocked, verified: verified)
        world.workspaces[index].settings.agent.playgroundUsed = true

        var beats: [Beat] = []
        let searching = !reply.sources.isEmpty
        if searching {
            beats.append(Beat(event: "tool", data: jv(["name": "search_knowledge", "status": "running", "summary": ""]), pause: 160))
            beats.append(Beat(event: "tool", data: jv(["name": "search_knowledge", "status": "done", "summary": reply.sources.count == 1 ? "1 passage" : "\(reply.sources.count) passages"]), pause: 520))
        }
        for tool in reply.tools {
            beats.append(Beat(event: "tool", data: jv(["name": "margin__" + tool.name, "status": "running", "summary": ""]), pause: 140))
            beats.append(Beat(event: "tool", data: jv(["name": "margin__" + tool.name, "status": "done", "summary": tool.summary]), pause: 640))
        }
        if reply.handoff {
            beats.append(Beat(event: "tool", data: jv(["name": "handoff", "status": "done", "summary": "To the team"]), pause: 260))
        }
        beats += words(reply.text).map { Beat(event: "delta", data: .object(["text": .string(($0.data["text"]?.string ?? "") + " ")]), pause: $0.pause) }
        if searching { beats.append(Beat(event: "sources", data: .object(["sources": .array(reply.sources)]), pause: 80)) }
        beats.append(Beat(event: "done", data: .object([
            "text_html": .string(KBMarkdown.html(from: reply.text)), "sources": .array(reply.sources), "procedures": .array(reply.procedures),
            "action": .null, "handoff": .bool(reply.handoff), "usd": .number(0.0041),
        ]), pause: 120))
        return beats
    }
}
#endif
