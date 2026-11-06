import SwiftUI

/// Settings › SLA policies, natively: targets checked top to bottom, the first enabled one
/// that matches a ticket's priority and team applies.
struct SLASettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store = SLAStore()
    @State private var editing: PolicyEdit?
    @State private var confirm: AccountConfirm?
    @State private var editMode: EditMode = .inactive

    private var canEdit: Bool { env.session.isAdmin }

    var body: some View {
        InboxLoadGate(load: store.load, retry: { await store.reload() }) {
            list
        }
        .accountTitle(SettingsPage.sla.title)
        .toolbar {
            if canEdit, store.load == .ready {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if store.policies.count > 1 {
                        Button(editMode.isEditing ? "Done" : "Reorder") {
                            withAnimation(Motion.snappy) { editMode = editMode.isEditing ? .inactive : .active }
                        }
                        .fontWeight(editMode.isEditing ? .semibold : .regular)
                    }
                    Button { editing = PolicyEdit(policy: nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New policy")
                }
            }
        }
        .sheet(item: $editing) { edit in
            SLAPolicyEditorSheet(store: store, policy: edit.policy, teams: env.directory.teams)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        .accountConfirm($confirm)
        .task { await store.start(api: env.session.api) }
    }

    private var list: some View {
        List {
            intro
            policiesSection
        }
        .inboxListStyle()
        .environment(\.editMode, $editMode)
        .refreshable { await store.reload() }
        .motion(Motion.snappy, value: store.policies.map(\.id))
    }

    private var intro: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Response and resolution targets. Policies are checked from top to bottom, and the first enabled one that matches a ticket's priority and team applies.")
                    .font(ODFont.footnote)
                    .foregroundStyle(Theme.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                if !canEdit { SettingsReadOnlyNote() }
                if !store.policies.isEmpty { InboxStatStrip(items: stats) }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            .listRowBackground(Color.clear)
        }
    }

    private var stats: [InboxStatStrip.Item] {
        let on = store.policies.filter(\.enabled)
        let reply = on.map(\.firstResponseMinutes).min().map { Format.minutes(Double($0)) } ?? "\u{2013}"
        let resolve = on.map(\.resolutionMinutes).min().map { Format.minutes(Double($0)) } ?? "\u{2013}"
        return [
            .init(label: "Policies", value: "\(store.policies.count)"),
            .init(label: "Enabled", value: "\(on.count)", tone: .green),
            .init(label: "Fastest reply", value: reply),
            .init(label: "Fastest resolution", value: resolve),
        ]
    }

    private var policiesSection: some View {
        Section {
            if store.policies.isEmpty {
                emptyRow
            } else {
                ForEach(Array(store.policies.enumerated()), id: \.element.id) { index, policy in
                    row(policy, number: index + 1)
                }
                .onMove(perform: canEdit ? { move(from: $0, to: $1) } : nil)
            }
        } footer: {
            Label("Due times are shown on tickets and in the list. A breach notifies the assignee.", systemImage: "timer")
                .font(ODFont.footnote)
                .foregroundStyle(Theme.fg3)
                .padding(.horizontal, 4)
        }
    }

    private var emptyRow: some View {
        let create: (() -> Void)? = canEdit ? { editing = PolicyEdit(policy: nil) } : nil
        return EmptyState(
            symbol: "timer",
            title: "No SLA policies",
            message: "Without a policy, tickets have no due times.",
            actionTitle: canEdit ? "New policy" : nil,
            action: create
        )
        .listRowBackground(Theme.surface)
    }

    private func row(_ policy: SLAPolicy, number: Int) -> some View {
        Button {
            if canEdit { editing = PolicyEdit(policy: policy) }
        } label: {
            SLAPolicyRow(
                policy: policy,
                number: number,
                team: policy.teamID.flatMap { id in env.directory.teams.first { $0.id == id } },
                canEdit: canEdit,
                toggle: { value in run { try await store.setEnabled(policy, value) } }
            )
        }
        .buttonStyle(RowPressStyle())
        .inboxListRow()
        .contextMenu {
            if canEdit {
                Button { editing = PolicyEdit(policy: policy) } label: { Label("Edit", systemImage: "pencil") }
                Divider()
                Button(role: .destructive) { askDelete(policy) } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canEdit {
                Button(role: .destructive) { askDelete(policy) } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private func move(from: IndexSet, to: Int) {
        var ids = store.policies.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        run { try await store.reorder(ids) }
    }

    private func askDelete(_ policy: SLAPolicy) {
        confirm = AccountConfirm(
            title: "Delete this policy?",
            message: "Tickets under \(policy.name) keep their current due times. New tickets fall through to the next matching policy.",
            confirmTitle: "Delete policy"
        ) {
            do {
                try await store.delete(policy)
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

    struct PolicyEdit: Identifiable {
        let id = UUID()
        var policy: SLAPolicy?
    }

    /// Policies have no page of their own: a link to one opens the list.
    struct Detail: View {
        let id: String

        var body: some View {
            SLASettings()
        }
    }
}

/// How tight a target is, as the web tints it.
enum SLATarget {
    case reply, resolve

    func tone(_ minutes: Int) -> Tone {
        let hot = self == .reply ? 60 : 8 * 60
        let warm = self == .reply ? 4 * 60 : 24 * 60
        return minutes <= hot ? .red : minutes <= warm ? .amber : .gray
    }
}

private struct SLAPolicyRow: View {
    let policy: SLAPolicy
    let number: Int
    let team: Team?
    let canEdit: Bool
    let toggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(ODFont.mono(11))
                .foregroundStyle(Theme.fg4)
                .frame(width: 16)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(policy.name).font(ODFont.sans(15, weight: .medium)).foregroundStyle(policy.enabled ? Theme.fg : Theme.fg2).lineLimit(1)
                    if !policy.enabled { TonePill(text: "Off", tone: .gray, height: 18) }
                }
                HStack(spacing: 5) {
                    if let priority = policy.priority { PriorityPill(priority: priority) } else { TonePill(text: "All priorities", tone: .gray) }
                    if let team { InboxTagChip(name: team.name, tone: Theme.avatarTone(for: team.id)) }
                }
                FlowRow {
                    target("First response", policy.firstResponseMinutes, .reply)
                    target("Resolution", policy.resolutionMinutes, .resolve)
                    if policy.businessHours {
                        TonePill(text: "Business hours", tone: .gray, height: 20) {
                            Image(systemName: "clock").font(.system(size: 9, weight: .semibold))
                        }
                    }
                }
            }
            Spacer(minLength: 6)
            Toggle("Enable \(policy.name)", isOn: Binding(get: { policy.enabled }, set: { toggle($0) }))
                .labelsHidden()
                .tint(Tone.green.solid)
                .disabled(!canEdit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func target(_ label: String, _ minutes: Int, _ kind: SLATarget) -> some View {
        let tone = policy.enabled ? kind.tone(minutes) : .gray
        return HStack(spacing: 4) {
            Image(systemName: "clock").font(.system(size: 9, weight: .semibold)).opacity(0.7)
            Text(label).font(ODFont.sans(11))
            Text(Format.minutes(Double(minutes))).font(ODFont.mono(11, weight: .medium))
        }
        .foregroundStyle(tone == .gray ? Theme.fg2 : tone.text)
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(tone == .gray ? Theme.sunken : tone.solid.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
    }
}

/// Chips that wrap onto a new line when they run out of room.
private struct FlowRow: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

// MARK: - Editor

private struct SLAPolicyEditorSheet: View {
    let store: SLAStore
    let policy: SLAPolicy?
    let teams: [Team]

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var priority: Priority?
    @State private var teamID: String?
    @State private var reply = SLADuration(total: 60)
    @State private var resolve = SLADuration(total: 1440)
    @State private var businessHours = false
    @State private var saving = false
    @State private var error: String?
    @State private var loaded = false

    private var problem: String? {
        guard let first = reply.minutes, let second = resolve.minutes else { return "Enter each time as a number, from 1 minute to 365 days." }
        if second < first { return "Resolution can't be sooner than the first response." }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AccountSheetHeader(
                    title: policy == nil ? "New SLA policy" : "Edit SLA policy",
                    subtitle: "Targets count every minute unless the policy counts business hours only."
                ) { dismiss() }
                ODTextField(label: "Name", text: $name, prompt: "Urgent tickets", submitLabel: .done)
                HStack(spacing: 10) {
                    InboxMenuField(label: "Applies to", value: priority.map { "\($0.title) priority" } ?? "Any priority", symbol: "flag", tone: priority?.tone) {
                        Picker("Applies to", selection: $priority) {
                            Text("Any priority").tag(Priority?.none)
                            ForEach(Priority.allCases) { value in Text("\(value.title) priority").tag(Priority?.some(value)) }
                        }
                    }
                    if !teams.isEmpty {
                        InboxMenuField(label: "Team", value: teams.first { $0.id == teamID }?.name ?? "Any team", symbol: "person.3") {
                            Picker("Team", selection: $teamID) {
                                Text("Any team").tag(String?.none)
                                ForEach(teams) { team in Text(team.name).tag(String?.some(team.id)) }
                            }
                        }
                    }
                }
                durationField("First response within", $reply, current: policy?.firstResponseMinutes)
                durationField("Resolve within", $resolve, current: policy?.resolutionMinutes)
                VStack(alignment: .leading, spacing: 6) {
                    InboxSwitchBox(title: "Count business hours only", hint: "The clock pauses outside business hours and on holidays.", isOn: $businessHours)
                    if businessHours && !store.hoursEnabled {
                        HStack(spacing: 6) {
                            Text("Business hours are off, so every minute counts until you turn them on.")
                                .font(ODFont.footnote)
                                .foregroundStyle(Tone.amber.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button("Set business hours") {
                        dismiss()
                        env.router.accountPath.append(.setting(.businessHours))
                    }
                    .font(ODFont.sans(13, weight: .medium))
                    .foregroundStyle(Theme.fg2)
                }
                FormError(text: error ?? (reply.minutes != nil && resolve.minutes != nil ? problem : nil))
                Button(action: save) { ButtonLabel(title: policy == nil ? "Create policy" : "Save policy", busy: saving) }
                    .buttonStyle(InkButtonStyle())
                    .disabled(saving)
            }
            .padding(22)
            .motion(Motion.snappy, value: error)
            .motion(Motion.snappy, value: businessHours)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.surface)
        .onAppear(perform: fill)
        .onChange(of: name) { _, value in
            if value.count > 80 { name = String(value.prefix(80)) }
            error = nil
        }
    }

    private func durationField(_ label: String, _ value: Binding<SLADuration>, current: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
            HStack(spacing: 8) {
                TextField("", text: value.text)
                    .keyboardType(.numberPad)
                    .font(ODFont.mono(15))
                    .padding(.horizontal, 12)
                    .frame(width: 96, height: 40)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(value.wrappedValue.minutes == nil ? Tone.red.solid : Theme.line, lineWidth: 1))
                    .accessibilityLabel(label)
                AccountSegmented(options: SLADuration.Unit.allCases, selection: value.unit, label: \.title, height: 40)
            }
            if let current, value.wrappedValue.minutes != current {
                Text("Currently \(Format.minutes(Double(current)))").font(ODFont.footnote).foregroundStyle(Theme.fg4)
            }
        }
    }

    private func fill() {
        guard !loaded else { return }
        loaded = true
        guard let policy else { return }
        name = policy.name
        priority = policy.priority
        teamID = policy.teamID
        reply = SLADuration(total: policy.firstResponseMinutes)
        resolve = SLADuration(total: policy.resolutionMinutes)
        businessHours = policy.businessHours
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { error = "Give the policy a name."; return }
        if let problem { error = problem; return }
        guard let first = reply.minutes, let second = resolve.minutes else { return }
        saving = true
        error = nil
        let body: [String: JSONValue] = [
            "name": .string(trimmed),
            "priority": priority.map { .string($0.rawValue) } ?? .null,
            "team_id": teamID.map(JSONValue.string) ?? .null,
            "first_response_minutes": .number(Double(first)),
            "resolution_minutes": .number(Double(second)),
            "business_hours": .bool(businessHours),
        ]
        Task {
            do {
                try await store.save(body, existing: policy)
                Haptics.success()
                env.toasts.show(policy == nil ? "Policy created" : "Policy saved", kind: .success)
                dismiss()
            } catch {
                Haptics.error()
                self.error = error.userMessage
            }
            saving = false
        }
    }
}

/// A target typed as a number and a unit, as the web's duration field.
struct SLADuration: Equatable {
    enum Unit: String, CaseIterable, Hashable {
        case m, h, d
        var title: String {
            switch self {
            case .m: "Minutes"
            case .h: "Hours"
            case .d: "Days"
            }
        }
        var factor: Int {
            switch self {
            case .m: 1
            case .h: 60
            case .d: 1440
            }
        }
    }

    var text: String
    var unit: Unit

    init(total: Int) {
        if total > 0 && total % 1440 == 0 {
            text = "\(total / 1440)"
            unit = .d
        } else if total > 0 && total % 60 == 0 {
            text = "\(total / 60)"
            unit = .h
        } else {
            text = "\(total)"
            unit = .m
        }
    }

    /// 1 minute to 365 days, or nil when it isn't a whole number in that range.
    var minutes: Int? {
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)), n > 0 else { return nil }
        let total = n * unit.factor
        return total <= 525_600 ? total : nil
    }
}

// MARK: - Store

@MainActor
@Observable
final class SLAStore {
    private(set) var policies: [SLAPolicy] = []
    private(set) var hoursEnabled = true
    private(set) var load: InboxLoad = .loading

    @ObservationIgnored private var api: APIClient?

    func start(api: APIClient) async {
        self.api = api
        await reload()
    }

    func reload() async {
        guard let api else { return }
        do {
            async let page: Page<SLAPolicy> = api.get("v1/sla-policies")
            async let hours: HoursConfig? = try? api.get("v1/business-hours")
            policies = try await page.data.sorted { $0.position < $1.position }
            if let value = await hours { hoursEnabled = value.enabled }
            load = .ready
        } catch {
            if error.isCancellation { return }
            if load != .ready { load = .failed(error.userMessage) }
        }
    }

    func save(_ body: [String: JSONValue], existing: SLAPolicy?) async throws {
        guard let api else { throw APIError.signedOut }
        if let existing {
            let saved: SLAPolicy = try await api.patch("v1/sla-policies/\(existing.id)", body: JSONValue.object(body))
            upsert(saved)
        } else {
            var body = body
            body["enabled"] = .bool(true)
            body["position"] = .number(Double(policies.count))
            let saved: SLAPolicy = try await api.post("v1/sla-policies", body: JSONValue.object(body))
            upsert(saved)
        }
    }

    func setEnabled(_ policy: SLAPolicy, _ enabled: Bool) async throws {
        guard let api else { return }
        let before = policies
        if let index = policies.firstIndex(where: { $0.id == policy.id }) { policies[index].enabled = enabled }
        do {
            let saved: SLAPolicy = try await api.patch("v1/sla-policies/\(policy.id)", body: ["enabled": enabled])
            upsert(saved)
        } catch {
            policies = before
            throw error
        }
    }

    func delete(_ policy: SLAPolicy) async throws {
        guard let api else { return }
        try await api.delete("v1/sla-policies/\(policy.id)")
        policies.removeAll { $0.id == policy.id }
    }

    /// Positions follow the new order; only the policies that moved are written, as on the web.
    func reorder(_ ids: [String]) async throws {
        guard let api else { return }
        let before = policies
        var next: [SLAPolicy] = ids.compactMap { id in policies.first { $0.id == id } }
        for index in next.indices { next[index].position = index }
        let changed = next.filter { moved in before.first { $0.id == moved.id }?.position != moved.position }
        policies = next
        do {
            for policy in changed {
                let _: SLAPolicy = try await api.patch("v1/sla-policies/\(policy.id)", body: ["position": policy.position])
            }
        } catch {
            policies = before
            throw error
        }
    }

    private func upsert(_ policy: SLAPolicy) {
        if let index = policies.firstIndex(where: { $0.id == policy.id }) { policies[index] = policy } else { policies.append(policy) }
        policies.sort { $0.position < $1.position }
    }
}
