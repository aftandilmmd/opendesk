import Foundation
import Observation

/// One row of an Everywhere list, with the workspace it belongs to.
struct EverywhereRow<Item: Identifiable & Sendable>: Identifiable, Sendable where Item.ID == String {
    var workspaceID: String
    var item: Item
    var id: String { workspaceID + ":" + item.id }
}

/// The Everywhere lists (contracts/api.md "Several workspaces"): tickets assigned to the person
/// and all mail, across every workspace they show, newest activity first. Each workspace's rows
/// come from its own request (its role, its private teams). Kept live by `OverviewStore`: when
/// a workspace's tickets or mail change, its rows are read again.
@MainActor
@Observable
final class EverywhereStore {
    static let shared = EverywhereStore()

    /// Rows each workspace contributes: its first page.
    static let perWorkspace = 50

    private(set) var tickets: [String: [Ticket]] = [:]
    private(set) var threads: [String: [MailThread]] = [:]
    private(set) var failed: [EverywhereList: Set<String>] = [:]
    private(set) var loading: Set<EverywhereList> = []
    private(set) var loadedOnce: Set<EverywhereList> = []

    @ObservationIgnored private var api: APIClient?
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var listener: UUID?
    @ObservationIgnored private weak var env: AppEnvironment?

    func start(env: AppEnvironment) {
        guard let user = env.session.user?.id else { return }
        let api = env.session.api
        let key = "\(ObjectIdentifier(api).hashValue)/\(user)"
        self.env = env
        guard key != self.key else { return }
        self.key = key
        self.api = api
        tickets = [:]
        threads = [:]
        failed = [:]
        loading = []
        loadedOnce = []
        OverviewStore.shared.unsubscribe(listener)
        listener = OverviewStore.shared.subscribe { [weak self] changed in
            guard let self else { return }
            Task { await self.reload(changed) }
        }
    }

    // MARK: Which workspaces

    /// The workspaces a list gathers: every one the person shows (not folded away, not
    /// suspended), with Tickets for theirs and with Mail for all mail.
    func workspaces(for list: EverywhereList) -> [Membership] {
        guard let env else { return [] }
        let overview = OverviewStore.shared
        return env.session.memberships.filter { membership in
            if overview.hidden.contains(membership.id) { return false }
            let entry = overview.overview(membership.id)
            if entry?.suspended == true { return false }
            switch list {
            case .mine: return membership.workspace.ticketsOn
            case .mail:
                guard overview.loaded else { return false }
                return entry?.mailCounts != nil
            }
        }
    }

    // MARK: Loading

    func load(_ list: EverywhereList) async {
        await fetch(list, workspaces: workspaces(for: list).map(\.id), showLoading: true)
    }

    /// Reads again what changed, for the lists already shown.
    private func reload(_ changed: Set<String>) async {
        for list in loadedOnce {
            let wanted = Set(workspaces(for: list).map(\.id))
            let ids = changed.intersection(wanted)
            if !ids.isEmpty { await fetch(list, workspaces: Array(ids), showLoading: false) }
        }
    }

    func retry(_ list: EverywhereList) async {
        await fetch(list, workspaces: Array(failed[list] ?? []), showLoading: false)
    }

    private func fetch(_ list: EverywhereList, workspaces ids: [String], showLoading: Bool) async {
        guard let api, !ids.isEmpty else {
            loadedOnce.insert(list)
            return
        }
        if showLoading { loading.insert(list) }
        defer { if showLoading { loading.remove(list) } }
        let limit = String(Self.perWorkspace)
        switch list {
        case .mine:
            let query = [
                URLQueryItem(name: "status", value: "open,pending,on_hold"), URLQueryItem(name: "assignee", value: "me"),
                URLQueryItem(name: "sort", value: "last_message_at"), URLQueryItem(name: "order", value: "desc"),
                URLQueryItem(name: "limit", value: limit),
            ]
            let results = await Self.each(ids) { id -> Page<Ticket>? in try? await api.get("v1/tickets", query: query, workspace: .id(id)) }
            for (id, page) in results {
                if let page { tickets[id] = page.data }
                mark(list, id, failed: page == nil)
            }
        case .mail:
            let query = [URLQueryItem(name: "box", value: "inbox"), URLQueryItem(name: "limit", value: limit)]
            let results = await Self.each(ids) { id -> Page<MailThread>? in try? await api.get("v1/collab/threads", query: query, workspace: .id(id)) }
            for (id, page) in results {
                if let page { threads[id] = page.data }
                mark(list, id, failed: page == nil)
            }
        }
        loadedOnce.insert(list)
    }

    private func mark(_ list: EverywhereList, _ workspace: String, failed: Bool) {
        var set = self.failed[list] ?? []
        if failed { set.insert(workspace) } else { set.remove(workspace) }
        self.failed[list] = set
    }

    private nonisolated static func each<T: Sendable>(_ ids: [String], _ body: @escaping @Sendable (String) async -> T?) async -> [(String, T?)] {
        await withTaskGroup(of: (String, T?).self) { group in
            for id in ids { group.addTask { (id, await body(id)) } }
            var out: [(String, T?)] = []
            for await result in group { out.append(result) }
            return out
        }
    }

    // MARK: Rows

    /// Every workspace's tickets assigned to the person, newest activity first.
    func mineRows() -> [EverywhereRow<Ticket>] {
        let shown = Set(workspaces(for: .mine).map(\.id))
        return tickets.filter { shown.contains($0.key) }
            .flatMap { id, list in list.map { EverywhereRow(workspaceID: id, item: $0) } }
            .sorted { $0.item.lastMessageAt > $1.item.lastMessageAt }
    }

    /// Every workspace's inbox mail, newest first.
    func mailRows() -> [EverywhereRow<MailThread>] {
        let shown = Set(workspaces(for: .mail).map(\.id))
        return threads.filter { shown.contains($0.key) }
            .flatMap { id, list in list.map { EverywhereRow(workspaceID: id, item: $0) } }
            .sorted { $0.item.lastMessageAt > $1.item.lastMessageAt }
    }

    /// The list's number, added up over its workspaces: tickets assigned to the person, or
    /// unread mail in their inboxes (the overview's).
    func count(_ list: EverywhereList) -> Int? {
        let overview = OverviewStore.shared
        guard overview.loaded else { return nil }
        let ids = workspaces(for: list).map(\.id)
        return ids.reduce(0) { total, id in
            let entry = overview.overview(id)
            switch list {
            case .mine: return total + (entry?.ticketCounts?.mine ?? 0)
            case .mail: return total + (entry?.mailCounts?.boxes["inbox"] ?? 0)
            }
        }
    }

    // MARK: Opening

    /// Opens a ticket: beside the list in its workspace, or after switching to its own.
    func open(_ row: EverywhereRow<Ticket>, env: AppEnvironment) {
        if row.workspaceID == env.session.workspace?.id {
            env.router.pick(.ticket(row.item))
        } else {
            env.router.open(DeepLink.Target(link: .ticket(id: row.item.id, scope: .folder(.mine)), server: nil, workspaceID: row.workspaceID))
        }
    }

    /// Opens a conversation, the same way.
    func open(_ row: EverywhereRow<MailThread>, env: AppEnvironment) {
        if row.workspaceID == env.session.workspace?.id {
            SpacesStore.shared.startMail(env: env)
            env.router.pick(.mailThread(row.item.id))
        } else {
            env.router.open(DeepLink.Target(link: .mail(row.item.id), server: nil, workspaceID: row.workspaceID))
        }
    }
}
