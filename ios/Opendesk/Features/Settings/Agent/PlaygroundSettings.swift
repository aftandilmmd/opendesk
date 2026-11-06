import SwiftUI

/// Settings > AI agent > Playground: chat with the agent as a visitor would. Replies follow
/// Behaviour's unsaved edits when there are any; settings here try other bots, models and
/// visitors without touching the real settings.
struct PlaygroundSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var chat = AgentChat()
    @State private var botID = ""
    @State private var model: String?
    @State private var visitorName = ""
    @State private var visitorEmail = ""
    @State private var verified = false
    @State private var settingsOpen = false
    @State private var testDraft: AgentTestDraft?
    @State private var improving: AgentImproveDraft?

    /// The playground has nothing to open; a link to one lands on the playground.
    struct Detail: View {
        let id: String

        var body: some View { PlaygroundSettings() }
    }

    var body: some View {
        let store = env.agent
        let bot = store.bots.value.first { $0.id == botID } ?? store.defaultBot
        AgentChatView(
            chat: chat,
            name: bot?.name ?? store.assistantName,
            look: bot?.look ?? .ollie,
            image: bot?.imageURL,
            send: { chat.send($0, api: store.api, settings: settings(store), visitor: visitor) },
            saveTest: { turn in
                var checks = [AgentExpectation(kind: turn.handoff ? "handoff" : "no_handoff", value: "")]
                if !turn.sources.isEmpty { checks.append(AgentExpectation(kind: "cites_knowledge", value: "")) }
                for procedure in turn.procedures.prefix(3) { checks.append(AgentExpectation(kind: "uses_procedure", value: procedure.id)) }
                testDraft = AgentTestDraft(messages: chat.conversation(upTo: turn), expectations: checks)
            },
            improve: { turn in
                improving = AgentImproveDraft(question: chat.question(before: turn), answer: turn.text)
            },
            header: AnyView(header(store))
        )
        .background(Theme.chrome.ignoresSafeArea())
        .accountTitle("Playground")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !chat.turns.isEmpty {
                    Button {
                        Haptics.tap()
                        withAnimation(Motion.snappy) { chat.reset() }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("Start over")
                }
                Button { settingsOpen = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Try different settings")
            }
        }
        .sheet(isPresented: $settingsOpen) {
            PlaygroundOverrides(botID: $botID, model: $model, name: $visitorName, email: $visitorEmail, verified: $verified)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        .sheet(item: $testDraft) { draft in AgentTestEditor(draft: draft).presentationCornerRadius(Theme.Radius.sheet) }
        .sheet(item: $improving) { draft in AgentImproveSheet(draft: draft).presentationCornerRadius(Theme.Radius.sheet) }
        .task {
            if store.config == nil { await store.loadConfig() }
            if !store.bots.loaded { await store.loadBots() }
        }
    }

    @ViewBuilder
    private func header(_ store: AgentStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.draft != nil {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "pencil.and.outline").font(.system(size: 13)).foregroundStyle(Tone.violet.text)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Using your unsaved changes").font(ODFont.sans(13.5, weight: .semibold)).foregroundStyle(Theme.fg)
                        Text("Replies follow the edits on the Behaviour page. Save them there when you are happy.").font(ODFont.footnote).foregroundStyle(Theme.fg2)
                        Button("Back to behaviour") { env.router.accountPath.append(.setting(.behaviour)) }
                            .buttonStyle(ChipButtonStyle(tone: .violet))
                            .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Tone.violet.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            if !store.aiOn, store.config != nil {
                AgentOffNotice(title: "AI is off for this workspace.", message: "Turn on AI to try the agent here.", action: "Open AI settings")
            }
            if chat.spent > 0 {
                HStack {
                    Text("\(AgentText.usd(chat.spent)) spent").font(ODFont.mono(11.5)).foregroundStyle(Theme.fg3)
                    Text("AI usage in this session").font(ODFont.sans(11.5)).foregroundStyle(Theme.fg4)
                }
            } else if chat.turns.isEmpty {
                Text("Chat with the agent as a visitor would. Nothing here reaches a customer or creates a ticket.\(store.config?.playgroundCost.map { " Each reply costs about \(AgentText.usd($0)) on the agent's model." } ?? "")")
                    .font(ODFont.footnote)
                    .foregroundStyle(Theme.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settings(_ store: AgentStore) -> [String: JSONValue] {
        var out = store.draft?.playgroundJSON ?? [:]
        if let model { out["widget_model"] = .string(model) }
        if !botID.isEmpty { out["bot_id"] = .string(botID) }
        return out
    }

    private var visitor: [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        if !AgentText.trimmed(visitorName).isEmpty { out["name"] = .string(AgentText.trimmed(visitorName)) }
        if !AgentText.trimmed(visitorEmail).isEmpty { out["email"] = .string(AgentText.trimmed(visitorEmail)) }
        if verified { out["verified"] = .bool(true) }
        return out
    }
}

/// "Try different settings": which bot answers, its model, and who the visitor is.
private struct PlaygroundOverrides: View {
    @Binding var botID: String
    @Binding var model: String?
    @Binding var name: String
    @Binding var email: String
    @Binding var verified: Bool

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let store = env.agent
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AccountSheetHeader(title: "Try different settings", subtitle: "Changes here only affect this playground.") { dismiss() }
                AccountSection(title: "Answer as") {
                    ForEach(Array(store.bots.value.enumerated()), id: \.element.id) { index, bot in
                        if index > 0 { AccountDivider() }
                        Button {
                            Haptics.selection()
                            botID = bot.isDefault ? "" : bot.id
                        } label: {
                            HStack(spacing: 12) {
                                BotFace(look: bot.look, image: bot.imageURL, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bot.name).font(ODFont.sans(15.5)).foregroundStyle(Theme.fg)
                                    if bot.isDefault { Text("Default").font(ODFont.footnote).foregroundStyle(Theme.fg3) }
                                }
                                Spacer()
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .opacity((botID.isEmpty ? bot.isDefault : botID == bot.id) ? 1 : 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
                AccountSection(title: "Model") {
                    AgentModelRow(title: "Agent model", model: Binding(get: { model ?? store.behaviour.widgetModel }, set: { model = $0 }))
                    if model != nil {
                        AccountDivider()
                        Button("Use saved") { model = nil }
                            .font(ODFont.sans(14.5, weight: .medium))
                            .foregroundStyle(Theme.fg2)
                            .padding(14)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    AgentGroupTitle(title: "Visitor")
                    AgentField(label: "Name", text: $name, prompt: "Ada Lovelace")
                    AgentField(label: "Email", text: $email, prompt: "ada@example.com", problem: email.isEmpty || email.contains("@") ? nil : "Enter a valid email", keyboard: .emailAddress)
                    Panel {
                        AccountToggleRow(symbol: "person.badge.shield.checkmark", tone: .teal, title: "Verified identity", subtitle: "As if your site signed the visitor in. Unlocks verified-only tools.", isOn: $verified)
                    }
                }
                Button("Change the real settings") {
                    dismiss()
                    env.router.accountPath.append(.setting(.behaviour))
                }
                .buttonStyle(ChipButtonStyle())
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.chrome)
    }
}
