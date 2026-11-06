import SwiftUI

/// Which view draws each settings page, and what a page's `id` opens.
enum SettingsCatalog {
    @MainActor @ViewBuilder
    static func page(_ page: SettingsPage) -> some View {
        switch page {
        case .general: GeneralSettings()
        case .members: MembersSettings()
        case .teams: TeamsSettings()
        case .billing: BillingSettings()
        case .ai: AISettings()
        case .integrations: IntegrationsSettings()
        case .labels: LabelsSettings()
        case .customFields: CustomFieldsSettings()
        case .assignment: AssignmentSettings()
        case .triage: TriageSettings()
        case .businessHours: BusinessHoursSettings()
        case .sla: SLASettings()
        case .automations: AutomationsSettings()
        case .mailboxes: MailboxesSettings()
        case .phone: PhoneSettings()
        case .supportChannels: SupportChannelsSettings()
        case .mailAccounts: MailAccountsSettings()
        case .mailCategories: MailCategoriesSettings()
        case .routing: RoutingSettings()
        case .brands: BrandsSettings()
        case .agentOverview: AgentOverviewSettings()
        case .bots: BotsSettings()
        case .behaviour: BehaviourSettings()
        case .knowledge: KnowledgeSettings()
        case .procedures: ProceduresSettings()
        case .tools: ToolsSettings()
        case .playground: PlaygroundSettings()
        case .tests: TestsSettings()
        case .apiKeys: APIKeysSettings()
        case .aiClients: AIClientsSettings()
        case .webhooks: WebhooksSettings()
        case .auditLog: AuditLogSettings()
        case .agentToAgent: AgentToAgentSettings()
        case .import, .emailDesign: SettingsWebFallback(page: page)
        }
    }

    @MainActor @ViewBuilder
    static func detail(_ page: SettingsPage, id: String) -> some View {
        switch page {
        case .general: GeneralSettings.Detail(id: id)
        case .members: MembersSettings.Detail(id: id)
        case .teams: TeamsSettings.Detail(id: id)
        case .billing: BillingSettings.Detail(id: id)
        case .ai: AISettings.Detail(id: id)
        case .integrations: IntegrationsSettings.Detail(id: id)
        case .labels: LabelsSettings.Detail(id: id)
        case .customFields: CustomFieldsSettings.Detail(id: id)
        case .assignment: AssignmentSettings.Detail(id: id)
        case .triage: TriageSettings.Detail(id: id)
        case .businessHours: BusinessHoursSettings.Detail(id: id)
        case .sla: SLASettings.Detail(id: id)
        case .automations: AutomationsSettings.Detail(id: id)
        case .mailboxes: MailboxesSettings.Detail(id: id)
        case .phone: PhoneSettings.Detail(id: id)
        case .supportChannels: SupportChannelsSettings.Detail(id: id)
        case .mailAccounts: MailAccountsSettings.Detail(id: id)
        case .mailCategories: MailCategoriesSettings.Detail(id: id)
        case .routing: RoutingSettings.Detail(id: id)
        case .brands: BrandsSettings.Detail(id: id)
        case .agentOverview: AgentOverviewSettings.Detail(id: id)
        case .bots: BotsSettings.Detail(id: id)
        case .behaviour: BehaviourSettings.Detail(id: id)
        case .knowledge: KnowledgeSettings.Detail(id: id)
        case .procedures: ProceduresSettings.Detail(id: id)
        case .tools: ToolsSettings.Detail(id: id)
        case .playground: PlaygroundSettings.Detail(id: id)
        case .tests: TestsSettings.Detail(id: id)
        case .apiKeys: APIKeysSettings.Detail(id: id)
        case .aiClients: AIClientsSettings.Detail(id: id)
        case .webhooks: WebhooksSettings.Detail(id: id)
        case .auditLog: AuditLogSettings.Detail(id: id)
        case .agentToAgent: AgentToAgentSettings.Detail(id: id)
        case .import, .emailDesign: SettingsWebFallback(page: page, id: id)
        }
    }
}
