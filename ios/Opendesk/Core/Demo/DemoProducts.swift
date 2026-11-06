#if DEBUG
import Foundation

/// Turns the open demo workspace's products on and off, so the app's Tickets off and Mail off
/// screens run their real code: `/demo/tickets-off`, `/demo/tickets-on`, `/demo/mail-off`, `/demo/mail-on`.
@MainActor
enum DemoProducts {
    static func run(_ action: String?, env: AppEnvironment) {
        guard DemoMode.isOn, let action, let workspace = env.session.workspace?.id else { return }
        let change: (tickets: Bool?, mail: Bool?)
        switch action {
        case "tickets-off": change = (false, nil)
        case "tickets-on": change = (true, nil)
        case "mail-off": change = (nil, false)
        case "mail-on": change = (nil, true)
        default: return
        }
        env.router.demoAction = nil
        Task {
            await DemoBackend.shared.setProducts(workspace: workspace, tickets: change.tickets, mail: change.mail)
            await env.session.membershipChanged()
        }
    }
}

extension DemoBackend {
    /// What `PATCH /v1/workspace {settings: {tickets_enabled, mail_enabled}}` would leave.
    func setProducts(workspace: String, tickets: Bool?, mail: Bool?) {
        guard let index = world.workspaces.firstIndex(where: { $0.id == workspace }) else { return }
        if let tickets {
            var settings = world.workspaces[index].workspace.settings ?? WorkspaceSettings()
            settings.ticketsEnabled = tickets
            world.workspaces[index].workspace.settings = settings
        }
        if let mail {
            world.workspaces[index].workspace.mailAvailable = mail
            world.workspaces[index].mail.enabled = mail && workspace == DemoSeed.marginID
        }
    }
}
#endif
