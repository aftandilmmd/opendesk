import SwiftUI

/// Settings › Mail accounts: the member's own Collab accounts (contracts/collab.md), private
/// or shared. IMAP connects here; Google and Microsoft sign in through the web app, whose
/// sign-in cookie the provider's callback checks. `Detail` opens an account by id.
struct MailAccountsSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store = MailAccountsStore()
    @State private var connecting = false
    @State private var web: String?

    var body: some View {
        AccountPage(title: "Mail accounts") {
            Text("Your own mail accounts, read and answered in opendesk like a mail client. Each change happens at your provider too.")
                .font(ODFont.callout)
                .foregroundStyle(Theme.fg3)
                .padding(.horizontal, 4)
            ChannelLoading(loaded: store.loaded, error: store.accounts.isEmpty ? store.error : nil, retry: reload) {
                if !store.status.enabled {
                    EmptyState(symbol: "at", title: "Collab is not on this plan", message: store.status.reason == "disabled" ? "Collab is turned off on this instance." : "Connect your own mail accounts with the Collab plan.")
                        .padding(.top, 30)
                } else if store.accounts.isEmpty {
                    empty
                } else {
                    let mine = store.accounts.filter { $0.account.owner?.id == env.session.user?.id }
                    let shared = store.accounts.filter { $0.account.owner?.id != env.session.user?.id }
                    if !mine.isEmpty { section("Yours", mine) }
                    if !shared.isEmpty { section("Shared with you", shared) }
                }
            }
        }
        .toolbar {
            if env.session.canWrite, store.status.enabled, !store.accounts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { connecting = true } label: { Image(systemName: "plus") }.accessibilityLabel("Connect an account")
                }
            }
        }
        .sheet(isPresented: $connecting) {
            MailAccountConnectSheet(store: store) { path in web = path }
        }
        .channelWebSheet($web) { reload() }
        .refreshable { await store.load(admin: env.session.isAdmin) }
        .onAppear {
            store.attach(env.session.api)
            reload()
        }
    }

    private func reload() { Task { await store.load(admin: env.session.isAdmin) } }

    private var empty: some View {
        VStack(spacing: 16) {
            EmptyState(
                symbol: "at",
                title: "No mail accounts yet",
                message: "Connect a Google, Microsoft or IMAP account to read and answer its mail here.",
                actionTitle: env.session.canWrite ? "Connect an account" : nil,
                action: env.session.canWrite ? { connecting = true } : nil
            )
            AccountSection {
                AccountRow(symbol: "lock", tone: .gray, title: "Private: only you see it")
                AccountDivider()
                AccountRow(symbol: "person.2", tone: .blue, title: "Shared: your team helps answer")
            }
        }
        .padding(.top, 20)
    }

    private func section(_ title: String, _ accounts: [SettingsMailAccount]) -> some View {
        AccountSection(title: title) {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, item in
                if index > 0 { AccountDivider() }
                SettingsDetailLink(page: .mailAccounts, id: item.id) {
                    MailAccountRow(item: item, me: env.session.user?.id, audience: audience(item.account))
                }
            }
        }
    }

    private func audience(_ account: MailAccount) -> String? {
        guard !account.isPrivate else { return nil }
        let audience = account.sharedWith
        if audience.everyone { return "Everyone" }
        var parts: [String] = []
        if !audience.teamIDs.isEmpty { parts.append(ChannelFormat.plural(audience.teamIDs.count, "team")) }
        if !audience.userIDs.isEmpty { parts.append(audience.userIDs.count == 1 ? "1 person" : "\(audience.userIDs.count) people") }
        return parts.isEmpty ? "Only you" : parts.joined(separator: ", ")
    }

    struct Detail: View {
        let id: String
        var body: some View { MailAccountDetailView(id: id) }
    }
}

struct MailAccountRow: View {
    let item: SettingsMailAccount
    var me: String?
    var audience: String?

    var body: some View {
        let account = item.account
        HStack(alignment: .top, spacing: 12) {
            AccountIconTile(symbol: MailAccountsStore.symbol(account.provider), tone: account.tone)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle().fill(account.tone.solid).frame(width: 7, height: 7)
                    Text(account.label).font(ODFont.sans(15.5, weight: .medium)).foregroundStyle(Theme.fg).lineLimit(1)
                    TonePill(text: account.isPrivate ? "Private" : "Shared", tone: account.isPrivate ? .gray : .blue, height: 19) {
                        Image(systemName: account.isPrivate ? "lock" : "person.2").font(.system(size: 9, weight: .semibold))
                    }
                    Spacer(minLength: 4)
                    MailAccountStatusPill(account: account)
                }
                Text(subline).font(ODFont.footnote).foregroundStyle(Theme.fg3).lineLimit(2)
                Text(account.lastSyncedAt.map { "Synced \(Format.relLong($0))" } ?? "Not synced yet").font(ODFont.sans(12)).foregroundStyle(Theme.fg3)
            }
            Chevron().padding(.top, 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var subline: String {
        let account = item.account
        var parts = [account.email]
        if let owner = account.owner {
            parts.append("Connected by \(owner.id == me ? "you" : owner.displayName)")
        } else {
            parts.append("Its owner left the workspace")
        }
        if let audience { parts.append(audience) }
        return parts.joined(separator: " · ")
    }
}

struct MailAccountStatusPill: View {
    let account: MailAccount

    var body: some View {
        if account.reconnect {
            TonePill(text: "Reconnect needed", tone: .red)
        } else {
            switch account.status {
            case "syncing": TonePill(text: "Syncing", tone: .blue) { PingDot(color: Tone.blue.solid, size: 5) }
            case "error": TonePill(text: "Error", tone: .red)
            case "paused": TonePill(text: "Paused", tone: .gray)
            default: TonePill(text: "Active", tone: .green)
            }
        }
    }
}

/// "Connect a mail account": where it is, who sees it, and for IMAP its servers.
struct MailAccountConnectSheet: View {
    let store: MailAccountsStore
    /// Opens the web app at a path (Google and Microsoft sign-in).
    let openWeb: (String) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var provider: String?
    @State private var shared = false
    @State private var audience = MailAudience(everyone: true)
    @State private var history = "1y"
    @State private var form = MailImapForm()
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ChannelSheet(title: provider == "imap" ? "Other (IMAP)" : "Connect a mail account") {
            if provider == nil {
                providerChoices
            } else {
                MailVisibilityPicker(shared: $shared, audience: $audience, canBePrivate: true)
                ChannelMenuField(label: "Older mail", value: MailAccountsStore.historyLabel(history), hint: "The last 30 days arrive first. Older mail follows in the background, and you can change this in the account's settings.") {
                    ForEach(["none", "1y", "2y", "5y", "all"], id: \.self) { value in Button(MailAccountsStore.historyLabel(value)) { history = value } }
                }
                if provider == "imap" {
                    imap
                } else {
                    let name = provider == "google" ? "Google" : "Microsoft"
                    Notice(text: "Signing in with \(name) runs in the web app, which opens here. Choose who sees the account there too; it keeps its own sign-in.")
                    Button("Continue with \(name)") {
                        dismiss()
                        openWeb("/settings/mail-accounts")
                    }
                    .buttonStyle(InkButtonStyle())
                }
                FormError(text: error)
                Button("Back") { provider = nil }.buttonStyle(OutlineButtonStyle())
                ChannelHint("opendesk never deletes mail at your provider.")
            }
        }
    }

    @ViewBuilder
    private var providerChoices: some View {
        Text("Where is the account?").font(ODFont.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
        let options = [("google", "Google", "Gmail and Google Workspace", store.status.google), ("microsoft", "Microsoft", "Outlook and Microsoft 365", store.status.microsoft), ("imap", "Other (IMAP)", "Any server with IMAP and SMTP", store.status.imap)].filter(\.3)
        if options.isEmpty {
            Notice(text: "No provider is set up on this instance yet. Ask whoever runs it to add a Google or Microsoft client, or turn on IMAP.")
        } else {
            VStack(spacing: 0) {
                ForEach(options, id: \.0) { option in
                    Button { provider = option.0 } label: {
                        AccountRow(symbol: MailAccountsStore.symbol(MailProvider(rawValue: option.0) ?? .imap), tone: .gray, title: option.1, subtitle: option.2) { Chevron() }
                    }
                    .buttonStyle(RowPressStyle())
                    if option.0 != options.last?.0 { Hairline(inset: 56) }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
    }

    @ViewBuilder
    private var imap: some View {
        ODTextField(label: "Email address", text: Binding(get: { form.email }, set: { form.setEmail($0) }), prompt: "name@company.com", contentType: .emailAddress, keyboard: .emailAddress)
        if let preset = form.preset { ChannelHint("Settings for \(preset) filled in") }
        ODTextField(label: "Name in the sidebar", text: $form.name, prompt: "Work, Sales, Personal")
        ODTextField(label: form.appPassword ? "App password" : "Password", text: $form.password, prompt: "", secure: true, contentType: .password)
        if form.appPassword, let preset = form.preset { ChannelHint("\(preset) needs an app password, made in its account settings.") }
        MailImapServerFields(form: $form)
        Button(action: submit) { ButtonLabel(title: saving ? "Signing in to both servers" : "Connect account", busy: saving) }
            .buttonStyle(InkButtonStyle())
            .disabled(saving || !form.valid(passwordRequired: true) || (shared && audience.isEmpty))
    }

    private func submit() {
        saving = true
        error = nil
        Task {
            do {
                var body = form.connectBody()
                body["visibility"] = .string(shared ? "shared" : "private")
                if shared { body["shared_with"] = MailAccountsStore.audienceJSON(audience) }
                if let since = MailAccountsStore.historySince(history) { body["history"] = .object(["since": since]) }
                let account = try await store.connectIMAP(body)
                Haptics.success()
                env.toasts.show("\(account.account.email) is connected. Its mail is syncing.", kind: .success)
                dismiss()
            } catch {
                Haptics.error()
                self.error = "Could not sign in. " + ((error as? APIError)?.detail ?? error.userMessage)
            }
            saving = false
        }
    }
}

/// Private or shared, and with whom: everyone, or teams and people.
struct MailVisibilityPicker: View {
    @Binding var shared: Bool
    @Binding var audience: MailAudience
    var canBePrivate = true
    var disabled = false
    /// The account's owner, who sees it anyway (the person connecting it when nil).
    var exclude: String?

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who sees it?").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
            VStack(spacing: 0) {
                AccountChoiceRow(symbol: "lock", title: "Private", subtitle: "Only you. Admins cannot see it either.", chosen: !shared) { shared = false }
                    .disabled(!canBePrivate || disabled)
                    .opacity(canBePrivate ? 1 : 0.5)
                Hairline(inset: 56)
                AccountChoiceRow(symbol: "person.2", tone: .blue, title: "Shared", subtitle: "Teammates you choose read and answer it with you.", chosen: shared) {
                    shared = true
                    if audience.isEmpty { audience = MailAudience(everyone: true) }
                }
                .disabled(disabled)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            if shared {
                AccountSegmented(options: [true, false], selection: Binding(get: { audience.everyone }, set: { everyone in
                    audience.everyone = everyone
                }), label: { $0 ? "Everyone" : "Choose teams and people" })
                .disabled(disabled)
                if !audience.everyone {
                    Text("Teams").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
                    pickList(env.directory.teams.map { ($0.id, $0.name) }, selected: $audience.teamIDs)
                    Text("People").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
                    pickList(env.directory.members.filter { $0.id != (exclude ?? env.session.user?.id) }.map { ($0.id, $0.user.name) }, selected: $audience.userIDs)
                    if audience.isEmpty { FormError(text: "Pick at least one team or person, or share with everyone") }
                }
            }
        }
    }

    private func pickList(_ items: [(String, String)], selected: Binding<[String]>) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.0) { index, item in
                if index > 0 { Hairline(inset: 14) }
                AccountChoiceRow(title: item.1, chosen: selected.wrappedValue.contains(item.0)) {
                    if let at = selected.wrappedValue.firstIndex(of: item.0) { selected.wrappedValue.remove(at: at) } else { selected.wrappedValue.append(item.0) }
                }
                .disabled(disabled)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// An IMAP account's address, password and servers (the web's IMAP form and presets).
struct MailImapForm: Equatable {
    var email = ""
    var name = ""
    var password = ""
    var smtpPassword = ""
    var settings = MailImapSettings()
    var preset: String?
    var appPassword = false

    struct Preset {
        var name: String
        var domains: [String]
        var imap: String
        var smtp: String
        var smtpPort = 465
        var appPassword = false
    }

    static let presets = [
        Preset(name: "Gmail", domains: ["gmail.com", "googlemail.com"], imap: "imap.gmail.com", smtp: "smtp.gmail.com", appPassword: true),
        Preset(name: "Outlook.com", domains: ["outlook.com", "hotmail.com", "live.com"], imap: "outlook.office365.com", smtp: "smtp.office365.com", smtpPort: 587),
        Preset(name: "iCloud Mail", domains: ["icloud.com", "me.com", "mac.com"], imap: "imap.mail.me.com", smtp: "smtp.mail.me.com", smtpPort: 587, appPassword: true),
        Preset(name: "Yahoo", domains: ["yahoo.com", "ymail.com"], imap: "imap.mail.yahoo.com", smtp: "smtp.mail.yahoo.com", appPassword: true),
        Preset(name: "AOL", domains: ["aol.com"], imap: "imap.aol.com", smtp: "smtp.aol.com", appPassword: true),
        Preset(name: "Fastmail", domains: ["fastmail.com", "fastmail.fm"], imap: "imap.fastmail.com", smtp: "smtp.fastmail.com", appPassword: true),
        Preset(name: "Zoho", domains: ["zoho.com", "zohomail.com"], imap: "imap.zoho.com", smtp: "smtp.zoho.com"),
        Preset(name: "GMX", domains: ["gmx.com", "gmx.net", "gmx.de"], imap: "imap.gmx.com", smtp: "mail.gmx.com", smtpPort: 587),
        Preset(name: "Yandex", domains: ["yandex.com", "yandex.ru"], imap: "imap.yandex.com", smtp: "smtp.yandex.com", appPassword: true),
    ]

    /// Typing a known domain fills its servers; another domain guesses imap. and smtp.
    mutating func setEmail(_ value: String) {
        email = value
        let domain = value.split(separator: "@").last.map { String($0).lowercased() } ?? ""
        guard value.contains("@"), !domain.isEmpty else { return }
        if let known = Self.presets.first(where: { $0.domains.contains(domain) }) {
            preset = known.name
            appPassword = known.appPassword
            settings.imapHost = known.imap
            settings.imapPort = 993
            settings.imapTLS = "tls"
            settings.smtpHost = known.smtp
            settings.smtpPort = known.smtpPort
            settings.smtpTLS = known.smtpPort == 465 ? "tls" : "starttls"
        } else if domain.contains(".") {
            preset = nil
            appPassword = false
            settings.imapHost = "imap.\(domain)"
            settings.imapPort = 993
            settings.imapTLS = "tls"
            settings.smtpHost = "smtp.\(domain)"
            settings.smtpPort = 465
            settings.smtpTLS = "tls"
        }
    }

    func valid(passwordRequired: Bool) -> Bool {
        (!passwordRequired || !password.isEmpty) && (email.isEmpty || ChannelValidate.email(email) || !passwordRequired)
            && ChannelServerFields.valid(host: settings.imapHost, port: settings.imapPort)
            && ChannelServerFields.valid(host: settings.smtpHost, port: settings.smtpPort)
    }

    func connectBody() -> ChannelBody {
        var body: ChannelBody = [
            "email": .string(email.trimmingCharacters(in: .whitespaces)),
            "imap_host": .string(settings.imapHost.trimmingCharacters(in: .whitespaces)), "imap_port": .chInt(settings.imapPort), "imap_tls": .string(settings.imapTLS),
            "smtp_host": .string(settings.smtpHost.trimmingCharacters(in: .whitespaces)), "smtp_port": .chInt(settings.smtpPort), "smtp_tls": .string(settings.smtpTLS),
            "password": .string(password),
        ]
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { body["name"] = .string(name.trimmingCharacters(in: .whitespaces)) }
        if !settings.imapUsername.isEmpty { body["imap_username"] = .string(settings.imapUsername) }
        if !settings.smtpUsername.isEmpty { body["smtp_username"] = .string(settings.smtpUsername) }
        if !smtpPassword.isEmpty { body["smtp_password"] = .string(smtpPassword) }
        return body
    }
}

/// The IMAP and SMTP blocks, and usernames when they are not the address.
struct MailImapServerFields: View {
    @Binding var form: MailImapForm
    @State private var advanced = false

    var body: some View {
        ChannelServerFields(title: "IMAP server", host: $form.settings.imapHost, port: $form.settings.imapPort, security: $form.settings.imapTLS, hostPrompt: "imap.example.com", tlsPort: 993, starttlsPort: 143)
        ChannelServerFields(title: "SMTP server", host: $form.settings.smtpHost, port: $form.settings.smtpPort, security: $form.settings.smtpTLS, hostPrompt: "smtp.example.com", tlsPort: 465, starttlsPort: 587)
        DisclosureGroup(isExpanded: $advanced) {
            VStack(alignment: .leading, spacing: 12) {
                ODTextField(label: "IMAP username", text: $form.settings.imapUsername, prompt: form.email, keyboard: .emailAddress)
                ODTextField(label: "SMTP username", text: $form.settings.smtpUsername, prompt: form.settings.imapUsername.isEmpty ? form.email : form.settings.imapUsername, keyboard: .emailAddress)
                ODTextField(label: "SMTP password", text: $form.smtpPassword, prompt: "", secure: true)
                ChannelHint("Only when it differs from the IMAP password")
            }
            .padding(.top, 10)
        } label: {
            Text("Advanced: Usernames, when they are not the address").font(ODFont.sans(14, weight: .medium)).foregroundStyle(Theme.fg)
        }
        .tint(Theme.fg2)
    }
}

@MainActor
@Observable
final class MailAccountsStore {
    private(set) var status = CollabSettingsStatus()
    private(set) var accounts: [SettingsMailAccount] = []
    private(set) var loaded = false
    private(set) var error: String?

    @ObservationIgnored private(set) var api: APIClient?

    func attach(_ api: APIClient) { self.api = api }

    func load(admin: Bool) async {
        guard let api else { return }
        do {
            status = try await api.get("v1/collab")
            if status.enabled {
                let query = admin ? [URLQueryItem(name: "manage", value: "true")] : []
                let list: ChannelList<SettingsMailAccount> = try await api.get("v1/collab/accounts", query: query)
                accounts = list.data
            }
            error = nil
        } catch {
            if !error.isCancellation { self.error = error.userMessage }
        }
        loaded = true
    }

    func account(_ id: String) -> SettingsMailAccount? { accounts.first { $0.id == id } }

    private func upsert(_ account: SettingsMailAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index] = account } else { accounts.append(account) }
    }

    func connectIMAP(_ body: ChannelBody) async throws -> SettingsMailAccount {
        guard let api else { throw CancellationError() }
        let account: SettingsMailAccount = try await api.post("v1/collab/accounts/imap", body: body, idempotencyKey: UUID().uuidString)
        upsert(account)
        return account
    }

    func patch(_ id: String, _ body: ChannelBody) async throws -> SettingsMailAccount {
        guard let api else { throw CancellationError() }
        let account: SettingsMailAccount = try await api.patch("v1/collab/accounts/\(id)", body: body)
        upsert(account)
        return account
    }

    func remove(_ id: String) async throws {
        guard let api else { return }
        try await api.delete("v1/collab/accounts/\(id)")
        accounts.removeAll { $0.id == id }
    }

    func sync(_ id: String) async throws {
        guard let api else { return }
        let _: EmptyBody = try await api.post("v1/collab/accounts/\(id)/sync")
    }

    func setCategories(_ id: String, _ body: ChannelBody) async throws -> SettingsMailAccount {
        guard let api else { throw CancellationError() }
        let account: SettingsMailAccount = try await api.send(APIRequest(method: "PUT", path: "v1/collab/accounts/\(id)/categories", body: try APICoding.encoder.encode(body)))
        upsert(account)
        return account
    }

    func categorySettings() async -> MailCategorySettings? {
        guard let api else { return nil }
        return try? await api.get("v1/collab/categories")
    }

    private func answer(_ method: String, _ path: String, _ body: ChannelBody? = nil) async throws -> SettingsMailAccount {
        guard let api else { throw CancellationError() }
        let data = try body.map { try APICoding.encoder.encode($0) }
        let account: SettingsMailAccount = try await api.send(APIRequest(method: method, path: path, body: data))
        upsert(account)
        return account
    }

    /// Starts an import of older mail, or starts it again with this range.
    func startHistory(_ id: String, since: JSONValue, spamTrash: Bool) async throws {
        _ = try await answer("PUT", "v1/collab/accounts/\(id)/history", ["since": since, "include_spam_trash": .bool(spamTrash)])
    }

    func pauseHistory(_ id: String, _ paused: Bool) async throws {
        _ = try await answer("PATCH", "v1/collab/accounts/\(id)/history", ["paused": .bool(paused)])
    }

    func stopHistory(_ id: String) async throws {
        _ = try await answer("DELETE", "v1/collab/accounts/\(id)/history")
    }

    func pullSignature(_ id: String) async throws -> SettingsMailAccount {
        try await answer("POST", "v1/collab/accounts/\(id)/signature/pull")
    }

    func pullDisplayName(_ id: String) async throws -> SettingsMailAccount {
        try await answer("POST", "v1/collab/accounts/\(id)/display-name/pull")
    }

    func rules(_ id: String) async -> [MailCategoryRule] {
        guard let api, let answer: JSONValue = try? await api.get("v1/collab/accounts/\(id)/category-rules") else { return [] }
        return (try? answer["rules"]?.decode([MailCategoryRule].self)) ?? []
    }

    func addRule(_ id: String, sender: String, category: String) async throws -> MailCategoryRule {
        guard let api else { throw CancellationError() }
        return try await api.post("v1/collab/accounts/\(id)/category-rules", body: ["sender": sender, "category": category])
    }

    func removeRule(_ id: String, rule: String) async throws {
        guard let api else { return }
        try await api.delete("v1/collab/accounts/\(id)/category-rules/\(rule)")
    }

    // MARK: Helpers

    nonisolated static func symbol(_ provider: MailProvider) -> String {
        switch provider {
        case .google: "envelope"
        case .microsoft: "envelope.badge"
        default: "server.rack"
        }
    }

    nonisolated static func historyLabel(_ value: String) -> String {
        switch value {
        case "none": "Only the last 30 days"
        case "2y": "Last 2 years"
        case "5y": "Last 5 years"
        case "all": "All mail"
        default: "Last year"
        }
    }

    /// `history.since`: null for all mail, nil (left out) for none.
    nonisolated static func historySince(_ value: String) -> JSONValue? {
        let years: Int
        switch value {
        case "none": return nil
        case "all": return .null
        case "2y": years = 2
        case "5y": years = 5
        default: years = 1
        }
        let date = Calendar.current.date(byAdding: .year, value: -years, to: Date()) ?? Date()
        return .string(date.formatted(Date.ISO8601FormatStyle()))
    }

    nonisolated static func audienceJSON(_ audience: MailAudience) -> JSONValue {
        audience.everyone
            ? .object(["everyone": .bool(true), "team_ids": .array([]), "user_ids": .array([])])
            : .object(["everyone": .bool(false), "team_ids": .chStrings(audience.teamIDs), "user_ids": .chStrings(audience.userIDs)])
    }

    nonisolated static let colors = ["gray", "red", "orange", "amber", "green", "teal", "blue", "indigo", "violet", "pink"]
}
