import Foundation

/// What the open workspace offers (contracts/api.md, `settings.tickets_enabled` and
/// `mail_available`; web `lib/products.ts`): both until the workspace says otherwise.
struct Products: Equatable, Sendable {
    var tickets = true
    var mail = true

    init(tickets: Bool = true, mail: Bool = true) {
        self.tickets = tickets
        self.mail = mail
    }

    init(_ workspace: Workspace?) {
        tickets = workspace?.ticketsOn ?? true
        mail = workspace?.mailOn ?? true
    }

    /// Whether `area` is there: Tickets off takes the ticket list and Reports away, Mail off takes Mail.
    func allows(_ area: AppArea) -> Bool {
        switch area {
        case .tickets, .reports: tickets
        case .mail: mail
        default: true
        }
    }

    /// Where a member lands: the inbox, else Mail, else the workspace's people.
    var home: AppArea {
        if tickets { return .tickets }
        if mail { return .mail }
        return .contacts
    }
}

@MainActor
extension AppEnvironment {
    var products: Products { Products(session.workspace?.workspace) }

    /// A change to the workspace's settings can turn a product on or off: read the
    /// membership again so `products` follows it live.
    func productsHeard(_ update: RealtimeUpdate) {
        guard case let .envelope(envelope) = update, envelope.type == "workspace.updated" else { return }
        Task { await session.membershipChanged() }
    }
}
