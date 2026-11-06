import SwiftUI

/// Settings › Audit log: security and admin activity in this workspace, newest first, by day,
/// filtered by category and by person, action or IP, loading older entries as it scrolls.
/// Admins only, as on the web.
struct AuditLogSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var pager = DevPager<AuditEntry>(limit: 50)
    @State private var category: AuditCategory = .all
    @State private var term = ""
    @State private var open: Set<String> = []

    var body: some View {
        if env.session.isAdmin {
            page
        } else {
            DevNoAccess(title: "Audit log", what: "the audit log")
        }
    }

    private var shown: [AuditEntry] {
        let needle = term.trimmingCharacters(in: .whitespaces).lowercased()
        return pager.items.filter { entry in
            (category == .all || AuditCategory.of(entry.action) == category) && (needle.isEmpty || AuditText.haystack(entry).contains(needle))
        }
    }

    private var filtered: Bool { category != .all || !term.trimmingCharacters(in: .whitespaces).isEmpty }

    private var page: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("Security and admin activity in this workspace: sign-ins, 2FA, members, keys, webhooks and mailboxes.")
                    .font(ODFont.footnote)
                    .foregroundStyle(Theme.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                categories
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.chrome.ignoresSafeArea())
        .accountTitle("Audit log")
        .searchable(text: $term, placement: .navigationBarDrawer(displayMode: .always), prompt: "Filter by person, action or IP")
        .task { if !pager.loaded { await pager.load(api: env.session.api, path: "v1/audit-logs") } }
        .refreshable { await pager.load(api: env.session.api, path: "v1/audit-logs") }
    }

    private var categories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(AuditCategory.allCases) { value in
                    let chosen = value == category
                    Button {
                        Haptics.selection()
                        withAnimation(Motion.snappy) { category = value }
                    } label: {
                        Text(value.title)
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
    }

    @ViewBuilder
    private var content: some View {
        let rows = shown
        if !pager.loaded {
            Panel { SkeletonRows(count: 8) }
        } else if let error = pager.error, pager.items.isEmpty {
            ErrorState(message: error) { Task { await pager.reload() } }
        } else if rows.isEmpty {
            Panel {
                if filtered {
                    EmptyState(
                        symbol: "line.3.horizontal.decrease.circle",
                        title: "Nothing matches",
                        message: pager.hasMore ? "Older entries load as you scroll." : "Try another category or search.",
                        actionTitle: "Clear filters"
                    ) {
                        category = .all
                        term = ""
                    }
                } else {
                    VStack(spacing: 6) {
                        EmptyState(symbol: "list.bullet.clipboard", title: "Nothing logged yet", message: "Sign-ins and admin changes appear here.")
                        VStack(alignment: .leading, spacing: 8) {
                            tip("checkmark.shield", "Sign-ins, 2FA and role changes are recorded")
                            tip("laptopcomputer.and.iphone", "Each entry keeps the person and IP address")
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            if filtered {
                DevPagerFoot(hasMore: pager.hasMore, loading: pager.loadingMore, count: pager.items.count) { await pager.loadMore() }
            }
        } else {
            ForEach(days(rows), id: \.day) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(group.label).font(ODFont.sans(12.5, weight: .medium)).foregroundStyle(Theme.fg3)
                        Text(String(group.rows.count)).font(ODFont.mono(11)).monospacedDigit().foregroundStyle(Theme.fg4)
                    }
                    .padding(.horizontal, 4)
                    Panel {
                        ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Hairline(inset: 50) }
                            AuditRow(entry: entry, open: open.contains(entry.id)) {
                                withAnimation(Motion.snappy) {
                                    if open.contains(entry.id) { open.remove(entry.id) } else { open.insert(entry.id) }
                                }
                            }
                        }
                    }
                }
            }
            DevPagerFoot(hasMore: pager.hasMore, loading: pager.loadingMore, count: pager.items.count, end: "That's everything") { await pager.loadMore() }
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Theme.fg3).frame(width: 18)
            Text(text).font(ODFont.footnote).foregroundStyle(Theme.fg2)
        }
    }

    private struct Day {
        var day: String
        var label: String
        var rows: [AuditEntry]
    }

    private func days(_ rows: [AuditEntry]) -> [Day] {
        var out: [Day] = []
        let calendar = Calendar.current
        for entry in rows {
            let key = calendar.startOfDay(for: entry.createdAt).timeIntervalSince1970.description
            if out.last?.day == key {
                out[out.count - 1].rows.append(entry)
            } else {
                out.append(Day(day: key, label: Format.dayLabel(entry.createdAt), rows: [entry]))
            }
        }
        return out
    }

    struct Detail: View {
        let id: String

        var body: some View {
            AuditLogSettings()
        }
    }
}

/// One entry: what it touched as a tile, who did what in a plain sentence, and when; open, its
/// action, entity, address and data.
struct AuditRow: View {
    let entry: AuditEntry
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        let glyph = AuditText.glyph(entry.action)
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 10) {
                    AccountIconTile(symbol: glyph.symbol, tone: glyph.tone, size: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        AuditText.sentence(entry)
                            .font(ODFont.sans(14))
                            .foregroundStyle(Theme.fg2)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            if AuditText.norm(entry.action) == "login.failed" {
                                TonePill(text: "Failed", tone: .red, height: 18)
                            }
                            if !entry.ip.isEmpty {
                                Text(entry.ip).font(ODFont.mono(11)).foregroundStyle(Theme.fg4).lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 6)
                    Text(Format.clock(entry.createdAt))
                        .font(ODFont.mono(11.5))
                        .monospacedDigit()
                        .foregroundStyle(Theme.fg3)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.fg4)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .padding(.top, 3)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityHint(Format.fullDate(entry.createdAt))
            .accessibilityAddTraits(open ? .isSelected : [])
            if open {
                details
                    .padding(.leading, 48)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            fact("Action", entry.action, mono: true)
            fact("Entity", entry.entityType + (entry.entityID.map { " \($0)" } ?? ""), mono: true)
            fact("IP address", entry.ip.isEmpty ? "–" : entry.ip, mono: true)
            fact("When", Format.fullDate(entry.createdAt))
            ForEach(entry.data.keys.sorted(), id: \.self) { key in
                fact(key, AuditText.value(entry.data[key]), mono: true, monoLabel: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.lineSoft, lineWidth: 1))
    }

    private func fact(_ label: String, _ value: String, mono: Bool = false, monoLabel: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(monoLabel ? ODFont.mono(11) : ODFont.sans(11.5, weight: .medium)).foregroundStyle(Theme.fg3)
            Text(value)
                .font(mono ? ODFont.mono(12) : ODFont.sans(13))
                .foregroundStyle(Theme.fg)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum AuditCategory: String, CaseIterable, Identifiable {
    case all, access, security, people, integrations, workspace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .access: "Sign-ins"
        case .security: "Security"
        case .people: "People"
        case .integrations: "Integrations"
        case .workspace: "Workspace"
        }
    }

    static func of(_ action: String) -> AuditCategory {
        let head = AuditText.norm(action).split(separator: ".").first.map(String.init) ?? ""
        switch head {
        case "login", "logout", "session", "oauth": return .access
        case "totp", "password", "mfa", "recovery_codes", "account": return .security
        case "member", "invitation", "team": return .people
        case "api_key", "webhook", "mailbox", "widget": return .integrations
        default: return .workspace
        }
    }
}

/// How an entry reads, after the web's audit log: a verb per action, the object it names, and
/// a tile by what it touched.
enum AuditText {
    /// "auth.login_failed" and "login.failed" read the same.
    static func norm(_ action: String) -> String {
        guard action.hasPrefix("auth.") else { return action }
        let rest = action.dropFirst(5)
        guard let underscore = rest.firstIndex(of: "_") else { return String(rest) }
        return rest.replacingCharacters(in: underscore ... underscore, with: ".")
    }

    static func glyph(_ action: String) -> (symbol: String, tone: Tone) {
        let a = norm(action)
        let head = a.split(separator: ".").first.map(String.init) ?? a
        if a == "login.failed" || a == "session.refresh_reused" { return ("exclamationmark.shield", .red) }
        switch head {
        case "login", "oauth", "identity": return ("arrow.right.circle", .blue)
        case "logout": return ("rectangle.portrait.and.arrow.right", .gray)
        case "session": return ("laptopcomputer.and.iphone", .blue)
        case "password", "account": return ("lock", .amber)
        case "totp", "2fa", "mfa", "recovery_codes", "passkey": return ("checkmark.shield", .amber)
        case "invitation": return ("person.badge.plus", .teal)
        case "member": return a == "member.invited" ? ("person.badge.plus", .teal) : ("person.2", .teal)
        case "team": return ("person.3", .teal)
        case "api_key": return ("key", .violet)
        case "webhook": return ("point.3.connected.trianglepath.dotted", .violet)
        case "mailbox", "collab": return ("tray", .indigo)
        case "widget", "widget_secret": return ("bubble.left", .cyan)
        case "billing": return ("creditcard", .green)
        case "ai": return ("sparkles", .violet)
        case "workspace": return a == "workspace.widget_secret_rotated" ? ("bubble.left", .cyan) : ("building.2", .gray)
        default: return ("gearshape", .gray)
        }
    }

    static let verbs: [String: String] = [
        "login.succeeded": "signed in",
        "login": "signed in",
        "login.failed": "failed to sign in",
        "member.invited": "invited",
        "logout": "signed out",
        "session.revoked": "revoked a session",
        "password.changed": "changed their password",
        "password.reset": "reset their password",
        "totp.enabled": "turned on two-factor authentication",
        "totp.disabled": "turned off two-factor authentication",
        "recovery_codes.used": "used a recovery code",
        "member.added": "added a member",
        "member.removed": "removed a member",
        "member.role_changed": "changed a member's role",
        "invitation.created": "invited someone",
        "invitation.revoked": "revoked an invitation",
        "invitation.accepted": "accepted an invitation",
        "api_key.created": "created an API key",
        "api_key.revoked": "revoked an API key",
        "api_key.scopes_changed": "changed an API key's permissions",
        "api_key.expiry_changed": "changed an API key's expiry",
        "api_key.deleted": "revoked an API key",
        "webhook.created": "created a webhook",
        "webhook.updated": "updated a webhook",
        "webhook.deleted": "deleted a webhook",
        "mailbox.connected": "connected a mailbox",
        "mailbox.created": "added a mailbox",
        "mailbox.disconnected": "disconnected a mailbox",
        "mailbox.deleted": "removed a mailbox",
        "workspace.updated": "updated workspace settings",
        "workspace.transferred": "transferred ownership",
        "widget.secret_rotated": "rotated the widget secret",
        "widget_secret.rotated": "rotated the widget secret",
        "workspace.widget_secret_rotated": "rotated the widget secret",
        "workspace.created": "created the workspace",
        "2fa.enabled": "turned on two-factor authentication",
        "2fa.disabled": "turned off two-factor authentication",
        "member.joined": "joined the workspace",
        "member.left": "left the workspace",
        "member.account_deleted": "deleted their account",
        "identity.linked": "linked a sign-in provider",
        "session.refresh_reused": "had a reused session token refused",
        "api_key.updated": "renamed an API key",
        "mailbox.updated": "updated a mailbox",
        "team.created": "created a team",
        "team.updated": "updated a team",
        "team.deleted": "deleted a team",
        "view.created": "created a view",
        "view.updated": "updated a view",
        "view.deleted": "deleted a view",
        "widget.settings_updated": "updated the chat widget",
        "ai.settings_updated": "updated AI settings",
        "billing.updated": "changed the subscription",
        "billing.ai_top_up_purchased": "added AI usage",
        "billing.ai_recharged": "auto-recharged the AI balance",
        "billing.auto_recharge_updated": "changed auto-recharge",
        "billing.auto_recharge_failed": "had an auto-recharge fail",
        // Older entries, from before AI usage was counted in US dollars.
        "billing.credits_purchased": "added AI usage",
        "billing.credits_recharged": "auto-recharged the AI balance",
        "billing.payment_failed": "had a payment fail",
        "billing.seats_synced": "synced billed seats",
        "billing.plan_changed": "changed the plan",
        "workspace.collab_changed": "changed Collab access",
        "sidebar.starter_updated": "published the starter Space",
        "sidebar.starter_removed": "removed the starter Space",
        "collab.account_connected": "connected a mail account",
        "collab.account_updated": "updated a mail account",
        "collab.account_disconnected": "disconnected a mail account",
        "collab.thread_shared": "shared a conversation",
        "collab.thread_assigned": "assigned a conversation",
        "support_channel.connected": "connected a support channel",
        "support_channel.disconnected": "disconnected a support channel",
        "support_channel.destination_created": "added a support channel destination",
        "support_channel.destination_deleted": "removed a support channel destination",
        "support_channel.identity_linked": "linked a chat account",
        "support_channel.identity_unlinked": "unlinked a chat account",
    ]

    private static let genericVerbs: Set<String> = ["created", "updated", "deleted", "removed", "added", "revoked", "connected", "disconnected", "enabled", "disabled", "rotated", "changed", "published", "invited"]

    private static func generic(_ action: String) -> String? {
        let a = norm(action)
        guard let dot = a.lastIndex(of: ".") else { return nil }
        let verb = String(a[a.index(after: dot)...])
        guard genericVerbs.contains(verb) else { return nil }
        let thing = a[..<dot].replacingOccurrences(of: "_", with: " ")
        let article = thing.first.map { "aeiou".contains($0) } == true || thing.hasPrefix("sla") ? "an" : "a"
        let named = thing == "sla policy" ? "SLA policy" : thing == "api key" ? "API key" : thing
        return "\(verb) \(article) \(named)"
    }

    static func verb(_ entry: AuditEntry) -> String? {
        verbs[norm(entry.action)] ?? verbs[entry.action] ?? generic(entry.action)
    }

    /// What the entry names: an email, a name, a URL or a title.
    static func object(_ entry: AuditEntry) -> String? {
        for key in ["email", "name", "url", "title"] {
            if let value = entry.data[key]?.string, !value.isEmpty { return value }
        }
        return nil
    }

    static func actor(_ entry: AuditEntry) -> String {
        if entry.actor.type == "user", let user = entry.actor.user { return user.name.isEmpty ? (user.email ?? "Someone") : user.name }
        if entry.actor.type == "api_key" { return "API key" }
        return entry.actor.type == "user" ? "Someone" : "System"
    }

    /// "Maya Chen created an API key Zapier sync".
    static func sentence(_ entry: AuditEntry) -> Text {
        var text = Text(actor(entry)).fontWeight(.medium).foregroundStyle(Theme.fg)
        if entry.actor.type == "api_key", let key = entry.actor.apiKeyID {
            text = text + Text(" " + String(key.prefix(8))).font(ODFont.mono(11.5)).foregroundStyle(Theme.fg4)
        }
        let object = object(entry)
        if let verb = verb(entry) {
            text = text + Text(" " + verb)
        } else {
            text = text + Text(" " + entry.action).font(ODFont.mono(12)).foregroundStyle(Theme.fg3)
        }
        if let object { text = text + Text(" " + object).fontWeight(.medium).foregroundStyle(Theme.fg) }
        if norm(entry.action) == "member.role_changed", let to = entry.data["to"]?.string, !to.isEmpty { text = text + Text(" to \(to)") }
        return text
    }

    /// Words to match a filter against: who, what, and on what.
    static func haystack(_ entry: AuditEntry) -> String {
        var parts = [entry.action, entry.actor.user?.name ?? "", entry.actor.user?.email ?? "", entry.ip, verbs[norm(entry.action)] ?? ""]
        for key in ["email", "name", "url", "title"] { parts.append(entry.data[key]?.string ?? "") }
        return parts.filter { !$0.isEmpty }.joined(separator: " ").lowercased()
    }

    static func value(_ value: JSONValue?) -> String {
        guard let value else { return "–" }
        switch value {
        case .null: return "–"
        case let .string(text): return text
        case let .bool(flag): return flag ? "true" : "false"
        case .number: return value.displayText ?? "–"
        default:
            guard let data = try? APICoding.encoder.encode(value) else { return "–" }
            return String(decoding: data, as: UTF8.self)
        }
    }
}
