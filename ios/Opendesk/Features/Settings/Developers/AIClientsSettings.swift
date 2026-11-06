import SwiftUI

/// Settings › AI clients: use opendesk from Claude, ChatGPT, Cursor, VS Code and other MCP
/// clients (contracts/agent.md "opendesk MCP server"). The server URL, copyable setup per client,
/// an API key made in place for clients that send a header, the clients connected with sign-in
/// (disconnect with a confirm), and the tools. Every member sees it; admins see everyone's clients.
struct AIClientsSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var server: AIClientServerInfo?
    @State private var serverError: String?
    @State private var connections: [AIClientConnectionRecord] = []
    @State private var connectionsLoaded = false
    @State private var connectionsError: String?
    @State private var client: AIClientSetup = .claude
    /// A key made on this page fills the snippets until the page is left; never stored.
    @State private var key: String?
    @State private var creatingKey = false
    @State private var confirm: AccountConfirm?

    private var admin: Bool { env.session.isAdmin }

    var body: some View {
        AccountPage(title: "AI clients", spacing: 22) {
            Text("Use opendesk from Claude, ChatGPT, Cursor, VS Code and other MCP clients. They work your tickets, contacts and help articles with the access you give them.")
                .font(ODFont.footnote)
                .foregroundStyle(Theme.fg3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            AccountSection(title: "MCP server URL", footer: "Clients that sign in with OAuth need only this address.") {
                Group {
                    if let server {
                        DevCopyField(value: server.url)
                    } else if let serverError {
                        HStack {
                            Text(serverError).font(ODFont.footnote).foregroundStyle(Tone.red.text)
                            Spacer()
                            Button("Try again") { Task { await loadServer() } }
                                .font(ODFont.sans(13.5, weight: .medium))
                                .foregroundStyle(Theme.fg)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: Theme.Radius.control).fill(Theme.active).frame(height: 42)
                    }
                }
                .padding(12)
            }

            if let server { setup(url: server.url) }

            connectionsSection

            if let server, !server.tools.isEmpty { tools(server.tools) }
        }
        .sheet(isPresented: $creatingKey) {
            AIClientKeySheet(client: client.label) { secret in key = secret }
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        .accountConfirm($confirm)
        .task {
            async let a: Void = loadServer()
            async let b: Void = loadConnections()
            _ = await (a, b)
        }
        .refreshable {
            await loadServer()
            await loadConnections()
        }
    }

    // MARK: Setup

    private func setup(url: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel("Connect a client")
                Text("Pick your client and follow the steps.").font(ODFont.footnote).foregroundStyle(Theme.fg3)
            }
            .padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AIClientSetup.allCases) { value in
                        let chosen = value == client
                        Button {
                            Haptics.selection()
                            withAnimation(Motion.snappy) { client = value }
                        } label: {
                            Text(value.label)
                                .font(ODFont.sans(13.5, weight: chosen ? .semibold : .medium))
                                .foregroundStyle(chosen ? Theme.inverseFg : Theme.fg2)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(chosen ? Theme.inverse : Theme.surface, in: Capsule())
                                .overlay(Capsule().strokeBorder(chosen ? Color.clear : Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(TapScaleStyle(scale: 0.95))
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        TonePill(text: client.oauth ? "Sign in" : "API key", tone: client.oauth ? .green : .gray, height: 19) {
                            Image(systemName: client.oauth ? "person.badge.key" : "key").font(.system(size: 9, weight: .semibold))
                        }
                        Text(client.steps)
                            .font(ODFont.footnote)
                            .foregroundStyle(Theme.fg2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(client.snippets(url: url, key: key).enumerated()), id: \.offset) { _, snippet in
                        DevCopyField(value: snippet, multiline: snippet.contains("\n"), secret: key.map { snippet.contains($0) } ?? false)
                    }
                    let extra = client.keySnippets(url: url, key: key)
                    if !extra.isEmpty {
                        Text("Or send an API key as a header instead of signing in:").font(ODFont.footnote).foregroundStyle(Theme.fg3)
                        ForEach(Array(extra.enumerated()), id: \.offset) { _, snippet in
                            DevCopyField(value: snippet, multiline: true, secret: key != nil)
                        }
                    }
                    if client.usesKey { keyNotice }
                    if let key, client.usesKey { DevCopyField(value: key, secret: true) }
                }
                .padding(14)
                .id(client)
                .transition(.opacity)
            }
        }
    }

    private var keyNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "key").font(.system(size: 12)).foregroundStyle(Theme.fg4)
            if key != nil {
                Text("Copy it now. It's shown once and filled into the snippets above until you leave this page.")
                    .fixedSize(horizontal: false, vertical: true)
            } else if admin {
                Text("This client sends an API key in a header.").fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Create a key for it") { creatingKey = true }
                    .buttonStyle(ChipButtonStyle())
            } else {
                Text("Ask an admin to create an API key for it.")
            }
            Spacer(minLength: 0)
        }
        .font(ODFont.footnote)
        .foregroundStyle(Theme.fg3)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    // MARK: Connections

    private var connectionsSection: some View {
        AccountSection(
            title: "Connected clients",
            footer: admin
                ? "Clients connected with sign-in, for every member. They act as the person who connected them."
                : "Clients connected with sign-in. They act as the person who connected them."
        ) {
            if !connectionsLoaded {
                SkeletonRows(count: 2)
            } else if let connectionsError, connections.isEmpty {
                EmptyState(symbol: "exclamationmark.triangle", title: "Couldn't load connected clients.", message: connectionsError, actionTitle: "Try again") {
                    Task { await loadConnections() }
                }
            } else if connections.isEmpty {
                VStack(spacing: 6) {
                    EmptyState(
                        symbol: "cable.connector",
                        title: "No clients connected yet",
                        message: "Add opendesk as a connector in Claude or ChatGPT with the URL above. It shows up here once you approve it."
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        tip("person.badge.key", "Sign in, no key to copy")
                        tip("checkmark.shield", "Never more than your role allows")
                    }
                    .padding(.bottom, 24)
                }
            } else {
                ForEach(Array(connections.enumerated()), id: \.element.id) { index, connection in
                    if index > 0 { Hairline(inset: 56) }
                    connectionRow(connection)
                }
            }
        }
        .motion(Motion.snappy, value: connections.map(\.id))
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Theme.fg3).frame(width: 18)
            Text(text).font(ODFont.footnote).foregroundStyle(Theme.fg2)
        }
    }

    private func connectionRow(_ c: AIClientConnectionRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AccountIconTile(symbol: "cable.connector", tone: .violet)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.client.name).font(ODFont.sans(15.5, weight: .medium)).foregroundStyle(Theme.fg).lineLimit(1)
                    Text(c.client.local ? "an app on this computer" : c.client.redirectHost)
                        .font(ODFont.sans(12))
                        .foregroundStyle(Theme.fg4)
                        .lineLimit(1)
                }
                FlowLayout(spacing: 4) {
                    ForEach(c.scopes, id: \.self) { DevScopeChip(scope: $0) }
                }
                HStack(spacing: 8) {
                    if admin, let user = c.user {
                        HStack(spacing: 5) {
                            Avatar(name: user.displayName, url: user.avatarURL, seed: user.id, size: 16)
                            Text(c.mine ? "you" : user.displayName).foregroundStyle(Theme.fg2).lineLimit(1)
                        }
                    }
                    if let used = c.lastUsedAt {
                        Text("Last used \(Format.relLong(used))").foregroundStyle(Theme.fg3)
                    }
                }
                .font(ODFont.sans(12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                confirm = AccountConfirm(
                    title: "Disconnect \(c.client.name)?",
                    message: "It stops working right away and needs to sign in again to reconnect.",
                    confirmTitle: "Disconnect"
                ) { await revoke(c) }
            } label: {
                Label("Disconnect", systemImage: "powerplug")
                    .labelStyle(.titleAndIcon)
                    .font(ODFont.sans(12.5, weight: .medium))
            }
            .buttonStyle(ChipButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Tools

    private func tools(_ tools: [AIClientTool]) -> some View {
        AccountSection(title: "Tools it offers", footer: "A client sees a tool only when its access includes the tool's scopes.") {
            ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                if index > 0 { Hairline(inset: 14) }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(tool.name).font(ODFont.mono(12.5)).foregroundStyle(Theme.fg)
                        TonePill(text: tool.readOnly ? "Read" : "Changes data", tone: tool.readOnly ? .gray : .amber, height: 18)
                    }
                    if !tool.description.isEmpty {
                        Text(tool.firstSentence).font(ODFont.footnote).foregroundStyle(Theme.fg3).fixedSize(horizontal: false, vertical: true)
                    }
                    if !tool.scopes.isEmpty {
                        FlowLayout(spacing: 4) { ForEach(tool.scopes, id: \.self) { DevMonoChip(text: $0) } }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Loading

    private func loadServer() async {
        do {
            server = try await env.session.api.get("v1/ai-clients/server")
            serverError = nil
        } catch {
            if !error.isCancellation, server == nil { serverError = error.userMessage }
        }
    }

    private func loadConnections() async {
        do {
            let list: Page<AIClientConnectionRecord> = try await env.session.api.get("v1/ai-clients/connections")
            connections = list.data
            connectionsError = nil
        } catch {
            if !error.isCancellation { connectionsError = error.userMessage }
        }
        connectionsLoaded = true
    }

    private func revoke(_ c: AIClientConnectionRecord) async {
        let before = connections
        withAnimation(Motion.snappy) { connections.removeAll { $0.id == c.id } }
        do {
            try await env.session.api.delete("v1/ai-clients/connections/\(c.id)")
            Haptics.success()
        } catch {
            connections = before
            env.toasts.show("Couldn't disconnect the client.", kind: .error)
        }
    }

    struct Detail: View {
        let id: String

        var body: some View {
            AIClientsSettings()
        }
    }
}

/// An API key for an AI client: a name, read or read and write, and an expiry. Asks for a fresh
/// sign-in as any new key does; the secret goes back to the page, which shows it once.
struct AIClientKeySheet: View {
    let client: String
    let onCreated: (String) -> Void

    private enum Access: String, CaseIterable { case read, write }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var access: Access = .read
    @State private var expiry: APIKeyExpiryPreset = .days90
    @State private var busy = false
    @State private var error: String?
    @State private var reauth: AccountStore.ReauthPrompt?
    @State private var ready = false

    private var scopes: [String] { access == .read ? AIClientSetup.readScopes : AIClientSetup.writeScopes }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AccountSheetHeader(title: "Create an API key for an AI client", subtitle: "The client gets only the tools these scopes allow.", closeLabel: "Cancel") { dismiss() }
                ODTextField(label: "Name", text: Binding(get: { name }, set: { name = String($0.prefix(80)) }), prompt: "Cursor on my laptop", submitLabel: .done)
                VStack(alignment: .leading, spacing: 8) {
                    DevFieldLabel(title: "Access")
                    AccountSegmented(options: Access.allCases, selection: $access) { $0 == .read ? "Read only" : "Read and write" }
                    Text(access == .read ? "Search and read tickets, contacts and articles." : "Also reply, add notes, update tickets and draft articles.")
                        .font(ODFont.footnote)
                        .foregroundStyle(Theme.fg3)
                    FlowLayout(spacing: 4) { ForEach(scopes, id: \.self) { DevScopeChip(scope: $0) } }
                }
                VStack(alignment: .leading, spacing: 8) {
                    DevFieldLabel(title: "Expires")
                    AccountSegmented(options: [APIKeyExpiryPreset.days30, .days90, .days365], selection: $expiry) { $0.short }
                }
                FormError(text: error)
                Button(action: submit) { ButtonLabel(title: "Create key", busy: busy) }
                    .buttonStyle(InkButtonStyle())
                    .disabled(busy)
            }
            .padding(22)
            .motion(Motion.snappy, value: error)
            .motion(Motion.snappy, value: access)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.surface)
        .devReauth($reauth)
        .onAppear {
            guard !ready else { return }
            ready = true
            name = client
        }
    }

    private func submit() {
        error = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Give the key a name."
            return
        }
        let new = APIKeysStore.NewKey(name: trimmed, scopes: scopes, expiresAt: expiry.date())
        busy = true
        Task {
            do {
                try await create(new)
            } catch {
                if let prompt = DevReauth.prompt(for: error, retry: { try await create(new) }) {
                    reauth = prompt
                } else if !error.isCancellation {
                    Haptics.error()
                    self.error = error.userMessage
                }
            }
            busy = false
        }
    }

    private func create(_ new: APIKeysStore.NewKey) async throws {
        APIKeysStore.shared.attach(env.session)
        let created = try await APIKeysStore.shared.create(new)
        Haptics.success()
        onCreated(created.secret)
        dismiss()
    }
}
