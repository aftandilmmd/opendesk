import SwiftUI

/// Settings › Triage, natively: what Ollie may set on a new ticket, how sure it has to be,
/// and whether the ticket is assigned afterwards.
struct TriageSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store = TriageStore()
    @State private var threshold = 0.8
    @State private var sliding = false

    private var name: String { env.directory.ai.assistantName ?? "Ollie" }
    private var canEdit: Bool { env.session.isAdmin }

    var body: some View {
        InboxLoadGate(load: store.load, retry: { await store.reload() }) {
            if let config = store.config { page(config) }
        }
        .accountTitle(SettingsPage.triage.title)
        .task { await store.start(api: env.session.api) }
    }

    private func page(_ config: TriageConfig) -> some View {
        let off = !config.available
        let disabled = !canEdit || off
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(name) reads each new ticket and sorts it, so your team starts with the right priority and labels.")
                        .font(ODFont.footnote)
                        .foregroundStyle(Theme.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                    if !canEdit { SettingsReadOnlyNote() }
                    if off { unavailable }
                    explainer(config)
                }

                AccountSection(title: "Decision engine") {
                    engineRow(config.engine)
                    AccountDivider(tiles: false)
                    thresholdRow(config, disabled: disabled)
                }

                Group {
                    AccountSection(title: "Triage") {
                        AccountToggleRow(
                            symbol: "sparkles",
                            tone: .violet,
                            title: "Triage new tickets",
                            subtitle: "\(name) looks at every new ticket as soon as it arrives.",
                            isOn: Binding(get: { config.autoTriage }, set: { value in run { try await store.set(["auto_triage": .bool(value)]) { $0.autoTriage = value } } }),
                            disabled: disabled
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("What \(name) may change").padding(.horizontal, 4)
                        Panel {
                            let shown = TriageField.allCases.filter { $0 != .severity || store.severityEnabled }
                            ForEach(Array(shown.enumerated()), id: \.element) { index, field in
                                if index > 0 { AccountDivider() }
                                AccountToggleRow(
                                    symbol: field.symbol,
                                    title: field.title,
                                    subtitle: field.hint,
                                    isOn: Binding(get: { config.fields.contains(field) }, set: { on in toggle(field, on, config) }),
                                    disabled: disabled
                                )
                            }
                        }
                        HStack(spacing: 10) {
                            Text("Always recorded:")
                            Label("Sentiment", systemImage: "face.smiling")
                            Label("Language", systemImage: "globe")
                            Label("Category", systemImage: "tag")
                        }
                        .labelStyle(TriageInlineLabel())
                        .font(ODFont.footnote)
                        .foregroundStyle(Theme.fg3)
                        .padding(.horizontal, 4)
                        Text("Pick what triage is allowed to set on a ticket.")
                            .font(ODFont.footnote)
                            .foregroundStyle(Theme.fg3)
                            .padding(.horizontal, 4)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        AccountSection(title: "After triage") {
                            AccountToggleRow(
                                symbol: "person.crop.circle.badge.checkmark",
                                title: "Assign after triage",
                                subtitle: store.assignMode == .none
                                    ? "Assignment is off, so the ticket goes to whoever has the fewest open tickets."
                                    : "The ticket is then assigned with your \(store.assignMode.title.lowercased()) mode.",
                                isOn: Binding(get: { config.assignAfterTriage }, set: { value in run { try await store.set(["assign_after_triage": .bool(value)]) { $0.assignAfterTriage = value } } }),
                                disabled: disabled
                            )
                        }
                        InboxSettingLink(title: "Assignment settings", page: .assignment)
                            .padding(.horizontal, 4)
                    }
                }
                .opacity(off ? 0.6 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
            .motion(Motion.snappy, value: config)
        }
        .background(Theme.chrome.ignoresSafeArea())
        .refreshable { await store.reload() }
        .onAppear { threshold = config.threshold }
        .onChange(of: config.threshold) { _, value in if !sliding { threshold = value } }
    }

    // MARK: Parts

    private var unavailable: some View {
        HStack(spacing: 12) {
            AccountIconTile(symbol: "cpu", tone: .violet, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI is not set up").font(ODFont.sans(14.5, weight: .medium)).foregroundStyle(Theme.fg)
                Text("\(name) needs an AI provider before it can triage tickets.").font(ODFont.footnote).foregroundStyle(Theme.fg2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if canEdit {
                Button { env.router.accountPath.append(.setting(.ai)) } label: {
                    Text("Open AI settings").font(ODFont.sans(13, weight: .medium))
                }
                .buttonStyle(OutlineButtonStyle())
                .fixedSize()
            }
        }
        .padding(12)
        .background(Tone.violet.solid.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Tone.violet.line, lineWidth: 1))
    }

    private func explainer(_ config: TriageConfig) -> some View {
        let on = config.available && config.autoTriage
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("How \(name) triages").font(ODFont.sans(14.5, weight: .semibold)).foregroundStyle(Theme.fg)
                    TonePill(text: on ? "On" : "Off", tone: on ? .green : .gray, height: 18)
                }
                Text("Every change \(name) makes shows in the ticket timeline as made by \(name), so anyone can see why a ticket moved and change it back.")
                    .font(ODFont.footnote)
                    .foregroundStyle(Theme.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Charged twice for my annual plan").font(ODFont.sans(13.5, weight: .medium)).foregroundStyle(Theme.fg).lineLimit(1)
                    Text("Maria Lopez \u{00B7} just now").font(ODFont.sans(11.5)).foregroundStyle(Theme.fg4)
                    VStack(alignment: .leading, spacing: 5) {
                        if config.fields.contains(.priority) { sampleLine("arrow.up", "Priority raised to high", tone: .orange) }
                        if config.fields.contains(.severity) && store.severityEnabled { sampleLine("exclamationmark.triangle", "Severity set to Sev 2", tone: .red) }
                        if config.fields.contains(.labels) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles").font(.system(size: 10)).foregroundStyle(Tone.violet.text)
                                InboxTagChip(name: "Billing", tone: .green)
                                Text("label added").font(ODFont.sans(12)).foregroundStyle(Theme.fg2)
                            }
                        }
                        sampleLine("face.smiling", "Sentiment and language recorded", tone: .violet)
                        if config.assignAfterTriage { sampleLine("person.crop.circle.badge.checkmark", "Assigned to the next teammate", tone: .violet) }
                    }
                    .padding(.top, 4)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.lineSoft, lineWidth: 1))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Example of a triaged ticket")
            }
            .padding(14)
        }
    }

    private func sampleLine(_ symbol: String, _ text: String, tone: Tone) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(tone.text).frame(width: 14)
            Text(text).font(ODFont.sans(12)).foregroundStyle(Theme.fg2)
        }
    }

    private func engineRow(_ engine: TriageEngine) -> some View {
        let status: (String, Tone) = engine.isDecisionModel
            ? (engine.connected ? ("Connected", .green) : ("Not reachable", .amber))
            : engine.isLLM ? ("LLM fallback", .gray) : ("Not set up", .gray)
        let title = engine.isDecisionModel ? "Decision model" : engine.isLLM ? "LLM fallback" : "Engine"
        let hint = engine.isDecisionModel
            ? "Fast, typed decisions with calibrated confidence. \(name) applies a decision only when it is sure enough."
            : engine.isLLM
                ? "Your AI model answers the same questions, with no calibrated confidence. Set TYPESAFE_API_KEY to use the decision model instead."
                : "Set TYPESAFE_API_KEY or an AI provider key to let \(name) triage."
        return VStack(alignment: .leading, spacing: 6) {
            AccountRow(symbol: "cpu", tone: engine.isDecisionModel ? .violet : .gray, title: title, subtitle: hint) {
                TonePill(text: status.0, tone: status.1) {
                    Circle().fill(status.1.solid).frame(width: 6, height: 6)
                }
            }
            if !engine.model.isEmpty && !engine.isDecisionModel {
                Text(engine.model)
                    .font(ODFont.mono(11.5))
                    .foregroundStyle(Theme.fg4)
                    .padding(.leading, 56)
                    .padding(.bottom, 8)
                    .accessibilityLabel("Model \(engine.model)")
            }
        }
    }

    private func thresholdRow(_ config: TriageConfig, disabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Confidence to apply").font(ODFont.sans(15.5)).foregroundStyle(Theme.fg)
                Spacer()
                Text("\(Int((threshold * 100).rounded()))%")
                    .font(ODFont.mono(13.5, weight: .medium))
                    .foregroundStyle(Theme.fg)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Text("At or above this, \(name) applies a decision. Below it, the decision waits as a suggestion an agent accepts with one click." + (config.engine.isDecisionModel ? "" : " The LLM fallback has no calibrated confidence, so its decisions apply directly."))
                .font(ODFont.footnote)
                .foregroundStyle(Theme.fg3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text("Eager").font(ODFont.sans(11.5)).foregroundStyle(Theme.fg4)
                Slider(value: $threshold, in: 0.5...0.99, step: 0.01) { editing in
                    sliding = editing
                    if !editing, abs(threshold - config.threshold) > 0.001 {
                        let value = threshold
                        run { try await store.set(["threshold": .number(value)]) { $0.threshold = value } }
                    }
                }
                .tint(Theme.fg)
                .accessibilityLabel("Confidence to apply")
                .accessibilityValue("\(Int((threshold * 100).rounded()))%")
                Text("Cautious").font(ODFont.sans(11.5)).foregroundStyle(Theme.fg4)
            }
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func toggle(_ field: TriageField, _ on: Bool, _ config: TriageConfig) {
        let next = on ? TriageField.allCases.filter { $0 == field || config.fields.contains($0) } : config.fields.filter { $0 != field }
        run { try await store.set(["fields": .array(next.map { .string($0.rawValue) })]) { $0.fields = next } }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        Task {
            do { try await work() } catch { env.toasts.error(error) }
        }
    }

    /// Triage has no detail pages: a link to one opens the page.
    struct Detail: View {
        let id: String

        var body: some View {
            TriageSettings()
        }
    }
}

private struct TriageInlineLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 10)).foregroundStyle(Theme.fg4)
            configuration.title
        }
    }
}

// MARK: - Store

@MainActor
@Observable
final class TriageStore {
    private(set) var config: TriageConfig?
    private(set) var assignMode: AutoAssignMode = .none
    private(set) var severityEnabled = true
    private(set) var load: InboxLoad = .loading

    @ObservationIgnored private var api: APIClient?

    func start(api: APIClient) async {
        self.api = api
        await reload()
    }

    func reload() async {
        guard let api else { return }
        do {
            async let triage: TriageConfig = api.get("v1/triage")
            async let assignment: AutoAssignConfig? = try? api.get("v1/assignment")
            async let flags: InboxWorkspaceFlags? = try? api.get("v1/workspace")
            config = try await triage
            if let value = await assignment { assignMode = value.mode }
            if let value = await flags { severityEnabled = value.severityEnabled }
            load = .ready
        } catch {
            if error.isCancellation { return }
            if load != .ready { load = .failed(error.userMessage) }
        }
    }

    /// Applied at once and put back if the server refuses it.
    func set(_ body: [String: JSONValue], apply: (inout TriageConfig) -> Void) async throws {
        guard let api, var next = config else { return }
        let before = config
        apply(&next)
        config = next
        do {
            config = try await api.patch("v1/triage", body: JSONValue.object(body))
        } catch {
            config = before
            throw error
        }
    }
}
