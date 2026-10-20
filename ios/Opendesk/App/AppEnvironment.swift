import Observation
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Match system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Everything the app shares, created once and handed down through the environment.
@MainActor
@Observable
final class AppEnvironment {
    let session = SessionStore()
    let realtime = RealtimeService()
    let directory = DirectoryStore()
    let inbox = InboxStore()
    let notifications = NotificationsStore()
    let router = Router()
    let toasts = ToastCenter()
    var appearance = Appearance(rawValue: Preferences.appearance) ?? .system {
        didSet { Preferences.appearance = appearance.rawValue }
    }

    var push: PushManager { PushManager.shared }

    @ObservationIgnored private var listener: UUID?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?

    init() {
        router.environment = self
        PushManager.shared.environment = self
        session.onReady = { [weak self] membership in self?.workspaceReady(membership) }
        session.onEnded = { [weak self] instance in self?.sessionEnded(instance) }
        realtime.onNotification = { [weak self] notification in self?.notifications.received(notification) }
        realtime.onMembershipChanged = { [weak self] in
            guard let self else { return }
            Task { await self.session.membershipChanged() }
        }
        notifications.onBadge = { count in PushManager.shared.setBadge(count) }
        #if DEBUG
        if DemoMode.isOn { router.startDemoLinks() }
        #endif
    }

    // MARK: Workspace lifecycle

    private func workspaceReady(_ membership: Membership) {
        guard let user = session.user else { return }
        let api = session.api
        realtime.unsubscribe(listener)
        realtime.start(api: api, workspaceID: membership.id, userID: user.id)
        listener = realtime.subscribe { [weak self] update in
            guard let self else { return }
            self.directory.handle(update)
            self.inbox.handle(update)
            self.notifications.handle(update)
        }
        directory.start(api: api)
        inbox.start(api: api, me: user.id)
        notifications.start(api: api, workspaceID: membership.id, memberships: session.memberships)
        push.sessionReady()
        startHeartbeat()
        router.workspaceReady()
        if let tap = push.takePendingTap() { router.open(tap.target) }
    }

    private func sessionEnded(_ instance: Instance) {
        heartbeat?.cancel()
        heartbeat = nil
        realtime.unsubscribe(listener)
        listener = nil
        realtime.stop()
        directory.reset()
        inbox.stop()
        notifications.stop()
        push.sessionEnded(instance)
        router.reset()
    }

    /// Switching workspaces keeps the session and restarts everything scoped to the workspace.
    func switchWorkspace(to membership: Membership) {
        guard membership.id != session.workspace?.id else { return }
        router.reset()
        session.select(membership)
    }

    // MARK: Foreground

    func foregrounded() {
        guard session.phase == .ready else { return }
        realtime.resume()
        notifications.foregrounded()
        startHeartbeat()
        Task { await push.refreshAuthorization() }
    }

    func backgrounded() {
        heartbeat?.cancel()
        heartbeat = nil
        realtime.setPresenceState(.idle)
    }

    /// Marks the user seen every 5 minutes while the app is open (auto-away), as the web does.
    private func startHeartbeat() {
        heartbeat?.cancel()
        let api = session.api
        heartbeat = Task {
            while !Task.isCancelled {
                let _: EmptyBody? = try? await api.post("v1/me/heartbeat", workspace: .current)
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }
}
