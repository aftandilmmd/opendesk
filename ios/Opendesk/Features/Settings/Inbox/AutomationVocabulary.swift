import Foundation

// The automation builder's vocabulary, as the web's (`components/settings2/automation.ts`,
// `ConditionRow.tsx`, `fieldRules.tsx`): triggers, condition fields and their operators,
// actions, and the rules a rule must meet before it saves (contracts/api.md "Automations").

enum AutomationTrigger: String, LenientEnum, CaseIterable, Identifiable {
    case ticketCreated = "ticket_created"
    case customerReplied = "customer_replied"
    case agentReplied = "agent_replied"
    case ticketUpdated = "ticket_updated"
    case callEnded = "call_ended"
    static let fallback = AutomationTrigger.ticketCreated
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ticketCreated: "A ticket is created"
        case .customerReplied: "The customer replies"
        case .agentReplied: "An agent replies"
        case .ticketUpdated: "A ticket is updated"
        case .callEnded: "A call ends"
        }
    }

    var short: String {
        switch self {
        case .ticketCreated: "Ticket created"
        case .customerReplied: "Customer replied"
        case .agentReplied: "Agent replied"
        case .ticketUpdated: "Ticket updated"
        case .callEnded: "Call ended"
        }
    }

    /// Each trigger keeps one hue across the list and the builder.
    var tone: Tone {
        switch self {
        case .ticketCreated: .blue
        case .customerReplied: .teal
        case .agentReplied: .indigo
        case .ticketUpdated: .amber
        case .callEnded: .green
        }
    }

    var symbol: String {
        switch self {
        case .ticketCreated: "plus.square"
        case .customerReplied: "arrowshape.turn.up.left.circle"
        case .agentReplied: "arrowshape.turn.up.left"
        case .ticketUpdated: "pencil.line"
        case .callEnded: "phone"
        }
    }
}

enum AutomationVocabulary {
    // MARK: Condition fields

    /// Every built-in field, in the web's order.
    static let builtInFields = [
        "subject", "body", "from_email", "channel", "mailbox_id", "received_at", "assignee_id", "team_id", "brand_id", "widget_id",
        "priority", "severity", "status", "tag", "call_outcome", "call_direction", "call_time", "call_missed_reason", "call_line",
        "call_tag", "time", "sentiment", "ai_decide",
    ]

    static let callFields: Set<String> = ["call_outcome", "call_direction", "call_time", "call_missed_reason", "call_line", "call_tag"]
    static let aiFields: Set<String> = ["sentiment", "ai_decide"]

    static func fieldTitle(_ field: String) -> String {
        switch field {
        case "subject": "Subject"
        case "body": "Message text"
        case "from_email": "Sender email"
        case "channel": "Channel"
        case "mailbox_id": "Mailbox"
        case "priority": "Priority"
        case "severity": "Severity"
        case "status": "Status"
        case "tag": "Label"
        case "received_at": "Address written to"
        case "team_id": "Team"
        case "brand_id": "Brand"
        case "widget_id": "Chat widget"
        case "assignee_id": "Assignee"
        case "call_outcome": "Call outcome"
        case "call_direction": "Call direction"
        case "call_time": "Call time"
        case "call_missed_reason": "Missed call reason"
        case "call_line": "Call line"
        case "call_tag": "Call label"
        case "time": "Business hours"
        case "sentiment": "Sentiment"
        case "ai_decide": "Ask Ollie a yes/no question"
        default: field
        }
    }

    // MARK: Operators

    /// Text fields take any operator; enumerated fields only is / is not.
    static func ops(for field: String) -> [String] {
        switch field {
        case "sentiment": ["equals", "not_equals"]
        case "ai_decide": ["gt", "lt"]
        case "received_at": ["equals", "not_equals", "contains", "any", "none"]
        case "call_line", "call_tag": ["equals", "not_equals", "contains", "not_contains"]
        case "subject", "body", "from_email": ["contains", "not_contains", "any", "none", "equals", "not_equals"]
        default: ["equals", "not_equals"]
        }
    }

    static func opTitle(_ op: String) -> String {
        switch op {
        case "contains": "contains"
        case "not_contains": "doesn't contain"
        case "equals", "eq": "is"
        case "not_equals": "is not"
        case "gt": "is above"
        case "lt": "is below"
        case "any": "contains any of"
        case "none": "contains none of"
        default: op
        }
    }

    static func isPhraseOp(_ op: String) -> Bool { op == "any" || op == "none" }

    // MARK: Phrases

    static let maxPhrases = 100

    /// One per line, trimmed, empty lines dropped.
    static func phrases(_ value: String) -> [String] {
        value.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// 1 to 100 phrases of up to 500 characters, 5000 in all.
    static func validPhrases(_ value: String) -> Bool {
        let list = phrases(value)
        return !list.isEmpty && list.count <= maxPhrases && list.allSatisfy { $0.count <= 500 } && list.joined(separator: "\n").count <= 5000
    }

    // MARK: ai_decide

    static func validProbability(_ value: String) -> Bool {
        guard let n = Double(value.trimmingCharacters(in: .whitespaces)), n.isFinite else { return false }
        return n >= 0.01 && n <= 0.99
    }

    static func validQuestion(_ question: String?) -> Bool {
        let n = (question ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count
        return n >= 3 && n <= 300
    }

    // MARK: Fixed values

    static let callOutcomes: [(String, String)] = [("missed", "Missed"), ("voicemail", "Voicemail"), ("answered", "Answered")]
    static let callDirections: [(String, String)] = [("inbound", "Inbound"), ("outbound", "Outbound")]
    static let callTimes: [(String, String)] = [("outside_business_hours", "Outside business hours"), ("business_hours", "Within business hours")]
    static let callReasons: [(String, String)] = [
        ("out_of_opening_hours", "Outside opening hours"), ("no_available_agent", "No teammate available"),
        ("agents_did_not_answer", "Nobody answered"), ("abandoned_in_ivr", "Hung up in the menu"),
        ("abandoned_in_classic", "Hung up while waiting"), ("short_abandoned", "Hung up quickly"), ("no_answer", "Not answered"),
        ("busy", "Line busy"), ("cancelled", "Hung up before an answer"), ("abandon", "Hung up in the queue"), ("failed", "Call failed"),
    ]
    static let sentiments: [(String, String)] = [("positive", "Positive"), ("neutral", "Neutral"), ("negative", "Negative"), ("frustrated", "Frustrated")]

    static func placeholder(for field: String) -> String {
        switch field {
        case "from_email": "@acme.com"
        case "received_at": "support@acme.com"
        case "subject": "refund"
        case "call_line": "B2B"
        default: "invoice"
        }
    }

    // MARK: Custom field rules

    /// `field.<key>` names a ticket field, `contact.field.<key>` the ticket contact's.
    static func isFieldRef(_ field: String) -> Bool { field.hasPrefix("field.") || field.hasPrefix("contact.field.") }

    static func parseFieldRef(_ field: String) -> (entity: String, key: String) {
        field.hasPrefix("contact.field.") ? ("contact", String(field.dropFirst("contact.field.".count))) : ("ticket", String(field.dropFirst("field.".count)))
    }

    static func ref(of field: CustomField) -> String {
        field.entity == "contact" ? "contact.field.\(field.key)" : "field.\(field.key)"
    }

    /// Operators per field type (contracts/api.md, custom field filters).
    static func fieldOps(_ type: CustomField.Kind?) -> [String] {
        switch type {
        case .number, .date: ["eq", "ne", "gt", "gte", "lt", "lte", "set", "not_set"]
        case .checkbox: ["eq", "ne", "set", "not_set"]
        case .select, .user: ["eq", "ne", "any", "none", "set", "not_set"]
        case .multiSelect: ["any", "all", "none", "eq", "ne", "set", "not_set"]
        default: ["eq", "ne", "contains", "not_contains", "set", "not_set"]
        }
    }

    static func fieldOpTitle(_ op: String, type: CustomField.Kind?) -> String {
        if type == .date {
            switch op {
            case "gt": return "is after"
            case "gte": return "is on or after"
            case "lt": return "is before"
            case "lte": return "is on or before"
            default: break
            }
        }
        switch op {
        case "eq": return "is"
        case "ne": return "is not"
        case "contains": return "contains"
        case "not_contains": return "doesn't contain"
        case "gt": return "is more than"
        case "gte": return "is at least"
        case "lt": return "is less than"
        case "lte": return "is at most"
        case "any": return "is any of"
        case "all": return "has all of"
        case "none": return "is none of"
        case "set": return "is set"
        case "not_set": return "is empty"
        default: return op
        }
    }

    static func fieldOpTakesValue(_ op: String) -> Bool { op != "set" && op != "not_set" }
    static func fieldOpTakesList(_ op: String) -> Bool { op == "any" || op == "all" || op == "none" }

    // MARK: Actions

    static let allActions = [
        "set_status", "set_priority", "set_severity", "assign_user", "assign_replier", "assign_team", "set_reply_address", "add_tag",
        "remove_tag", "set_field", "send_reply", "add_note", "mark_spam", "delete_ticket", "merge_into_open_ticket", "ai_triage", "run_procedure",
    ]

    static let aiActions: Set<String> = ["ai_triage", "run_procedure"]

    static func actionTitle(_ type: String) -> String {
        switch type {
        case "set_status": "Set status to"
        case "set_priority": "Set priority to"
        case "set_severity": "Set severity to"
        case "assign_user": "Assign to"
        case "assign_replier": "Assign to the agent who replied"
        case "assign_team": "Assign to team"
        case "add_tag": "Add label"
        case "remove_tag": "Remove label"
        case "send_reply": "Send a reply"
        case "add_note": "Add an internal note"
        case "mark_spam": "Mark as spam"
        case "delete_ticket": "Delete ticket"
        case "merge_into_open_ticket": "Merge into the contact's open ticket"
        case "set_field": "Set field"
        case "set_reply_address": "Set reply address"
        case "ai_triage": "Run AI triage"
        case "run_procedure": "Ollie runs a procedure"
        default: type
        }
    }

    static func actionSymbol(_ type: String) -> String {
        switch type {
        case "set_status": "circle.dashed"
        case "set_priority": "chart.bar"
        case "set_severity": "exclamationmark.triangle"
        case "assign_user", "assign_replier": "person.crop.circle"
        case "assign_team": "person.3"
        case "set_reply_address": "envelope"
        case "add_tag": "tag"
        case "remove_tag": "tag.slash"
        case "set_field": "slider.horizontal.3"
        case "send_reply": "arrowshape.turn.up.left"
        case "add_note": "note.text"
        case "mark_spam": "xmark.bin"
        case "delete_ticket": "trash"
        case "merge_into_open_ticket": "arrow.triangle.merge"
        case "ai_triage", "run_procedure": "sparkles"
        default: "bolt"
        }
    }

    /// set_field may write "" to clear, so it needs only its field.
    static func actionNeedsValue(_ type: String) -> Bool {
        !["mark_spam", "delete_ticket", "assign_replier", "ai_triage", "set_field"].contains(type)
    }

    /// A merge runs only when a ticket is created; Ollie's own changes never run a procedure again.
    static func actionFits(_ type: String, _ trigger: AutomationTrigger) -> Bool {
        if type == "merge_into_open_ticket" { return trigger == .ticketCreated }
        if type == "run_procedure" { return trigger != .ticketUpdated }
        return true
    }

    static let mergeWindowDefault = 7
    private static let mergeWindowChoices = [1, 2, 3, 7, 14, 30]

    static func validMergeWindow(_ value: String) -> Bool {
        guard !value.isEmpty, value.allSatisfy(\.isASCII), value.allSatisfy(\.isNumber), let n = Int(value) else { return false }
        return n >= 1 && n <= 30
    }

    /// The windows offered, with one saved through the API outside them.
    static func mergeWindows(_ current: String) -> [Int] {
        guard validMergeWindow(current), let n = Int(current), !mergeWindowChoices.contains(n) else { return mergeWindowChoices }
        return (mergeWindowChoices + [n]).sorted()
    }

    /// A new action of a type, with its defaults.
    static func newAction(_ type: String) -> AutomationAction {
        type == "merge_into_open_ticket" ? AutomationAction(type: type, value: String(mergeWindowDefault), sameSubject: true) : AutomationAction(type: type)
    }

    // MARK: Validation

    static func conditionInvalid(_ c: AutomationCondition) -> Bool {
        if isFieldRef(c.field) { return fieldOpTakesValue(c.op) && c.value.trimmingCharacters(in: .whitespaces).isEmpty }
        if c.field == "ai_decide" { return !validProbability(c.value) || !validQuestion(c.question) }
        if isPhraseOp(c.op) { return !validPhrases(c.value) }
        return c.value.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// A phrase list past the API's bounds; an empty one is a missing value.
    static func overPhrases(_ c: AutomationCondition) -> Bool {
        !isFieldRef(c.field) && isPhraseOp(c.op) && !phrases(c.value).isEmpty && !validPhrases(c.value)
    }

    static func isEmptyHTML(_ html: String) -> Bool {
        HTMLText.plain(from: html).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func actionInvalid(_ a: AutomationAction, trigger: AutomationTrigger) -> Bool {
        if !actionFits(a.type, trigger) { return true }
        if a.type == "set_field" { return (a.field ?? "").isEmpty }
        if a.type == "merge_into_open_ticket" { return !validMergeWindow(a.value) }
        guard actionNeedsValue(a.type) else { return false }
        if a.type == "send_reply" || a.type == "add_note" { return isEmptyHTML(a.value) }
        return a.value.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// What stops a rule from saving, in the web's words and order.
    static func problems(name: String, trigger: AutomationTrigger, conditions: [AutomationCondition], actions: [AutomationAction]) -> [String] {
        var out: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append("Name the automation.") }
        if actions.isEmpty { out.append("Add at least one action.") }
        if conditions.contains(where: { conditionInvalid($0) && !overPhrases($0) }) { out.append("Every condition needs a value, or remove it.") }
        if conditions.contains(where: overPhrases) {
            out.append("A phrase list takes 1 to 100 phrases, one per line, of up to 500 characters each.")
        }
        if actions.contains(where: { actionInvalid($0, trigger: trigger) && actionFits($0.type, trigger) }) { out.append("Every action needs a value.") }
        if actions.contains(where: { !actionFits($0.type, trigger) && $0.type != "run_procedure" }) {
            out.append("Merge into the contact's open ticket runs only when a ticket is created.")
        }
        if actions.contains(where: { !actionFits($0.type, trigger) && $0.type == "run_procedure" }) {
            out.append("Ollie can't run a procedure when a ticket is updated. Pick another trigger.")
        }
        if trigger != .callEnded && conditions.contains(where: { callFields.contains($0.field) }) {
            out.append("Call conditions need the trigger A call ends.")
        }
        return out
    }
}
