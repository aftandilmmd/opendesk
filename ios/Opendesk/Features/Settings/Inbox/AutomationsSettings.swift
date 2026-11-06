import SwiftUI

/// Settings › Automations, natively: rules that run on their own, in order, top to bottom.
struct AutomationsSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store = AutomationsStore()
    @State private var confirm: AccountConfirm?
    @State private var editMode: EditMode = .inactive
    @State private var started = false

    private var canEdit: Bool { env.session.isAdmin }

    var body: some View {
        InboxLoadGate(load: store.load, retry: { await store.reload() }) {
            list
        }
        .accountTitle(SettingsPage.automations.title)
        .toolbar {
            if canEdit, store.load == .ready {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if store.automations.count > 1 {
                        Button(editMode.isEditing ? "Done" : "Reorder") {
                            withAnimation(Motion.snappy) { editMode = editMode.isEditing ? .inactive : .active }
                        }
                        .fontWeight(editMode.isEditing ? .semibold : .regular)
                    }
                    Button { env.router.openSetting(.automations, id: "new") } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New automation")
                }
            }
        }
        .accountConfirm($confirm)
        .task {
            await store.start(api: env.session.api, lookups: false)
            started = true
        }
        .onAppear {
            // Back from an automation: show what it saved.
            if started { Task { await store.reload() } }
        }
    }

    private var list: some View {
        List {
            intro
            rulesSection
        }
        .inboxListStyle()
        .environment(\.editMode, $editMode)
        .refreshable { await store.reload() }
        .motion(Motion.snappy, value: store.automations.map(\.id))
    }

    private var intro: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rules that run on their own when something happens to a ticket. They run in order, top to bottom.")
                    .font(ODFont.footnote)
                    .foregroundStyle(Theme.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                if !canEdit { SettingsReadOnlyNote() }
                if !store.automations.isEmpty { InboxStatStrip(items: stats) }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            .listRowBackground(Color.clear)
        }
    }

    private var stats: [InboxStatStrip.Item] {
        let active = store.automations.filter(\.enabled).count
        let paused = store.automations.count - active
        let runs = store.automations.reduce(0) { $0 + $1.runCount }
        return [
            .init(label: "Automations", value: "\(store.automations.count)"),
            .init(label: "Active", value: "\(active)", tone: .green),
            .init(label: "Paused", value: "\(paused)", tone: paused > 0 ? .amber : nil),
            .init(label: "Runs", value: InboxText.compact(runs)),
        ]
    }

    private var rulesSection: some View {
        Section {
            if store.automations.isEmpty {
                emptyRow
            } else {
                ForEach(store.automations) { rule in row(rule) }
                    .onMove(perform: canEdit ? { move(from: $0, to: $1) } : nil)
            }
        }
    }

    private var emptyRow: some View {
        let create: (() -> Void)? = canEdit ? { env.router.openSetting(.automations, id: "new") } : nil
        return EmptyState(
            symbol: "bolt",
            title: "No automations yet",
            message: "Route billing mail to the billing team, label urgent words, or close spam without lifting a finger.",
            actionTitle: canEdit ? "New automation" : nil,
            action: create
        )
        .listRowBackground(Theme.surface)
    }

    private func row(_ rule: AutomationRule) -> some View {
        SettingsDetailLink(page: .automations, id: rule.id) {
            AutomationRow(rule: rule, canEdit: canEdit) { value in run { try await store.setEnabled(rule, value) } }
        }
        .inboxListRow()
        .contextMenu {
            if canEdit {
                Button { env.router.openSetting(.automations, id: rule.id) } label: { Label("Edit", systemImage: "pencil") }
                Button { run { try await store.setEnabled(rule, !rule.enabled) } } label: {
                    Label(rule.enabled ? "Pause" : "Turn on", systemImage: rule.enabled ? "pause.circle" : "play.circle")
                }
                Divider()
                Button(role: .destructive) { askDelete(rule) } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canEdit {
                Button(role: .destructive) { askDelete(rule) } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private func move(from: IndexSet, to: Int) {
        var ids = store.automations.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        run { try await store.reorder(ids) }
    }

    private func askDelete(_ rule: AutomationRule) {
        confirm = AccountConfirm(
            title: "Delete this automation?",
            message: "\(rule.name) stops running. Tickets it already changed stay as they are.",
            confirmTitle: "Delete"
        ) {
            do {
                try await store.delete(rule)
                Haptics.success()
            } catch {
                env.toasts.error(error)
            }
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        Task {
            do { try await work() } catch { env.toasts.error(error) }
        }
    }

    /// One automation's editor; "new" creates one.
    struct Detail: View {
        let id: String

        var body: some View {
            AutomationEditor(id: id)
        }
    }
}

private struct AutomationRow: View {
    let rule: AutomationRule
    let canEdit: Bool
    let toggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            AccountIconTile(symbol: rule.trigger.symbol, tone: rule.enabled ? rule.trigger.tone : .gray)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rule.name).font(ODFont.sans(15, weight: .medium)).foregroundStyle(rule.enabled ? Theme.fg : Theme.fg2).lineLimit(1)
                    if !rule.enabled { TonePill(text: "Paused", tone: .gray, height: 18) }
                }
                Text([
                    rule.trigger.short,
                    InboxText.count(rule.conditions.count, "condition", "conditions"),
                    InboxText.count(rule.actions.count, "action", "actions"),
                    "\(InboxText.compact(rule.runCount)) runs",
                ].joined(separator: " \u{00B7} "))
                .font(ODFont.footnote)
                .foregroundStyle(Theme.fg3)
                .lineLimit(1)
            }
            Spacer(minLength: 6)
            Toggle("Enable \(rule.name)", isOn: Binding(get: { rule.enabled }, set: { toggle($0) }))
                .labelsHidden()
                .tint(Tone.green.solid)
                .disabled(!canEdit)
            Chevron()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}

// MARK: - Editor

/// When, if and then: the web's automation builder, with each condition and action edited in a sheet.
private struct AutomationEditor: View {
    let id: String

    @Environment(AppEnvironment.self) private var env
    @State private var store = AutomationsStore()
    @State private var draft: AutomationsStore.Draft?
    @State private var initial: AutomationsStore.Draft?
    @State private var showErrors = false
    @State private var error: String?
    @State private var saving = false
    @State private var editingCondition: Int?
    @State private var editingAction: Int?
    @State private var confirm: AccountConfirm?

    private var isNew: Bool { id == "new" }
    private var existing: AutomationRule? { store.rule(id) }
    private var canEdit: Bool { env.session.isAdmin }
    private var dirty: Bool { draft != nil && draft != initial }
    private var choices: AutomationChoices { AutomationChoices(directory: env.directory, store: store) }

    var body: some View {
        content
            .accountTitle(isNew ? "New automation" : (draft?.name.isEmpty == false ? draft!.name : "Automation"))
            .toolbar {
                if canEdit, draft != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isNew ? "Create" : "Save", action: save)
                            .fontWeight(.semibold)
                            .disabled(saving || (!isNew && !dirty))
                    }
                }
            }
            .sheet(item: Binding(get: { editingCondition.map(EditIndex.init) }, set: { editingCondition = $0?.index })) { edit in
                if let draft, draft.conditions.indices.contains(edit.index) {
                    AutomationConditionSheet(choices: choices, trigger: draft.trigger, initial: draft.conditions[edit.index]) { value in
                        self.draft?.conditions[edit.index] = value
                    }
                    .presentationDetents([.large])
                    .presentationCornerRadius(Theme.Radius.sheet)
                }
            }
            .sheet(item: Binding(get: { editingAction.map(EditIndex.init) }, set: { editingAction = $0?.index })) { edit in
                if let draft, draft.actions.indices.contains(edit.index) {
                    AutomationActionSheet(choices: choices, trigger: draft.trigger, initial: draft.actions[edit.index]) { value in
                        self.draft?.actions[edit.index] = value
                    }
                    .presentationDetents([.large])
                    .presentationCornerRadius(Theme.Radius.sheet)
                }
            }
            .accountConfirm($confirm)
            .task {
                await store.start(api: env.session.api, lookups: true)
                fill()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch store.load {
        case .loading:
            ScrollView { Panel { SkeletonRows(count: 4) }.padding(16) }
                .background(Theme.chrome.ignoresSafeArea())
        case let .failed(message):
            ErrorState(message: message) { Task { await store.reload(); fill() } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.chrome.ignoresSafeArea())
        case .ready:
            if let draft {
                editor(draft)
            } else {
                EmptyState(symbol: "bolt.slash", title: "Automation not found", message: "It may have been deleted.", actionTitle: "Back to automations") {
                    if !env.router.accountPath.isEmpty { env.router.accountPath.removeLast() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.chrome.ignoresSafeArea())
            }
        }
    }

    private func editor(_ draft: AutomationsStore.Draft) -> some View {
        let problems = AutomationVocabulary.problems(name: draft.name, trigger: draft.trigger, conditions: draft.conditions, actions: draft.actions)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(isNew ? "Choose when it runs, what has to match, and what it does." : "Ran \((existing?.runCount ?? 0).formatted()) times")
                        .font(ODFont.footnote)
                        .foregroundStyle(Theme.fg3)
                    if !canEdit { SettingsReadOnlyNote() }
                    HStack(alignment: .bottom, spacing: 10) {
                        ODTextField(label: "Name", text: binding.name, prompt: "Route billing mail to the billing team", submitLabel: .done)
                        HStack(spacing: 8) {
                            Circle().fill(draft.enabled ? Tone.green.solid : Theme.fg4).frame(width: 6, height: 6)
                            Text(draft.enabled ? "On" : "Off").font(ODFont.sans(13, weight: .medium)).foregroundStyle(draft.enabled ? Tone.green.text : Theme.fg3)
                            Toggle("Automation enabled", isOn: binding.enabled).labelsHidden().tint(Tone.green.solid)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 44)
                        .background(draft.enabled ? Tone.green.solid.opacity(0.1) : Theme.hover, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    }
                    if showErrors && draft.name.trimmingCharacters(in: .whitespaces).isEmpty { FormError(text: "Name the automation.") }
                }

                step(1, "When", tone: .blue) {
                    Panel {
                        HStack(spacing: 12) {
                            AccountIconTile(symbol: draft.trigger.symbol, tone: draft.trigger.tone)
                            Menu {
                                Picker("Trigger", selection: Binding(get: { draft.trigger }, set: { setTrigger($0) })) {
                                    ForEach(AutomationTrigger.allCases.filter { $0 != .callEnded || store.hasPhone || draft.trigger == .callEnded }) { trigger in
                                        Text(trigger.title).tag(trigger)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(draft.trigger.title).font(ODFont.sans(15, weight: .medium)).foregroundStyle(Theme.fg)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.fg4)
                                }
                                .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Trigger, \(draft.trigger.title)")
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 54)
                    }
                }

                step(2, draft.conditions.isEmpty ? "For every ticket" : "If all of these match", hint: draft.conditions.isEmpty ? "No conditions: the actions run every time." : nil, tone: .amber) {
                    Panel {
                        ForEach(Array(draft.conditions.enumerated()), id: \.offset) { index, condition in
                            if index > 0 { Hairline() }
                            builderRow(
                                lead: index == 0 ? "If" : "and",
                                text: choices.summary(condition),
                                symbol: AutomationVocabulary.aiFields.contains(condition.field) ? "sparkles" : nil,
                                invalid: showErrors && AutomationVocabulary.conditionInvalid(condition),
                                open: { editingCondition = index },
                                remove: { self.draft?.conditions.remove(at: index) },
                                removeLabel: "Remove condition"
                            )
                        }
                        if !draft.conditions.isEmpty { Hairline() }
                        addRow("Add condition") {
                            self.draft?.conditions.append(AutomationCondition(field: "subject", op: "contains", value: ""))
                            editingCondition = (self.draft?.conditions.count ?? 1) - 1
                        }
                    }
                }

                step(3, "Then", tone: .green) {
                    Panel {
                        ForEach(Array(draft.actions.enumerated()), id: \.offset) { index, action in
                            if index > 0 { Hairline() }
                            builderRow(
                                lead: "Do",
                                text: choices.summary(action),
                                symbol: AutomationVocabulary.actionSymbol(action.type),
                                invalid: showErrors && AutomationVocabulary.actionInvalid(action, trigger: draft.trigger),
                                open: { editingAction = index },
                                remove: { self.draft?.actions.remove(at: index) },
                                removeLabel: "Remove action"
                            )
                        }
                        if draft.actions.isEmpty {
                            Text("Add at least one action.")
                                .font(ODFont.footnote)
                                .foregroundStyle(showErrors ? Tone.red.text : Theme.fg3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.top, 12)
                        } else {
                            Hairline()
                        }
                        addRow("Add action") {
                            self.draft?.actions.append(AutomationAction(type: "add_tag"))
                            editingAction = (self.draft?.actions.count ?? 1) - 1
                        }
                    }
                }

                if error != nil || (showErrors && !problems.isEmpty) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let error { Text(error).font(ODFont.footnote).foregroundStyle(Tone.red.text) }
                        if showErrors {
                            ForEach(problems, id: \.self) { problem in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Circle().fill(Tone.red.solid).frame(width: 5, height: 5)
                                    Text(problem).font(ODFont.footnote).foregroundStyle(Theme.fg2).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tone.red.solid.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Tone.red.line, lineWidth: 1))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if canEdit {
                    VStack(spacing: 10) {
                        Button(action: save) { ButtonLabel(title: isNew ? "Create automation" : "Save", busy: saving) }
                            .buttonStyle(InkButtonStyle())
                            .disabled(saving || (!isNew && !dirty))
                        if let existing {
                            Button("Delete") { askDelete(existing) }
                                .buttonStyle(AccountDangerButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
            .disabled(!canEdit)
            .motion(Motion.snappy, value: draft)
            .motion(Motion.snappy, value: showErrors)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.chrome.ignoresSafeArea())
        .onChange(of: draft.name) { _, value in
            if value.count > 80 { self.draft?.name = String(value.prefix(80)) }
        }
    }

    // MARK: Parts

    private var binding: Binding<AutomationsStore.Draft> {
        Binding(get: { draft ?? AutomationsStore.Draft() }, set: { draft = $0 })
    }

    private func step<Content: View>(_ n: Int, _ title: String, hint: String? = nil, tone: Tone, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(n)")
                    .font(ODFont.mono(11, weight: .semibold))
                    .foregroundStyle(tone.text)
                    .frame(width: 22, height: 22)
                    .background(tone.solid.opacity(0.13), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(title).font(ODFont.sans(14.5, weight: .semibold)).foregroundStyle(Theme.fg)
            }
            if let hint { Text(hint).font(ODFont.footnote).foregroundStyle(Theme.fg3).padding(.leading, 30) }
            content()
        }
    }

    private func builderRow(lead: String, text: String, symbol: String?, invalid: Bool, open: @escaping () -> Void, remove: @escaping () -> Void, removeLabel: String) -> some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(lead).font(ODFont.sans(12.5)).foregroundStyle(Theme.fg4).frame(width: 28, alignment: .leading)
                    if let symbol { Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Theme.fg3) }
                    Text(text)
                        .font(ODFont.sans(14.5))
                        .foregroundStyle(invalid ? Tone.red.text : Theme.fg)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if invalid { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 12)).foregroundStyle(Tone.red.solid) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.fg4).frame(width: 30, height: 30)
            }
            .accessibilityLabel(removeLabel)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
    }

    private func addRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(ODFont.sans(13.5, weight: .medium))
                .foregroundStyle(Theme.fg2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    // MARK: Actions

    private func fill() {
        guard draft == nil, store.load == .ready else { return }
        if isNew {
            draft = AutomationsStore.Draft()
            initial = draft
        } else if let existing {
            draft = AutomationsStore.Draft(existing)
            initial = draft
        }
    }

    /// A new automation's blank first condition becomes a call one when it is about calls.
    private func setTrigger(_ trigger: AutomationTrigger) {
        guard var next = draft else { return }
        if trigger == .callEnded, next.conditions.count == 1, next.conditions[0].field == "subject", next.conditions[0].value.isEmpty {
            next.conditions = [AutomationCondition(field: "call_outcome", op: "equals", value: "missed")]
        }
        next.trigger = trigger
        draft = next
    }

    private func save() {
        guard let draft else { return }
        error = nil
        showErrors = true
        guard AutomationVocabulary.problems(name: draft.name, trigger: draft.trigger, conditions: draft.conditions, actions: draft.actions).isEmpty else {
            Haptics.error()
            return
        }
        saving = true
        Task {
            do {
                let saved = try await store.save(draft, existing: existing)
                Haptics.success()
                env.toasts.show(isNew ? "Automation created" : "Automation saved", kind: .success)
                let fresh = AutomationsStore.Draft(saved)
                self.draft = fresh
                initial = fresh
                showErrors = false
                if isNew, let index = env.router.accountPath.lastIndex(of: .detail(.automations, "new")) {
                    env.router.accountPath[index] = .detail(.automations, saved.id)
                }
            } catch {
                Haptics.error()
                self.error = error.userMessage
            }
            saving = false
        }
    }

    private func askDelete(_ rule: AutomationRule) {
        confirm = AccountConfirm(
            title: "Delete this automation?",
            message: "\(rule.name) stops running. Tickets it already changed stay as they are.",
            confirmTitle: "Delete"
        ) {
            do {
                try await store.delete(rule)
                Haptics.success()
                env.toasts.show("Automation deleted", kind: .success)
                initial = draft
                if let index = env.router.accountPath.lastIndex(of: .detail(.automations, rule.id)) {
                    env.router.accountPath.remove(at: index)
                }
            } catch {
                env.toasts.error(error)
            }
        }
    }

    private struct EditIndex: Identifiable {
        let index: Int
        var id: Int { index }
    }
}
