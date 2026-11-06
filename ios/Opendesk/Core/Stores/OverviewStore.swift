import Foundation
import Observation

/// Every workspace's sidebar numbers (`GET /v1/me/overview`), kept live while a screen that shows
/// them is up: the open workspace through the app's own socket, the others through one socket of
/// an `all_workspaces` realtime token (contracts/tokens.md, contracts/realtime.md), which joins
/// `workspace:<wid>` and the private team channels for each workspace the token covers, and
/// `user:<uid>`. An event that changes tickets or mail marks its workspace; a burst refetches
/// the overview once after two seconds, and lists that follow a workspace hear which changed.
@MainActor
@Observable
final class OverviewStore {
    static let shared = OverviewStore()

    private(set) var workspaces: [WorkspaceOverview] = []
    /// Folded away in the switcher (`WorkspacePrefs.hidden`): out of the Everywhere lists.
    private(set) var hidden: Set<String> = []
    private(set) var loaded = false

    @ObservationIgnored private var api: APIClient?
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var focus = ""
    @ObservationIgnored private var userID = ""
    @ObservationIgnored private var several = false
    @ObservationIgnored private weak var realtime: RealtimeService?
    @ObservationIgnored private var realtimeListener: UUID?
    @ObservationIgnored private var socket: PhoenixSocket?
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private var topics: Set<String> = []
    @ObservationIgnored private var followers = 0
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var dirty: Set<String> = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var listeners: [UUID: (Set<String>) -> Void] = [:]

    // MARK: Lifecycle

    /// Starts for the signed-in person and the open workspace; the same again keeps what is loaded.
    func start(env: AppEnvironment) {
        guard let user = env.session.user?.id, let workspace = env.session.workspace?.id else { return }
        let api = env.session.api
        let key = "\(ObjectIdentifier(api).hashValue)/\(user)/\(workspace)"
        guard key != self.key else { return }
        let samePerson = self.key?.hasPrefix("\(ObjectIdentifier(api).hashValue)/\(user)/") == true
        stopSocket()
        if let realtimeListener { realtime?.unsubscribe(realtimeListener) }
        self.key = key
        self.api = api
        focus = workspace
        userID = user
        several = env.session.memberships.count > 1
        if !samePerson {
            workspaces = []
            hidden = []
            loaded = false
        }
        realtime = env.realtime
        realtimeListener = env.realtime.subscribe { [weak self] update in
            guard let self else { return }
            switch update {
            case .resync: self.mark(self.focus)
            case let .envelope(envelope): if Self.counts(envelope.type) { self.mark(self.focus) }
            }
        }
        Task { await refresh() }
        if followers > 0 { startSocket() }
    }

    func refresh() async {
        guard let api else { return }
        async let overview: OverviewList? = try? api.get("v1/me/overview", workspace: .none)
        async let prefs: WorkspacePrefs? = try? api.get("v1/me/workspace-prefs", workspace: .none)
        if let list = await overview { workspaces = list.workspaces }
        if let value = await prefs { hidden = Set(value.hidden) }
        // Asked once: rows that wait for it show, numbered or not.
        loaded = true
    }

    func overview(_ workspace: String) -> WorkspaceOverview? { workspaces.first { $0.id == workspace } }

    /// Hears which workspaces changed after each refetch the socket caused.
    func subscribe(_ handler: @escaping (Set<String>) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = handler
        return id
    }

    func unsubscribe(_ id: UUID?) {
        guard let id else { return }
        listeners[id] = nil
    }

    // MARK: Following

    /// A screen showing other workspaces' numbers came up: keep them live.
    func follow() {
        followers += 1
        idleTask?.cancel()
        idleTask = nil
        if socket == nil { startSocket() }
    }

    /// It went away: the socket closes a little later, unless another screen follows by then.
    func unfollow() {
        followers = max(0, followers - 1)
        guard followers == 0 else { return }
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, !Task.isCancelled, self.followers == 0 else { return }
            self.stopSocket()
        }
    }

    /// Back in the foreground: sockets die while suspended, and the numbers may have moved.
    func resume() {
        guard key != nil else { return }
        if let socket { Task { await socket.nudge() } }
        Task { await refresh() }
    }

    // MARK: Socket

    private func startSocket() {
        guard socket == nil, several, let api, !userID.isEmpty else { return }
        #if DEBUG
        // The demo has no gateway: its other workspaces only change when opened.
        if DemoMode.isOn { return }
        #endif
        let instance = api.instance
        let covered: @Sendable (String) -> Void = { [weak self] token in
            Task { @MainActor in self?.cover(token: token) }
        }
        let socket = PhoenixSocket {
            var request = APIRequest(method: "POST", path: "v1/realtime/token", query: [URLQueryItem(name: "all_workspaces", value: "true")], body: Data("{}".utf8))
            request.workspace = .current
            let token: RealtimeToken = try await api.send(request)
            covered(token.token)
            return SocketEndpoint(url: RealtimeService.socketURL(instance: instance, token: token), token: token.token)
        }
        self.socket = socket
        topics = []
        pump = Task { [weak self] in
            for await signal in socket.signals {
                guard let self else { return }
                self.handle(signal)
            }
        }
        let user = "user:\(userID)"
        topics.insert(user)
        Task {
            await socket.join(user)
            await socket.connect()
        }
    }

    private func stopSocket() {
        pump?.cancel()
        pump = nil
        if let socket { Task { await socket.finish() } }
        socket = nil
        topics = []
    }

    /// The token says which workspaces and private teams it covers: join those, leave the rest.
    private func cover(token: String) {
        guard let socket else { return }
        var want: Set<String> = ["user:\(userID)"]
        for (workspace, teams) in Self.covered(by: token) where workspace != focus {
            want.insert("workspace:\(workspace)")
            for team in teams { want.insert("team:\(workspace):\(team)") }
        }
        let leaving = topics.subtracting(want)
        let joining = want.subtracting(topics)
        topics = want
        guard !leaving.isEmpty || !joining.isEmpty else { return }
        Task {
            for topic in leaving { await socket.leave(topic) }
            for topic in joining { await socket.join(topic) }
        }
    }

    private func handle(_ signal: SocketSignal) {
        switch signal {
        case let .joined(topic, ok, _, _):
            // Events published between the last read and the join never arrive: read once more.
            guard ok, let workspace = Self.workspace(of: topic) else { return }
            mark(workspace)
        case let .message(frame):
            guard frame.event == "event", let envelope = try? frame.payload.decode(Envelope.self), !envelope.workspaceID.isEmpty else { return }
            // The open workspace's events reach the app's own socket.
            guard envelope.workspaceID != focus, Self.counts(envelope.type) else { return }
            mark(envelope.workspaceID)
        case .connecting, .open, .closed:
            break
        }
    }

    // MARK: Coalescing

    private func mark(_ workspace: String) {
        guard !workspace.isEmpty else { return }
        dirty.insert(workspace)
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            let changed = self.dirty
            self.dirty = []
            await self.refresh()
            self.flushTask = nil
            for handler in self.listeners.values { handler(changed) }
            if !self.dirty.isEmpty, let first = self.dirty.first { self.mark(first) }
        }
    }

    /// Events that move a workspace's sidebar numbers or its lists.
    nonisolated static func counts(_ type: String) -> Bool {
        type.hasPrefix("ticket.") || type.hasPrefix("collab.") || type.hasPrefix("notification.")
            || type == "message.created" || type == "event.hidden" || type == "workspace.updated"
    }

    nonisolated static func workspace(of topic: String) -> String? {
        let parts = topic.split(separator: ":")
        guard parts.count >= 2, parts[0] == "workspace" || parts[0] == "team" else { return nil }
        return String(parts[1])
    }

    /// The workspaces a `ws` token covers with their private teams: its own (`wid`, `teams`) and
    /// those of its `workspaces` claim. Read only to know what to join; the gateway checks it.
    nonisolated static func covered(by token: String) -> [String: [String]] {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return [:] }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64), let claims = try? JSONValue.parse(data) else { return [:] }
        var out: [String: [String]] = [:]
        if let wid = claims["wid"]?.string { out[wid] = claims["teams"]?.array?.compactMap(\.string) ?? [] }
        for (wid, entry) in claims["workspaces"]?.object ?? [:] {
            out[wid] = entry["teams"]?.array?.compactMap(\.string) ?? []
        }
        return out
    }
}
