import SwiftUI
import UniformTypeIdentifiers

// Pieces the Developers and Admin pages share: copy fields for URLs and secrets, mono chips,
// summary strips, HTTP status pills, the private-teams field, a cursor pager, and the fresh
// sign-in the web asks for before a key or a wider permission.

// MARK: - Access

/// A page only admins see (the web's NoAccess).
struct DevNoAccess: View {
    let title: String
    let what: String

    var body: some View {
        AccountPage(title: title) {
            EmptyState(symbol: "lock", title: "Admins only", message: "Ask a workspace admin if you need to change \(what).")
                .padding(.top, 60)
        }
    }
}

/// `AccountPage` with a lazy stack, for a page that ends in a paged list: its foot loads the
/// next page only once scrolled to.
struct DevLazyPage<Content: View>: View {
    let title: String
    var spacing: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing) { content() }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.chrome.ignoresSafeArea())
        .accountTitle(title)
    }
}

// MARK: - Fresh sign-in

enum DevReauth {
    /// A prompt for a refusal that needs a recent sign-in (`reauth_required`) or one that passed
    /// two-factor (`mfa_required`); nil for any other error. `retry` runs once signed in again.
    @MainActor
    static func prompt(for error: Error, retry: @escaping @MainActor () async throws -> Void) -> AccountStore.ReauthPrompt? {
        guard let failure = error as? APIError, failure.code == "reauth_required" || failure.code == "mfa_required" else { return nil }
        return AccountStore.ReauthPrompt(needsMFA: failure.code == "mfa_required", retry: retry)
    }
}

extension View {
    /// The Security page's own "Confirm it's you" sheet: the password (and a code), then the change runs.
    func devReauth(_ prompt: Binding<AccountStore.ReauthPrompt?>) -> some View {
        sheet(item: prompt) { prompt in
            AccountReauthSheet(prompt: prompt)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(Theme.Radius.sheet)
        }
    }
}

// MARK: - Text bits

/// A small mono chip for scopes, event names and ids.
struct DevMonoChip: View {
    let text: String
    var tone: Tone?
    var struck = false

    var body: some View {
        Text(text)
            .font(ODFont.mono(11.5))
            .strikethrough(struck)
            .foregroundStyle(struck ? Theme.fg4 : (tone?.text ?? Theme.fg2))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 21)
            .background(tone?.soft ?? Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous).strokeBorder(tone?.line ?? Theme.line, lineWidth: 1))
    }
}

/// A scope chip: write scopes in amber, as the web marks what changes data.
struct DevScopeChip: View {
    let scope: String

    var body: some View {
        DevMonoChip(text: scope, tone: scope.hasSuffix(":write") ? .amber : nil)
    }
}

/// An HTTP status in its tone: 2xx green, 3xx amber, 4xx and 5xx red.
struct DevCodePill: View {
    let code: Int?

    var body: some View {
        if let code {
            let tone: Tone = code < 300 ? .green : code < 400 ? .amber : .red
            Text(String(code))
                .font(ODFont.mono(11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tone.text)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(tone.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
        } else {
            Text("–").font(ODFont.mono(12)).foregroundStyle(Theme.fg4)
        }
    }
}

/// A state pill with a dot (Active, Failing, Expired).
struct DevStatePill: View {
    let text: String
    let tone: Tone

    var body: some View {
        TonePill(text: text, tone: tone) {
            Circle().fill(tone.solid).frame(width: 6, height: 6)
        }
    }
}

/// Counts over a list, side by side (the web's SummaryStrip).
struct DevSummaryStrip: View {
    struct Item: Identifiable {
        var label: String
        var value: String
        var tone: Tone?
        var hint: String?
        var id: String { label }
    }

    let items: [Item]

    var body: some View {
        Panel {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Rectangle().fill(Theme.lineSoft).frame(width: 1).padding(.vertical, 10) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.label)
                            .font(ODFont.sans(11.5, weight: .medium))
                            .foregroundStyle(Theme.fg3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(item.value)
                            .font(ODFont.sans(19, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(item.tone?.text ?? Theme.fg)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                        if let hint = item.hint {
                            Text(hint)
                                .font(ODFont.sans(10.5))
                                .foregroundStyle(Theme.fg4)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Labels and values under each other, for a request's or an audit entry's facts.
struct DevFacts: View {
    struct Fact: Identifiable {
        var label: String
        var value: String
        var mono = false
        var id: String { label }
    }

    let facts: [Fact]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                if index > 0 { Hairline(inset: 14) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(fact.label).font(ODFont.sans(12, weight: .medium)).foregroundStyle(Theme.fg3)
                    Text(fact.value)
                        .font(fact.mono ? ODFont.mono(13) : ODFont.sans(14.5))
                        .foregroundStyle(Theme.fg)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }
}

// MARK: - Copying

/// A value to copy: a URL, a snippet or a secret. A secret goes to this device's clipboard
/// only, and leaves it after a few minutes.
struct DevCopyField: View {
    let value: String
    var multiline = false
    var secret = false

    @State private var copied = false

    var body: some View {
        HStack(alignment: multiline ? .top : .center, spacing: 8) {
            Group {
                if multiline {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(value)
                            .font(ODFont.mono(12))
                            .lineSpacing(2)
                            .fixedSize()
                            .padding(.vertical, 10)
                    }
                } else {
                    Text(value)
                        .font(ODFont.mono(13))
                        .lineLimit(secret ? 3 : 1)
                        .truncationMode(.middle)
                        .padding(.vertical, 11)
                }
            }
            .foregroundStyle(Theme.fg)
            .textSelection(.enabled)
            .privacySensitive(secret)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(copied ? Tone.green.text : Theme.fg2)
                    .frame(width: 32, height: 32)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(TapScaleStyle(scale: 0.9))
            .padding(.top, multiline ? 6 : 0)
            .accessibilityLabel(copied ? "Copied" : "Copy")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func copy() {
        if secret {
            UIPasteboard.general.setItems(
                [[UTType.utf8PlainText.identifier: value]],
                options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(180)]
            )
        } else {
            UIPasteboard.general.string = value
        }
        Haptics.success()
        withAnimation(Motion.snappy) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(Motion.snappy) { copied = false }
        }
    }
}

/// A new secret, shown once: the value to copy and the line that it won't be shown again.
struct DevSecretPanel: View {
    let secret: String
    let warning: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DevCopyField(value: secret, secret: true)
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(Tone.amber.solid).frame(width: 6, height: 6).padding(.top, 5)
                Text(warning).font(ODFont.footnote).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Tone.amber.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tone.amber.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
    }
}

// MARK: - Choices

/// A small toggle chip with a check, in place of a checkbox.
struct DevCheckChip: View {
    let title: String
    let on: Bool
    var mono = false
    var disabled = false
    let toggle: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(on ? Theme.fg : Theme.fg4)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(mono ? ODFont.mono(12) : ODFont.sans(13, weight: .medium))
                    .foregroundStyle(on ? Theme.fg : Theme.fg3)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(on ? Theme.active : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.chip + 1, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip + 1, style: .continuous).strokeBorder(on ? Theme.lineStrong : Theme.line, lineWidth: 1))
        }
        .buttonStyle(TapScaleStyle(scale: 0.95))
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A form label with an optional note on the right.
struct DevFieldLabel: View {
    let title: String
    var note: String?

    var body: some View {
        HStack {
            Text(title).font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
            Spacer()
            if let note { Text(note).font(ODFont.mono(11.5)).foregroundStyle(Theme.fg4) }
        }
    }
}

// MARK: - Teams and bots

/// The workspace's teams and bots, as the key and webhook forms need them, per workspace.
@MainActor
@Observable
final class DevDirectory {
    static let shared = DevDirectory()

    private(set) var teams: [DevTeam] = []
    private(set) var bots: [DevBot] = []
    private(set) var botsLoaded = false
    @ObservationIgnored private var workspaceID: String?
    @ObservationIgnored private var teamsLoaded = false

    var privateTeams: [DevTeam] { teams.filter(\.isPrivate) }

    func bot(_ id: String?) -> DevBot? {
        guard let id else { return nil }
        return bots.first { $0.id == id }
    }

    private func reset(for session: SessionStore) {
        let id = session.workspace?.id
        guard id != workspaceID else { return }
        workspaceID = id
        teams = []
        bots = []
        botsLoaded = false
        teamsLoaded = false
    }

    func loadTeams(_ session: SessionStore) async {
        reset(for: session)
        guard !teamsLoaded else { return }
        if let list: [DevTeam] = try? await session.api.all("v1/teams") {
            teams = list
            teamsLoaded = true
        }
    }

    func loadBots(_ session: SessionStore) async {
        reset(for: session)
        guard !botsLoaded else { return }
        if let page: Page<DevBot> = try? await session.api.get("v1/bots", query: [URLQueryItem(name: "limit", value: "100")]) {
            bots = page.data
        }
        botsLoaded = true
    }
}

/// A key's or webhook's private teams, each with who granted it.
struct DevGrantedTeams: View {
    let grants: [DevTeamGrant]

    var body: some View {
        if !grants.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(grants) { grant in
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Theme.fg4)
                        Text(grant.name).font(ODFont.sans(12, weight: .medium)).foregroundStyle(Theme.fg2)
                        if let by = grant.grantedBy {
                            Text("Granted by \(by.displayName)").font(ODFont.sans(12)).foregroundStyle(Theme.fg4)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Private teams this sees: \(grants.map(\.name).joined(separator: ", "))")
        }
    }
}

/// Which private teams' tickets a key or webhook includes. Only people on a private team can
/// include it; anyone can take one out.
struct DevPrivateTeamsField: View {
    @Binding var value: [String]
    var grants: [DevTeamGrant] = []

    @Environment(AppEnvironment.self) private var env

    private var directory: DevDirectory { DevDirectory.shared }

    var body: some View {
        let teams = directory.privateTeams
        Group {
            if !teams.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    DevFieldLabel(title: "Private teams")
                    Panel {
                        ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                            if index > 0 { Hairline(inset: 14) }
                            row(team)
                        }
                    }
                    Text("Tickets of private teams are left out unless you include the team. Only people on a private team can include it; anyone can take one out.")
                        .font(ODFont.footnote)
                        .foregroundStyle(Theme.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task { await directory.loadTeams(env.session) }
    }

    private func row(_ team: DevTeam) -> some View {
        let mine = team.memberIDs.contains(env.session.user?.id ?? "")
        let on = value.contains(team.id)
        let by = on ? grants.first { $0.id == team.id }?.grantedBy : nil
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(Tone(label: team.color).solid).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.name).font(ODFont.sans(15)).foregroundStyle(Theme.fg)
                if let by { Text("Granted by \(by.displayName)").font(ODFont.footnote).foregroundStyle(Theme.fg3) }
                if !mine { Text("You're not on this team").font(ODFont.footnote).foregroundStyle(Theme.fg4) }
            }
            Spacer(minLength: 8)
            Toggle("Include \(team.name)'s tickets", isOn: Binding(
                get: { on },
                set: { include in value = include ? value + [team.id] : value.filter { $0 != team.id } }
            ))
            .labelsHidden()
            .tint(Tone.green.solid)
            .disabled(!mine && !on)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(mine ? Color.clear : Theme.sunken.opacity(0.6))
    }
}

// MARK: - Paging

/// A cursor-paged list (`{data, next_cursor}`) that loads more as it scrolls.
@MainActor
@Observable
final class DevPager<Item: Decodable & Sendable & Identifiable> where Item.ID == String {
    private(set) var items: [Item] = []
    private(set) var loaded = false
    private(set) var loading = false
    private(set) var loadingMore = false
    private(set) var error: String?
    private(set) var nextCursor: String?

    @ObservationIgnored private var api: APIClient?
    @ObservationIgnored private var path = ""
    @ObservationIgnored private var query: [URLQueryItem] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored let limit: Int

    init(limit: Int = 50) { self.limit = limit }

    var hasMore: Bool { nextCursor != nil }

    /// The first page of `path` with `query`, in place of what was there.
    func load(api: APIClient, path: String, query: [URLQueryItem] = []) async {
        let changed = path != self.path || query != self.query
        self.api = api
        self.path = path
        self.query = query
        generation += 1
        let current = generation
        if changed {
            items = []
            loaded = false
            nextCursor = nil
        }
        loading = true
        defer { if current == generation { loading = false } }
        do {
            let page: Page<Item> = try await api.get(path, query: query + [URLQueryItem(name: "limit", value: String(limit))])
            guard current == generation else { return }
            items = page.data
            nextCursor = page.nextCursor.flatMap { $0.isEmpty ? nil : $0 }
            error = nil
            loaded = true
        } catch {
            guard current == generation, !error.isCancellation else { return }
            self.error = error.userMessage
            loaded = true
        }
    }

    func reload() async {
        guard let api else { return }
        await load(api: api, path: path, query: query)
    }

    func loadMore() async {
        guard let api, let cursor = nextCursor, !loadingMore, !loading else { return }
        let current = generation
        loadingMore = true
        defer { loadingMore = false }
        let more = query + [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "cursor", value: cursor)]
        guard let page: Page<Item> = try? await api.get(path, query: more), current == generation else { return }
        let known = Set(items.map(\.id))
        items += page.data.filter { !known.contains($0.id) }
        let next = page.nextCursor.flatMap { $0.isEmpty ? nil : $0 }
        // A cursor that comes back again would never end.
        nextCursor = next == cursor ? nil : next
    }
}

/// The foot of a paged list: loads the next page as it comes into view.
struct DevPagerFoot: View {
    let hasMore: Bool
    let loading: Bool
    /// What is loaded so far: a new page brings the foot back into view, so it asks again.
    var count = 0
    var end: String?
    let more: () async -> Void

    var body: some View {
        HStack {
            if loading || hasMore {
                ProgressView().controlSize(.small)
            } else if let end {
                Text(end).font(ODFont.footnote).foregroundStyle(Theme.fg4)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .onAppear { if hasMore { Task { await more() } } }
        .id("\(hasMore)-\(count)")
    }
}

// MARK: - Time

extension Date {
    /// The end of a picked day, where the admin is: a key expiring "on" a date works all that day.
    static func endOfDay(_ day: Date) -> Date {
        let start = Calendar.current.startOfDay(for: day)
        return Calendar.current.date(byAdding: DateComponents(hour: 23, minute: 59), to: start) ?? day
    }

    /// RFC 3339, as the API takes dates.
    var devISO: String { formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: false)) }
}
