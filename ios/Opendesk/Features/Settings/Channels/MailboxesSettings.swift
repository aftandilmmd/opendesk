import SwiftUI

/// Settings › Mailboxes: the addresses whose mail becomes tickets, their health, and what
/// each one does. `Detail` opens a mailbox by id, or "new" (with "new/<brandID>") to add one.
struct MailboxesSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store = MailboxSettingsStore()
    @State private var testing: SettingsMailbox?
    @State private var confirm: AccountConfirm?

    private var admin: Bool { env.session.isAdmin }

    var body: some View {
        AccountPage(title: "Mailboxes") {
            Text("Email addresses whose mail becomes tickets. Replies go out from the same address.")
                .font(ODFont.callout)
                .foregroundStyle(Theme.fg3)
                .padding(.horizontal, 4)
            if !admin, !store.forbidden { SettingsReadOnlyNote() }
            if store.forbidden {
                EmptyState(symbol: "lock", title: "Only admins manage mailboxes", message: "Ask an admin of this workspace to add or change a mailbox.")
                    .padding(.top, 40)
            } else {
                ChannelLoading(loaded: store.loaded, error: store.mailboxes.isEmpty ? store.error : nil, retry: reload) {
                    if store.mailboxes.isEmpty {
                        empty
                    } else {
                        summary
                        list
                    }
                }
            }
        }
        .toolbar {
            if admin, !store.mailboxes.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { env.router.openSetting(.mailboxes, id: "new") } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add mailbox")
                }
            }
        }
        .sheet(item: $testing) { mailbox in
            MailboxTestSheet(mailbox: mailbox, store: store)
        }
        .accountConfirm($confirm)
        .refreshable { await store.load() }
        .onAppear {
            store.attach(env.session.api)
            reload()
        }
    }

    private func reload() { Task { await store.load() } }

    private var empty: some View {
        VStack(spacing: 16) {
            EmptyState(
                symbol: "tray.2",
                title: "No mailboxes yet",
                message: "Forward your support address from any provider, then choose how replies are sent.",
                actionTitle: admin ? "Add a mailbox" : nil,
                action: admin ? { env.router.openSetting(.mailboxes, id: "new") } : nil
            )
            AccountSection {
                AccountRow(symbol: "arrowshape.turn.up.right", tone: .teal, title: "Forwarding works with any provider")
                AccountDivider()
                AccountRow(symbol: "person.3", tone: .blue, title: "Each mailbox can route to a team")
            }
        }
        .padding(.top, 20)
    }

    private var summary: some View {
        let attention = store.mailboxes.filter(\.needsAttention).count
        let disabled = store.mailboxes.filter(\.disabled).count
        let active = store.mailboxes.filter { $0.status == "active" && !$0.needsAttention }.count
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                ChannelStatTile(value: "\(store.mailboxes.count)", label: "Mailboxes")
                ChannelStatTile(value: "\(active)", label: "Active", hint: attention == 0 && disabled == 0 ? "All receiving mail" : nil, tone: .green)
            }
            GridRow {
                ChannelStatTile(value: "\(attention)", label: "Needs attention", hint: attention > 0 ? "Open to see the error" : nil, tone: attention > 0 ? .red : .gray)
                ChannelStatTile(value: "\(disabled)", label: "Disabled", hint: "Not syncing")
            }
        }
    }

    private var list: some View {
        AccountSection(title: ChannelFormat.plural(store.mailboxes.count, "mailbox", "mailboxes")) {
            ForEach(Array(store.sorted.enumerated()), id: \.element.id) { index, mailbox in
                if index > 0 { AccountDivider() }
                SettingsDetailLink(page: .mailboxes, id: mailbox.id) {
                    MailboxRow(mailbox: mailbox, team: env.directory.team(mailbox.teamID)?.name)
                }
                .contextMenu {
                    if admin {
                        Button { testing = mailbox } label: { Label("Test connection", systemImage: "checkmark.seal") }
                        Button { toggle(mailbox) } label: {
                            Label(mailbox.disabled ? "Enable" : "Disable", systemImage: mailbox.disabled ? "play" : "pause")
                        }
                        Button(role: .destructive) { askRemove(mailbox) } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            }
        }
    }

    private func toggle(_ mailbox: SettingsMailbox) {
        Task {
            do {
                try await store.setEnabled(mailbox, mailbox.disabled)
                Haptics.success()
            } catch {
                env.toasts.error(error)
            }
        }
    }

    private func askRemove(_ mailbox: SettingsMailbox) {
        Task {
            let usage = await store.usage(mailbox.id)
            confirm = AccountConfirm(title: "Remove mailbox?", message: MailboxSettingsStore.removeMessage(mailbox, usage: usage), confirmTitle: "Remove") {
                do {
                    try await store.remove(mailbox.id)
                    Haptics.success()
                    env.toasts.show("Mailbox removed", kind: .success)
                } catch {
                    env.toasts.error(error)
                }
            }
        }
    }

    struct Detail: View {
        let id: String

        var body: some View {
            if id == "new" || id.hasPrefix("new/") {
                MailboxNewView(brandID: id.hasPrefix("new/") ? String(id.dropFirst(4)) : nil)
            } else {
                MailboxDetailView(id: id)
            }
        }
    }
}

/// A mailbox in the list: its kind, name and address, how it connects, and its state.
struct MailboxRow: View {
    let mailbox: SettingsMailbox
    var team: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AccountIconTile(symbol: MailboxKinds.symbol(mailbox), tone: MailboxKinds.tone(mailbox))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(mailbox.label).font(ODFont.sans(15.5, weight: .medium)).foregroundStyle(Theme.fg).lineLimit(1)
                    Spacer(minLength: 4)
                    MailboxStatusPill(mailbox: mailbox)
                }
                Text(mailbox.email).font(ODFont.mono(12.5)).foregroundStyle(Theme.fg2).lineLimit(1)
                Text(mailbox.connectionLabel).font(ODFont.footnote).foregroundStyle(Theme.fg3).lineLimit(2)
                HStack(spacing: 6) {
                    TonePill(text: team ?? "No team", tone: .gray, height: 19) {
                        Image(systemName: "person.3").font(.system(size: 9, weight: .semibold))
                    }
                    lastMail
                }
                .padding(.top, 2)
            }
            Chevron().padding(.top, 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var lastMail: some View {
        let quiet = mailbox.quietDays(now: AppClock.now)
        Text(mailbox.lastReceivedAt.map { "Last mail \(Format.relLong($0))" } ?? "No mail yet")
            .font(ODFont.sans(12))
            .foregroundStyle(quiet != nil ? Tone.amber.text : Theme.fg3)
            .lineLimit(1)
    }
}

struct MailboxStatusPill: View {
    let mailbox: SettingsMailbox

    var body: some View {
        if mailbox.imapOff {
            TonePill(text: "Not receiving", tone: .amber)
        } else if mailbox.systemOff {
            TonePill(text: "Not sending", tone: .amber)
        } else {
            switch mailbox.status {
            case "error": TonePill(text: "Needs attention", tone: .red) { PingDot(color: Tone.red.solid, size: 5) }
            case "disabled": TonePill(text: "Disabled", tone: .gray)
            default: TonePill(text: "Active", tone: .green)
            }
        }
    }
}

/// "Connection test": runs the check as it opens.
struct MailboxTestSheet: View {
    let mailbox: SettingsMailbox
    let store: MailboxSettingsStore

    @Environment(\.dismiss) private var dismiss
    @State private var result: MailboxTestResult?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AccountSheetHeader(title: "Connection test", subtitle: mailbox.email) { dismiss() }
            if let result {
                ChannelTestResults(result: result)
            } else if failed {
                FormError(text: "The test couldn't run. Try again in a moment.")
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Signing in to the server").font(ODFont.callout).foregroundStyle(Theme.fg3)
                }
            }
            Button("Done") { dismiss() }.buttonStyle(InkButtonStyle())
        }
        .padding(22)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface)
        .presentationDetents([.medium])
        .presentationCornerRadius(Theme.Radius.sheet)
        .task {
            do {
                result = try await store.test(mailbox.id)
            } catch {
                failed = true
            }
        }
    }
}
