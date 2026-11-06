import SwiftUI

/// Settings > AI agent > Tests: saved conversations that check the agent's answers. Runs go
/// through the queue and update live; with unsaved Behaviour changes they run against those.
struct TestsSettings: View {
    enum Filter: String, CaseIterable { case all, failing, passing, never }

    @Environment(AppEnvironment.self) private var env
    @State private var filter: Filter = .all
    @State private var editing: AgentTestDraft?
    @State private var confirm: AccountConfirm?
    @State private var starting = false
    @State private var stopping = false

    var body: some View {
        let store = env.agent
        let tests = store.tests.value
        let run = store.activeRun
        let shown = tests.filter { matches($0, filter, run: run) }
        AccountPage(title: "Tests", spacing: 20) {
            AgentIntro(text: "Saved conversations that check \(store.assistantName)'s answers. Run them after you change instructions, knowledge or tools.")
            if store.draft != nil {
                Notice(text: "You have unsaved behaviour changes. Run tests against them before you save.", tone: .violet, symbol: "slider.horizontal.3")
            }
            if !store.tests.loaded {
                Panel { SkeletonRows(count: 3) }
            } else if let error = store.tests.error, tests.isEmpty {
                Panel { ErrorState(message: error) { Task { await store.loadTests() } } }
            } else if tests.isEmpty {
                empty(store)
            } else {
                summary(store, tests)
                if let run { runBanner(run, store) }
                let newly = tests.filter { $0.lastResult?.newlyFailing == true }.count
                if run == nil, newly > 0 {
                    Notice(text: newly == 1 ? "1 test started failing since the run before" : "\(newly) tests started failing since the run before", tone: .red, symbol: "exclamationmark.triangle")
                }
                VStack(alignment: .leading, spacing: 8) {
                    AccountSegmented(options: Filter.allCases, selection: $filter, label: { label($0, tests, run: run) })
                    Panel {
                        if shown.isEmpty {
                            Text("No tests here.").font(ODFont.footnote).foregroundStyle(Theme.fg3).frame(maxWidth: .infinity).padding(.vertical, 28)
                        }
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, test in
                            if index > 0 { AccountDivider() }
                            SettingsDetailLink(page: .tests, id: test.id) {
                                AgentTestRow(test: test, state: .of(test, run: run))
                            }
                            .contextMenu { menu(test, store, running: run != nil) }
                        }
                    }
                    .motion(Motion.snappy, value: shown.map(\.id))
                }
            }
            Text(note(store))
                .font(ODFont.footnote)
                .foregroundStyle(Theme.fg3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !tests.isEmpty {
                    Button {
                        Task { await start(nil, store) }
                    } label: {
                        if starting { ProgressView() } else { Label("Run all", systemImage: "play") }
                    }
                    .disabled(starting || run != nil)
                    .accessibilityLabel("Run all")
                }
                Button { editing = AgentTestDraft() } label: { Image(systemName: "plus") }
                    .disabled(tests.count >= AgentTests.maxTests)
                    .accessibilityLabel("New test")
            }
        }
        .sheet(item: $editing) { draft in AgentTestEditor(draft: draft).presentationCornerRadius(Theme.Radius.sheet) }
        .accountConfirm($confirm)
        .refreshable { await load(store) }
        .task { await load(store) }
    }

    private func load(_ store: AgentStore) async {
        if store.config == nil { await store.loadConfig() }
        await store.loadTests()
        await store.loadRuns()
        if !store.servers.loaded { await store.loadServers() }
        if !store.procedures.loaded { await store.loadProcedures() }
    }

    private func matches(_ test: AgentTest, _ filter: Filter, run: AgentTestRun?) -> Bool {
        let state = AgentTestState.of(test, run: run)
        return switch filter {
        case .all: true
        case .failing: state == .failed || state == .error
        case .passing: state == .passed
        case .never: state == .never
        }
    }

    private func label(_ filter: Filter, _ tests: [AgentTest], run: AgentTestRun?) -> String {
        let count = filter == .all ? 0 : tests.filter { matches($0, filter, run: run) }.count
        let title = switch filter {
        case .all: "All"
        case .failing: "Failing"
        case .passing: "Passing"
        case .never: "Not run"
        }
        return count > 0 ? "\(title) \(count)" : title
    }

    private func note(_ store: AgentStore) -> String {
        let cost = store.config?.playgroundCost.map { AgentText.usd($0) } ?? "a cent"
        return "Each test answered or graded costs about \(cost) on the agent's model, as playground replies do. Tools that change things never run in tests."
    }

    private func empty(_ store: AgentStore) -> some View {
        Panel {
            VStack(spacing: 16) {
                EmptyState(symbol: "checklist", title: "No tests yet", message: "A test is a visitor's question and what \(store.assistantName)'s answer must do. Run your tests before you save new instructions, so a fix in one place doesn't break another.")
                HStack(spacing: 8) {
                    Button { editing = AgentTestDraft() } label: { Label("New test", systemImage: "plus") }
                        .buttonStyle(InkButtonStyle(fullWidth: false, height: 38))
                    Button { env.router.accountPath.append(.setting(.playground)) } label: { Label("Open the playground", systemImage: "flask") }
                        .buttonStyle(OutlineButtonStyle(fullWidth: false, height: 38))
                }
                VStack(alignment: .leading, spacing: 6) {
                    AgentTip(text: "Save any playground conversation as a test")
                    AgentTip(text: "Improving an answer can save a test too")
                }
                .padding(.bottom, 20)
            }
        }
    }

    private func summary(_ store: AgentStore, _ tests: [AgentTest]) -> some View {
        let results = tests.compactMap(\.lastResult).filter(\.final)
        let passed = results.filter { $0.status == "passed" }.count
        let newly = results.filter(\.newlyFailing).count
        let last = store.runs.value.first { !$0.active }
        return AgentStatGrid {
            AgentStat(label: "Pass rate", value: results.isEmpty ? "None" : AgentText.percent(passed, of: results.count), hint: results.isEmpty ? "No results yet" : "\(passed) of \(results.count) passing", tone: results.isEmpty ? nil : passed == results.count ? .green : nil)
            AgentStat(label: "Newly failing", value: newly.formatted(), hint: "Passed in the run before", tone: newly > 0 ? .red : nil)
            AgentStat(label: "Last run", value: last.flatMap { $0.finishedAt ?? $0.createdAt }.map { Format.relShort($0) } ?? "Never run", hint: last.map { $0.draft ? "Against unsaved changes" : "Against saved settings" })
            AgentStat(label: "Spent", value: last.map { AgentText.usd($0.usd) } ?? AgentText.usd(0), hint: "AI usage of the last run")
        }
    }

    private func runBanner(_ run: AgentTestRun, _ store: AgentStore) -> some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(run.status == "queued" ? "Starting the run…" : "Running tests: \(run.done) of \(run.total)")
                            .font(ODFont.sans(14.5, weight: .medium))
                            .foregroundStyle(Theme.fg)
                            .contentTransition(.numericText())
                        HStack(spacing: 6) {
                            if run.passed > 0 { Text("\(run.passed) passed").foregroundStyle(Tone.green.text) }
                            if run.failed + run.errored > 0 { Text("\(run.failed + run.errored) failed").foregroundStyle(Tone.red.text) }
                            if run.draft { Text("Unsaved changes").foregroundStyle(Tone.violet.text) }
                        }
                        .font(ODFont.footnote)
                    }
                    Spacer()
                    Button {
                        Task { await stop(run, store) }
                    } label: {
                        ButtonLabel(title: "Stop", busy: stopping)
                    }
                    .buttonStyle(ChipButtonStyle())
                    .disabled(stopping)
                }
                ProgressView(value: run.progress)
                    .tint(Tone.violet.solid)
                    .accessibilityLabel("Test run progress")
                    .motion(Motion.snappy, value: run.done)
            }
        }
    }

    @ViewBuilder
    private func menu(_ test: AgentTest, _ store: AgentStore, running: Bool) -> some View {
        Button("Run this test", systemImage: "play") { Task { await start([test.id], store) } }
            .disabled(running)
        Button("Edit", systemImage: "pencil") { editing = AgentTestDraft(test: test) }
        Button("Delete", systemImage: "trash", role: .destructive) { confirm = AgentTestActions.delete(test, env: env) }
    }

    private func start(_ ids: [String]?, _ store: AgentStore) async {
        starting = true
        defer { starting = false }
        do {
            try await store.startRun(ids)
            Haptics.success()
        } catch {
            env.toasts.show("Couldn't start the run. \(error.userMessage)", kind: .error)
        }
    }

    private func stop(_ run: AgentTestRun, _ store: AgentStore) async {
        guard let api = store.api else { return }
        stopping = true
        defer { stopping = false }
        do {
            let stopped: AgentTestRun = try await api.post("v1/ai/agent/test-runs/\(run.id)/cancel")
            store.upsert(stopped)
            Haptics.tap()
        } catch {
            env.toasts.show("Couldn't stop the run. \(error.userMessage)", kind: .error)
        }
    }
}

/// One test in the list: its name, first message, state and checks.
private struct AgentTestRow: View {
    let test: AgentTest
    let state: AgentTestState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: state.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(state.tone.text)
                .frame(width: 22, height: 22)
                .symbolEffect(.pulse, isActive: state == .queued)
            VStack(alignment: .leading, spacing: 3) {
                Text(test.name.isEmpty ? test.firstVisitorLine : test.name)
                    .font(ODFont.sans(15))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                if !test.name.isEmpty, !test.firstVisitorLine.isEmpty {
                    Text(test.firstVisitorLine).font(ODFont.footnote).foregroundStyle(Theme.fg3).lineLimit(1)
                }
                HStack(spacing: 6) {
                    AgentTestStatePill(state: state)
                    if test.lastResult?.newlyFailing == true, state != .queued {
                        TonePill(text: "Newly failing", tone: .red, height: 18)
                    }
                    Text(Format.plural(test.expectations.count, "check", "checks"))
                        .font(ODFont.sans(12))
                        .foregroundStyle(Theme.fg4)
                }
            }
            Spacer(minLength: 8)
            Chevron()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

@MainActor
enum AgentTestActions {
    static func delete(_ test: AgentTest, env: AppEnvironment, after: @escaping @MainActor () -> Void = {}) -> AccountConfirm {
        let name = test.name.isEmpty ? test.firstVisitorLine : test.name
        return AccountConfirm(title: "Delete this test?", message: "\"\(name)\" and its results will be removed.", confirmTitle: "Delete") {
            guard let api = env.agent.api else { return }
            do {
                try await api.delete("v1/ai/agent/tests/\(test.id)")
                env.agent.tests.value.removeAll { $0.id == test.id }
                Haptics.success()
                after()
            } catch {
                env.toasts.show("Couldn't delete the test. \(error.userMessage)", kind: .error)
            }
        }
    }
}

// MARK: - A test

extension TestsSettings {
    /// One test: the conversation, what it expects, and the latest answer with each check.
    struct Detail: View {
        let id: String

        @Environment(AppEnvironment.self) private var env
        @State private var editing: AgentTestDraft?
        @State private var confirm: AccountConfirm?
        @State private var starting = false

        var body: some View {
            let store = env.agent
            let test = store.tests.value.first { $0.id == id }
            let run = store.activeRun
            AccountPage(title: test.map { $0.name.isEmpty ? "Test" : $0.name } ?? "Test", spacing: 20) {
                if let test {
                    content(test, store, run: run)
                } else if !store.tests.loaded {
                    Panel { SkeletonRows(count: 3) }
                } else {
                    Panel { EmptyState(symbol: "checklist", title: "This test is gone", message: "It may have been deleted.") }
                }
            }
            .toolbar {
                if let test {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Run this test", systemImage: "play") { Task { await start(test, store) } }
                                .disabled(run != nil)
                            Button("Edit", systemImage: "pencil") { editing = AgentTestDraft(test: test) }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                confirm = AgentTestActions.delete(test, env: env) {
                                    if !env.router.accountPath.isEmpty { env.router.accountPath.removeLast() }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More")
                    }
                }
            }
            .sheet(item: $editing) { draft in AgentTestEditor(draft: draft).presentationCornerRadius(Theme.Radius.sheet) }
            .accountConfirm($confirm)
            .refreshable {
                await store.loadTests()
                await store.loadRuns()
            }
            .task {
                if store.config == nil { await store.loadConfig() }
                if !store.tests.loaded { await store.loadTests() }
                if !store.runs.loaded { await store.loadRuns() }
                if !store.servers.loaded { await store.loadServers() }
                if !store.procedures.loaded { await store.loadProcedures() }
            }
        }

        @ViewBuilder
        private func content(_ test: AgentTest, _ store: AgentStore, run: AgentTestRun?) -> some View {
            let state = AgentTestState.of(test, run: run)
            HStack(spacing: 8) {
                AgentTestStatePill(state: state)
                if test.lastResult?.newlyFailing == true, state != .queued { TonePill(text: "Newly failing", tone: .red) }
                Spacer()
                Button {
                    Task { await start(test, store) }
                } label: {
                    if starting { ProgressView().controlSize(.small) } else { Label("Run this test", systemImage: "play") }
                }
                .buttonStyle(ChipButtonStyle())
                .disabled(starting || run != nil)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Conversation")
                Panel(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(test.messages.enumerated()), id: \.offset) { _, line in
                            if line.role == "visitor" {
                                AssistantUserBubble(text: line.text)
                            } else {
                                HStack(alignment: .top, spacing: 8) {
                                    BotFace(look: store.defaultBot?.look ?? .ollie, image: store.defaultBot?.imageURL, size: 22)
                                    Text(line.text).font(ODFont.sans(14.5)).foregroundStyle(Theme.fg).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        if test.visitor.verified {
                            Label("Runs as a signed-in visitor.", systemImage: "checkmark.shield")
                                .font(ODFont.footnote)
                                .foregroundStyle(Theme.fg3)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Expects")
                Panel(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(test.expectations.enumerated()), id: \.offset) { _, expectation in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "smallcircle.filled.circle").font(.system(size: 9)).foregroundStyle(Theme.fg4)
                                Text(store.expectationText(expectation)).font(ODFont.sans(14.5)).foregroundStyle(Theme.fg).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Latest answer")
                if let result = test.lastResult, result.final {
                    latest(result, store)
                } else {
                    Panel(padding: 14) {
                        Text(state == .queued ? "Running now. The answer shows here when it's graded." : "This test hasn't run yet.")
                            .font(ODFont.footnote)
                            .foregroundStyle(Theme.fg3)
                    }
                }
            }
        }

        private func latest(_ result: AgentTestResult, _ store: AgentStore) -> some View {
            let answer = KBMarkdown.markdown(from: result.answerHTML) ?? HTMLText.plain(from: result.answerHTML)
            return Panel(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    if let error = result.error {
                        Notice(text: error, tone: .amber, symbol: "exclamationmark.circle")
                    }
                    if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("\(store.assistantName) wrote no answer.").font(ODFont.footnote).foregroundStyle(Theme.fg3)
                    } else {
                        MarkdownText(text: answer, size: 14.5)
                    }
                    if result.handoff {
                        Label("Handed off", systemImage: "person.2").font(ODFont.sans(12.5, weight: .medium)).foregroundStyle(Tone.amber.text)
                    }
                    if let action = result.action {
                        Label("Asked to confirm: \(action.title)", systemImage: "hand.raised").font(ODFont.sans(12.5)).foregroundStyle(Tone.amber.text)
                    }
                    ForEach(Array(result.procedures.enumerated()), id: \.offset) { _, procedure in
                        Label("Followed \(procedure.name)", systemImage: "list.number").font(ODFont.sans(12.5)).foregroundStyle(Theme.fg3)
                    }
                    if !result.sources.isEmpty {
                        AgentFlow(spacing: 6) {
                            ForEach(Array(result.sources.enumerated()), id: \.offset) { _, source in
                                HStack(spacing: 4) {
                                    Image(systemName: source.symbol).font(.system(size: 10))
                                    Text(source.title.isEmpty ? "Untitled" : source.title).font(ODFont.sans(12)).lineLimit(1)
                                }
                                .foregroundStyle(Theme.fg2)
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                                .background(Theme.sunken, in: Capsule())
                            }
                        }
                    }
                    if !result.checks.isEmpty {
                        Hairline()
                        AgentCheckList(checks: result.checks)
                    }
                    HStack(spacing: 6) {
                        if let finished = result.finishedAt { Text(Format.relLong(finished)) }
                        if result.draft { Text("· Against unsaved changes") }
                        if result.usd > 0 { Text("· \(AgentText.usd(result.usd))") }
                    }
                    .font(ODFont.sans(12))
                    .foregroundStyle(Theme.fg4)
                }
            }
        }

        private func start(_ test: AgentTest, _ store: AgentStore) async {
            starting = true
            defer { starting = false }
            do {
                try await store.startRun([test.id])
                Haptics.success()
            } catch {
                env.toasts.show("Couldn't start the run. \(error.userMessage)", kind: .error)
            }
        }
    }
}
