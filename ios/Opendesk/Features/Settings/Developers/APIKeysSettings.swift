import SwiftUI

/// Settings › API keys: the workspace's keys with their access, request log and expiry, a new
/// key shown once, and each key's own page (`Detail`): permissions, expiry, bot, recording and
/// its request log. Admins only, as on the web.
struct APIKeysSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var creating = false
    @State private var sheet: APIKeySheet?
    @State private var confirm: AccountConfirm?
    @State private var showExpired = false

    private var store: APIKeysStore { APIKeysStore.shared }

    var body: some View {
        if env.session.isAdmin {
            page
        } else {
            DevNoAccess(title: "API keys", what: "API keys")
        }
    }

    private var page: some View {
        let now = AppClock.now
        let sorted = store.sorted
        let live = sorted.filter { $0.state(now: now) != .expired }
        let expired = sorted.filter { $0.state(now: now) == .expired }
        return AccountPage(title: "API keys", spacing: 18) {
            (Text("Keys act on this workspace through the public API with only the scopes you give them. Send them as ")
                + Text("Authorization: Bearer od_live_…").font(ODFont.mono(12.5)).foregroundStyle(Theme.fg2))
                .font(ODFont.footnote)
                .foregroundStyle(Theme.fg3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            if !sorted.isEmpty { summary(sorted, now: now) }
            if !store.loaded {
                Panel { SkeletonRows(count: 3) }
            } else if let error = store.error, sorted.isEmpty {
                ErrorState(message: error) { Task { await store.load(env.session) } }
            } else if sorted.isEmpty {
                empty
            } else {
                AccountSection(title: Format.plural(sorted.count, "key")) {
                    ForEach(Array(live.enumerated()), id: \.element.id) { index, key in
                        if index > 0 { Hairline(inset: 56) }
                        row(key, now: now)
                    }
                    if !expired.isEmpty {
                        if !live.isEmpty { Hairline() }
                        Button {
                            Haptics.selection()
                            withAnimation(Motion.snappy) { showExpired.toggle() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .rotationEffect(.degrees(showExpired ? 90 : 0))
                                Text("Expired keys (\(expired.count))").font(ODFont.sans(13.5))
                                Spacer()
                            }
                            .foregroundStyle(Theme.fg3)
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityAddTraits(showExpired ? .isSelected : [])
                        if showExpired {
                            ForEach(expired) { key in
                                Hairline(inset: 56)
                                row(key, now: now)
                            }
                        }
                    }
                }
                .motion(Motion.snappy, value: sorted.map(\.id))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New key")
            }
        }
        .sheet(isPresented: $creating) {
            CreateAPIKeySheet()
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        .apiKeySheet($sheet)
        .accountConfirm($confirm)
        .task {
            await store.load(env.session)
            if store.keys.contains(where: { $0.botID != nil }) { await DevDirectory.shared.loadBots(env.session) }
        }
        .refreshable { await store.load(env.session) }
    }

    private func summary(_ keys: [APIKeyRecord], now: Date) -> some View {
        let active = keys.filter { $0.state(now: now) != .expired }.count
        let expiring = keys.filter { $0.state(now: now) == .expiring }.count
        let expired = keys.filter { $0.state(now: now) == .expired }.count
        let unused = keys.filter { $0.lastUsedAt == nil }.count
        return DevSummaryStrip(items: [
            .init(label: "Active", value: String(active), tone: active > 0 ? .green : nil),
            .init(label: "Expiring soon", value: String(expiring), tone: expiring > 0 ? .amber : nil, hint: "Within 14 days"),
            .init(label: "Never used", value: String(unused)),
            .init(label: "Expired", value: String(expired), tone: expired > 0 ? .gray : nil),
        ])
    }

    private var empty: some View {
        Panel {
            VStack(spacing: 6) {
                EmptyState(
                    symbol: "key",
                    title: "No API keys yet",
                    message: "Create a key to connect a script, an integration or your own backend.",
                    actionTitle: "New key"
                ) { creating = true }
                VStack(alignment: .leading, spacing: 8) {
                    tip("checkmark.shield", "Scopes limit what each key can do")
                    tip("eye.slash", "A new key is shown only once")
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Theme.fg3).frame(width: 18)
            Text(text).font(ODFont.footnote).foregroundStyle(Theme.fg2)
        }
    }

    private func row(_ key: APIKeyRecord, now: Date) -> some View {
        APIKeyRow(
            key: key,
            now: now,
            open: { env.router.openSetting(.apiKeys, id: key.id) },
            openErrors: { env.router.openSetting(.apiKeys, id: "\(key.id)/errors") },
            changeExpiry: { sheet = .expiry(key) }
        ) {
            APIKeyMenuItems(key: key, sheet: $sheet, confirm: $confirm, openLog: { env.router.openSetting(.apiKeys, id: key.id) })
        }
    }

    // MARK: Detail

    /// A key (`<id>`), the key opened on its last day's failures (`<id>/errors`), or one of
    /// its requests (`<id>/requests/<request id>`).
    struct Detail: View {
        let id: String

        var body: some View {
            let parts = id.split(separator: "/").map(String.init)
            if parts.count >= 3, parts[1] == "requests" {
                APIKeyRequestDetailView(keyID: parts[0], requestID: parts[2])
            } else {
                APIKeyDetailView(keyID: parts.first ?? id, errorsOnly: parts.count == 2 && parts[1] == "errors")
            }
        }
    }
}

/// What a key's menu or a sheet changes about it.
enum APIKeySheet: Identifiable {
    case scopes(APIKeyRecord), expiry(APIKeyRecord), bot(APIKeyRecord), rename(APIKeyRecord)

    var id: String {
        switch self {
        case let .scopes(key): "scopes-\(key.id)"
        case let .expiry(key): "expiry-\(key.id)"
        case let .bot(key): "bot-\(key.id)"
        case let .rename(key): "rename-\(key.id)"
        }
    }
}

extension View {
    func apiKeySheet(_ item: Binding<APIKeySheet?>) -> some View {
        sheet(item: item) { sheet in
            Group {
                switch sheet {
                case let .scopes(key): APIKeyScopesSheet(key: key).presentationDetents([.large])
                case let .expiry(key): APIKeyExpirySheet(key: key).presentationDetents([.large])
                case let .bot(key): APIKeyBotSheet(key: key).presentationDetents([.medium, .large])
                case let .rename(key): APIKeyRenameSheet(key: key).presentationDetents([.height(250)])
                }
            }
            .presentationCornerRadius(Theme.Radius.sheet)
        }
    }
}

/// A key's actions, for its row's menu and its page's.
struct APIKeyMenuItems: View {
    let key: APIKeyRecord
    @Binding var sheet: APIKeySheet?
    @Binding var confirm: AccountConfirm?
    var openLog: (() -> Void)?
    var onRevoked: (() -> Void)?

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Button("Rename", systemImage: "pencil") { sheet = .rename(key) }
        if APIKeyScopes.canSpeak(key.scopes) {
            Button("Speak as a bot", systemImage: "face.smiling") { sheet = .bot(key) }
        }
        Button("Edit permissions", systemImage: "slider.horizontal.3") { sheet = .scopes(key) }
        if key.state() != .expired {
            Button("Change expiry", systemImage: "calendar.badge.clock") { sheet = .expiry(key) }
        }
        if let openLog {
            Button("Request log", systemImage: "list.bullet.indent", action: openLog)
        }
        Button(key.recordRequests ? "Stop recording requests" : "Record requests", systemImage: key.recordRequests ? "record.circle.fill" : "record.circle") {
            let on = !key.recordRequests
            Task {
                do {
                    try await APIKeysStore.shared.optimistic(key.id, ["record_requests": .bool(on)]) { $0.recordRequests = on }
                } catch {
                    env.toasts.show("Couldn't change recording", kind: .error)
                }
            }
        }
        Divider()
        Button("Revoke", systemImage: "trash", role: .destructive) {
            confirm = AccountConfirm(
                title: "Revoke this key?",
                message: "Anything using \(key.name) stops working right away. This can't be undone.",
                confirmTitle: "Revoke key"
            ) {
                do {
                    try await APIKeysStore.shared.revoke(key.id)
                    Haptics.success()
                    onRevoked?()
                } catch {
                    env.toasts.show("Couldn't revoke the key", kind: .error)
                }
            }
        }
    }
}

/// One key in the list: name, prefix and who made it; its access as chips; its log, last use
/// and expiry. The row opens the key's page; its failures open the log on them.
struct APIKeyRow<Menu: View>: View {
    let key: APIKeyRecord
    let now: Date
    let open: () -> Void
    let openErrors: () -> Void
    let changeExpiry: () -> Void
    @ViewBuilder var menu: () -> Menu

    private var state: APIKeyRecord.State { key.state(now: now) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AccountIconTile(symbol: "key", tone: state == .expired ? .gray : .violet)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(key.name).font(ODFont.sans(15.5, weight: .medium)).foregroundStyle(Theme.fg).lineLimit(1)
                        if state == .expired { DevStatePill(text: "Expired", tone: .gray) }
                    }
                    HStack(spacing: 5) {
                        Text("\(String(key.prefix.prefix(12)))…").font(ODFont.mono(11.5)).foregroundStyle(Theme.fg4)
                        if let created = key.createdAt {
                            Text("·").foregroundStyle(Theme.fg4)
                            if let by = key.createdBy { Avatar(name: by.displayName, url: by.avatarURL, seed: by.id, size: 14) }
                            Text(Format.shortDate(created)).font(ODFont.sans(11.5)).foregroundStyle(Theme.fg4)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(key.createdBy.map { "Created by \($0.displayName), \(Format.fullDate(key.createdAt))" } ?? Format.fullDate(key.createdAt))
                }
                if key.botID != nil { APIKeySpeaksAs(botID: key.botID) }
                APIKeyAccessChips(scopes: key.scopes)
                DevGrantedTeams(grants: key.privateTeams)
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SwiftUI.Menu { menu() } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.fg3)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(key.name)")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityAction(named: "Open", open)
    }

    private var meta: some View {
        FlowLayout(spacing: 10) {
            APIKeyLogCell(key: key, openErrors: openErrors)
            Text(key.lastUsedAt.map { "Used \(Format.relLong($0))" } ?? "Never used")
                .font(ODFont.sans(12))
                .foregroundStyle(key.lastUsedAt == nil ? Theme.fg4 : Theme.fg3)
            expiry
        }
    }

    @ViewBuilder
    private var expiry: some View {
        let label = Text(key.expiresAt.map { "Expires \(Format.shortDate($0, now: now))" } ?? "No expiry")
            .font(ODFont.sans(12, weight: state == .expiring ? .medium : .regular))
            .foregroundStyle(key.expiresAt == nil || state == .expired ? Theme.fg4 : state == .expiring ? Tone.amber.text : Theme.fg3)
        if state == .expired {
            label
        } else {
            Button(action: changeExpiry) { label.underline(false) }
                .buttonStyle(.plain)
                .accessibilityLabel("Change the expiry of \(key.name)")
        }
    }
}

/// The log column: a recording key's "On" and its failures of the last 24 hours, which open
/// the log on those failures; "Not recording" otherwise.
struct APIKeyLogCell: View {
    let key: APIKeyRecord
    let openErrors: () -> Void

    var body: some View {
        if !key.recordRequests {
            Text("Not recording").font(ODFont.sans(12)).foregroundStyle(Theme.fg4)
        } else {
            let errors = key.errorCount24h ?? 0
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Circle().fill(Tone.green.solid).frame(width: 6, height: 6)
                    Text("Logging on").font(ODFont.sans(12, weight: .medium)).foregroundStyle(Tone.green.text)
                }
                if errors > 0 {
                    Button(action: openErrors) {
                        Text(Format.plural(errors, "error") + " in 24 h")
                            .font(ODFont.sans(12, weight: .medium))
                            .foregroundStyle(Tone.red.text)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show these failures: \(errors) in 24 hours")
                } else {
                    Text("0 errors in 24 h").font(ODFont.sans(12)).foregroundStyle(Theme.fg4)
                }
            }
        }
    }
}

/// "Speaks as Julia" under a key that speaks as a bot.
struct APIKeySpeaksAs: View {
    let botID: String?

    var body: some View {
        let bot = DevDirectory.shared.bot(botID)
        HStack(spacing: 6) {
            if let bot {
                BotAvatar(bot: bot.ref, size: 16)
            } else {
                Image(systemName: "face.smiling").font(.system(size: 12)).foregroundStyle(Theme.fg4)
            }
            Text("Speaks as \(bot?.name ?? (DevDirectory.shared.botsLoaded ? "a bot" : "…"))").font(ODFont.sans(12.5)).foregroundStyle(Theme.fg3).lineLimit(1)
        }
    }
}

/// A key's own page: what it reaches, when it expires, the bot it speaks as, recording and
/// the requests it made.
struct APIKeyDetailView: View {
    let keyID: String
    let errorsOnly: Bool

    @Environment(AppEnvironment.self) private var env
    @State private var status: APIKeyRequestStatus = .all
    @State private var since: Date?
    @State private var pager = DevPager<APIKeyRequestRecord>()
    @State private var sheet: APIKeySheet?
    @State private var confirm: AccountConfirm?
    @State private var ready = false

    private var store: APIKeysStore { APIKeysStore.shared }

    init(keyID: String, errorsOnly: Bool) {
        self.keyID = keyID
        self.errorsOnly = errorsOnly
        // Opened from a key's failures: the errors of the last 24 hours.
        _status = State(initialValue: errorsOnly ? .errors : .all)
        _since = State(initialValue: errorsOnly ? AppClock.now.addingTimeInterval(-86400) : nil)
    }

    var body: some View {
        if !env.session.isAdmin {
            DevNoAccess(title: "API keys", what: "API keys")
        } else {
            let key = store.key(keyID)
            DevLazyPage(title: key?.name ?? "API key") {
                if let key {
                    content(key)
                } else if store.loaded {
                    EmptyState(symbol: "key", title: "Key not found", message: "It may have been revoked.", actionTitle: "Back to API keys") { back() }
                        .padding(.top, 40)
                } else {
                    Panel { SkeletonRows(count: 4) }
                }
            }
            .toolbar {
                if let key {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            APIKeyMenuItems(key: key, sheet: $sheet, confirm: $confirm, onRevoked: back)
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Actions for \(key.name)")
                    }
                }
            }
            .apiKeySheet($sheet)
            .accountConfirm($confirm)
            .task {
                guard !ready else { return }
                ready = true
                if !store.loaded { await store.load(env.session) }
                if store.key(keyID)?.botID != nil { await DevDirectory.shared.loadBots(env.session) }
            }
            .refreshable {
                await store.load(env.session)
                await pager.reload()
            }
        }
    }

    @ViewBuilder
    private func content(_ key: APIKeyRecord) -> some View {
        let state = key.state()
        header(key, state: state)

        AccountSection(title: "Access") {
            Button { sheet = .scopes(key) } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        APIKeyAccessChips(scopes: key.scopes, shown: nil)
                        Text("View and change permissions").font(ODFont.footnote).foregroundStyle(Theme.fg3)
                    }
                    Spacer(minLength: 8)
                    Chevron().padding(.top, 4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel("View and change permissions: \(key.name)")
        }

        AccountSection {
            if state == .expired {
                AccountRow(symbol: "calendar", title: "Expires") { valueText(key.expiresAt.map { Format.fullDate($0) } ?? "No expiry") }
            } else {
                Button { sheet = .expiry(key) } label: {
                    AccountRow(symbol: "calendar", tone: state == .expiring ? .amber : .gray, title: "Expires") {
                        AccountDisclosure(value: key.expiresAt.map { Format.shortDate($0) } ?? "Never")
                    }
                }
                .buttonStyle(RowPressStyle())
                .accessibilityLabel("Change the expiry of \(key.name)")
            }
            AccountDivider()
            AccountRow(symbol: "clock", title: "Last used") { valueText(key.lastUsedAt.map { Format.relLong($0) } ?? "Never used") }
            if APIKeyScopes.canSpeak(key.scopes) {
                AccountDivider()
                Button { sheet = .bot(key) } label: {
                    AccountRow(symbol: "face.smiling", tone: key.botID == nil ? .gray : .violet, title: "Speaks as") {
                        AccountDisclosure(value: key.botID == nil ? "No bot" : DevDirectory.shared.bot(key.botID)?.name ?? (DevDirectory.shared.botsLoaded ? "A bot" : "…"))
                    }
                }
                .buttonStyle(RowPressStyle())
            }
            if !key.privateTeams.isEmpty {
                AccountDivider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Private teams this sees").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg3)
                    DevGrantedTeams(grants: key.privateTeams)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
        }

        AccountSection(footer: key.recordRequests ? "Every request this key makes is kept 90 days." : nil) {
            AccountToggleRow(symbol: "record.circle", tone: key.recordRequests ? .green : .gray, title: "Record requests", isOn: Binding(
                get: { key.recordRequests },
                set: { on in
                    Task {
                        do {
                            try await store.optimistic(key.id, ["record_requests": .bool(on)]) { $0.recordRequests = on }
                        } catch {
                            env.toasts.show("Couldn't change recording", kind: .error)
                        }
                    }
                }
            ))
            if key.recordRequests, let errors = key.errorCount24h, errors > 0 {
                AccountDivider()
                Button {
                    Haptics.tap()
                    withAnimation(Motion.snappy) {
                        status = .errors
                        since = AppClock.now.addingTimeInterval(-86400)
                    }
                } label: {
                    AccountRow(symbol: "exclamationmark.triangle", tone: .red, title: Format.plural(errors, "error") + " in 24 h", subtitle: "Show these failures") {
                        Chevron()
                    }
                }
                .buttonStyle(RowPressStyle())
            }
        }

        APIKeyRequestLogSection(key: key, status: $status, since: $since, pager: pager)

        Button {
            confirm = AccountConfirm(
                title: "Revoke this key?",
                message: "Anything using \(key.name) stops working right away. This can't be undone.",
                confirmTitle: "Revoke key"
            ) {
                do {
                    try await store.revoke(key.id)
                    Haptics.success()
                    back()
                } catch {
                    env.toasts.show("Couldn't revoke the key", kind: .error)
                }
            }
        } label: {
            Label("Revoke key", systemImage: "trash")
        }
        .buttonStyle(OutlineButtonStyle(tint: Tone.red.text))
    }

    private func header(_ key: APIKeyRecord, state: APIKeyRecord.State) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AccountIconTile(symbol: "key", tone: state == .expired ? .gray : .violet, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(key.name).font(ODFont.sans(19, weight: .semibold)).tracking(-0.3).foregroundStyle(Theme.fg)
                    switch state {
                    case .expired: DevStatePill(text: "Expired", tone: .gray)
                    case .expiring: DevStatePill(text: "Expires soon", tone: .amber)
                    case .active: EmptyView()
                    }
                }
                Text("\(key.prefix)…").font(ODFont.mono(12.5)).foregroundStyle(Theme.fg3).textSelection(.enabled)
                if let created = key.createdAt {
                    HStack(spacing: 6) {
                        if let by = key.createdBy {
                            Avatar(name: by.displayName, url: by.avatarURL, seed: by.id, size: 16)
                            Text("Created by \(by.displayName), \(Format.shortDate(created))")
                        } else {
                            Text("Created \(Format.shortDate(created))")
                        }
                    }
                    .font(ODFont.footnote)
                    .foregroundStyle(Theme.fg3)
                }
                if key.botID != nil { APIKeySpeaksAs(botID: key.botID) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func valueText(_ text: String) -> some View {
        Text(text).font(ODFont.sans(14.5)).foregroundStyle(Theme.fg3).lineLimit(1)
    }

    private func back() {
        if !env.router.accountPath.isEmpty { env.router.accountPath.removeLast() }
    }
}
