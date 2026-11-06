import SwiftUI

/// Settings › Integrations: the products connected over MCP that Ollie can read and act in,
/// and the catalog to connect more (web `Integrations.tsx`, contracts/integrations.md).
/// Signing in to a product with its own sign-in runs in the web app, whose browser holds the
/// sign-in cookie; the page refreshes when it closes. Tokens and open servers connect here.
struct IntegrationsSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store = IntegrationsStore()
    @State private var category = "all"
    @State private var connecting: WSIntegrationProvider?
    @State private var addingCustom = false
    @State private var web: AccountWebPage?
    @State private var confirm: AccountConfirm?

    private var admin: Bool { env.session.isAdmin }

    var body: some View {
        AccountPage(title: "Integrations") {
            if store.loaded {
                if !admin { SettingsReadOnlyNote(text: "Only admins can connect and change integrations.") }
                intro
                connected
                if admin { catalog }
            } else if let error = store.error {
                ErrorState(message: error) { Task { await store.load() } }
            } else {
                WSLoading(rows: 5)
            }
        }
        .refreshable { await store.load() }
        .task {
            store.attach(env.session.api)
            await store.load()
        }
        .sheet(item: $connecting) { provider in
            WSConnectSheet(provider: provider, store: store) { needsWeb in
                if needsWeb { openWeb() }
            }
            .presentationDetents([.large])
            .presentationCornerRadius(Theme.Radius.sheet)
        }
        .sheet(isPresented: $addingCustom) {
            WSConnectSheet(provider: nil, store: store) { needsWeb in
                if needsWeb { openWeb() }
            }
            .presentationDetents([.large])
            .presentationCornerRadius(Theme.Radius.sheet)
        }
        .sheet(item: $web, onDismiss: { Task { await store.load() } }) { page in
            AccountSafariView(url: page.url).ignoresSafeArea()
        }
        .accountConfirm($confirm)
    }

    private func openWeb() {
        web = env.session.instance.webURL(path: "/settings/integrations").map(AccountWebPage.init)
    }

    // MARK: Sections

    private var intro: some View {
        Text("Connect the tools your team already uses. Ollie can look things up in them and, with approval, make changes there, such as filing an issue from a ticket.")
            .font(ODFont.sans(13.5))
            .foregroundStyle(Theme.fg3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var connected: some View {
        if store.integrations.isEmpty {
            Panel {
                EmptyState(symbol: "puzzlepiece.extension", title: "Nothing connected yet", message: admin ? "Pick a product below to connect it." : "An admin can connect products in Integrations.")
            }
        } else {
            AccountSection(title: "Connected") {
                let list = store.integrations.sorted { ($0.statusRank, $0.name.lowercased()) < ($1.statusRank, $1.name.lowercased()) }
                ForEach(Array(list.enumerated()), id: \.element.id) { index, integration in
                    if index > 0 { Hairline(inset: 58) }
                    SettingsDetailLink(page: .integrations, id: integration.id) {
                        WSIntegrationLine(integration: integration)
                    }
                    .contextMenu { if admin { actions(integration) } }
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ integration: WSIntegration) -> some View {
        Button(integration.enabled ? "Turn off" : "Turn on", systemImage: integration.enabled ? "pause.circle" : "play.circle") {
            Task { await run { try await store.update(integration.id, enabled: !integration.enabled) } }
        }
        if integration.status == "pending" || (integration.status == "error" && integration.authType == "oauth") {
            Button("Sign in on the web", systemImage: "arrow.up.right.square") { openWeb() }
        }
        Button("Refresh tools", systemImage: "arrow.clockwise") {
            Task { await run(success: "Tools refreshed") { try await store.sync(integration.id) } }
        }
        Button("Disconnect", systemImage: "xmark.circle", role: .destructive) { askDisconnect(integration) }
    }

    private var catalog: some View {
        let connectedProviders = Set(store.integrations.map(\.provider))
        let providers = store.catalog
            .filter { category == "all" || $0.category == category }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let categories = ["all"] + WSCategories.all.filter { key in store.catalog.contains { $0.category == key } }
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Connect")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(categories, id: \.self) { key in
                        Button(WSCategories.title(key)) {
                            Haptics.selection()
                            withAnimation(Motion.snappy) { category = key }
                        }
                        .buttonStyle(ChipButtonStyle(filled: category == key))
                    }
                }
            }
            Panel {
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 { Hairline(inset: 58) }
                    Button { connecting = provider } label: {
                        HStack(spacing: 12) {
                            WSIntegrationTile(name: provider.name, provider: provider.key, iconURL: nil)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name).font(ODFont.sans(15.5, weight: .medium)).foregroundStyle(Theme.fg)
                                Text(provider.description).font(ODFont.sans(13)).foregroundStyle(Theme.fg3).lineLimit(2).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            if connectedProviders.contains(provider.key) {
                                TonePill(text: "Connected", tone: .green)
                            } else {
                                Image(systemName: provider.auth == "token" ? "key" : "arrow.up.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.fg4)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
                if !providers.isEmpty { Hairline(inset: 0) }
                Button { addingCustom = true } label: {
                    HStack(spacing: 12) {
                        AccountIconTile(symbol: "server.rack", tone: .gray, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Custom server").font(ODFont.sans(15.5, weight: .medium)).foregroundStyle(Theme.fg)
                            Text("Any remote MCP server, by its URL.").font(ODFont.sans(13)).foregroundStyle(Theme.fg3)
                        }
                        Spacer()
                        Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.fg4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
            }
        }
    }

    // MARK: Actions

    private func run(success: String? = nil, _ action: () async throws -> Void) async {
        do {
            try await action()
            if let success { env.toasts.show(success, kind: .success) }
        } catch {
            env.toasts.error(error)
        }
    }

    private func askDisconnect(_ integration: WSIntegration) {
        confirm = AccountConfirm(
            title: "Disconnect \(integration.name)?",
            message: "Ollie stops using it right away, and its sign-in is deleted. Links on tickets stay.",
            confirmTitle: "Disconnect"
        ) {
            await run(success: "\(integration.name) disconnected") { try await store.disconnect(integration.id) }
        }
    }

    struct Detail: View {
        let id: String

        var body: some View {
            WSIntegrationDetail(id: id)
        }
    }
}

// MARK: - Store

@MainActor
@Observable
final class IntegrationsStore {
    private(set) var integrations: [WSIntegration] = []
    private(set) var catalog: [WSIntegrationProvider] = []
    private(set) var loaded = false
    private(set) var error: String?

    @ObservationIgnored private var api: APIClient?

    func attach(_ api: APIClient) { self.api = api }

    func integration(_ id: String) -> WSIntegration? { integrations.first { $0.id == id } }

    func load() async {
        guard let api else { return }
        do {
            let list: WSList<WSIntegration> = try await api.get("v1/integrations")
            integrations = list.data
            if catalog.isEmpty, let providers: WSList<WSIntegrationProvider> = try? await api.get("v1/integrations/catalog") {
                catalog = providers.data
            }
            loaded = true
            error = nil
        } catch {
            if !error.isCancellation, !loaded { self.error = error.userMessage }
        }
    }

    private func adopt(_ integration: WSIntegration) {
        if let index = integrations.firstIndex(where: { $0.id == integration.id }) {
            integrations[index] = integration
        } else {
            integrations.append(integration)
        }
    }

    struct Connected: Decodable, Sendable {
        var integration: WSIntegration
        var authorizeURL: String?

        enum CodingKeys: String, CodingKey {
            case integration
            case authorizeURL = "authorize_url"
        }
    }

    /// Connects a catalog product or a custom server; `true` when its sign-in has to finish on the web.
    func connect(_ body: [String: JSONValue]) async throws -> Bool {
        guard let api else { return false }
        let result: Connected = try await api.post("v1/integrations", body: JSONValue.object(body))
        adopt(result.integration)
        return result.authorizeURL != nil || result.integration.status == "pending"
    }

    func update(_ id: String, enabled: Bool? = nil, disabled: [String]? = nil, ask: [String]? = nil, auto: [String]? = nil, token: String? = nil) async throws {
        guard let api else { return }
        var body: [String: JSONValue] = [:]
        if let enabled { body["enabled"] = .bool(enabled) }
        if let disabled { body["disabled_tools"] = .array(disabled.map(JSONValue.string)) }
        if let ask { body["ask_tools"] = .array(ask.map(JSONValue.string)) }
        if let auto { body["auto_tools"] = .array(auto.map(JSONValue.string)) }
        if let token { body["token"] = .string(token) }
        let saved: WSIntegration = try await api.patch("v1/integrations/\(id)", body: JSONValue.object(body))
        adopt(saved)
    }

    /// One tool's setting, saved at once; the lists are sent whole.
    func setTool(_ integrationID: String, _ tool: String, enabled: Bool? = nil, askFirst: Bool? = nil, autoRun: Bool? = nil) async throws {
        guard var integration = integration(integrationID), let index = integration.tools.firstIndex(where: { $0.name == tool }) else { return }
        let before = integration
        if let enabled { integration.tools[index].enabled = enabled }
        if let askFirst { integration.tools[index].askFirst = askFirst }
        if let autoRun { integration.tools[index].autoRun = autoRun }
        adopt(integration)
        do {
            try await update(
                integrationID,
                disabled: integration.tools.filter { !$0.enabled }.map(\.name),
                ask: integration.tools.filter { $0.readOnly && $0.askFirst }.map(\.name),
                auto: integration.tools.filter { !$0.readOnly && $0.autoRun }.map(\.name)
            )
        } catch {
            adopt(before)
            throw error
        }
    }

    func sync(_ id: String) async throws {
        guard let api else { return }
        let saved: WSIntegration = try await api.post("v1/integrations/\(id)/sync")
        adopt(saved)
    }

    func disconnect(_ id: String) async throws {
        guard let api else { return }
        try await api.delete("v1/integrations/\(id)")
        integrations.removeAll { $0.id == id }
    }
}

// MARK: - Pieces

struct WSIntegrationTile: View {
    let name: String
    let provider: String
    let iconURL: String?

    var body: some View {
        let tone = WSCategories.tone(provider)
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tone.soft)
            if let iconURL, let url = URL(string: iconURL) {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFit().padding(6)
                    } else {
                        initials(tone)
                    }
                }
            } else {
                initials(tone)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    private func initials(_ tone: Tone) -> some View {
        Text(String(name.prefix(1)).uppercased()).font(ODFont.sans(14, weight: .semibold)).foregroundStyle(tone.text)
    }
}

struct WSIntegrationLine: View {
    let integration: WSIntegration

    var body: some View {
        let state = integration.state
        HStack(spacing: 12) {
            WSIntegrationTile(name: integration.name, provider: integration.provider, iconURL: integration.iconURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(integration.name).font(ODFont.sans(15.5, weight: .medium)).foregroundStyle(Theme.fg).lineLimit(1)
                Text(integration.summary)
                    .font(ODFont.sans(13))
                    .foregroundStyle(integration.status == "error" ? Tone.red.text : Theme.fg3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            TonePill(text: state.title, tone: state.tone)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.fg4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// One connection: its state, on or off, and what each of its tools may do.
struct WSIntegrationDetail: View {
    let id: String

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var store = IntegrationsStore()
    @State private var web: AccountWebPage?
    @State private var confirm: AccountConfirm?
    @State private var newToken = ""
    @State private var replacingToken = false

    private var admin: Bool { env.session.isAdmin }

    var body: some View {
        AccountPage(title: store.integration(id)?.name ?? "Integration") {
            if let integration = store.integration(id) {
                if !admin { SettingsReadOnlyNote(text: "Only admins can change integrations.") }
                header(integration)
                connection(integration)
                tools(integration)
                if admin { danger(integration) }
            } else if store.loaded {
                EmptyState(symbol: "puzzlepiece.extension", title: "Not connected anymore", message: "This integration was disconnected.")
            } else if let error = store.error {
                ErrorState(message: error) { Task { await store.load() } }
            } else {
                WSLoading(rows: 4)
            }
        }
        .refreshable { await store.load() }
        .task {
            store.attach(env.session.api)
            await store.load()
        }
        .sheet(item: $web, onDismiss: { Task { await store.load() } }) { page in
            AccountSafariView(url: page.url).ignoresSafeArea()
        }
        .sheet(isPresented: $replacingToken) {
            WSTokenSheet(title: "Replace token", help: store.catalog.first { $0.key == store.integration(id)?.provider }?.tokenHelp, token: $newToken) {
                try await store.update(id, token: newToken.trimmingCharacters(in: .whitespacesAndNewlines))
                newToken = ""
                env.toasts.show("Token saved", kind: .success)
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(Theme.Radius.sheet)
        }
        .accountConfirm($confirm)
    }

    private func header(_ integration: WSIntegration) -> some View {
        let state = integration.state
        return Panel {
            HStack(spacing: 12) {
                WSIntegrationTile(name: integration.name, provider: integration.provider, iconURL: integration.iconURL)
                VStack(alignment: .leading, spacing: 3) {
                    Text(integration.name).font(ODFont.sans(17, weight: .semibold)).foregroundStyle(Theme.fg)
                    if !integration.host.isEmpty {
                        Text(integration.host).font(ODFont.mono(12.5)).foregroundStyle(Theme.fg3).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                TonePill(text: state.title, tone: state.tone, height: 22)
            }
            .padding(14)
            if integration.status == "error", !integration.lastError.isEmpty {
                Hairline(inset: 0)
                Text(integration.lastError)
                    .font(ODFont.sans(13))
                    .foregroundStyle(Tone.red.text)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func connection(_ integration: WSIntegration) -> some View {
        AccountSection(footer: integration.syncedAt.map { "Tools refreshed \(Format.relLong($0))." }) {
            AccountToggleRow(
                title: "Ollie can use it",
                subtitle: integration.enabled ? "Ollie can use its tools, as set below." : "Turned off. Nothing is deleted.",
                isOn: Binding(get: { integration.enabled }, set: { on in
                    Task { await run { try await store.update(integration.id, enabled: on) } }
                }),
                disabled: !admin
            )
            if admin {
                if integration.authType == "oauth" && integration.status != "connected" {
                    AccountDivider(tiles: false)
                    Button {
                        web = env.session.instance.webURL(path: "/settings/integrations").map(AccountWebPage.init)
                    } label: {
                        AccountRow(title: "Sign in on the web", subtitle: "\(integration.name) signs in in the browser. This page refreshes when you come back.") {
                            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.fg4)
                        }
                    }
                    .buttonStyle(RowPressStyle())
                }
                if integration.authType == "token" {
                    AccountDivider(tiles: false)
                    Button { replacingToken = true } label: {
                        AccountRow(title: "Replace token") { AccountDisclosure() }
                    }
                    .buttonStyle(RowPressStyle())
                }
                AccountDivider(tiles: false)
                Button {
                    Task { await run(success: "Tools refreshed") { try await store.sync(integration.id) } }
                } label: {
                    AccountRow(title: "Refresh tools", subtitle: "Fetch the server's current list of tools.") {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.fg4)
                    }
                }
                .buttonStyle(RowPressStyle())
            }
        }
    }

    @ViewBuilder
    private func tools(_ integration: WSIntegration) -> some View {
        let reads = integration.tools.filter(\.readOnly)
        let writes = integration.tools.filter { !$0.readOnly }
        if integration.tools.isEmpty {
            Panel {
                EmptyState(symbol: "wrench.and.screwdriver", title: "No tools yet", message: integration.status == "connected" ? "Refresh the tools to fetch them from the server." : "The tools appear once it's signed in.")
            }
        } else {
            if !reads.isEmpty {
                AccountSection(title: "Reads", footer: "Lookups run without asking, unless set to ask first.") {
                    ForEach(Array(reads.enumerated()), id: \.element.id) { index, tool in
                        if index > 0 { AccountDivider(tiles: false) }
                        toolRow(integration, tool, modeTitle: "Ask first", mode: tool.askFirst) { on in
                            try await store.setTool(integration.id, tool.name, askFirst: on)
                        }
                    }
                }
            }
            if !writes.isEmpty {
                AccountSection(title: "Changes", footer: "Changes wait for the teammate's approval, unless set to run on their own.") {
                    ForEach(Array(writes.enumerated()), id: \.element.id) { index, tool in
                        if index > 0 { AccountDivider(tiles: false) }
                        toolRow(integration, tool, modeTitle: "Run without asking", mode: tool.autoRun) { on in
                            try await store.setTool(integration.id, tool.name, autoRun: on)
                        }
                    }
                }
            }
        }
    }

    private func toolRow(_ integration: WSIntegration, _ tool: WSIntegrationTool, modeTitle: String, mode: Bool, setMode: @escaping (Bool) async throws -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.title).font(ODFont.sans(15, weight: .medium)).foregroundStyle(tool.enabled ? Theme.fg : Theme.fg4)
                    if !tool.description.isEmpty {
                        Text(tool.description).font(ODFont.sans(12.5)).foregroundStyle(Theme.fg3).lineLimit(3)
                    }
                }
                Spacer(minLength: 8)
                Toggle(tool.title, isOn: Binding(get: { tool.enabled }, set: { on in
                    Task { await run { try await store.setTool(integration.id, tool.name, enabled: on) } }
                }))
                .labelsHidden()
                .tint(Tone.green.solid)
                .disabled(!admin)
            }
            if tool.enabled {
                Button {
                    Task { await run { try await setMode(!mode) } }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode ? "checkmark.square.fill" : "square")
                            .foregroundStyle(mode ? Theme.fg : Theme.fg4)
                        Text(modeTitle).font(ODFont.sans(13)).foregroundStyle(Theme.fg2)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!admin)
                .accessibilityAddTraits(mode ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func danger(_ integration: WSIntegration) -> some View {
        AccountSection {
            Button {
                confirm = AccountConfirm(
                    title: "Disconnect \(integration.name)?",
                    message: "Ollie stops using it right away, and its sign-in is deleted. Links on tickets stay.",
                    confirmTitle: "Disconnect"
                ) {
                    await run(success: "\(integration.name) disconnected") {
                        try await store.disconnect(integration.id)
                        dismiss()
                    }
                }
            } label: {
                AccountRow(symbol: "xmark.circle", tone: .red, title: "Disconnect", titleColor: Tone.red.text)
            }
            .buttonStyle(RowPressStyle())
        }
    }

    private func run(success: String? = nil, _ action: () async throws -> Void) async {
        do {
            try await action()
            if let success { env.toasts.show(success, kind: .success) }
        } catch {
            env.toasts.error(error)
        }
    }
}

/// Connecting a catalog product (`provider`) or, without one, a custom server.
struct WSConnectSheet: View {
    let provider: WSIntegrationProvider?
    let store: IntegrationsStore
    let done: (_ needsWeb: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var name = ""
    @State private var url = ""
    @State private var auth = "none"
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    private var custom: Bool { provider == nil }
    private var usesToken: Bool { custom ? auth == "token" : provider?.auth == "token" }
    private var usesWeb: Bool { custom ? auth == "oauth" : provider?.auth == "oauth" }

    private var ready: Bool {
        if custom {
            guard url.trimmingCharacters(in: .whitespaces).hasPrefix("https://") else { return false }
        }
        return !usesToken || !token.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AccountSheetHeader(title: provider.map { "Connect \($0.name)" } ?? "Custom server", subtitle: provider?.description ?? "Connect any remote MCP server over HTTPS.") { dismiss() }
                if custom {
                    ODTextField(label: "Name", text: $name, prompt: "Order lookup", submitLabel: .next)
                    ODTextField(label: "Server URL", text: $url, prompt: "https://mcp.example.com/mcp", contentType: .URL, keyboard: .URL, submitLabel: .next)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sign-in").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
                        AccountSegmented(options: ["none", "token", "oauth"], selection: $auth) {
                            switch $0 {
                            case "token": "Token"
                            case "oauth": "Its own sign-in"
                            default: "None"
                            }
                        }
                    }
                }
                if usesToken {
                    ODTextField(label: "Access token", text: $token, prompt: "Paste the token", secure: true, submitLabel: .done)
                    if let help = provider?.tokenHelp, !help.isEmpty {
                        Text(help).font(ODFont.footnote).foregroundStyle(Theme.fg3).fixedSize(horizontal: false, vertical: true)
                    }
                    if let raw = provider?.tokenURL, let link = URL(string: raw) {
                        Button("Create a token", systemImage: "arrow.up.right") { openURL(link) }
                            .font(ODFont.sans(14, weight: .medium))
                            .foregroundStyle(Tone.blue.text)
                    }
                }
                if usesWeb {
                    Notice(text: "Signing in to \(provider?.name ?? "the server") finishes in the web app. It opens next, and this page refreshes when you close it.", tone: .blue, symbol: "safari")
                }
                FormError(text: error)
                Button(action: connect) { ButtonLabel(title: usesWeb ? "Continue on the web" : "Connect", busy: busy) }
                    .buttonStyle(InkButtonStyle())
                    .disabled(!ready || busy)
            }
            .padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.surface)
    }

    private func connect() {
        // The web app's browser holds the cookie a product's own sign-in needs, so it starts there.
        if usesWeb && !custom {
            dismiss()
            done(true)
            return
        }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            var body: [String: JSONValue] = ["provider": .string(provider?.key ?? "custom")]
            if custom {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { body["name"] = .string(trimmed) }
                body["url"] = .string(url.trimmingCharacters(in: .whitespaces))
                body["auth"] = .string(auth)
            }
            if usesToken { body["token"] = .string(token.trimmingCharacters(in: .whitespacesAndNewlines)) }
            do {
                let needsWeb = try await store.connect(body)
                Haptics.success()
                dismiss()
                done(needsWeb)
            } catch {
                Haptics.error()
                self.error = error.userMessage
            }
        }
    }
}

/// Pasting a new token for a token sign-in.
struct WSTokenSheet: View {
    let title: String
    let help: String?
    @Binding var token: String
    let save: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AccountSheetHeader(title: title, subtitle: help) { dismiss() }
            ODTextField(label: "Access token", text: $token, prompt: "Paste the token", secure: true, submitLabel: .done)
            FormError(text: error)
            Button {
                busy = true
                error = nil
                Task {
                    defer { busy = false }
                    do {
                        try await save()
                        dismiss()
                    } catch {
                        self.error = error.userMessage
                    }
                }
            } label: { ButtonLabel(title: "Save token", busy: busy) }
                .buttonStyle(InkButtonStyle())
                .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Theme.surface)
    }
}
