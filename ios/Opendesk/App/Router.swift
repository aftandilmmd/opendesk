import Observation
import SwiftUI

/// A ticket pushed on the inbox stack. `seed` shows the row's copy while the full ticket loads.
struct TicketRoute: Hashable {
    let id: String
    var seed: Ticket?

    static func == (lhs: TicketRoute, rhs: TicketRoute) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Tabs, the inbox stack, and links from outside the app (universal links,
/// `opendesk://open?path=`, notification taps).
@MainActor
@Observable
final class Router {
    var tab: AppTab = .inbox
    var inboxPath: [TicketRoute] = []
    var notificationsPath: [TicketRoute] = []
    var showOllie = false
    /// The ticket on screen, so a push for it stays quiet in the foreground.
    var visibleTicketID: String?

    @ObservationIgnored weak var environment: AppEnvironment?
    @ObservationIgnored private var pending: DeepLink.Target?

    func reset() {
        inboxPath = []
        notificationsPath = []
        visibleTicketID = nil
        showOllie = false
    }

    /// A URL the app was asked to open.
    func handle(url: URL) {
        guard let env = environment else { return }
        // OAuth callbacks are answered by the web authentication session itself.
        if url.scheme == "opendesk", url.host() == "auth" { return }
        #if DEBUG
        if DemoMode.isOn, url.scheme == "opendesk", url.host() == "demo" { return openDemo(url.path()) }
        #endif
        guard let target = DeepLink.parse(url: url, instance: env.session.instance) else {
            if url.scheme == "opendesk" { env.toasts.show("That link isn't one the app can open.") }
            return
        }
        open(target)
    }

    func open(_ target: DeepLink.Target) {
        guard let env = environment else { return }
        let session = env.session
        guard session.phase == .ready else {
            pending = target
            return
        }
        if let server = target.server, let url = URL(string: server), PushPayload.origin(url) != PushPayload.origin(session.instance.apiURL) {
            env.toasts.show("That's from another opendesk server (\(url.host() ?? server)). Switch servers in Account to open it.")
            return
        }
        if let workspaceID = target.workspaceID, workspaceID != session.workspace?.id {
            guard let membership = session.memberships.first(where: { $0.id == workspaceID }) else {
                env.toasts.show("You're not a member of that workspace.")
                return
            }
            pending = DeepLink.Target(link: target.link, server: nil, workspaceID: nil)
            env.switchWorkspace(to: membership)
            return
        }
        go(target.link)
    }

    /// Opens what waited for sign-in or a workspace switch.
    func workspaceReady() {
        #if DEBUG
        if let screen = pendingDemoScreen {
            pendingDemoScreen = nil
            openDemo(screen)
        }
        #endif
        guard let target = pending else { return }
        pending = nil
        open(target)
    }

    private func go(_ link: DeepLink) {
        guard let env = environment else { return }
        switch link {
        case let .ticket(id, scope):
            // The link's folder or view becomes the list behind the ticket, as on the web.
            if let scope { env.inbox.setScope(scope) }
            showOllie = false
            tab = .inbox
            inboxPath = [TicketRoute(id: id)]
        case let .scope(scope):
            env.inbox.setScope(scope)
            tab = .inbox
            inboxPath = []
        case .notifications:
            tab = .notifications
            notificationsPath = []
        }
    }

    #if DEBUG
    @ObservationIgnored private var pendingDemoScreen: String?

    /// Demo mode takes app paths without the system's "Open in" prompt, for the QA harness:
    /// `OPENDESK_DEMO_OPEN=<path>` at launch, and during a run the path written to the app's
    /// `tmp/opendesk-demo-open` followed by the Darwin notification `sh.opendesk.demo.open`.
    func startDemoLinks() {
        if let path = AppInfo.debugValue("OPENDESK_DEMO_OPEN") { openDemo(path) }
        DemoLinks.watch { [weak self] path in self?.openDemo(path) }
    }

    /// Any path `DeepLink` reads (`/inbox/unassigned/<id>`, `/views/<id>`, `/notifications`),
    /// an `opendesk://` URL, or a screen no link names: `/account`, `/ollie`.
    func openDemo(_ raw: String) {
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("opendesk://"), let url = URL(string: path) { return handle(url: url) }
        guard environment?.session.phase == .ready else {
            pendingDemoScreen = path
            return
        }
        switch path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
        case "account":
            showOllie = false
            tab = .account
        case "ollie":
            showOllie = true
        case "inbox":
            showOllie = false
            tab = .inbox
            inboxPath = []
        default:
            guard let link = DeepLink.parse(path: path) else { return }
            open(DeepLink.Target(link: link, server: nil, workspaceID: nil))
        }
    }
    #endif

    func openTicket(_ ticket: Ticket) {
        let route = TicketRoute(id: ticket.id, seed: ticket)
        switch tab {
        case .notifications: notificationsPath.append(route)
        default: inboxPath.append(route)
        }
    }
}
