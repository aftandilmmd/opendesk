import SwiftUI

/// What a rule's pickers offer and how a saved value reads, from the directory and the store's lookups.
@MainActor
struct AutomationChoices {
    let teams: [Team]
    let members: [Member]
    let tags: [Tag]
    let fields: [CustomField]
    let aiEnabled: Bool
    let store: AutomationsStore

    init(directory: DirectoryStore, store: AutomationsStore) {
        teams = directory.teams
        members = directory.assignable
        tags = directory.tags
        fields = directory.fields
        aiEnabled = directory.ai.enabled
        self.store = store
    }

    // MARK: Conditions

    func customField(_ ref: String) -> CustomField? {
        guard AutomationVocabulary.isFieldRef(ref) else { return nil }
        let parsed = AutomationVocabulary.parseFieldRef(ref)
        return fields.first { $0.entity == parsed.entity && $0.key == parsed.key }
    }

    /// Built-in fields the trigger allows (AI ones with AI on, team and brand ones once there are
    /// teams or brands), then ticket and contact fields; the current field always stays.
    func fieldOptions(current: String, trigger: AutomationTrigger) -> [InboxOption] {
        let builtIn = AutomationVocabulary.builtInFields.filter { field in
            if field == current { return true }
            if field == "time" { return false }
            if AutomationVocabulary.callFields.contains(field) && trigger != .callEnded { return false }
            if field == "severity" && !store.severityEnabled { return false }
            if AutomationVocabulary.aiFields.contains(field) && !aiEnabled { return false }
            if field == "team_id" && teams.isEmpty { return false }
            if field == "brand_id" && store.brands.count < 2 { return false }
            return true
        }
        let custom = fields.filter { field in
            (field.entity == "ticket" || field.entity == "contact") && (!field.archived || AutomationVocabulary.ref(of: field) == current)
        }
        let group: String? = custom.isEmpty ? nil : "Ticket"
        var out = builtIn.map { field in
            InboxOption(value: field, label: AutomationVocabulary.fieldTitle(field), symbol: AutomationVocabulary.aiFields.contains(field) ? "sparkles" : nil, tone: AutomationVocabulary.aiFields.contains(field) ? .violet : nil, group: group)
        }
        out += custom.sorted { ($0.entity, $0.position) < ($1.entity, $1.position) }.map { field in
            InboxOption(value: AutomationVocabulary.ref(of: field), label: field.name, symbol: field.type.symbol, group: field.entity == "contact" ? "Contact fields" : "Ticket fields", keywords: [field.key])
        }
        return out
    }

    func fieldLabel(_ field: String) -> String {
        if AutomationVocabulary.isFieldRef(field) {
            guard let custom = customField(field) else { return "This field was deleted" }
            return custom.entity == "contact" ? "Contact: \(custom.name)" : custom.name
        }
        return AutomationVocabulary.fieldTitle(field)
    }

    func opOptions(_ condition: AutomationCondition) -> [(String, String)] {
        if AutomationVocabulary.isFieldRef(condition.field) {
            let type = customField(condition.field)?.type
            return AutomationVocabulary.fieldOps(type).map { ($0, AutomationVocabulary.fieldOpTitle($0, type: type)) }
        }
        return AutomationVocabulary.ops(for: condition.field).map { ($0, AutomationVocabulary.opTitle($0)) }
    }

    func opLabel(_ condition: AutomationCondition) -> String {
        opOptions(condition).first { $0.0 == condition.op }?.1 ?? condition.op
    }

    /// The choices for a built-in condition's value, or nil when it is typed.
    func valueOptions(_ condition: AutomationCondition) -> [InboxOption]? {
        if AutomationVocabulary.isPhraseOp(condition.op) { return nil }
        switch condition.field {
        case "status": return TicketStatus.allCases.map { InboxOption(value: $0.rawValue, label: $0.title) }
        case "priority": return Priority.allCases.map { InboxOption(value: $0.rawValue, label: $0.title, tone: $0.tone) }
        case "severity": return Severity.allCases.map { InboxOption(value: $0.rawValue, label: $0.title, hint: $0.hint) } + [InboxOption(value: "none", label: "No severity")]
        case "channel": return Channel.allCases.map { InboxOption(value: $0.rawValue, label: $0.title) }
        case "mailbox_id": return store.mailboxes.map { InboxOption(value: $0.id, label: $0.name, hint: $0.email) }
        case "team_id": return [InboxOption(value: "none", label: "No team")] + teams.map { InboxOption(value: $0.id, label: $0.name) }
        case "assignee_id": return [InboxOption(value: "none", label: "Unassigned")] + memberOptions
        case "brand_id": return store.brands.map { InboxOption(value: $0.id, label: $0.name) }
        case "widget_id":
            return [InboxOption(value: "none", label: "No widget")] + store.widgets.map { widget in
                InboxOption(value: widget.id, label: widget.name, hint: store.brands.count > 1 ? store.brands.first { $0.id == widget.brandID }?.name : nil)
            }
        case "tag": return tagOptions
        case "call_outcome": return AutomationVocabulary.callOutcomes.map { InboxOption(value: $0.0, label: $0.1) }
        case "call_direction": return AutomationVocabulary.callDirections.map { InboxOption(value: $0.0, label: $0.1) }
        case "call_time", "time": return AutomationVocabulary.callTimes.map { InboxOption(value: $0.0, label: $0.1) }
        case "call_missed_reason": return AutomationVocabulary.callReasons.map { InboxOption(value: $0.0, label: $0.1) }
        case "sentiment": return AutomationVocabulary.sentiments.map { InboxOption(value: $0.0, label: $0.1) }
        case "call_line":
            guard condition.op == "equals" || condition.op == "not_equals" else { return nil }
            var options = store.lines.map { InboxOption(value: $0.id, label: $0.name) }
            if !condition.value.isEmpty && !options.contains(where: { $0.value == condition.value }) {
                options.append(InboxOption(value: condition.value, label: condition.value))
            }
            return options
        default: return nil
        }
    }

    func valuePlaceholder(_ field: String) -> String {
        switch field {
        case "status": "Choose a status"
        case "priority": "Choose a priority"
        case "severity": "Choose a severity"
        case "channel": "Choose a channel"
        case "mailbox_id": "Choose a mailbox"
        case "team_id": "Choose a team"
        case "assignee_id": "Choose a teammate"
        case "brand_id": "Choose a brand"
        case "widget_id": "Choose a widget"
        case "tag": "Choose a label"
        case "sentiment": "Choose a sentiment"
        case "call_line": "Choose a line"
        default: "Choose a value"
        }
    }

    var memberOptions: [InboxOption] {
        members.map { InboxOption(value: $0.id, label: $0.user.name, hint: $0.user.email, keywords: [$0.user.email ?? ""]) }
    }

    var tagOptions: [InboxOption] {
        tags.filter { $0.archived != true }.map { InboxOption(value: $0.name, label: $0.name, tone: $0.color.map { Tone(label: $0) } ?? LabelPalette.tone(for: $0.name)) }
    }

    func fieldValueOptions(_ field: CustomField) -> [InboxOption] {
        switch field.type {
        case .select, .multiSelect: field.options.map { InboxOption(value: $0.id, label: $0.label, tone: Tone(label: $0.color)) }
        case .user: memberOptions
        default: []
        }
    }

    /// How a condition reads in its row: "Subject contains refund".
    func summary(_ condition: AutomationCondition) -> String {
        let field = fieldLabel(condition.field)
        if condition.field == "ai_decide" {
            let question = (condition.question ?? "").trimmingCharacters(in: .whitespaces)
            let pct = Double(condition.value).map { "\(Int(($0 * 100).rounded()))%" } ?? condition.value
            return question.isEmpty ? field : "\u{201C}\(question)\u{201D} \(condition.op == "lt" ? "below" : "above") \(pct)"
        }
        let op = opLabel(condition)
        if AutomationVocabulary.isFieldRef(condition.field) {
            guard AutomationVocabulary.fieldOpTakesValue(condition.op) else { return "\(field) \(op)" }
            return "\(field) \(op) \(fieldValueLabel(condition.field, condition.value))"
        }
        return "\(field) \(op) \(valueLabel(condition))"
    }

    func valueLabel(_ condition: AutomationCondition) -> String {
        if AutomationVocabulary.isPhraseOp(condition.op) {
            let list = AutomationVocabulary.phrases(condition.value)
            if list.isEmpty { return "\u{2026}" }
            return list.count == 1 ? list[0] : "\(list[0]) and \(list.count - 1) more"
        }
        if condition.value.isEmpty { return "\u{2026}" }
        return valueOptions(condition)?.first { $0.value == condition.value }?.label ?? condition.value
    }

    func fieldValueLabel(_ ref: String, _ value: String) -> String {
        if value.isEmpty { return "\u{2026}" }
        guard let field = customField(ref) else { return value }
        switch field.type {
        case .select, .multiSelect, .user:
            let options = fieldValueOptions(field)
            let labels = value.split(separator: ",").map { id in options.first { $0.value == String(id) }?.label ?? String(id) }
            return labels.joined(separator: ", ")
        case .checkbox: return value == "true" ? "Yes" : value == "false" ? "No" : value
        default: return value
        }
    }

    // MARK: Actions

    func actionOptions(current: String, trigger: AutomationTrigger) -> [InboxOption] {
        let hasTicketFields = fields.contains { $0.entity == "ticket" && !$0.archived }
        return AutomationVocabulary.allActions
            .filter { $0 == current || !AutomationVocabulary.aiActions.contains($0) || aiEnabled }
            .filter { $0 == current || $0 != "set_field" || hasTicketFields }
            .filter { $0 == current || $0 != "set_severity" || store.severityEnabled }
            .filter { $0 == current || AutomationVocabulary.actionFits($0, trigger) }
            .map { type in
                InboxOption(value: type, label: AutomationVocabulary.actionTitle(type), symbol: AutomationVocabulary.actionSymbol(type), tone: AutomationVocabulary.aiActions.contains(type) ? .violet : nil)
            }
    }

    func actionValueOptions(_ type: String) -> [InboxOption]? {
        switch type {
        case "set_status": TicketStatus.allCases.filter { $0 != .closed }.map { InboxOption(value: $0.rawValue, label: $0.title) }
        case "set_priority": Priority.allCases.map { InboxOption(value: $0.rawValue, label: $0.title, tone: $0.tone) }
        case "set_severity": Severity.allCases.map { InboxOption(value: $0.rawValue, label: $0.title, hint: $0.hint) }
        case "assign_user": memberOptions
        case "assign_team": teams.map { InboxOption(value: $0.id, label: $0.name) }
        case "set_reply_address": store.mailboxes.map { InboxOption(value: $0.id, label: $0.name, hint: $0.email) }
        case "add_tag", "remove_tag": tagOptions
        case "run_procedure": store.procedures.map { InboxOption(value: $0.id, label: $0.name, hint: $0.enabled ? nil : "Off") }
        default: nil
        }
    }

    func actionPlaceholder(_ type: String) -> String {
        switch type {
        case "set_status": "Choose a status"
        case "set_priority": "Choose a priority"
        case "set_severity": "Choose a severity"
        case "assign_user": "Choose a teammate"
        case "assign_team": "Choose a team"
        case "set_reply_address": "Choose a mailbox"
        case "add_tag", "remove_tag": "Choose a label"
        case "run_procedure": "Choose a procedure"
        default: "Choose a value"
        }
    }

    /// How an action reads in its row: "Add label billing".
    func summary(_ action: AutomationAction) -> String {
        let title = AutomationVocabulary.actionTitle(action.type)
        switch action.type {
        case "assign_replier", "mark_spam", "delete_ticket", "ai_triage":
            return title
        case "send_reply", "add_note":
            let text = HTMLText.plain(from: action.value).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? title : "\(title): \(text)"
        case "merge_into_open_ticket":
            let days = Int(action.value) ?? AutomationVocabulary.mergeWindowDefault
            return "\(title), within \(days == 1 ? "1 day" : "\(days) days")\(action.sameSubject == false ? "" : ", same subject only")"
        case "set_field":
            guard let key = action.field, let field = fields.first(where: { $0.entity == "ticket" && $0.key == key }) else { return title }
            return action.value.isEmpty ? "Clear \(field.name)" : "Set \(field.name) to \(fieldValueLabel("field.\(key)", action.value))"
        default:
            if action.value.isEmpty { return "\(title) \u{2026}" }
            let label = actionValueOptions(action.type)?.first { $0.value == action.value }?.label ?? action.value
            return "\(title) \(label)"
        }
    }
}

// MARK: - Condition editor

/// One condition, edited in a sheet: field, operator and value, or Ollie's question.
struct AutomationConditionSheet: View {
    let choices: AutomationChoices
    let trigger: AutomationTrigger
    let initial: AutomationCondition
    let apply: (AutomationCondition) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var c = AutomationCondition(field: "subject", op: "contains", value: "")
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AccountSheetHeader(title: "Condition", subtitle: nil) { dismiss() }
                InboxPickerField(label: "Field", title: "Field", options: choices.fieldOptions(current: c.field, trigger: trigger), value: c.field, placeholder: "Field") { pickField($0) }
                if c.field != "ai_decide" {
                    InboxMenuField(label: "Operator", value: choices.opLabel(c)) {
                        Picker("Operator", selection: Binding(get: { c.op }, set: { pickOp($0) })) {
                            ForEach(choices.opOptions(c), id: \.0) { option in Text(option.1).tag(option.0) }
                        }
                    }
                }
                valueEditor
                Button {
                    apply(c)
                    dismiss()
                } label: { ButtonLabel(title: "Done", busy: false) }
                    .buttonStyle(InkButtonStyle())
            }
            .padding(22)
            .motion(Motion.snappy, value: c)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.surface)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            c = initial
        }
    }

    private func pickField(_ field: String) {
        if AutomationVocabulary.isFieldRef(field) {
            let ops = AutomationVocabulary.fieldOps(choices.customField(field)?.type)
            let op = AutomationVocabulary.isFieldRef(c.field) && ops.contains(c.op) ? c.op : (ops.first ?? "eq")
            c = AutomationCondition(field: field, op: op, value: "")
        } else if field == "ai_decide" {
            c = AutomationCondition(field: field, op: "gt", value: "0.7", question: "")
        } else {
            let ops = AutomationVocabulary.ops(for: field)
            let op = !AutomationVocabulary.isFieldRef(c.field) && ops.contains(c.op) ? c.op : (ops.first ?? "equals")
            c = AutomationCondition(field: field, op: op, value: "")
        }
    }

    private func pickOp(_ op: String) {
        if AutomationVocabulary.isFieldRef(c.field) {
            c.value = AutomationVocabulary.fieldOpTakesValue(op) ? c.value : ""
        } else if AutomationVocabulary.isPhraseOp(c.op) && !AutomationVocabulary.isPhraseOp(op) {
            // Leaving a phrase list keeps its first phrase as the single value.
            c.value = AutomationVocabulary.phrases(c.value).first ?? ""
        }
        c.op = op
    }

    @ViewBuilder
    private var valueEditor: some View {
        if AutomationVocabulary.isFieldRef(c.field) {
            if let field = choices.customField(c.field) {
                AutomationFieldValue(field: field, op: c.op, value: $c.value, choices: choices, allowClear: false)
            } else {
                Text("This field was deleted").font(ODFont.footnote).foregroundStyle(Theme.fg4)
            }
        } else if c.field == "ai_decide" {
            decide
        } else if AutomationVocabulary.isPhraseOp(c.op) {
            let count = AutomationVocabulary.phrases(c.value).count
            VStack(alignment: .leading, spacing: 6) {
                AccountTextEditor(label: "\(AutomationVocabulary.fieldTitle(c.field)) phrases", text: $c.value, prompt: "One phrase per line", minHeight: 110, mono: c.field == "from_email" || c.field == "received_at")
                Text("\(count) \(count == 1 ? "phrase" : "phrases"), up to \(AutomationVocabulary.maxPhrases)")
                    .font(ODFont.footnote)
                    .foregroundStyle(count > AutomationVocabulary.maxPhrases ? Tone.red.text : Theme.fg3)
            }
        } else if let options = choices.valueOptions(c) {
            InboxPickerField(
                label: "Value",
                title: choices.valuePlaceholder(c.field),
                options: options,
                value: c.value.isEmpty ? nil : c.value,
                placeholder: choices.valuePlaceholder(c.field),
                createTitle: c.field == "tag" ? { "Use \u{201C}\($0)\u{201D}" } : nil
            ) { c.value = $0 }
        } else {
            ODTextField(label: "\(AutomationVocabulary.fieldTitle(c.field)) value", text: $c.value, prompt: AutomationVocabulary.placeholder(for: c.field), keyboard: c.field == "from_email" || c.field == "received_at" ? .emailAddress : .default, submitLabel: .done)
                .textInputAutocapitalization(.never)
        }
    }

    private var decide: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                AccountTextEditor(label: "Question", text: Binding(get: { c.question ?? "" }, set: { c.question = String($0.replacingOccurrences(of: "\n", with: " ").prefix(300)) }), prompt: "Is the customer at risk of churning?", minHeight: 70)
                Text("Ollie answers with a probability of yes. Every question in one run is asked together.")
                    .font(ODFont.footnote)
                    .foregroundStyle(Theme.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                InboxMenuField(label: "When the probability of yes", value: c.op == "lt" ? "is below" : "is above") {
                    Picker("Operator", selection: $c.op) {
                        Text("is above").tag("gt")
                        Text("is below").tag("lt")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Probability of yes").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
                    TextField("0.7", text: Binding(get: { c.value }, set: { c.value = String($0.filter { $0.isNumber || $0 == "." }.prefix(4)) }))
                        .keyboardType(.decimalPad)
                        .font(ODFont.mono(15))
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(AutomationVocabulary.validProbability(c.value) ? Theme.line : Tone.red.solid, lineWidth: 1))
                }
            }
            if AutomationVocabulary.validProbability(c.value), let p = Double(c.value) {
                Text("\(Int((p * 100).rounded()))% likely").font(ODFont.footnote).foregroundStyle(Theme.fg3)
            }
        }
    }
}

// MARK: - Action editor

/// One action, edited in a sheet: what it does and its value.
struct AutomationActionSheet: View {
    let choices: AutomationChoices
    let trigger: AutomationTrigger
    let initial: AutomationAction
    let apply: (AutomationAction) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var a = AutomationAction(type: "add_tag")
    @State private var text = ""
    @State private var loaded = false

    private var rich: Bool { a.type == "send_reply" || a.type == "add_note" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AccountSheetHeader(title: "Action", subtitle: nil) { dismiss() }
                InboxPickerField(label: "Do", title: "Action", options: choices.actionOptions(current: a.type, trigger: trigger), value: a.type, placeholder: "Action") { type in
                    a = AutomationVocabulary.newAction(type)
                    text = ""
                }
                control
                Button {
                    var out = a
                    if rich { out.value = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : HTMLText.html(fromPlain: text) }
                    apply(out)
                    dismiss()
                } label: { ButtonLabel(title: "Done", busy: false) }
                    .buttonStyle(InkButtonStyle())
            }
            .padding(22)
            .motion(Motion.snappy, value: a)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.surface)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            a = initial
            if initial.type == "send_reply" || initial.type == "add_note" { text = HTMLText.plain(from: initial.value) }
        }
    }

    @ViewBuilder
    private var control: some View {
        switch a.type {
        case "assign_replier":
            hint("Assigns whoever wrote the reply. Add the condition Assignee is Unassigned to leave tickets someone already has with them.")
        case "mark_spam":
            hint("Moves the ticket to Spam. No reply is sent.")
        case "delete_ticket":
            hint("Deletes the ticket: it leaves every view, and nothing else runs on it.")
        case "ai_triage":
            hint("Sets labels, priority, sentiment and language from the conversation.")
        case "send_reply":
            VStack(alignment: .leading, spacing: 6) {
                AccountTextEditor(label: "Reply text", text: $text, prompt: "Thanks for writing in. We've received your message\u{2026}", minHeight: 140)
                hint("Sender variables, like the agent's name, are empty in automated replies.")
            }
        case "add_note":
            AccountTextEditor(label: "Note text", text: $text, prompt: "Internal note for the team", minHeight: 120)
        case "merge_into_open_ticket":
            VStack(alignment: .leading, spacing: 12) {
                InboxMenuField(label: "Window", value: mergeLabel(Int(a.value) ?? AutomationVocabulary.mergeWindowDefault)) {
                    Picker("Window", selection: $a.value) {
                        ForEach(AutomationVocabulary.mergeWindows(a.value), id: \.self) { n in Text(mergeLabel(n)).tag(String(n)) }
                    }
                }
                InboxSwitchBox(title: "Same subject only", isOn: Binding(get: { a.sameSubject != false }, set: { a.sameSubject = $0 }))
                hint("Merges a new ticket into the same contact's latest open, pending or on hold ticket. Nothing else runs on it after that.")
            }
        case "set_field":
            setField
        default:
            if let options = choices.actionValueOptions(a.type) {
                VStack(alignment: .leading, spacing: 6) {
                    InboxPickerField(
                        label: "Value",
                        title: choices.actionPlaceholder(a.type),
                        options: options,
                        value: a.value.isEmpty ? nil : a.value,
                        placeholder: choices.actionPlaceholder(a.type),
                        createTitle: a.type == "add_tag" ? { "Create \u{201C}\($0)\u{201D}" } : nil
                    ) { a.value = $0 }
                    if a.type == "set_reply_address" { hint("Must be an address of the ticket's brand; skipped otherwise.") }
                    if a.type == "run_procedure" {
                        hint("Ollie works the ticket by it: internal notes, labels, priority and connected tools set to run without asking. It never replies to the customer.")
                        InboxSettingLink(title: options.isEmpty ? "Write a procedure" : "Manage procedures", page: .procedures)
                    }
                }
            }
        }
        if !AutomationVocabulary.actionFits(a.type, trigger) {
            FormError(text: a.type == "run_procedure" ? "Ollie can't run a procedure when a ticket is updated. Pick another trigger." : "Merge into the contact's open ticket runs only when a ticket is created.")
        }
    }

    @ViewBuilder
    private var setField: some View {
        let ticketFields = choices.fields.filter { $0.entity == "ticket" && (!$0.archived || $0.key == a.field) }
        InboxPickerField(
            label: "Field",
            title: "Choose a field",
            options: ticketFields.map { InboxOption(value: $0.key, label: $0.name, symbol: $0.type.symbol, keywords: [$0.key]) },
            value: a.field,
            placeholder: "Choose a field"
        ) { key in
            a.field = key
            a.value = ""
        }
        if let key = a.field, let field = ticketFields.first(where: { $0.key == key }) {
            AutomationFieldValue(field: field, op: "eq", value: $a.value, choices: choices, allowClear: true)
            hint("Leave empty to clear")
        }
    }

    private func mergeLabel(_ n: Int) -> String { n == 1 ? "Within 1 day" : "Within \(n) days" }

    private func hint(_ text: String) -> some View {
        Text(text).font(ODFont.footnote).foregroundStyle(Theme.fg3).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Custom field values

/// A value for a custom field rule or set_field, by the field's type. Lists are comma-joined ids.
struct AutomationFieldValue: View {
    let field: CustomField
    let op: String
    @Binding var value: String
    let choices: AutomationChoices
    let allowClear: Bool

    @State private var picking = false

    private var multiple: Bool {
        if field.type == .multiSelect { return allowClear || (op != "eq" && op != "ne") }
        return AutomationVocabulary.fieldOpTakesList(op)
    }

    var body: some View {
        if !AutomationVocabulary.fieldOpTakesValue(op) {
            Text("No value needed").font(ODFont.footnote).foregroundStyle(Theme.fg3)
        } else {
            switch field.type {
            case .select, .multiSelect, .user:
                options
            case .checkbox:
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(field.name) value").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
                    AccountSegmented(options: ["true", "false"], selection: Binding(get: { value == "false" ? "false" : "true" }, set: { value = $0 })) { $0 == "true" ? "Yes" : "No" }
                }
                .onAppear { if value.isEmpty && !allowClear { value = "true" } }
            case .date:
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(field.name) value").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
                    HStack {
                        DatePicker("\(field.name) value", selection: Binding(get: { Self.date(value) ?? .now }, set: { value = Self.iso($0) }), displayedComponents: .date)
                            .labelsHidden()
                        if allowClear && !value.isEmpty {
                            Button("Clear") { value = "" }.font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg3)
                        }
                    }
                }
            case .number:
                ODTextField(label: "\(field.name) value", text: $value, prompt: "0", keyboard: .decimalPad, submitLabel: .done)
            default:
                ODTextField(label: "\(field.name) value", text: $value, prompt: "", keyboard: field.type == .email ? .emailAddress : field.type == .url ? .URL : .default, submitLabel: .done)
                    .textInputAutocapitalization(.never)
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        let all = choices.fieldValueOptions(field)
        let isUser = field.type == .user
        if multiple {
            let ids = value.split(separator: ",").map(String.init)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(field.name) value").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
                Button { picking = true } label: {
                    InboxFieldBox(
                        value: ids.isEmpty ? (isUser ? "Choose people" : "Choose options") : choices.fieldValueLabel(AutomationVocabulary.ref(of: field), value),
                        placeholder: ids.isEmpty
                    )
                }
                .buttonStyle(TapScaleStyle(scale: 0.99))
            }
            .sheet(isPresented: $picking) {
                InboxOptionSheet(title: isUser ? "Choose people" : "Choose options", options: all, multiple: true, selected: Set(ids)) { picked in
                    value = all.map(\.value).filter { picked.contains($0) }.joined(separator: ",")
                }
                .presentationDetents([.medium, .large])
            }
        } else {
            InboxPickerField(
                label: "\(field.name) value",
                title: isUser ? "Choose a person" : "Choose an option",
                options: all,
                value: value.isEmpty ? nil : value,
                placeholder: isUser ? "Choose a person" : "Choose an option"
            ) { value = $0 }
        }
    }

    private static func date(_ iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func iso(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
