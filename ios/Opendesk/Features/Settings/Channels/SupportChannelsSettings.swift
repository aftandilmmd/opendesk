import SwiftUI

/// Settings › Support channels: Slack, Discord and Telegram bots where agents work email
/// tickets in threads, where each team's tickets go, what Ollie may do there, and how
/// deliveries are doing. Bots connect with pasted credentials, so all of it is native.
struct SupportChannelsSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store = SupportChannelsStore()
    @State private var connecting: SupportProvider?
    @State private var rotating: SupportConnection?
    @State private var adding: SupportConnection?
    @State private var routing: SupportDestination?
    @State private var ollie: SupportDestination?
    @State private var linkCode: String?
    @State private var confirm: AccountConfirm?
    @State private var busy: String?
    @State private var setupOpen: Set<String> = []

    private var admin: Bool { env.session.isAdmin }

    var body: some View {
        AccountPage(title: "Support channels") {
            Text("Mirror email tickets into Slack, Discord and Telegram. Teammates can reply, add notes and work tickets from the ticket's thread.")
                .font(ODFont.callout)
                .foregroundStyle(Theme.fg3)
                .padding(.horizontal, 4)
            if !admin { SettingsReadOnlyNote() }
            ChannelLoading(loaded: store.loaded, error: store.error, retry: reload) {
                connections
                if !store.connections.isEmpty { ollieActions }
                if admin {
                    reliability
                    deliveries
                }
                providers
            }
        }
        .toolbar {
            if env.session.canWrite {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Link my account", action: makeLinkCode).font(ODFont.sans(15, weight: .medium))
                }
            }
        }
        .sheet(item: $connecting) { provider in
            SupportConnectSheet(provider: provider, connection: nil, store: store) { connection in adding = connection }
        }
        .sheet(item: $rotating) { connection in
            if let provider = store.provider(connection.provider) {
                SupportConnectSheet(provider: provider, connection: connection, store: store) { _ in }
            }
        }
        .sheet(item: $adding) { connection in SupportDestinationSheet(connection: connection, store: store) }
        .sheet(item: $routing) { destination in SupportRoutingSheet(destination: destination, store: store) }
        .sheet(item: $ollie) { destination in SupportOllieSheet(destination: destination, store: store) }
        .sheet(item: Binding(get: { linkCode.map(SupportLinkCode.init) }, set: { linkCode = $0?.code })) { code in
            ChannelSheet(title: "Link your chat account", subtitle: "Send this code to the bot from your chat account: /opendesk link \(code.code) in Slack, or /link \(code.code) in Discord and Telegram. It works once and expires in 10 minutes.") {
                ChannelCopyField(text: code.code, copiedMessage: "Code copied")
                Button("Done") { linkCode = nil }.buttonStyle(InkButtonStyle())
            }
            .presentationDetents([.medium])
        }
        .accountConfirm($confirm)
        .refreshable { await store.load(admin: admin) }
        .task {
            store.attach(env.session.api)
            await store.load(admin: admin)
        }
    }

    private func reload() { Task { await store.load(admin: admin) } }

    // MARK: Connections

    private var connections: some View {
        AccountSection(title: "Connections", footer: "Bot credentials are stored encrypted. opendesk sets up Discord and Telegram for you; Slack needs a few steps in its own settings.") {
            if store.connections.isEmpty {
                VStack(spacing: 0) {
                    EmptyState(symbol: "bubble.left.and.bubble.right", title: "No support channels yet", message: "Connect a bot, then choose where each team's email tickets appear.")
                    AccountDivider()
                    AccountRow(symbol: "text.bubble", tone: .blue, title: "Each ticket gets its own thread")
                    AccountDivider()
                    AccountRow(symbol: "sparkles", tone: .violet, title: "Ask Ollie about a ticket in its thread")
                    AccountDivider()
                    AccountRow(symbol: "at", tone: .teal, title: "Mention the bot in a channel to create a ticket")
                }
            } else {
                ForEach(Array(store.connections.enumerated()), id: \.element.id) { index, connection in
                    if index > 0 { AccountDivider() }
                    connectionRow(connection)
                }
            }
        }
    }

    private func connectionRow(_ connection: SupportConnection) -> some View {
        let provider = store.provider(connection.provider)
        let (pill, tone) = SupportChannelsStore.pill(connection)
        let account = [connection.externalAccountHandle, connection.externalAccountName == connection.name ? "" : connection.externalAccountName].filter { !$0.isEmpty }.joined(separator: " · ")
        let destinations = store.destinations.filter { $0.connectionID == connection.id }
        let manual = provider.map { !$0.configures } ?? false
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AccountIconTile(symbol: SupportChannelsStore.symbol(connection.provider), tone: SupportChannelsStore.tone(connection.provider))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(connection.name).font(ODFont.sans(15.5, weight: .medium)).foregroundStyle(Theme.fg).lineLimit(1)
                        Text(provider?.name ?? connection.provider.capitalized).font(ODFont.footnote).foregroundStyle(Theme.fg3)
                        Spacer(minLength: 4)
                        TonePill(text: pill, tone: tone)
                    }
                    if !account.isEmpty { Text(account).font(ODFont.footnote).foregroundStyle(Theme.fg2) }
                    if !connection.lastError.isEmpty {
                        Text(connection.lastError).font(ODFont.footnote).foregroundStyle(Tone.red.text).fixedSize(horizontal: false, vertical: true)
                    } else if connection.healthStatus != "healthy", !connection.healthDetail.isEmpty, !(manual && connection.healthStatus == "action_required") {
                        Text(connection.healthDetail).font(ODFont.footnote).foregroundStyle(Theme.fg3).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if admin, manual { setup(connection) }
            if destinations.isEmpty {
                if admin {
                    HStack(spacing: 6) {
                        Text("Tickets aren't going anywhere yet.").font(ODFont.footnote).foregroundStyle(Theme.fg3)
                        Button("Add a destination") { adding = connection }.font(ODFont.sans(13, weight: .medium))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(destinations) { destination in destinationChip(destination) }
                }
            }
            if admin {
                HStack(spacing: 8) {
                    ChannelRowButton(title: "Test connection", busy: busy == connection.id) { test(connection) }
                    ChannelRowButton(title: "Add destination") { adding = connection }
                    Spacer(minLength: 0)
                    Menu {
                        Button { rotating = connection } label: { Label("Rotate credentials", systemImage: "key") }
                        Button(role: .destructive) { askDisconnect(connection) } label: { Label("Disconnect", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.fg2).frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Actions for \(connection.name)")
                }
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private func setup(_ connection: SupportConnection) -> some View {
        let healthy = connection.healthStatus == "healthy"
        let open = setupOpen.contains(connection.id) || !healthy
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Finish setting up the app").font(ODFont.sans(13.5, weight: .semibold)).foregroundStyle(Theme.fg)
                Spacer()
                if healthy {
                    Button(open ? "Hide" : "Show setup steps") {
                        if open { setupOpen.remove(connection.id) } else { setupOpen.insert(connection.id) }
                    }
                    .font(ODFont.sans(13, weight: .medium))
                }
            }
            if open {
                ChannelCopyField(label: "Events address", text: connection.webhookURL, copiedMessage: "Events address copied")
                ForEach(Array(SupportChannelsStore.setupSteps(connection.provider).enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).").font(ODFont.mono(12)).foregroundStyle(Theme.fg3)
                        Text(step).font(ODFont.footnote).foregroundStyle(Theme.fg2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !healthy {
                    ChannelHint("This changes to Connected once the provider sends its first event. Mention the bot in a channel to send one.")
                }
            }
        }
        .padding(12)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    private func destinationChip(_ destination: SupportDestination) -> some View {
        var parts = [env.directory.team(destination.teamID)?.name ?? "All teams"]
        if let priority = destination.priority { parts.append(priority.capitalized) }
        if !destination.conditions.isEmpty { parts.append(ChannelFormat.plural(destination.conditions.count, "condition")) }
        if destination.mode == "copy" { parts.append("also posts") }
        if destination.includeNotes { parts.append("with notes") }
        return HStack(spacing: 8) {
            Text("#\(destination.label)").font(ODFont.mono(12.5, weight: .medium)).foregroundStyle(Theme.fg)
            Text(parts.joined(separator: " · ")).font(ODFont.sans(12.5)).foregroundStyle(Theme.fg3).lineLimit(1)
            Spacer(minLength: 0)
            if admin {
                Menu {
                    Button { routing = destination } label: { Label("Routing", systemImage: "slider.horizontal.3") }
                    Button { ollie = destination } label: { Label("Ollie settings", systemImage: "sparkles") }
                    Button(role: .destructive) { askRemove(destination) } label: { Label("Remove", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 15)).foregroundStyle(Theme.fg3).frame(width: 28, height: 28)
                }
                .accessibilityLabel("Actions for #\(destination.label)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.active.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.control - 2, style: .continuous))
    }

    // MARK: Ollie

    private var ollieActions: some View {
        AccountSection(title: "Ollie in support channels", footer: "Typed commands such as reply, note and status are the agent's own and always work. Changes Ollie suggests to a customer reply, a new ticket or a close still ask for confirmation.") {
            Text("Ollie summarizes each new ticket thread, suggests replies, answers questions and warns about SLAs and unhappy customers. Choose which changes it may make when it decides to.")
                .font(ODFont.footnote).foregroundStyle(Theme.fg3).padding(14)
            ForEach(SupportChannelsStore.ollieActions, id: \.key) { action in
                AccountDivider(tiles: false)
                AccountToggleRow(title: action.title, subtitle: action.hint, isOn: Binding(get: { store.ollie.contains(action.key) }, set: { on in
                    Task {
                        do { try await store.setOllie(action.key, on) } catch { env.toasts.show("Couldn't save what Ollie may do.", kind: .error) }
                    }
                }), disabled: !admin)
            }
        }
    }

    // MARK: Reliability

    @ViewBuilder
    private var reliability: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Reliability").padding(.horizontal, 4)
                Spacer()
                Button("Refresh metrics") { Task { await store.loadOperations() } }.font(ODFont.sans(13, weight: .medium))
            }
            Text("Connection health, delivery latency and inbound webhook activity for the last 24 hours.")
                .font(ODFont.footnote).foregroundStyle(Theme.fg3).padding(.horizontal, 4)
            if let ops = store.operations {
                if ops.alerted > 0 {
                    ChannelBanner(tone: .red, title: ops.alerted == 1 ? "1 connection has remained unhealthy for at least 15 minutes. Administrators have been notified." : "\(ops.alerted) connections have remained unhealthy for at least 15 minutes. Administrators have been notified.")
                }
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        ChannelStatTile(value: "\(ops.healthy) of \(ops.total)", label: "Connection health", hint: ops.unhealthy > 0 ? "\(ops.unhealthy) need\(ops.unhealthy == 1 ? "s" : "") attention" : "No unhealthy connections", tone: ops.unhealthy > 0 ? .red : .gray)
                        ChannelStatTile(value: SupportChannelsStore.duration(ops.averageLatencyMS), label: "Average delivery latency", hint: ops.oldestPendingAt.map { "Oldest pending \(Format.relLong($0))" } ?? "Maximum \(SupportChannelsStore.duration(ops.maximumLatencyMS))")
                    }
                    GridRow {
                        ChannelStatTile(value: "\(ops.rejected)", label: "Rejected webhooks", hint: "Last 24 hours")
                        ChannelStatTile(value: "\(ops.duplicates)", label: "Duplicates suppressed", hint: "Last 24 hours")
                    }
                }
                FlowLayout(spacing: 6) {
                    TonePill(text: "Queued · \(ops.queued)", tone: .amber)
                    TonePill(text: "Retrying · \(ops.retrying)", tone: .amber)
                    TonePill(text: "Delivered · \(ops.delivered)", tone: .green)
                    TonePill(text: "Failed · \(ops.failed)", tone: .red)
                }
                ChannelHint("Delivery totals from the last 24 hours")
            } else if store.operationsFailed {
                Notice(text: "Operational metrics couldn't be loaded.", tone: .red, symbol: "exclamationmark.triangle")
            }
        }
    }

    private var deliveries: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Delivery activity").padding(.horizontal, 4)
                Spacer()
                Button("Refresh deliveries") { Task { await store.loadDeliveries(reset: true) } }.font(ODFont.sans(13, weight: .medium))
            }
            Text("Recent ticket events sent to provider channels. Failed events stay here until retried.")
                .font(ODFont.footnote).foregroundStyle(Theme.fg3).padding(.horizontal, 4)
            Panel {
                if store.deliveries.isEmpty {
                    EmptyState(symbol: "paperplane", title: "No delivery activity yet", message: "Ticket events will appear here after they are sent to a support channel.")
                } else {
                    ForEach(Array(store.deliveries.enumerated()), id: \.element.id) { index, delivery in
                        if index > 0 { Hairline(inset: 14) }
                        deliveryRow(delivery)
                    }
                    if store.deliveriesCursor != nil {
                        Hairline()
                        Button("Load more") { Task { await store.loadDeliveries(reset: false) } }
                            .font(ODFont.sans(14, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(12)
                    }
                }
            }
        }
    }

    private func deliveryRow(_ delivery: SupportDelivery) -> some View {
        let (label, tone): (String, Tone) = switch delivery.status {
        case "delivered": ("Delivered", .green)
        case "failed": ("Failed", .red)
        case "retrying": ("Retrying", .amber)
        default: ("Queued", .amber)
        }
        return HStack(alignment: .top, spacing: 10) {
            TonePill(text: label, tone: tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(delivery.ticketNumber.map { "Ticket #\($0)" } ?? "Event \(delivery.eventSeq)").font(ODFont.sans(14, weight: .medium)).foregroundStyle(Theme.fg)
                Text([delivery.eventType == "ticket.created" ? "Ticket created" : delivery.eventType == "ticket.updated" ? "Ticket updated" : "Message added",
                      delivery.attempts == 0 ? "Waiting for first attempt" : ChannelFormat.plural(delivery.attempts, "attempt")].joined(separator: " · "))
                    .font(ODFont.footnote).foregroundStyle(Theme.fg3)
                if delivery.status == "failed", !delivery.lastError.isEmpty {
                    Text(delivery.lastError).font(ODFont.footnote).foregroundStyle(Tone.red.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                if let updated = delivery.updatedAt { Text(Format.relShort(updated)).font(ODFont.sans(12)).foregroundStyle(Theme.fg3) }
                if delivery.status == "failed" {
                    ChannelRowButton(title: "Retry") {
                        Task {
                            do {
                                try await store.retry(delivery)
                                env.toasts.show("Delivery queued for retry.", kind: .success)
                            } catch {
                                env.toasts.show("Couldn't retry this delivery.", kind: .error)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: Providers

    private var providers: some View {
        AccountSection(title: "Available providers", footer: admin ? "Connect a bot account for each chat product your team works in." : "An admin can connect provider accounts.") {
            ForEach(Array(store.providers.enumerated()), id: \.element.id) { index, provider in
                if index > 0 { AccountDivider() }
                Button { connecting = provider } label: {
                    AccountRow(symbol: SupportChannelsStore.symbol(provider.key), tone: SupportChannelsStore.tone(provider.key), title: provider.name, subtitle: SupportChannelsStore.blurb(provider)) {
                        if admin { Chevron() }
                    }
                }
                .buttonStyle(RowPressStyle())
                .disabled(!admin)
            }
        }
    }

    // MARK: Actions

    private func test(_ connection: SupportConnection) {
        busy = connection.id
        Task {
            do {
                let tested = try await store.test(connection.id)
                let ok = tested.status != "error" && tested.healthStatus == "healthy"
                env.toasts.show(ok ? "The connection works." : "Checked. The connection still needs attention.", kind: ok ? .success : .info)
            } catch {
                env.toasts.show("Couldn't test the connection.", kind: .error)
            }
            busy = nil
        }
    }

    private func askDisconnect(_ connection: SupportConnection) {
        confirm = AccountConfirm(title: "Disconnect support channel", message: "Disconnect \(connection.name)? Its destinations are removed and its ticket threads stop updating.", confirmTitle: "Disconnect") {
            do {
                try await store.disconnect(connection.id)
                Haptics.success()
                env.toasts.show("Support channel disconnected.", kind: .success)
            } catch {
                env.toasts.show("Couldn't disconnect the support channel.", kind: .error)
            }
        }
    }

    private func askRemove(_ destination: SupportDestination) {
        confirm = AccountConfirm(title: "Remove destination", message: "Stop mirroring tickets to #\(destination.label)? Threads already posted stay in the channel.", confirmTitle: "Remove") {
            do {
                try await store.removeDestination(destination.id)
                Haptics.success()
                env.toasts.show("Destination removed.", kind: .success)
            } catch {
                env.toasts.show("Couldn't remove the destination.", kind: .error)
            }
        }
    }

    private func makeLinkCode() {
        Task {
            do {
                linkCode = try await store.linkCode()
            } catch {
                env.toasts.show("Couldn't create a link code.", kind: .error)
            }
        }
    }

    struct Detail: View {
        let id: String
        var body: some View { SupportChannelsSettings() }
    }
}

private struct SupportLinkCode: Identifiable {
    let code: String
    var id: String { code }
}

@MainActor
@Observable
final class SupportChannelsStore {
    private(set) var providers: [SupportProvider] = []
    private(set) var connections: [SupportConnection] = []
    private(set) var destinations: [SupportDestination] = []
    private(set) var ollie: [String] = []
    private(set) var deliveries: [SupportDelivery] = []
    private(set) var deliveriesCursor: String?
    private(set) var operations: SupportOperations?
    private(set) var operationsFailed = false
    private(set) var mailboxes: [SettingsMailbox] = []
    private(set) var brands: [SettingsBrand] = []
    private(set) var loaded = false
    private(set) var error: String?

    @ObservationIgnored private(set) var api: APIClient?

    func attach(_ api: APIClient) { self.api = api }

    func provider(_ key: String) -> SupportProvider? { providers.first { $0.key == key } }

    func load(admin: Bool) async {
        guard let api else { return }
        do {
            async let providers: ChannelList<SupportProvider> = api.get("v1/support-channels/providers")
            async let connections: ChannelList<SupportConnection> = api.get("v1/support-channels/connections")
            async let destinations: ChannelList<SupportDestination> = api.get("v1/support-channels/destinations")
            async let ollie: JSONValue? = try? api.get("v1/support-channels/ollie")
            self.providers = try await providers.data
            self.connections = try await connections.data
            self.destinations = try await destinations.data
            self.ollie = await ollie?["actions"]?.array?.compactMap(\.string) ?? []
            error = nil
        } catch {
            if !error.isCancellation { self.error = error.userMessage }
        }
        loaded = true
        if admin {
            async let ops: Void = loadOperations()
            async let list: Void = loadDeliveries(reset: true)
            if let page: ChannelList<SettingsMailbox> = try? await api.get("v1/mailboxes", query: [URLQueryItem(name: "limit", value: "100")]) { mailboxes = page.data }
            if let page: ChannelList<SettingsBrand> = try? await api.get("v1/brands", query: [URLQueryItem(name: "limit", value: "100")]) { brands = page.data }
            _ = await (ops, list)
        }
    }

    func loadOperations() async {
        guard let api else { return }
        do {
            operations = try await api.get("v1/support-channels/operations")
            operationsFailed = false
        } catch {
            if !error.isCancellation { operationsFailed = true }
        }
    }

    func loadDeliveries(reset: Bool) async {
        guard let api else { return }
        var query = [URLQueryItem(name: "limit", value: "50")]
        if !reset, let cursor = deliveriesCursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        guard let page: ChannelList<SupportDelivery> = try? await api.get("v1/support-channels/deliveries", query: query) else { return }
        deliveries = reset ? page.data : deliveries + page.data
        deliveriesCursor = page.nextCursor
    }

    private func upsert(_ connection: SupportConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) { connections[index] = connection } else { connections.append(connection) }
    }

    private func upsert(_ destination: SupportDestination) {
        if let index = destinations.firstIndex(where: { $0.id == destination.id }) { destinations[index] = destination } else { destinations.append(destination) }
    }

    func discover(provider: String, credentials: [String: String]) async throws -> [SupportOption] {
        guard let api else { return [] }
        let body: ChannelBody = ["credentials": .object(credentials.mapValues(JSONValue.string))]
        let page: ChannelList<SupportOption> = try await api.post("v1/support-channels/providers/\(provider)/accounts", body: body)
        return page.data
    }

    func connect(provider: String, name: String, credentials: [String: String]) async throws -> SupportConnection {
        guard let api else { throw CancellationError() }
        var body: ChannelBody = ["provider": .string(provider), "credentials": .object(credentials.mapValues(JSONValue.string))]
        if !name.isEmpty { body["name"] = .string(name) }
        let connection: SupportConnection = try await api.post("v1/support-channels/connections", body: body, idempotencyKey: UUID().uuidString)
        upsert(connection)
        return connection
    }

    func rotate(_ id: String, credentials: [String: String]) async throws {
        guard let api else { return }
        let connection: SupportConnection = try await api.patch("v1/support-channels/connections/\(id)", body: ["credentials": JSONValue.object(credentials.mapValues(JSONValue.string))])
        upsert(connection)
    }

    func test(_ id: String) async throws -> SupportConnection {
        guard let api else { throw CancellationError() }
        let connection: SupportConnection = try await api.post("v1/support-channels/connections/\(id)/test")
        upsert(connection)
        return connection
    }

    func disconnect(_ id: String) async throws {
        guard let api else { return }
        try await api.delete("v1/support-channels/connections/\(id)")
        connections.removeAll { $0.id == id }
        destinations.removeAll { $0.connectionID == id }
    }

    func channels(_ connectionID: String) async throws -> [SupportOption] {
        guard let api else { return [] }
        let page: ChannelList<SupportOption> = try await api.get("v1/support-channels/connections/\(connectionID)/destinations")
        return page.data
    }

    func addDestination(_ body: ChannelBody) async throws {
        guard let api else { return }
        let destination: SupportDestination = try await api.post("v1/support-channels/destinations", body: body, idempotencyKey: UUID().uuidString)
        upsert(destination)
    }

    func patchDestination(_ id: String, _ body: ChannelBody) async throws {
        guard let api else { return }
        let destination: SupportDestination = try await api.patch("v1/support-channels/destinations/\(id)", body: body)
        upsert(destination)
    }

    func removeDestination(_ id: String) async throws {
        guard let api else { return }
        try await api.delete("v1/support-channels/destinations/\(id)")
        destinations.removeAll { $0.id == id }
    }

    /// Turns one of Ollie's actions on or off, saving the whole list in the web's order.
    func setOllie(_ key: String, _ on: Bool) async throws {
        guard let api else { return }
        let before = ollie
        var next = Set(ollie)
        if on { next.insert(key) } else { next.remove(key) }
        ollie = Self.ollieActions.map(\.key).filter { next.contains($0) }
        do {
            let _: JSONValue = try await api.send(APIRequest(method: "PUT", path: "v1/support-channels/ollie", body: try APICoding.encoder.encode(["actions": ollie])))
        } catch {
            ollie = before
            throw error
        }
    }

    func retry(_ delivery: SupportDelivery) async throws {
        guard let api else { return }
        let _: JSONValue = try await api.post("v1/support-channels/deliveries/\(delivery.eventSeq)/retry")
        if let index = deliveries.firstIndex(where: { $0.id == delivery.id }) { deliveries[index].status = "queued" }
    }

    func linkCode() async throws -> String {
        guard let api else { throw CancellationError() }
        let answer: JSONValue = try await api.post("v1/me/support-channel-link-code", idempotencyKey: UUID().uuidString)
        return answer["code"]?.string ?? ""
    }

    // MARK: Copy

    static let ollieActions: [(key: String, title: String, hint: String)] = [
        ("reply", "Send replies", "Ollie may prepare a reply to the customer. It's sent only after the agent confirms."),
        ("note", "Add internal notes", "Ollie may add a note the customer can't see."),
        ("assign_self", "Assign tickets", "Ollie may assign the ticket to the agent talking to it."),
        ("status", "Change status", "Ollie may change the ticket's status. Closing asks for confirmation."),
        ("priority", "Change priority", "Ollie may raise or lower the ticket's priority."),
        ("create_ticket", "Create tickets", "Ollie may create a ticket from a channel message after confirmation."),
    ]

    static func pill(_ connection: SupportConnection) -> (String, Tone) {
        if connection.status == "error" { return ("Needs attention", .red) }
        switch connection.healthStatus {
        case "healthy": return ("Connected", .green)
        case "action_required": return ("Finish setup", .amber)
        case "error": return ("Check failed", .red)
        default: return ("Not tested", .gray)
        }
    }

    static func symbol(_ provider: String) -> String {
        switch provider {
        case "slack": "number"
        case "discord": "gamecontroller"
        case "telegram": "paperplane"
        default: "bubble.left.and.bubble.right"
        }
    }

    static func tone(_ provider: String) -> Tone {
        switch provider {
        case "slack": .violet
        case "discord": .indigo
        case "telegram": .blue
        default: .green
        }
    }

    static func blurb(_ provider: SupportProvider) -> String? {
        switch provider.key {
        case "slack": "Mirror email tickets into Slack threads and work them by talking to Ollie."
        default: provider.description.isEmpty ? nil : provider.description
        }
    }

    static func setup(_ provider: SupportProvider) -> String? {
        switch provider.key {
        case "slack": "Create a Slack app with the chat:write, app_mentions:read, channels:read, groups:read, channels:history, groups:history and files:read bot scopes, install it, then paste its bot token and signing secret. After connecting, opendesk shows the setup steps to finish in Slack."
        case "discord": "Create a Discord bot, turn on its Message Content intent and copy its token and public key. opendesk finds its servers and registers the interactions endpoint and commands."
        case "telegram": "Create a bot with BotFather, turn off its privacy mode (/setprivacy) and paste its token. opendesk sets up the webhook. Then make the bot an admin of a forum group."
        default: nil
        }
    }

    static func setupSteps(_ provider: String) -> [String] {
        switch provider {
        case "slack": [
            "In your Slack app, open Event Subscriptions, turn it on and paste the address above as the Request URL.",
            "Under Subscribe to bot events, add app_mention, message.channels and message.groups, then save.",
            "Open Interactivity & Shortcuts, turn it on and use the same address as its Request URL.",
            "Open Slash Commands, create /opendesk and use the same address as its Request URL.",
            "Invite the bot to each channel you route tickets to: /invite @your-bot.",
        ]
        default: ["Enter this address in the provider's settings as the address it sends events to."]
        }
    }

    static func emptyChannels(_ provider: String) -> String {
        switch provider {
        case "slack": "The bot isn't in any channel yet. Invite it with /invite @your-bot in Slack, then refresh."
        case "discord": "No text channels found. Give the bot access to a text channel in this server, then refresh."
        case "telegram": "No forum groups yet. Make the bot an admin of a group with topics turned on, or send a message in a group it's already in, then refresh."
        default: "No channels found. Refresh after giving the bot access to one."
        }
    }

    static func duration(_ ms: Double) -> String {
        guard ms > 0 else { return "-" }
        if ms < 1000 { return "\(Int(ms)) ms" }
        if ms < 60_000 { return String(format: "%.1f s", ms / 1000) }
        return String(format: "%.1f min", ms / 60_000)
    }
}
