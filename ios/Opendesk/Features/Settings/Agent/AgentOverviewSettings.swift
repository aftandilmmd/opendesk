import Charts
import SwiftUI

/// Settings > AI agent > Overview: how the widget agent did over a range (GET /v1/ai/agent/report),
/// led by the setup checklist until it is complete, with the review queue, a by-day chart,
/// the tools it called and the questions it couldn't answer.
struct AgentOverviewSettings: View {
    enum Range: Int, CaseIterable, Hashable {
        case week = 7, month = 30, quarter = 90

        var title: String { "\(rawValue) days" }
    }

    @Environment(AppEnvironment.self) private var env
    @State private var range: Range = .month
    @State private var report: AgentReport?
    @State private var error: String?
    @State private var loading = false
    @State private var improving: AgentImproveDraft?

    /// The overview lists nothing of its own to open; a link to one lands on the overview.
    struct Detail: View {
        let id: String

        var body: some View { AgentOverviewSettings() }
    }

    var body: some View {
        let store = env.agent
        AccountPage(title: "AI agent", spacing: 22) {
            AgentIntro(text: "How the agent did in the chat widget: what it resolved, when it handed off, and what it couldn't answer.")
            AgentSetupPanel()
            if store.config != nil, !store.behaviour.widgetAnswers {
                AgentOffNotice()
            }
            AccountSegmented(options: Range.allCases, selection: $range, label: \.title)
            content(store)
        }
        .refreshable { await reload(store) }
        .task(id: range) { await reload(store) }
        .task {
            if store.config == nil { await store.loadConfig() }
        }
        .sheet(item: $improving) { draft in
            AgentImproveSheet(draft: draft).presentationCornerRadius(Theme.Radius.sheet)
        }
    }

    @ViewBuilder
    private func content(_ store: AgentStore) -> some View {
        if report == nil, error == nil {
            Panel { SkeletonRows(count: 4) }
        } else if let report {
            if report.conversations == 0 && report.replies == 0 {
                Panel {
                    EmptyState(title: "No agent conversations in this range", message: "When the agent answers chat widget visitors, its conversations, handoffs and ratings show up here.", actionTitle: "Try it in the playground", action: { env.router.accountPath.append(.setting(.playground)) }) {
                        OllieMark(size: 30)
                    }
                    Button("Set up behaviour") { env.router.accountPath.append(.setting(.behaviour)) }
                        .buttonStyle(ChipButtonStyle())
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 20)
                }
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    tiles(report)
                    AgentReviewQueue(improving: $improving)
                    AgentTrend(report: report)
                    tools(report)
                    gaps(report)
                }
                .opacity(loading ? 0.6 : 1)
                .motion(Motion.fade, value: loading)
            }
        } else if let error {
            Panel { ErrorState(title: "Couldn't load the report", message: error) { Task { await reload(store) } } }
        }
    }

    private func tiles(_ d: AgentReport) -> some View {
        let rate: (Int) -> String = { n in d.conversations > 0 ? AgentText.percent(n, of: d.conversations) : "–" }
        let rated = d.ratingsUp + d.ratingsDown
        return AgentStatGrid {
            AgentStat(label: "Conversations", value: d.conversations.formatted(), hint: Format.plural(d.replies, "reply", "replies"), tone: .violet)
            AgentStat(label: "Resolved", value: rate(d.resolved), hint: "\(d.resolved.formatted()) without a person", tone: .green)
            AgentStat(label: "Handoffs", value: d.handoffs.formatted(), hint: "\(rate(d.handoffs)) of conversations", tone: .amber)
            AgentStat(label: "Rated helpful", value: rated > 0 ? AgentText.percent(d.ratingsUp, of: rated) : "–", hint: "\(d.ratingsUp) helpful · \(d.ratingsDown) not helpful")
            AgentStat(label: "Spent", value: AgentText.usd(d.usd), hint: "AI usage of the agent's replies")
        }
    }

    private func tools(_ d: AgentReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                AgentGroupTitle(title: "Tools", hint: "Calls the agent made to your connected tools.")
                Spacer()
                Button("Manage tools") { env.router.accountPath.append(.setting(.tools)) }
                    .buttonStyle(ChipButtonStyle())
            }
            Panel {
                if d.tools.isEmpty {
                    EmptyState(symbol: "wrench.and.screwdriver", title: "No tool calls", message: "Connect an MCP server so the agent can look up orders, accounts and more.")
                } else {
                    HStack {
                        Text("Tool").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Calls").frame(width: 56, alignment: .trailing)
                        Text("Errors").frame(width: 60, alignment: .trailing)
                    }
                    .font(ODFont.sans(11.5, weight: .medium))
                    .foregroundStyle(Theme.fg3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    ForEach(d.tools) { tool in
                        Hairline()
                        HStack {
                            Text(tool.tool.replacingOccurrences(of: "__", with: " · "))
                                .font(ODFont.mono(12.5))
                                .foregroundStyle(Theme.fg)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(tool.calls.formatted()).frame(width: 56, alignment: .trailing)
                            Text(tool.errors.formatted())
                                .foregroundStyle(tool.calls > 0 && Double(tool.errors) / Double(tool.calls) > 0.1 ? Tone.red.text : Theme.fg2)
                                .frame(width: 60, alignment: .trailing)
                                .accessibilityLabel("\(AgentText.percent(tool.errors, of: tool.calls)) of calls failed")
                        }
                        .font(ODFont.sans(13.5))
                        .monospacedDigit()
                        .foregroundStyle(Theme.fg2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private func gaps(_ d: AgentReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AgentGroupTitle(title: "Knowledge gaps", hint: "Questions the agent couldn't answer from your knowledge.")
            Panel {
                if d.gaps.isEmpty {
                    EmptyState(symbol: "book", title: "No gaps in this range", message: "Questions the agent couldn't answer will appear here, ready to become articles.")
                } else {
                    ForEach(Array(d.gaps.enumerated()), id: \.offset) { index, gap in
                        if index > 0 { Hairline(inset: 14) }
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(gap.question).font(ODFont.sans(14.5)).foregroundStyle(Theme.fg).fixedSize(horizontal: false, vertical: true)
                                Text(gap.count == 1 ? "Asked once" : "Asked \(gap.count) times").font(ODFont.footnote).foregroundStyle(Theme.fg3)
                            }
                            Spacer(minLength: 8)
                            Button {
                                Haptics.tap()
                                env.router.show(.kb, [.article("new")])
                            } label: {
                                Label("Write an article", systemImage: "doc.badge.plus").labelStyle(.iconOnly)
                            }
                            .buttonStyle(ChipButtonStyle())
                            .accessibilityLabel("Write an article")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                    }
                }
            }
        }
    }

    private func reload(_ store: AgentStore) async {
        guard let api = store.api else { return }
        loading = true
        defer { loading = false }
        let calendar = Calendar(identifier: .gregorian)
        let to = AppClock.now
        let from = calendar.date(byAdding: .day, value: -(range.rawValue - 1), to: to) ?? to
        let format = Date.ISO8601FormatStyle().year().month().day()
        do {
            report = try await api.get("v1/ai/agent/report", query: [URLQueryItem(name: "from", value: from.formatted(format)), URLQueryItem(name: "to", value: to.formatted(format))])
            error = nil
        } catch {
            guard !error.isCancellation else { return }
            if report == nil { self.error = error.userMessage } else { env.toasts.error(error) }
        }
    }
}

/// "Get your agent ready": the setup checklist, until every required step is done.
struct AgentSetupPanel: View {
    @Environment(AppEnvironment.self) private var env
    @State private var open = true

    private static let copy: [String: (title: String, why: String, action: String)] = [
        "ai_on": ("Turn on AI", "Ollie needs AI switched on for the workspace before it can answer anyone.", "Open AI settings"),
        "identity": ("Name your agent and tell it how to help", "A name, a picture and instructions make answers sound like your team.", "Set up identity"),
        "knowledge": ("Give it something to know", "Ollie answers only from published help articles and ready knowledge sources.", "Add knowledge"),
        "tools": ("Connect tools", "Let Ollie look up orders or accounts in your own systems.", "Connect a tool"),
        "playground": ("Test it in the playground", "Ask a few real questions and check the answers before visitors do.", "Open the playground"),
        "widget": ("Install the chat widget", "Visitors reach Ollie through the widget on your site.", "Install the widget"),
        "answers_on": ("Let Ollie answer chats", "Turn on answers so Ollie replies to visitors and hands off when it should.", "Turn on answers"),
        "email_answers": ("Answer email too", "Turn on Ollie for a mailbox to draft or send email replies.", "Choose a mailbox"),
    ]

    var body: some View {
        let store = env.agent
        Group {
            if let setup = store.setup.value, !setup.complete, !setup.steps.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        Haptics.tap()
                        withAnimation(Motion.snappy) { open.toggle() }
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().stroke(Tone.violet.line, lineWidth: 3)
                                Circle()
                                    .trim(from: 0, to: setup.total > 0 ? CGFloat(setup.done) / CGFloat(setup.total) : 0)
                                    .stroke(Tone.violet.solid, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Get your agent ready").font(ODFont.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
                                Text("\(setup.done) of \(setup.total) done").font(ODFont.footnote).foregroundStyle(Theme.fg3)
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.fg3)
                                .rotationEffect(.degrees(open ? 180 : 0))
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(setup.done) of \(setup.total) required steps done")
                    .accessibilityHint(open ? "Hide steps" : "Show steps")
                    if open {
                        ForEach(setup.steps) { step in
                            Hairline(inset: 14)
                            row(step, blocked: setup.blocked(step), next: setup.next?.id == step.id)
                        }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                .transition(.opacity)
            }
        }
        .task { await store.loadSetup() }
    }

    private func row(_ step: AgentSetup.Step, blocked: Bool, next: Bool) -> some View {
        let copy = Self.copy[step.id]
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17))
                .foregroundStyle(step.done ? Tone.green.solid : next ? Tone.violet.solid : Theme.fg4)
                .accessibilityLabel(step.done ? "Done" : "Not done yet")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(copy?.title ?? step.title)
                        .font(ODFont.sans(14.5, weight: .medium))
                        .foregroundStyle(step.done ? Theme.fg3 : Theme.fg)
                        .strikethrough(step.done, color: Theme.fg4)
                    if step.optional { TonePill(text: "Optional", tone: .gray, height: 18) }
                }
                if !step.done {
                    Text(copy?.why ?? step.description).font(ODFont.footnote).foregroundStyle(Theme.fg3).fixedSize(horizontal: false, vertical: true)
                    if blocked {
                        Text("Turn on AI first").font(ODFont.sans(12, weight: .medium)).foregroundStyle(Tone.amber.text).padding(.top, 2)
                    } else if !step.href.isEmpty {
                        Button(copy?.action ?? "Open") {
                            Haptics.tap()
                            env.router.openAgentHref(step.href)
                        }
                        .buttonStyle(ChipButtonStyle(tone: next ? .violet : nil, filled: next))
                        .padding(.top, 4)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// "Needs review": answers rated not helpful and handoffs, each a tap from the conversation
/// or a better answer. Dismissing is optimistic.
struct AgentReviewQueue: View {
    @Binding var improving: AgentImproveDraft?

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let store = env.agent
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                AgentGroupTitle(title: "Needs review", hint: "Answers visitors rated not helpful, and conversations Ollie handed off, in the last 30 days.")
                Spacer()
                if !store.review.value.isEmpty {
                    Text("\(store.review.value.count)").font(ODFont.mono(11)).foregroundStyle(Theme.fg3)
                }
            }
            Panel {
                if !store.review.loaded {
                    SkeletonRows(count: 2)
                } else if store.review.value.isEmpty {
                    EmptyState(title: "Nothing to review", message: "Answers rated not helpful and handoffs show up here, ready to improve.") {
                        OllieMark(size: 26, state: .done)
                    }
                } else {
                    ForEach(Array(store.review.value.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Hairline(inset: 14) }
                        row(item, store)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
            }
            .motion(Motion.snappy, value: store.review.value.map(\.id))
        }
        .task { await store.loadReview() }
    }

    private func row(_ item: AgentReviewItem, _ store: AgentStore) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TonePill(text: item.ratedDown ? "Not helpful" : "Handed off", tone: item.ratedDown ? .red : .amber) {
                    Image(systemName: item.ratedDown ? "hand.thumbsdown" : "hand.raised").font(.system(size: 10, weight: .semibold))
                }
                Text("#\(item.ticketNumber)").font(ODFont.mono(11.5)).foregroundStyle(Theme.fg4)
                if !item.contactName.isEmpty {
                    Text("· \(item.contactName)").font(ODFont.sans(12)).foregroundStyle(Theme.fg4).lineLimit(1)
                }
                Text("· \(Format.relShort(item.createdAt))").font(ODFont.sans(12)).foregroundStyle(Theme.fg4)
                Spacer(minLength: 0)
            }
            Text(item.question.isEmpty ? "No visitor message" : item.question)
                .font(ODFont.sans(14.5, weight: .medium))
                .foregroundStyle(Theme.fg)
                .lineLimit(2)
            Text("Ollie: \(item.answer)")
                .font(ODFont.footnote)
                .foregroundStyle(Theme.fg3)
                .lineLimit(2)
            HStack(spacing: 8) {
                Button {
                    env.router.show(.tickets, [.ticket(TicketRoute(id: item.ticketID))])
                } label: {
                    Label("Open", systemImage: "arrow.up.right")
                }
                .buttonStyle(ChipButtonStyle())
                Button {
                    improving = AgentImproveDraft(question: item.question, answer: item.answer, messageID: item.id, ratedDown: item.ratedDown)
                } label: {
                    Label("Improve answer", systemImage: "wand.and.stars")
                }
                .buttonStyle(ChipButtonStyle(tone: .violet))
                Spacer()
                Button {
                    Task { await dismissItem(item, store) }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.fg3).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func dismissItem(_ item: AgentReviewItem, _ store: AgentStore) async {
        guard let api = store.api else { return }
        let before = store.review.value
        Haptics.tap()
        store.review.value.removeAll { $0.id == item.id }
        do {
            let _: EmptyBody = try await api.post("v1/ai/agent/review/\(item.id)/dismiss")
        } catch {
            store.review.value = before
            env.toasts.error(error)
        }
    }
}

/// "By day": conversations the agent took part in and how they ended, as a chart or a table.
struct AgentTrend: View {
    let report: AgentReport

    @State private var table = false

    private struct Point: Identifiable {
        let id = UUID()
        let day: Date
        let series: String
        let value: Int
    }

    private var points: [Point] {
        let format = Date.ISO8601FormatStyle().year().month().day()
        return report.byDay.flatMap { day -> [Point] in
            guard let date = try? format.parse(day.date) else { return [] }
            return [
                Point(day: date, series: "Conversations", value: day.conversations),
                Point(day: date, series: "Resolved", value: day.resolved),
                Point(day: date, series: "Handoffs", value: day.handoffs),
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                AgentGroupTitle(title: "By day", hint: "Conversations the agent took part in, and how they ended.")
                Spacer()
                Button(table ? "Chart" : "Table") {
                    Haptics.selection()
                    withAnimation(Motion.snappy) { table.toggle() }
                }
                .buttonStyle(ChipButtonStyle())
            }
            Panel(padding: table ? 0 : 14) {
                if table {
                    tableView
                } else {
                    Chart(points) { point in
                        LineMark(x: .value("Day", point.day, unit: .day), y: .value("Count", point.value))
                            .foregroundStyle(by: .value("Series", point.series))
                            .interpolationMethod(.monotone)
                    }
                    .chartForegroundStyleScale(["Conversations": Tone.violet.solid, "Resolved": Tone.teal.solid, "Handoffs": Tone.amber.solid])
                    .chartLegend(position: .bottom, alignment: .leading)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(Theme.lineSoft)
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine().foregroundStyle(Theme.lineSoft)
                            AxisValueLabel()
                        }
                    }
                    .frame(height: 200)
                    .accessibilityLabel("Agent conversations over \(report.byDay.count) days")
                }
            }
        }
    }

    private var tableView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Day").frame(maxWidth: .infinity, alignment: .leading)
                Text("Chats").frame(width: 50, alignment: .trailing)
                Text("Resolved").frame(width: 70, alignment: .trailing)
                Text("Handoffs").frame(width: 70, alignment: .trailing)
            }
            .font(ODFont.sans(11.5, weight: .medium))
            .foregroundStyle(Theme.fg3)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            ForEach(report.byDay.reversed()) { day in
                Hairline()
                HStack {
                    Text(dayLabel(day.date)).frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(day.conversations)").frame(width: 50, alignment: .trailing)
                    Text("\(day.resolved)").frame(width: 70, alignment: .trailing)
                    Text("\(day.handoffs)").frame(width: 70, alignment: .trailing)
                }
                .font(ODFont.sans(13.5))
                .monospacedDigit()
                .foregroundStyle(Theme.fg2)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
        }
    }

    private func dayLabel(_ raw: String) -> String {
        guard let date = try? Date.ISO8601FormatStyle().year().month().day().parse(raw) else { return raw }
        return Format.shortDate(date)
    }
}
