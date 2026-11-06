import SwiftUI

/// A group of the workspace's settings, in the web app's order (Settings in the web's sidebar).
enum SettingsGroup: String, CaseIterable, Hashable {
    case workspace, inbox, channels, agent, developers, admin

    var title: String {
        switch self {
        case .workspace: "Workspace"
        case .inbox: "Inbox"
        case .channels: "Channels"
        case .agent: "AI agent"
        case .developers: "Developers"
        case .admin: "Admin"
        }
    }
}

/// One of the workspace's settings pages. The raw value is its path under the web app's
/// `/settings/`, which the demo links and the web fallback use.
enum SettingsPage: String, CaseIterable, Hashable {
    case general = "workspace"
    case members, teams
    case billing
    case ai
    case integrations
    case `import`

    case labels = "tags"
    case customFields = "custom-fields"
    case assignment, triage
    case businessHours = "business-hours"
    case sla, automations

    case mailboxes, phone
    case supportChannels = "support-channels"
    case mailAccounts = "mail-accounts"
    case mailCategories = "mail-categories"
    case routing
    case brands
    case emailDesign = "email-design"

    case agentOverview = "ai/agent"
    case bots = "ai/bots"
    case behaviour = "ai/behaviour"
    case knowledge = "ai/knowledge"
    case procedures = "ai/procedures"
    case tools = "ai/tools"
    case playground = "ai/playground"
    case tests = "ai/tests"

    case apiKeys = "api-keys"
    case aiClients = "ai-clients"
    case webhooks

    case auditLog = "audit-log"

    /// Personal, under Your settings: talking to other agents' assistants over Collab mail.
    case agentToAgent = "agent-to-agent"

    var group: SettingsGroup? {
        switch self {
        case .general, .members, .teams, .billing, .ai, .integrations, .import: .workspace
        case .labels, .customFields, .assignment, .triage, .businessHours, .sla, .automations: .inbox
        case .mailboxes, .phone, .supportChannels, .mailAccounts, .mailCategories, .routing, .brands, .emailDesign: .channels
        case .agentOverview, .bots, .behaviour, .knowledge, .procedures, .tools, .playground, .tests: .agent
        case .apiKeys, .aiClients, .webhooks: .developers
        case .auditLog: .admin
        case .agentToAgent: nil
        }
    }

    var title: String {
        switch self {
        case .general: "General"
        case .members: "Members"
        case .teams: "Teams"
        case .billing: "Plan and billing"
        case .ai: "AI"
        case .integrations: "Integrations"
        case .import: "Import"
        case .labels: "Labels"
        case .customFields: "Custom fields"
        case .assignment: "Assignment"
        case .triage: "Triage"
        case .businessHours: "Business hours"
        case .sla: "SLA policies"
        case .automations: "Automations"
        case .mailboxes: "Mailboxes"
        case .phone: "Phone"
        case .supportChannels: "Support channels"
        case .mailAccounts: "Mail accounts"
        case .mailCategories: "Inbox categories"
        case .routing: "Routing"
        case .brands: "Brands and widgets"
        case .emailDesign: "Email design"
        case .agentOverview: "Overview"
        case .bots: "Bots"
        case .behaviour: "Behaviour"
        case .knowledge: "Knowledge"
        case .procedures: "Procedures"
        case .tools: "Tools"
        case .playground: "Playground"
        case .tests: "Tests"
        case .apiKeys: "API keys"
        case .aiClients: "AI clients"
        case .webhooks: "Webhooks"
        case .auditLog: "Audit log"
        case .agentToAgent: "Agent-to-agent"
        }
    }

    var symbol: String {
        switch self {
        case .general: "building.2"
        case .members: "person.2"
        case .teams: "person.3"
        case .billing: "creditcard"
        case .ai: "cpu"
        case .integrations: "puzzlepiece.extension"
        case .import: "square.and.arrow.down"
        case .labels: "tag"
        case .customFields: "slider.horizontal.3"
        case .assignment: "shuffle"
        case .triage: "sparkles"
        case .businessHours: "clock"
        case .sla: "gauge.with.dots.needle.67percent"
        case .automations: "bolt"
        case .mailboxes: "tray.2"
        case .phone: "phone"
        case .supportChannels: "bubble.left.and.bubble.right"
        case .mailAccounts: "at"
        case .mailCategories: "rectangle.split.3x1"
        case .routing: "arrow.triangle.branch"
        case .brands: "bubble.left.and.text.bubble.right"
        case .emailDesign: "paintpalette"
        case .agentOverview: "square.grid.2x2"
        case .bots: "face.smiling"
        case .behaviour: "slider.horizontal.3"
        case .knowledge: "book"
        case .procedures: "scroll"
        case .tools: "wrench.and.screwdriver"
        case .playground: "flask"
        case .tests: "checklist"
        case .apiKeys: "key"
        case .aiClients: "cable.connector"
        case .webhooks: "point.3.connected.trianglepath.dotted"
        case .auditLog: "list.bullet.clipboard"
        case .agentToAgent: "bubble.left.and.text.bubble.right"
        }
    }

    /// Ollie's pages carry its violet (the AI colour); the rest are grey like the web's sidebar.
    var tone: Tone {
        group == .agent || self == .agentToAgent ? .violet : .gray
    }

    /// Pages that only shape tickets: not listed while the workspace has Tickets off
    /// (`TICKET_SETTINGS` in the web app).
    var ticketsOnly: Bool {
        switch self {
        case .labels, .customFields, .assignment, .triage, .businessHours, .sla, .automations,
             .mailboxes, .phone, .supportChannels, .routing, .brands, .emailDesign: true
        default: false
        }
    }

    /// Pages that stay on the web: a template designer and bulk imports from other helpdesks
    /// need a large screen and a keyboard. Each opens the web app's page in the in-app browser.
    var webOnly: Bool {
        self == .emailDesign || self == .import
    }

    /// The web app's page, for the pages that stay there.
    var webPath: String { "/settings/\(rawValue)" }

    /// What the open workspace lists in `group`, as the web's settings sidebar does.
    @MainActor
    static func visible(in group: SettingsGroup, env: AppEnvironment) -> [SettingsPage] {
        allCases.filter { $0.group == group && $0.isVisible(env: env) }
    }

    @MainActor
    func isVisible(env: AppEnvironment) -> Bool {
        let session = env.session
        let admin = session.isAdmin
        let ai = env.directory.ai.enabled
        let collab = env.directory.collab.enabled
        if ticketsOnly, session.workspace?.workspace.ticketsOn == false { return false }
        switch self {
        case .ai: return ai || admin
        case .mailAccounts, .mailCategories: return collab
        case .agentToAgent: return collab && ai
        default: break
        }
        if group == .agent { return admin && ai }
        return true
    }
}
