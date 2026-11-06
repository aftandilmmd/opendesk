import SwiftUI

/// An Everywhere list (`/everywhere/mine`, `/everywhere/mail`): tickets assigned to you, or all
/// mail, across every workspace you show, newest activity first. Each row carries its workspace's
/// badge and opens there: beside the list in the open workspace, after switching otherwise.
struct EverywhereListView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showScopes = false
    @FocusState private var searchFocused: Bool

    private var store: EverywhereStore { .shared }
    private var list: EverywhereList { env.router.everywhere }

    var body: some View {
        VStack(spacing: 0) {
            GlassHeaderBar(
                title: list.title,
                subtitle: subtitle,
                query: .constant(""),
                searchPrompt: "",
                searchFocused: $searchFocused,
                menuLabel: "Areas",
                searchable: false,
                onMenu: { showScopes = true }
            ) {
                GlassCircleButton(symbol: list == .mine ? EverywhereList.mail.symbol : EverywhereList.mine.symbol, label: list == .mine ? "All mail everywhere" : "Assigned to me everywhere", badge: 0) {
                    Haptics.selection()
                    env.router.everywhere = list == .mine ? .mail : .mine
                    env.router.inboxPath = []
                }
            }
            content
                .panelSurface()
        }
        .background(Theme.chrome.ignoresSafeArea())
        .toolbarVisibility(.hidden, for: .navigationBar)
        .followsOverview()
        .onAppear { store.start(env: env) }
        .task(id: list.rawValue + "/\(OverviewStore.shared.loaded)") {
            store.start(env: env)
            if list == .mine || OverviewStore.shared.loaded { await store.load(list) }
        }
        .sheet(isPresented: $showScopes) {
            ScopeSheet()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(Theme.Radius.sheet)
        }
    }

    private var subtitle: Text? {
        let workspaces = store.workspaces(for: list)
        guard !workspaces.isEmpty else { return nil }
        let names = workspaces.map(\.workspace.name)
        return Text(names.count <= 3 ? names.joined(separator: ", ") : Format.plural(names.count, "workspace"))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let failed = store.workspaces(for: list).filter { store.failed[list]?.contains($0.id) == true }
        switch list {
        case .mine:
            rows(store.mineRows(), failed: failed, empty: EmptyState(symbol: "checkmark.circle", title: "Nothing assigned to you", message: "Open tickets assigned to you in any workspace show up here.")) { row in
                ticketRow(row)
            } open: { store.open($0, env: env) }
        case .mail:
            if OverviewStore.shared.loaded, store.workspaces(for: .mail).isEmpty {
                EmptyState(symbol: "envelope", title: "No mail in your workspaces", message: "Mail shows here from every workspace with Mail and a connected account.")
                    .frame(maxHeight: .infinity)
            } else {
                rows(store.mailRows(), failed: failed, empty: EmptyState(symbol: "tray", title: "No mail yet", message: "Conversations in your inboxes across workspaces show up here.")) { row in
                    threadRow(row)
                } open: { store.open($0, env: env) }
            }
        }
    }

    @ViewBuilder
    private func rows<Item, Row: View, Empty: View>(
        _ rows: [EverywhereRow<Item>],
        failed: [Membership],
        empty: Empty,
        @ViewBuilder row: @escaping (EverywhereRow<Item>) -> Row,
        open: @escaping (EverywhereRow<Item>) -> Void
    ) -> some View {
        if !store.loadedOnce.contains(list), rows.isEmpty {
            ScrollView { SkeletonRows() }
                .scrollDisabled(true)
        } else {
            List {
                ForEach(failed) { membership in
                    failure(membership)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Theme.surface)
                }
                ForEach(rows) { entry in
                    Button {
                        Haptics.tap()
                        open(entry)
                    } label: {
                        row(entry)
                    }
                    .buttonStyle(RowPressStyle())
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(picked(entry) ? Theme.hover : Theme.surface)
                }
                if rows.isEmpty {
                    empty
                        .listRowSeparator(.hidden)
                        .listRowBackground(Theme.surface)
                } else {
                    Text("The newest \(EverywhereStore.perWorkspace) of each workspace. Open a workspace to see the rest.")
                        .font(ODFont.footnote)
                        .foregroundStyle(Theme.fg4)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Theme.surface)
                }
                Color.clear.frame(height: 90)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.surface)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .refreshable {
                await OverviewStore.shared.refresh()
                await store.load(list)
            }
            .motion(Motion.snappy, value: rows.map(\.id))
        }
    }

    private func picked<Item>(_ entry: EverywhereRow<Item>) -> Bool {
        guard entry.workspaceID == env.session.workspace?.id, let picked = env.router.picked else { return false }
        switch picked {
        case let .ticket(route): return route.id == entry.item.id
        case let .mailThread(id): return id == entry.item.id
        default: return false
        }
    }

    private func failure(_ membership: Membership) -> some View {
        HStack(spacing: 10) {
            WorkspaceAvatar(workspace: membership.workspace, size: 18)
            Text("Couldn't load \(membership.workspace.name).")
                .font(ODFont.sans(13))
                .foregroundStyle(Tone.amber.text)
            Spacer()
            Button("Try again") {
                Haptics.tap()
                Task { await store.retry(list) }
            }
            .font(ODFont.sans(13, weight: .semibold))
            .foregroundStyle(Tone.amber.text)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Tone.amber.soft)
    }

    private func workspace(_ id: String) -> Workspace? {
        env.session.memberships.first { $0.id == id }?.workspace
    }

    private func ticketRow(_ row: EverywhereRow<Ticket>) -> some View {
        let ticket = row.item
        let ws = workspace(row.workspaceID)
        return HStack(alignment: .top, spacing: 12) {
            if let ws { WorkspaceAvatar(workspace: ws, size: 26).padding(.top, 1) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    PriorityIcon(priority: ticket.priority)
                    Text(ticket.subject.isEmpty ? "No subject" : ticket.subject)
                        .font(ODFont.sans(15, weight: .medium))
                        .foregroundStyle(Theme.fg)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Text("#\(ticket.number)").font(ODFont.mono(12)).foregroundStyle(Theme.fg4)
                    Text(ws?.name ?? "").font(ODFont.footnote).foregroundStyle(Theme.fg3).lineLimit(1)
                    if let contact = ticket.contact {
                        Text("·").foregroundStyle(Theme.fg4)
                        Text(contact.name.isEmpty ? contact.email ?? "" : contact.name)
                            .font(ODFont.footnote)
                            .foregroundStyle(Theme.fg3)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 5) {
                Text(Format.relShort(ticket.lastMessageAt)).font(ODFont.mono(11)).foregroundStyle(Theme.fg4)
                StatusPill(status: ticket.status)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Hairline(inset: 54) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(ws.map { "Opens in \($0.name)" } ?? "")
    }

    private func threadRow(_ row: EverywhereRow<MailThread>) -> some View {
        let thread = row.item
        let ws = workspace(row.workspaceID)
        let from = thread.participants.first
        return HStack(alignment: .top, spacing: 12) {
            if let ws { WorkspaceAvatar(workspace: ws, size: 26).padding(.top, 1) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if thread.unread {
                        Circle().fill(Tone.blue.solid).frame(width: 7, height: 7).accessibilityLabel("Unread")
                    }
                    Text(from.map { $0.name.isEmpty ? $0.email : $0.name } ?? thread.subject)
                        .font(ODFont.sans(15, weight: thread.unread ? .semibold : .regular))
                        .foregroundStyle(thread.unread ? Theme.fg : Theme.fg2)
                        .lineLimit(1)
                    if thread.hasAttachments {
                        Image(systemName: "paperclip").font(.system(size: 11)).foregroundStyle(Theme.fg4)
                    }
                }
                Text(thread.subject + (thread.snippet.isEmpty ? "" : " · " + thread.snippet))
                    .font(ODFont.footnote)
                    .foregroundStyle(Theme.fg3)
                    .lineLimit(1)
                Text(ws?.name ?? "").font(ODFont.caption).foregroundStyle(Theme.fg4).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(Format.relShort(thread.lastMessageAt)).font(ODFont.mono(11)).foregroundStyle(Theme.fg4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Hairline(inset: 54) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(ws.map { "Opens in \($0.name)" } ?? "")
    }
}

/// The Everywhere lists at the top of the switcher, with their numbers.
struct EverywhereEntries: View {
    @Environment(AppEnvironment.self) private var env
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Everywhere").padding(.horizontal, 4)
            Panel {
                ForEach(Array(EverywhereList.allCases.enumerated()), id: \.element) { index, list in
                    if index > 0 { Hairline(inset: 46) }
                    Button {
                        Haptics.selection()
                        env.router.openEverywhere(list)
                        onOpen()
                    } label: {
                        SpaceRowView(row: SpaceRowModel(
                            id: list.rawValue, title: list.title, mark: .symbol(list.symbol),
                            count: EverywhereStore.shared.count(list), workspaceID: "",
                            destination: .everywhere(list),
                            selected: env.router.tab == .inbox && env.router.shownArea == .everywhere && env.router.everywhere == list
                        ))
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
        }
        .onAppear { EverywhereStore.shared.start(env: env) }
    }
}

extension Router {
    /// Opens an Everywhere list in the Inbox tab.
    func openEverywhere(_ list: EverywhereList) {
        everywhere = list
        show(.everywhere, [])
    }
}
