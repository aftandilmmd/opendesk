import SwiftUI

/// Settings › Phone: cloud phone systems whose calls land on the caller's ticket, what each
/// call does there, and the automation a missed call can start. Everything is native: phone
/// systems connect with an API key, never OAuth.
struct PhoneSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store = PhoneSettingsStore()
    @State private var connecting: PhoneCredentialsEdit?
    @State private var webhook: PhoneConnection?
    @State private var confirm: AccountConfirm?
    @State private var busy: String?
    @State private var creatingAutomation = false

    private var admin: Bool { env.session.isAdmin }

    var body: some View {
        AccountPage(title: "Phone") {
            Text("Connect your cloud phone system. Every call lands on the caller's ticket, with who took it, how long it lasted and its recording.")
                .font(ODFont.callout)
                .foregroundStyle(Theme.fg3)
                .padding(.horizontal, 4)
            if !admin { SettingsReadOnlyNote() }
            ChannelLoading(loaded: store.loaded, error: store.error, retry: reload) {
                systems
                ForEach(store.connections) { connection in calls(connection) }
                if !store.connections.isEmpty { automations }
                if !store.unconnected.isEmpty { available }
            }
        }
        .sheet(item: $connecting) { edit in
            PhoneCredentialsSheet(edit: edit, store: store) { connection in
                if let provider = store.provider(connection.provider), provider.manualWebhook, connection.webhookURL != nil {
                    webhook = connection
                }
            }
        }
        .sheet(item: $webhook) { connection in PhoneWebhookSheet(connection: connection, provider: store.provider(connection.provider)) }
        .accountConfirm($confirm)
        .refreshable { await store.load() }
        .task {
            store.attach(env.session.api)
            await store.load()
        }
    }

    private func reload() { Task { await store.load() } }

    // MARK: Systems

    private var systems: some View {
        AccountSection(title: "Phone systems", footer: "Calls from these accounts are documented on tickets.") {
            if store.connections.isEmpty {
                VStack(spacing: 0) {
                    EmptyState(symbol: "phone", title: "No phone system yet", message: "Connect Aircall or Voys and every call is documented on the caller's ticket.")
                    AccountDivider()
                    AccountRow(symbol: "list.bullet.rectangle", tone: .blue, title: "Calls in the ticket timeline")
                    AccountDivider()
                    AccountRow(symbol: "phone.arrow.down.left", tone: .amber, title: "Missed calls never go unanswered")
                    AccountDivider()
                    AccountRow(symbol: "bolt", tone: .violet, title: "Automations when a call ends")
                }
            } else {
                ForEach(Array(store.connections.enumerated()), id: \.element.id) { index, connection in
                    if index > 0 { AccountDivider() }
                    connectionRow(connection)
                }
            }
        }
    }

    private func connectionRow(_ connection: PhoneConnection) -> some View {
        let provider = store.provider(connection.provider)
        let state = PhoneHealth(connection: connection, provider: provider)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AccountIconTile(symbol: "phone.connection", tone: .green)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(connection.name).font(ODFont.sans(15.5, weight: .medium)).foregroundStyle(Theme.fg)
                        Text(provider?.name ?? connection.provider.capitalized).font(ODFont.footnote).foregroundStyle(Theme.fg3)
                        Spacer(minLength: 4)
                        TonePill(text: state.pill, tone: state.tone)
                    }
                    if let line = state.detail {
                        Text(line).font(ODFont.footnote).foregroundStyle(state.failing ? Tone.red.text : Theme.fg2).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(connection.lastEventAt.map { "Last call event \(Format.relLong($0))" } ?? "No call yet. Calls show up on tickets as soon as they ring.")
                        .font(ODFont.footnote).foregroundStyle(Theme.fg3)
                }
            }
            if admin, let url = connection.webhookURL {
                ChannelCopyField(label: provider?.manualWebhook == true ? "Webhook address, to add in \(provider?.name ?? "the phone system") as a call notification" : "Webhook address, registered in your account by opendesk", text: url, copiedMessage: "Webhook address copied")
                if provider?.key == "voys", state.waiting { PhoneVoysSteps() }
            }
            if admin {
                HStack(spacing: 8) {
                    ChannelRowButton(title: "Test", busy: busy == connection.id) { test(connection) }
                    ChannelRowButton(title: "Replace key") { connecting = PhoneCredentialsEdit(provider: provider, connection: connection) }
                        .accessibilityLabel("Replace the credentials of \(connection.name)")
                    if provider?.manualWebhook == true {
                        ChannelRowButton(title: "New address") { askRotate(connection) }
                            .accessibilityLabel("Make a new webhook address for \(connection.name)")
                    }
                    Spacer(minLength: 0)
                    Button { askDisconnect(connection) } label: {
                        Image(systemName: "trash").font(.system(size: 14, weight: .medium)).foregroundStyle(Tone.red.text).frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Disconnect \(connection.name)")
                }
            }
        }
        .padding(14)
    }

    // MARK: Calls

    private func calls(_ connection: PhoneConnection) -> some View {
        let provider = store.provider(connection.provider)
        return AccountSection(title: "Calls from \(connection.name)", footer: "Where a call goes, and what it does there.") {
            ChannelMenuRow(
                title: "Use a recently solved ticket",
                subtitle: connection.reuseDays > 0 ? "When the caller has no open ticket, the call goes on their latest ticket solved in the chosen time." : "When the caller has no open ticket, the call opens a new one.",
                value: PhoneSettingsStore.reuseLabel(connection.reuseDays),
                disabled: !admin
            ) {
                ForEach([0, 1, 3, 7, 14, 30], id: \.self) { days in
                    Button(PhoneSettingsStore.reuseLabel(days)) { update(connection, ["reuse_days": .chInt(days)]) }
                }
            }
            AccountDivider(tiles: false)
            AccountToggleRow(title: "Assign answered calls", subtitle: "A ticket nobody has goes to the teammate who took the call. Teammates are matched by their email.", isOn: Binding(get: { connection.assignAnswered }, set: { update(connection, ["assign_answered": .bool($0)]) }), disabled: !admin)
            if provider?.insightCards == true {
                AccountDivider(tiles: false)
                AccountToggleRow(title: "Show the caller in \(provider?.name ?? "Aircall")", subtitle: "While a call rings, \(provider?.name ?? "Aircall") shows the caller, the ticket the call goes on and their latest tickets.", isOn: Binding(get: { connection.insightCards }, set: { update(connection, ["insight_cards": .bool($0)]) }), disabled: !admin)
            }
            AccountDivider(tiles: false)
            AccountRow(title: "Call from opendesk", subtitle: "Phone numbers on contacts and tickets open your phone app. Set \(provider?.name ?? connection.name) as the default app for phone links to call with it.")
        }
    }

    private var automations: some View {
        let guide = store.connections.first?.provider == "voys" ? "voys" : "aircall"
        return AccountSection(title: "Automations", footer: "Automations can run when a call ends, with its outcome, direction, line, labels and whether it came outside business hours.") {
            if admin {
                ChannelActionRow(title: "Missed call outside opening hours", subtitle: "Reopen the caller's ticket, add a note and raise its priority. Created switched off, for you to review.", button: "Create", busy: creatingAutomation) { createAutomation() }
            } else {
                AccountRow(title: "Missed call outside opening hours", subtitle: "Reopen the caller's ticket, add a note and raise its priority. Created switched off, for you to review.")
            }
            AccountDivider(tiles: false)
            if let url = URL(string: "https://docs.opendesk.sh/guides/\(guide)/") {
                Link(destination: url) {
                    AccountRow(title: "Phone guide", subtitle: "Setup steps and automation examples.") {
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.fg4)
                    }
                }
                .buttonStyle(RowPressStyle())
            }
        }
    }

    private var available: some View {
        AccountSection(title: "Phone systems you can connect", footer: admin ? "Pick one to connect it with its API key." : "An admin can connect a phone system.") {
            ForEach(Array(store.unconnected.enumerated()), id: \.element.id) { index, provider in
                if index > 0 { AccountDivider() }
                Button { connecting = PhoneCredentialsEdit(provider: provider, connection: nil) } label: {
                    AccountRow(symbol: "phone.badge.plus", tone: .green, title: provider.name, subtitle: PhoneSettingsStore.blurb(provider)) {
                        if admin { Chevron() }
                    }
                }
                .buttonStyle(RowPressStyle())
                .disabled(!admin)
            }
        }
    }

    // MARK: Actions

    private func update(_ connection: PhoneConnection, _ body: ChannelBody) {
        Task {
            do {
                try await store.patch(connection.id, body)
            } catch {
                env.toasts.show("Couldn't save the change.", kind: .error)
            }
        }
    }

    private func test(_ connection: PhoneConnection) {
        busy = connection.id
        Task {
            do {
                let tested = try await store.test(connection.id)
                env.toasts.show(tested.healthStatus == "healthy" ? "The connection works." : "The connection needs attention.", kind: tested.healthStatus == "healthy" ? .success : .info)
            } catch {
                env.toasts.show("Couldn't test the connection.", kind: .error)
            }
            busy = nil
        }
    }

    private func askRotate(_ connection: PhoneConnection) {
        let name = store.provider(connection.provider)?.name ?? connection.name
        confirm = AccountConfirm(title: "Make a new webhook address?", message: "The current address stops working at once. Paste the new one in \(name) to keep receiving calls.", confirmTitle: "Make a new address") {
            do {
                webhook = try await store.rotate(connection.id)
            } catch {
                env.toasts.show("Couldn't make a new webhook address.", kind: .error)
            }
        }
    }

    private func askDisconnect(_ connection: PhoneConnection) {
        let provider = store.provider(connection.provider)
        let name = provider?.name ?? connection.name
        let message = provider?.manualWebhook == true
            ? "opendesk stops documenting new calls from \(name). Remove the call notification in \(name) as well. Calls already on tickets stay."
            : "opendesk removes its own webhook from \(name) and stops documenting new calls. Calls already on tickets stay."
        confirm = AccountConfirm(title: "Disconnect the phone system?", message: message, confirmTitle: "Disconnect") {
            do {
                try await store.remove(connection.id)
                Haptics.success()
                env.toasts.show("Phone system disconnected.", kind: .success)
            } catch {
                env.toasts.show("Couldn't disconnect the phone system.", kind: .error)
            }
        }
    }

    private func createAutomation() {
        creatingAutomation = true
        Task {
            do {
                try await store.createMissedCallAutomation()
                Haptics.success()
                env.toasts.show("Automation created, switched off.", kind: .success)
                if let id = store.lastAutomationID { env.router.openSetting(.automations, id: id) }
            } catch {
                env.toasts.error(error)
            }
            creatingAutomation = false
        }
    }

    struct Detail: View {
        let id: String
        var body: some View { PhoneSettings() }
    }
}

/// The pill and the line under a phone connection (the web's health rules, in order).
private struct PhoneHealth {
    var pill: String
    var tone: Tone
    var detail: String?
    var failing = false
    var waiting = false

    init(connection: PhoneConnection, provider: PhoneProvider?) {
        let name = provider?.name ?? connection.name
        waiting = provider?.manualWebhook == true && connection.healthCode == "webhook_missing"
        if connection.status == "error" || connection.healthStatus == "error" {
            pill = "Not working"
            tone = .red
            failing = true
        } else if connection.healthStatus == "healthy" {
            pill = "Receiving calls"
            tone = .green
        } else if waiting {
            pill = "Waiting for the first call"
            tone = .amber
        } else if connection.healthStatus == "action_required" {
            pill = "Action needed"
            tone = .amber
        } else {
            pill = "Not checked yet"
            tone = .gray
        }
        if waiting {
            detail = "No call has come in yet. Add the webhook address below in \(name), then make a test call."
        } else {
            switch connection.healthCode {
            case "receiving": detail = "Calls are sent to opendesk."
            case "webhook_missing": detail = "The phone system is not sending calls to opendesk. Test the connection to set it up again."
            case "credentials_refused": detail = "The phone system refused the credentials. Replace them with working ones."
            case "provider_unreachable": detail = "Couldn't reach the phone system. Try again in a moment."
            default: detail = connection.healthDetail.isEmpty ? (connection.lastError.isEmpty ? nil : connection.lastError) : connection.healthDetail
            }
        }
    }
}

private struct PhoneVoysSteps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array([
                "In Voys Freedom, open Integratie, then Gespreksnotificaties, and click Toevoegen.",
                "Enter a description such as opendesk, and choose Custom as the service.",
                "Paste the webhook address as the Web hook URL.",
                "Tick the summary and transcription events (they need Voys Intelligence), then click Opslaan.",
                "Make a test call: the connection says Receiving calls as soon as it comes in.",
            ].enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).").font(ODFont.mono(12)).foregroundStyle(Theme.fg3)
                    Text(step).font(ODFont.footnote).foregroundStyle(Theme.fg2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct PhoneCredentialsEdit: Identifiable {
    let id = UUID()
    var provider: PhoneProvider?
    /// Set when replacing the credentials of a connection.
    var connection: PhoneConnection?
}

/// Connect a phone system, or replace its credentials.
private struct PhoneCredentialsSheet: View {
    let edit: PhoneCredentialsEdit
    let store: PhoneSettingsStore
    let done: (PhoneConnection) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var saving = false
    @State private var error: String?

    private var name: String { edit.provider?.name ?? edit.connection?.name ?? "the phone system" }
    private var fields: [PhoneProvider.Field] { edit.provider?.fields ?? [] }
    private var ready: Bool { fields.allSatisfy { !(values[$0.name] ?? "").trimmingCharacters(in: .whitespaces).isEmpty } }

    var body: some View {
        ChannelSheet(title: edit.connection == nil ? "Connect \(name)" : "Replace the credentials of \(edit.connection?.name ?? name)", subtitle: PhoneSettingsStore.setup(edit.provider)) {
            ForEach(fields, id: \.name) { field in
                ODTextField(label: field.label, text: Binding(get: { values[field.name] ?? "" }, set: { values[field.name] = $0 }), prompt: "", secure: field.secret, keyboard: .asciiCapable)
            }
            FormError(text: error)
            Button(action: submit) { ButtonLabel(title: edit.connection == nil ? "Connect" : "Replace", busy: saving) }
                .buttonStyle(InkButtonStyle())
                .disabled(!ready || saving)
        }
    }

    private func submit() {
        guard let provider = edit.provider else { return }
        saving = true
        error = nil
        let credentials = values.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        Task {
            do {
                let connection: PhoneConnection
                if let existing = edit.connection {
                    connection = try await store.patch(existing.id, ["credentials": .object(credentials.mapValues(JSONValue.string))])
                    env.toasts.show("Credentials replaced.", kind: .success)
                } else {
                    connection = try await store.connect(provider: provider.key, credentials: credentials)
                    env.toasts.show("\(provider.name) connected.", kind: .success)
                }
                Haptics.success()
                dismiss()
                let changed = edit.connection?.webhookURL != connection.webhookURL
                if edit.connection == nil || changed { done(connection) }
            } catch {
                Haptics.error()
                self.error = (error as? APIError)?.detail ?? "Couldn't connect \(provider.name)."
            }
            saving = false
        }
    }
}

/// "Add opendesk in {name}": the webhook address a manual phone system needs.
private struct PhoneWebhookSheet: View {
    let connection: PhoneConnection
    let provider: PhoneProvider?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let name = provider?.name ?? connection.name
        ChannelSheet(title: "Add opendesk in \(name)", subtitle: "\(name) sends calls to this address once you add it as a call notification.") {
            if let url = connection.webhookURL { ChannelCopyField(text: url, copiedMessage: "Webhook address copied") }
            if provider?.key == "voys" { PhoneVoysSteps() }
            Button("Done") { dismiss() }.buttonStyle(InkButtonStyle())
        }
    }
}

@MainActor
@Observable
final class PhoneSettingsStore {
    private(set) var providers: [PhoneProvider] = []
    private(set) var connections: [PhoneConnection] = []
    private(set) var loaded = false
    private(set) var error: String?
    private(set) var lastAutomationID: String?

    @ObservationIgnored private var api: APIClient?

    func attach(_ api: APIClient) { self.api = api }

    var unconnected: [PhoneProvider] {
        providers.filter { provider in !connections.contains { $0.provider == provider.key } }
    }

    func provider(_ key: String) -> PhoneProvider? { providers.first { $0.key == key } }

    func load() async {
        guard let api else { return }
        do {
            async let providers: ChannelList<PhoneProvider> = api.get("v1/phone/providers")
            async let connections: ChannelList<PhoneConnection> = api.get("v1/phone/connections")
            self.providers = try await providers.data
            self.connections = try await connections.data
            error = nil
        } catch {
            if !error.isCancellation { self.error = error.userMessage }
        }
        loaded = true
    }

    private func upsert(_ connection: PhoneConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) { connections[index] = connection } else { connections.append(connection) }
    }

    func connect(provider: String, credentials: [String: String]) async throws -> PhoneConnection {
        guard let api else { throw CancellationError() }
        let body: ChannelBody = ["provider": .string(provider), "credentials": .object(credentials.mapValues(JSONValue.string))]
        let connection: PhoneConnection = try await api.post("v1/phone/connections", body: body, idempotencyKey: UUID().uuidString)
        upsert(connection)
        return connection
    }

    @discardableResult
    func patch(_ id: String, _ body: ChannelBody) async throws -> PhoneConnection {
        guard let api else { throw CancellationError() }
        let connection: PhoneConnection = try await api.patch("v1/phone/connections/\(id)", body: body)
        upsert(connection)
        return connection
    }

    func test(_ id: String) async throws -> PhoneConnection {
        guard let api else { throw CancellationError() }
        let connection: PhoneConnection = try await api.post("v1/phone/connections/\(id)/test")
        upsert(connection)
        return connection
    }

    func rotate(_ id: String) async throws -> PhoneConnection {
        guard let api else { throw CancellationError() }
        let connection: PhoneConnection = try await api.post("v1/phone/connections/\(id)/rotate-webhook")
        upsert(connection)
        return connection
    }

    func remove(_ id: String) async throws {
        guard let api else { return }
        try await api.delete("v1/phone/connections/\(id)")
        connections.removeAll { $0.id == id }
    }

    func createMissedCallAutomation() async throws {
        guard let api else { return }
        let body: ChannelBody = [
            "name": .string("Missed call outside opening hours"),
            "trigger": .string("call_ended"),
            "conditions": .array([
                .object(["field": .string("call_direction"), "op": .string("equals"), "value": .string("inbound")]),
                .object(["field": .string("call_outcome"), "op": .string("equals"), "value": .string("missed")]),
                .object(["field": .string("call_time"), "op": .string("equals"), "value": .string("outside_business_hours")]),
            ]),
            "actions": .array([
                .object(["type": .string("set_status"), "value": .string("open")]),
                .object(["type": .string("add_note"), "value": .string("<p>Missed call outside opening hours: call back.</p>")]),
                .object(["type": .string("set_priority"), "value": .string("high")]),
            ]),
            "enabled": .bool(false),
            "position": .chInt(0),
        ]
        let created: JSONValue = try await api.post("v1/automations", body: body, idempotencyKey: UUID().uuidString)
        lastAutomationID = created["id"]?.string
    }

    static func reuseLabel(_ days: Int) -> String {
        switch days {
        case 0: "Never"
        case 1: "Within 1 day"
        default: "Within \(days) days"
        }
    }

    static func blurb(_ provider: PhoneProvider) -> String? {
        switch provider.key {
        case "aircall": "Cloud phone system. Calls, recordings and AI summaries land on tickets."
        case "voys": "Dutch cloud phone system. Calls, Voys Intelligence transcripts and summaries land on tickets."
        default: nil
        }
    }

    static func setup(_ provider: PhoneProvider?) -> String? {
        switch provider?.key {
        case "aircall": "In Aircall, open Integrations & API, then API keys, and create a key. Paste its API ID and token here: opendesk registers its own webhook in your account and leaves the others alone."
        case "voys": "In Voys Freedom, open your personal settings and copy your API token. Use an admin's token with access to call recordings, so transcripts and summaries come along. Next, you add opendesk's webhook address in Voys."
        default: nil
        }
    }
}
