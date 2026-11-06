import SwiftUI

/// Connect a bot, or rotate its credentials. Discord finds the bot's servers first.
struct SupportConnectSheet: View {
    let provider: SupportProvider
    /// Set when rotating the credentials of a connection.
    let connection: SupportConnection?
    let store: SupportChannelsStore
    let connected: (SupportConnection) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var values: [String: String] = [:]
    @State private var servers: [SupportOption]?
    @State private var server: String?
    @State private var finding = false
    @State private var saving = false
    @State private var error: String?

    private var filled: Bool { provider.typed.allSatisfy { !(values[$0.name] ?? "").trimmingCharacters(in: .whitespaces).isEmpty } }
    private var needsServer: Bool { connection == nil && provider.discovered != nil }

    var body: some View {
        ChannelSheet(
            title: connection == nil ? "Connect \(provider.name)" : "Rotate credentials for \(connection?.name ?? provider.name)",
            subtitle: connection == nil ? SupportChannelsStore.setup(provider) : "Enter the replacement credentials for the same provider account. Destinations and ticket threads stay connected."
        ) {
            if connection == nil {
                ODTextField(label: "Connection name", text: $name, prompt: provider.name)
                ChannelHint("Optional.")
            }
            ForEach(provider.typed, id: \.name) { field in
                ODTextField(label: field.label, text: Binding(get: { values[field.name] ?? "" }, set: {
                    values[field.name] = $0
                    servers = nil
                    server = nil
                }), prompt: "", secure: field.secret, keyboard: .asciiCapable)
                if !field.help.isEmpty, !["slack", "discord", "telegram"].contains(provider.key) { ChannelHint(field.help) }
            }
            if needsServer, let servers {
                if servers.isEmpty {
                    Notice(text: "This bot is not installed in any servers yet.", tone: .amber, symbol: "exclamationmark.triangle")
                } else {
                    HStack(alignment: .bottom, spacing: 8) {
                        ChannelMenuField(label: provider.discovered?.label ?? "Server", value: servers.first { $0.id == server }?.name ?? "Choose a server") {
                            ForEach(servers) { option in Button(option.name.isEmpty ? option.id : option.name) { server = option.id } }
                        }
                        Button(action: find) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .medium)).frame(width: 46, height: 46)
                        }
                        .accessibilityLabel("Refresh servers")
                    }
                }
            }
            FormError(text: error)
            if needsServer && server == nil {
                Button(action: find) { ButtonLabel(title: "Find servers", busy: finding) }
                    .buttonStyle(InkButtonStyle())
                    .disabled(!filled || finding)
            } else {
                Button(action: submit) { ButtonLabel(title: connection == nil ? "Connect" : "Rotate credentials", busy: saving) }
                    .buttonStyle(InkButtonStyle())
                    .disabled(!filled || saving)
            }
        }
    }

    private var credentials: [String: String] {
        var out = values.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let field = provider.discovered {
            if let server { out[field.name] = server } else if let connection { out[field.name] = connection.externalAccountID }
        }
        return out
    }

    private func find() {
        finding = true
        error = nil
        Task {
            do {
                let found = try await store.discover(provider: provider.key, credentials: credentials)
                servers = found
                if found.count == 1 { server = found[0].id }
            } catch {
                self.error = (error as? APIError)?.detail ?? "Couldn't load servers for \(provider.name)."
            }
            finding = false
        }
    }

    private func submit() {
        saving = true
        error = nil
        Task {
            do {
                if let connection {
                    try await store.rotate(connection.id, credentials: credentials)
                    env.toasts.show("Credentials rotated.", kind: .success)
                    dismiss()
                } else {
                    let made = try await store.connect(provider: provider.key, name: name.trimmingCharacters(in: .whitespaces), credentials: credentials)
                    Haptics.success()
                    env.toasts.show("\(provider.name) connected.", kind: .success)
                    dismiss()
                    try? await Task.sleep(for: .milliseconds(450))
                    connected(made)
                }
            } catch {
                Haptics.error()
                self.error = (error as? APIError)?.detail ?? (connection == nil ? "Couldn't connect \(provider.name)." : "Couldn't rotate the credentials.")
            }
            saving = false
        }
    }
}

/// The conditions a support channel route can test (`DESTINATION_FIELDS` on the web).
@MainActor
enum SupportConditionFields {
    static func all(env: AppEnvironment, mailboxes: [SettingsMailbox], brands: [SettingsBrand]) -> [ChannelConditionField] {
        let text = ["contains", "not_contains", "equals", "not_equals"]
        var fields = [
            ChannelConditionField(key: "subject", label: "Subject", group: "Message", ops: text, value: .text("refund")),
            ChannelConditionField(key: "from_email", label: "Sender email", group: "Message", ops: text, value: .text("@acme.com")),
            ChannelConditionField(key: "received_at", label: "Address written to", group: "Message", ops: ["equals", "not_equals", "contains"], value: .text("support@company.com")),
            ChannelConditionField(key: "mailbox_id", label: "Mailbox", group: "Ticket", ops: ["equals", "not_equals"], value: .choice(mailboxes.map { ChannelChoice(value: $0.id, label: $0.email) })),
        ]
        if brands.count > 1 {
            fields.append(ChannelConditionField(key: "brand_id", label: "Brand", group: "Ticket", ops: ["equals", "not_equals"], value: .choice(brands.map { ChannelChoice(value: $0.id, label: $0.name) })))
        }
        fields += [
            ChannelConditionField(key: "severity", label: "Severity", group: "Ticket", ops: ["equals", "not_equals"], value: .choice(Severity.allCases.map { ChannelChoice(value: $0.rawValue, label: $0.title) })),
            ChannelConditionField(key: "sentiment", label: "Sentiment", group: "Ticket", ops: ["equals", "not_equals"], value: .choice(["positive", "neutral", "negative", "frustrated"].map { ChannelChoice(value: $0, label: $0.capitalized) })),
            ChannelConditionField(key: "tag", label: "Label", group: "Ticket", ops: ["equals", "not_equals"], value: .choice(env.directory.tags.map { ChannelChoice(value: $0.name, label: $0.name) })),
            ChannelConditionField(key: "time", label: "Business hours", group: "Ticket", ops: ["equals", "not_equals"], value: .choice([
                ChannelChoice(value: "business_hours", label: "Within business hours"), ChannelChoice(value: "outside_business_hours", label: "Outside business hours"),
            ])),
        ]
        return fields
    }

    static func complete(_ conditions: [ChannelCondition]) -> Bool {
        conditions.allSatisfy { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

/// Where a route posts, what its threads show, and how long its messages run.
private struct SupportRoutingFields: View {
    @Binding var mode: String
    @Binding var conditions: [ChannelCondition]
    @Binding var mirror: [String]
    @Binding var includeNotes: Bool
    let fields: [ChannelConditionField]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Posting").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
            AccountSegmented(options: ["route", "copy"], selection: $mode) { $0 == "route" ? "Route here" : "Also post here" }
            ChannelHint(mode == "route"
                ? "A connection posts each ticket to its most specific matching route: team first, then priority, then the route with more conditions."
                : "Posts every matching ticket as well as its route, such as urgent tickets in an escalation channel.")
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Only when").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
            ChannelHint("Conditions choose where a ticket's thread starts. Once a ticket has a thread here, it keeps following the ticket.")
            ChannelConditionsEditor(conditions: $conditions, fields: fields, joiner: "and", max: 10, newField: "tag")
            if !SupportConditionFields.complete(conditions) { FormError(text: "Fill in every condition, or remove it.") }
        }
        VStack(alignment: .leading, spacing: 0) {
            Text("Show in threads").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2).padding(.bottom, 4)
            ChannelHint("The ticket card always stays current.").padding(.bottom, 6)
            VStack(spacing: 0) {
                mirrorToggle("customer_replies", "Customer replies")
                Hairline()
                mirrorToggle("agent_replies", "Agent replies")
                Hairline()
                AccountToggleRow(title: "Include internal notes", subtitle: "Off by default. When on, notes are posted to this channel and Ollie can use them in its answers there.", isOn: $includeNotes)
                Hairline()
                mirrorToggle("status_changes", "Status changes")
                Hairline()
                mirrorToggle("assignee_changes", "Assignee changes")
                Hairline()
                mirrorToggle("priority_changes", "Priority changes")
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
    }

    private func mirrorToggle(_ key: String, _ title: String) -> some View {
        AccountToggleRow(title: title, isOn: Binding(get: { mirror.contains(key) }, set: { on in
            if on { if !mirror.contains(key) { mirror.append(key) } } else { mirror.removeAll { $0 == key } }
        }))
    }
}

/// "Add destination": a team, a priority, a channel the bot can post in, and its routing.
struct SupportDestinationSheet: View {
    let connection: SupportConnection
    let store: SupportChannelsStore

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var teamID: String?
    @State private var priority: String?
    @State private var channels: [SupportOption]?
    @State private var channelsFailed = false
    @State private var channelID = ""
    @State private var channelName = ""
    @State private var typing = false
    @State private var mode = "route"
    @State private var conditions: [ChannelCondition] = []
    @State private var mirror = ["customer_replies", "agent_replies"]
    @State private var includeNotes = false
    @State private var limit = 3500
    @State private var saving = false
    @State private var error: String?

    private var used: Set<String> { Set(store.destinations.filter { $0.connectionID == connection.id }.map(\.channelID)) }
    private var duplicate: Bool {
        mode == "route" && store.destinations.contains {
            $0.connectionID == connection.id && $0.mode == "route" && $0.teamID == teamID && $0.priority == priority && $0.conditions.same(as: conditions)
        }
    }

    var body: some View {
        ChannelSheet(title: "Add destination", subtitle: "Choose which email tickets go to this channel: a public team, a priority and any conditions. More specific routes take precedence.") {
            ChannelTeamMenu(label: "Team", teamID: $teamID, none: "All public teams")
            ChannelMenuField(label: "Priority", value: priority?.capitalized ?? "All priorities") {
                Button("All priorities") { priority = nil }
                ForEach(["low", "normal", "high", "urgent"], id: \.self) { value in Button(value.capitalized) { priority = value } }
            }
            if duplicate { FormError(text: "A destination already uses this team and priority.") }
            channel
            SupportRoutingFields(mode: $mode, conditions: $conditions, mirror: $mirror, includeNotes: $includeNotes, fields: SupportConditionFields.all(env: env, mailboxes: store.mailboxes, brands: store.brands))
            VStack(alignment: .leading, spacing: 6) {
                Text("Message length").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
                AccountSegmented(options: [1000, 2000, 3500], selection: $limit) { "\($0) characters" }
                ChannelHint("Longer messages are shortened with a View in opendesk link. Providers may use a lower limit.")
            }
            FormError(text: error)
            Button(action: submit) { ButtonLabel(title: "Add destination", busy: saving) }
                .buttonStyle(InkButtonStyle())
                .disabled(saving || duplicate || channelID.trimmingCharacters(in: .whitespaces).isEmpty || !SupportConditionFields.complete(conditions))
        }
        .task { await loadChannels() }
    }

    @ViewBuilder
    private var channel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if typing {
                ODTextField(label: "Channel ID", text: $channelID, prompt: "C0123ABCD", keyboard: .asciiCapable)
                ChannelHint("The provider's ID for the channel, such as C0123ABCD in Slack or -1001234567890 in Telegram.")
            } else {
                let options = (channels ?? []).filter { !used.contains($0.id) && $0.available }
                HStack(alignment: .bottom, spacing: 8) {
                    ChannelMenuField(label: "Provider channel", value: channels == nil ? "Loading channels" : (options.first { $0.id == channelID }.map { "#\($0.name.isEmpty ? $0.id : $0.name)" } ?? "Choose a channel")) {
                        ForEach(options) { option in
                            Button("#\(option.name.isEmpty ? option.id : option.name)") {
                                channelID = option.id
                                channelName = option.name
                            }
                        }
                    }
                    Button { Task { await loadChannels() } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .medium)).frame(width: 46, height: 46)
                    }
                    .accessibilityLabel("Refresh channels")
                }
                if channelsFailed {
                    FormError(text: "Couldn't load channels from the provider.")
                } else if channels != nil, options.isEmpty {
                    ChannelHint(SupportChannelsStore.emptyChannels(connection.provider))
                } else {
                    ChannelHint("Channels the bot can post in.")
                }
            }
            Button(typing ? "Choose from the list instead" : "Enter a channel ID instead") {
                typing.toggle()
                channelID = ""
                channelName = ""
            }
            .font(ODFont.sans(13, weight: .medium))
        }
    }

    private func loadChannels() async {
        channels = nil
        channelsFailed = false
        do {
            channels = try await store.channels(connection.id)
        } catch {
            channels = []
            channelsFailed = true
        }
    }

    private func submit() {
        saving = true
        error = nil
        var body: ChannelBody = [
            "connection_id": .string(connection.id),
            "external_channel_id": .string(channelID.trimmingCharacters(in: .whitespaces)),
            "mode": .string(mode),
            "conditions": (try? JSONValue.from(conditions)) ?? .array([]),
            "mirror": .chStrings(mirror),
            "include_notes": .bool(includeNotes),
            "message_limit": .chInt(limit),
        ]
        if let teamID { body["team_id"] = .string(teamID) }
        if let priority { body["priority"] = .string(priority) }
        if !channelName.isEmpty { body["external_channel_name"] = .string(channelName) }
        Task {
            do {
                try await store.addDestination(body)
                Haptics.success()
                env.toasts.show("Destination added.", kind: .success)
                dismiss()
            } catch {
                Haptics.error()
                self.error = (error as? APIError)?.detail ?? "Couldn't add the destination."
            }
            saving = false
        }
    }
}

/// "Routing for #channel": which tickets start a thread there and what their threads show.
struct SupportRoutingSheet: View {
    let destination: SupportDestination
    let store: SupportChannelsStore

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "route"
    @State private var conditions: [ChannelCondition] = []
    @State private var mirror: [String] = []
    @State private var includeNotes = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ChannelSheet(title: "Routing for #\(destination.label)", subtitle: "Choose which tickets start a thread in this channel and what their threads show.") {
            SupportRoutingFields(mode: $mode, conditions: $conditions, mirror: $mirror, includeNotes: $includeNotes, fields: SupportConditionFields.all(env: env, mailboxes: store.mailboxes, brands: store.brands))
            FormError(text: error)
            Button(action: save) { ButtonLabel(title: "Save", busy: saving) }
                .buttonStyle(InkButtonStyle())
                .disabled(saving || !SupportConditionFields.complete(conditions))
        }
        .onAppear {
            mode = destination.mode
            conditions = destination.conditions
            mirror = destination.mirror
            includeNotes = destination.includeNotes
        }
    }

    private func save() {
        saving = true
        Task {
            do {
                try await store.patchDestination(destination.id, [
                    "mode": .string(mode), "conditions": (try? JSONValue.from(conditions)) ?? .array([]),
                    "mirror": .chStrings(mirror), "include_notes": .bool(includeNotes),
                ])
                Haptics.success()
                env.toasts.show("Routing saved.", kind: .success)
                dismiss()
            } catch {
                self.error = "Couldn't save the routing."
            }
            saving = false
        }
    }
}

/// "Ollie in #channel": summaries, warnings, answer length and personality there.
struct SupportOllieSheet: View {
    let destination: SupportDestination
    let store: SupportChannelsStore

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var summary = true
    @State private var warnings = true
    @State private var length = "standard"
    @State private var personality = ""
    @State private var saving = false
    @State private var error: String?

    private var valid: Bool { ChannelValidate.plain(personality) && personality.count <= 500 }

    var body: some View {
        ChannelSheet(title: "Ollie in #\(destination.label)", subtitle: "How Ollie works in this channel's ticket threads.") {
            VStack(spacing: 0) {
                AccountToggleRow(symbol: "text.append", tone: .violet, title: "Summarize new threads", subtitle: "Ollie posts what the customer needs, what they've tried, their sentiment and urgency when a ticket's thread opens. Uses AI credits.", isOn: $summary)
                Hairline(inset: 56)
                AccountToggleRow(symbol: "exclamationmark.bubble", tone: .violet, title: "SLA and sentiment warnings", subtitle: "Ollie warns in the thread when an SLA target is near or missed, and when the customer sounds unhappy.", isOn: $warnings)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                Text("Response length").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
                AccountSegmented(options: ["brief", "standard", "detailed"], selection: $length) { $0.capitalized }
                ChannelHint("How long Ollie's answers and suggestions are in this channel.")
            }
            AccountTextEditor(label: "Personality", text: $personality, prompt: "Friendly and upbeat, plain words, no jargon", minHeight: 90)
            ChannelHint("How Ollie sounds here. It shapes tone only and never changes what Ollie may do.")
            if !ChannelValidate.plain(personality) { FormError(text: "The personality can't contain < or >.") }
            FormError(text: error)
            Button(action: save) { ButtonLabel(title: "Save", busy: saving) }
                .buttonStyle(InkButtonStyle())
                .disabled(saving || !valid)
        }
        .onAppear {
            summary = destination.ollieSummary
            warnings = destination.ollieWarnings
            length = destination.ollieLength
            personality = destination.olliePersonality
        }
    }

    private func save() {
        saving = true
        Task {
            do {
                try await store.patchDestination(destination.id, [
                    "ollie_summary": .bool(summary), "ollie_warnings": .bool(warnings), "ollie_length": .string(length),
                    "ollie_personality": .string(personality.trimmingCharacters(in: .whitespacesAndNewlines)),
                ])
                Haptics.success()
                env.toasts.show("Ollie settings saved.", kind: .success)
                dismiss()
            } catch {
                self.error = "Couldn't save Ollie's settings."
            }
            saving = false
        }
    }
}
