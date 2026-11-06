import Foundation
import Observation

/// What the AI agent's settings pages share: the agent's config, bots, knowledge, procedures,
/// tools, tests and runs, kept fresh by the workspace's events, and the Behaviour page's unsaved
/// edits, which the playground and test runs try before they are saved.
@MainActor
@Observable
final class AgentStore {
    static let shared = AgentStore()

    /// One list's state: nothing yet, its rows, or why it failed.
    struct Slot<Value> {
        var value: Value
        var loaded = false
        var error: String?
    }

    private(set) var config: AgentConfig?
    private(set) var configError: String?
    private(set) var models: AgentModels?
    var bots = Slot<[AgentBot]>(value: [])
    var knowledge = Slot<[KnowledgeSource]>(value: [])
    var procedures = Slot<[AgentProcedure]>(value: [])
    var servers = Slot<[McpServer]>(value: [])
    var tests = Slot<[AgentTest]>(value: [])
    var runs = Slot<[AgentTestRun]>(value: [])
    var review = Slot<[AgentReviewItem]>(value: [])
    var setup = Slot<AgentSetup?>(value: nil)
    var mailboxes = Slot<[AgentMailbox]>(value: [])

    /// The Behaviour page's unsaved edits, tried by the playground and test runs.
    var draft: AgentBehaviour?

    @ObservationIgnored private(set) var api: APIClient?
    @ObservationIgnored private var workspaceID: String?
    @ObservationIgnored private var listener: UUID?
    @ObservationIgnored private var refetch: [String: Task<Void, Never>] = [:]

    /// Points the store at the open workspace, starting over when it changed.
    func bind(_ env: AppEnvironment) {
        let id = env.session.workspace?.id
        if id != workspaceID {
            workspaceID = id
            reset()
        }
        api = env.session.api
        if listener == nil {
            listener = env.realtime.subscribe { [weak self] update in self?.handle(update) }
        }
    }

    private func reset() {
        config = nil
        configError = nil
        models = nil
        bots = Slot(value: [])
        knowledge = Slot(value: [])
        procedures = Slot(value: [])
        servers = Slot(value: [])
        tests = Slot(value: [])
        runs = Slot(value: [])
        review = Slot(value: [])
        setup = Slot(value: nil)
        mailboxes = Slot(value: [])
        draft = nil
    }

    // MARK: Loading

    var assistantName: String { config?.assistantName ?? "Ollie" }
    var aiOn: Bool { config?.enabled ?? false }
    /// The behaviour as saved, or as edited when Behaviour has unsaved changes.
    var behaviour: AgentBehaviour { draft ?? config?.behaviour ?? AgentBehaviour() }
    var defaultBot: AgentBot? { bots.value.first(where: \.isDefault) ?? bots.value.first }
    var activeRun: AgentTestRun? { runs.value.first(where: \.active) }

    func loadConfig() async {
        guard let api else { return }
        do {
            config = try await api.get("v1/ai/config")
            configError = nil
        } catch {
            if config == nil { configError = error.userMessage }
        }
    }

    func loadModels() async {
        guard let api, models == nil else { return }
        models = try? await api.get("v1/ai/models")
    }

    private func fill<Value>(_ slot: ReferenceWritableKeyPath<AgentStore, Slot<Value>>, _ load: (APIClient) async throws -> Value) async {
        guard let api else { return }
        do {
            let value = try await load(api)
            self[keyPath: slot] = Slot(value: value, loaded: true)
        } catch {
            guard !error.isCancellation else { return }
            self[keyPath: slot].loaded = true
            self[keyPath: slot].error = error.userMessage
        }
    }

    func loadBots() async {
        await fill(\.bots) { try await $0.all("v1/bots") as [AgentBot] }
        bots.value.sort { $0.position < $1.position }
    }

    func loadKnowledge() async { await fill(\.knowledge) { try await $0.all("v1/ai/knowledge") as [KnowledgeSource] } }
    func loadProcedures() async { await fill(\.procedures) { (try await $0.get("v1/ai/procedures") as Page<AgentProcedure>).data } }
    func loadServers() async { await fill(\.servers) { try await $0.all("v1/ai/mcp-servers") as [McpServer] } }
    func loadTests() async { await fill(\.tests) { (try await $0.get("v1/ai/agent/tests") as Page<AgentTest>).data } }
    func loadRuns() async { await fill(\.runs) { (try await $0.get("v1/ai/agent/test-runs") as Page<AgentTestRun>).data } }
    func loadReview() async { await fill(\.review) { (try await $0.get("v1/ai/agent/review") as Page<AgentReviewItem>).data } }
    func loadSetup() async { await fill(\.setup) { try await $0.get("v1/ai/agent/setup") as AgentSetup } }
    func loadMailboxes() async { await fill(\.mailboxes) { try await $0.all("v1/mailboxes") as [AgentMailbox] } }

    // MARK: Writing

    /// PATCH /v1/ai/settings with only what changed; the config is read back after.
    func saveBehaviour(_ next: AgentBehaviour) async throws {
        guard let api else { return }
        let changed = next.patch(from: config?.behaviour ?? AgentBehaviour())
        guard !changed.isEmpty else { return }
        let _: JSONValue = try await api.patch("v1/ai/settings", body: JSONValue.object(changed))
        draft = nil
        await loadConfig()
        refresh("setup") { await $0.loadSetup() }
    }

    func setAnswers(_ on: Bool) async throws {
        guard let api else { return }
        let _: JSONValue = try await api.patch("v1/ai/settings", body: JSONValue.object(["widget_answers": .bool(on)]))
        if var config {
            config.behaviour.widgetAnswers = on
            self.config = config
        }
        draft?.widgetAnswers = on
        refresh("setup") { await $0.loadSetup() }
    }

    func upsert(_ bot: AgentBot) {
        if let index = bots.value.firstIndex(where: { $0.id == bot.id }) { bots.value[index] = bot } else { bots.value.append(bot) }
        if bot.isDefault {
            for index in bots.value.indices where bots.value[index].id != bot.id { bots.value[index].isDefault = false }
        }
        bots.value.sort { $0.position < $1.position }
    }

    func upsert(_ source: KnowledgeSource) {
        if let index = knowledge.value.firstIndex(where: { $0.id == source.id }) { knowledge.value[index] = source } else { knowledge.value.insert(source, at: 0) }
    }

    func upsert(_ procedure: AgentProcedure) {
        if let index = procedures.value.firstIndex(where: { $0.id == procedure.id }) { procedures.value[index] = procedure } else { procedures.value.append(procedure) }
    }

    func upsert(_ server: McpServer) {
        if let index = servers.value.firstIndex(where: { $0.id == server.id }) { servers.value[index] = server } else { servers.value.append(server) }
    }

    func upsert(_ test: AgentTest) {
        if let index = tests.value.firstIndex(where: { $0.id == test.id }) { tests.value[index] = test } else { tests.value.insert(test, at: 0) }
    }

    func upsert(_ run: AgentTestRun) {
        if let index = runs.value.firstIndex(where: { $0.id == run.id }) { runs.value[index] = run } else { runs.value.insert(run, at: 0) }
    }

    /// Starts a run of `ids` (every test when nil), with the Behaviour draft when there is one.
    @discardableResult
    func startRun(_ ids: [String]? = nil, settings: [String: JSONValue]? = nil) async throws -> AgentTestRun {
        var body: [String: JSONValue] = [:]
        if let ids { body["test_ids"] = .array(ids.map(JSONValue.string)) }
        if let settings { body["settings"] = .object(settings) } else if let draft { body["settings"] = .object(draft.playgroundJSON) }
        guard let api else { throw APIError.signedOut }
        let run: AgentTestRun = try await api.post("v1/ai/agent/test-runs", body: JSONValue.object(body))
        upsert(run)
        return run
    }

    // MARK: Realtime

    private func handle(_ update: RealtimeUpdate) {
        guard workspaceID != nil else { return }
        switch update {
        case .resync:
            if config != nil { refresh("config") { await $0.loadConfig() } }
            if bots.loaded { refresh("bots") { await $0.loadBots() } }
            if knowledge.loaded { refresh("knowledge") { await $0.loadKnowledge() } }
            if procedures.loaded { refresh("procedures") { await $0.loadProcedures() } }
            if servers.loaded { refresh("servers") { await $0.loadServers() } }
            if tests.loaded { refresh("tests") { await $0.loadTests() } }
            if runs.loaded { refresh("runs") { await $0.loadRuns() } }
            if review.loaded { refresh("review") { await $0.loadReview() } }
        case let .envelope(envelope):
            apply(envelope)
        }
    }

    private func apply(_ envelope: Envelope) {
        let type = envelope.type
        switch type {
        case "workspace.updated":
            if config != nil { refresh("config") { await $0.loadConfig() } }
        case let t where t.hasPrefix("bot."):
            if bots.loaded { refresh("bots") { await $0.loadBots() } }
        case let t where t.hasPrefix("widget.") || t.hasPrefix("mailbox."):
            if bots.loaded { refresh("bots") { await $0.loadBots() } }
            if t.hasPrefix("mailbox."), mailboxes.loaded { refresh("mailboxes") { await $0.loadMailboxes() } }
        case "ai_knowledge.deleted":
            if let id = envelope.string("source_id") { knowledge.value.removeAll { $0.id == id } }
        case let t where t.hasPrefix("ai_knowledge."):
            if let source = envelope.member("source", as: KnowledgeSource.self) { upsert(source) } else if knowledge.loaded { refresh("knowledge") { await $0.loadKnowledge() } }
        case "ai_mcp_server.deleted":
            if let id = envelope.string("mcp_server_id") { servers.value.removeAll { $0.id == id } }
        case let t where t.hasPrefix("ai_mcp_server."):
            if let server = envelope.member("mcp_server", as: McpServer.self) { upsert(server) } else if servers.loaded { refresh("servers") { await $0.loadServers() } }
        case "ai_procedure.deleted":
            if let id = envelope.string("procedure_id") { procedures.value.removeAll { $0.id == id } }
        case let t where t.hasPrefix("ai_procedure."):
            if let procedure = envelope.member("procedure", as: AgentProcedure.self) { upsert(procedure) } else if procedures.loaded { refresh("procedures") { await $0.loadProcedures() } }
        case "ai_agent_test.deleted":
            if let id = envelope.string("test_id") { tests.value.removeAll { $0.id == id } }
        case "ai_agent_test.created", "ai_agent_test.updated":
            if let test = envelope.member("test", as: AgentTest.self) { upsert(test) }
        case "ai_agent_test_run.created", "ai_agent_test_run.updated":
            if let run = envelope.member("run", as: AgentTestRun.self) {
                upsert(run)
                if !run.active { refresh("tests") { await $0.loadTests() } }
            }
        case "ai_agent_test_result.updated":
            if let result = envelope.member("result", as: AgentTestResult.self),
               let index = tests.value.firstIndex(where: { $0.id == result.testID }) {
                tests.value[index].lastResult = result
            }
        case "ai_agent_review.updated":
            if review.loaded { refresh("review") { await $0.loadReview() } }
        default:
            break
        }
    }

    /// One refetch per list at a time, a moment after the last event, so a burst is one call.
    func refresh(_ key: String, _ work: @escaping @MainActor (AgentStore) async -> Void) {
        refetch[key]?.cancel()
        refetch[key] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            await work(self)
        }
    }
}
