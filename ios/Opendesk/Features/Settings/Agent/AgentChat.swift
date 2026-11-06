import SwiftUI

// A chat with the agent as a visitor sees it (POST /v1/ai/agent/playground, streamed): the
// Playground page and a bot's Test tab. Nothing here reaches a customer or creates a ticket.

@MainActor
@Observable
final class AgentChat {
    struct Step: Identifiable, Hashable {
        var id: String { name }
        var name: String
        var status: String
        var summary: String
    }

    struct Turn: Identifiable {
        let id = UUID()
        var role: String
        var text: String
        var steps: [Step] = []
        var sources: [AgentSource] = []
        var procedures: [AgentProcedureRef] = []
        var action: AgentAction?
        var handoff = false
        var usd: Double = 0
        var live = false
        var stopped = false
        var error: String?
    }

    private(set) var turns: [Turn] = []
    private(set) var spent: Double = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    var busy: Bool { turns.last?.live ?? false }

    /// The conversation so far, as the API takes it.
    var history: [AgentLine] {
        turns.filter { !$0.text.isEmpty && $0.error == nil }.map { AgentLine(role: $0.role, text: $0.text) }
    }

    func reset() {
        task?.cancel()
        task = nil
        turns = []
        spent = 0
    }

    func stop() {
        task?.cancel()
        task = nil
        if let index = turns.indices.last, turns[index].live {
            turns[index].live = false
            turns[index].stopped = true
        }
    }

    func send(_ text: String, api: APIClient?, settings: [String: JSONValue]?, visitor: [String: JSONValue]?) {
        guard let api, !busy else { return }
        let question = AgentText.trimmed(text)
        guard !question.isEmpty else { return }
        turns.append(Turn(role: "visitor", text: question))
        var body: [String: JSONValue] = ["messages": .array(history.map(\.json))]
        if let settings, !settings.isEmpty { body["settings"] = .object(settings) }
        if let visitor, !visitor.isEmpty { body["visitor"] = .object(visitor) }
        turns.append(Turn(role: "agent", text: "", live: true))
        let index = turns.count - 1
        let payload = JSONValue.object(body)
        task = Task { [weak self] in
            do {
                let stream = try await api.stream("v1/ai/agent/playground", body: payload)
                for try await event in stream {
                    guard let self, !Task.isCancelled else { return }
                    self.apply(event, at: index)
                }
                self?.finish(at: index)
            } catch {
                guard let self, !error.isCancellation else { return }
                self.fail(error.userMessage, at: index)
            }
        }
    }

    private func apply(_ event: SSEEvent, at index: Int) {
        guard turns.indices.contains(index) else { return }
        let data = event.json()
        switch event.event {
        case "delta":
            turns[index].text += data?["text"]?.string ?? ""
        case "tool":
            let step = Step(name: data?["name"]?.string ?? "", status: data?["status"]?.string ?? "running", summary: data?["summary"]?.string ?? "")
            if let at = turns[index].steps.firstIndex(where: { $0.name == step.name && $0.status == "running" }) {
                turns[index].steps[at] = step
            } else {
                turns[index].steps.append(step)
            }
        case "sources":
            turns[index].sources = (data?["sources"]).flatMap { try? $0.decode([AgentSource].self) } ?? []
        case "done", "result":
            guard let data else { return }
            if let html = data["text_html"]?.string, !html.isEmpty {
                turns[index].text = KBMarkdown.markdown(from: html) ?? HTMLText.plain(from: html)
            }
            if let sources = data["sources"].flatMap({ try? $0.decode([AgentSource].self) }), !sources.isEmpty { turns[index].sources = sources }
            turns[index].procedures = data["procedures"].flatMap { try? $0.decode([AgentProcedureRef].self) } ?? []
            turns[index].action = data["action"].flatMap { $0.isNull ? nil : try? $0.decode(AgentAction.self) }
            turns[index].handoff = data["handoff"]?.bool ?? false
            let usd = data["usd"]?.double ?? 0
            turns[index].usd = usd
            spent += usd
            finish(at: index)
        case "error":
            fail(data?["detail"]?.string ?? data?["message"]?.string ?? "The agent couldn't reply", at: index)
        default:
            break
        }
    }

    private func finish(at index: Int) {
        guard turns.indices.contains(index), turns[index].live else { return }
        turns[index].live = false
        turns[index].steps = turns[index].steps.map { var s = $0; if s.status == "running" { s.status = "done" }; return s }
        task = nil
    }

    private func fail(_ message: String, at index: Int) {
        guard turns.indices.contains(index) else { return }
        turns[index].live = false
        turns[index].error = message
        task = nil
        Haptics.error()
    }

    /// The visitor's message an agent turn answered.
    func question(before turn: Turn) -> String {
        guard let at = turns.firstIndex(where: { $0.id == turn.id }) else { return "" }
        return turns[..<at].last { $0.role == "visitor" }?.text ?? ""
    }

    /// The conversation up to and including the visitor message `turn` answered.
    func conversation(upTo turn: Turn) -> [AgentLine] {
        guard let at = turns.firstIndex(where: { $0.id == turn.id }) else { return history }
        return AgentTests.conversation(turns[..<at].filter { !$0.text.isEmpty && $0.error == nil }.map { AgentLine(role: $0.role, text: $0.text) })
    }
}

/// The thread and its composer, pinned under it so the next message is always in reach.
struct AgentChatView: View {
    let chat: AgentChat
    let name: String
    var look: BotLook = .ollie
    var image: String?
    var suggestions: [String] = ["How do I reset my password?", "Where is my order?", "Can I get a refund?"]
    var emptyMessage = "Ask what your customers ask. Read-only tools run for real; tools that need confirmation stop at the action card."
    let send: (String) -> Void
    var saveTest: ((AgentChat.Turn) -> Void)?
    var improve: ((AgentChat.Turn) -> Void)?
    /// Above the thread (notes, a draft banner).
    var header: AnyView?

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let header { header }
                    if chat.turns.isEmpty {
                        empty
                    }
                    ForEach(chat.turns) { turn in
                        if turn.role == "visitor" {
                            AssistantUserBubble(text: turn.text)
                        } else {
                            AgentTurnView(turn: turn, name: name, look: look, image: image, saveTest: saveTest, improve: improve)
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: chat.turns.last?.text) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: chat.turns.count) { _, _ in
                withAnimation(Motion.snappy) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        // The composer takes the bottom edge, as in a ticket or a mail thread.
        .tabBarHidden()
    }

    private var empty: some View {
        VStack(spacing: 14) {
            BotFace(look: look, image: image, size: 64, alive: true)
            VStack(spacing: 6) {
                Text("Say hello to \(name)").font(ODFont.sans(17, weight: .semibold)).foregroundStyle(Theme.fg)
                Text(emptyMessage)
                    .font(ODFont.callout)
                    .foregroundStyle(Theme.fg3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        Haptics.tap()
                        send(suggestion)
                    } label: {
                        Text(suggestion).font(ODFont.sans(14)).foregroundStyle(Theme.fg).padding(.horizontal, 14).frame(height: 36)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(TapScaleStyle())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(text: $text, axis: .vertical) { Text("Write as a visitor").foregroundStyle(Theme.fg4) }
                .font(ODFont.sans(15.5))
                .lineLimit(1 ... 6)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(submit)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(focused ? Theme.lineStrong : Theme.line, lineWidth: 1))
            Button {
                if chat.busy { chat.stop() } else { submit() }
            } label: {
                Image(systemName: chat.busy ? "stop.fill" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.inverseFg)
                    .frame(width: 40, height: 40)
                    .background(Theme.inverse, in: Circle())
                    .opacity(chat.busy || !AgentText.trimmed(text).isEmpty ? 1 : 0.35)
            }
            .buttonStyle(TapScaleStyle(scale: 0.9))
            .disabled(!chat.busy && AgentText.trimmed(text).isEmpty)
            .accessibilityLabel(chat.busy ? "Stop" : "Send")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.chrome.opacity(0.94))
    }

    private func submit() {
        let value = AgentText.trimmed(text)
        guard !value.isEmpty, !chat.busy else { return }
        Haptics.tap()
        text = ""
        send(value)
    }
}

/// One reply of the agent: its tool steps, the answer, what it cited, and what would happen next.
struct AgentTurnView: View {
    let turn: AgentChat.Turn
    let name: String
    let look: BotLook
    var image: String?
    var saveTest: ((AgentChat.Turn) -> Void)?
    var improve: ((AgentChat.Turn) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                BotFace(look: look, image: image, size: 22, mood: turn.live ? .thinking : .idle)
                Text(name).font(ODFont.sans(13.5, weight: .semibold)).foregroundStyle(Theme.fg)
                AITag()
                Spacer()
                if turn.usd > 0 {
                    Text(AgentText.usd(turn.usd)).font(ODFont.mono(11)).foregroundStyle(Theme.fg4)
                }
            }
            ForEach(turn.steps) { step in
                HStack(spacing: 8) {
                    Group {
                        if step.status == "running" {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: step.status == "error" ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(step.status == "error" ? Tone.red.solid : Tone.green.solid)
                        }
                    }
                    .font(.system(size: 12))
                    .frame(width: 14)
                    Text(step.summary.isEmpty ? step.name.replacingOccurrences(of: "__", with: " · ") : step.summary)
                        .font(ODFont.sans(12.5))
                        .foregroundStyle(Theme.fg3)
                        .lineLimit(2)
                }
            }
            if let error = turn.error {
                Notice(text: "The agent couldn't reply. \(error)", tone: .red, symbol: "exclamationmark.circle")
            } else if turn.text.isEmpty && turn.live {
                AssistantThinking(name: name)
            } else if !turn.text.isEmpty {
                AssistantAnswerText(text: turn.text, live: turn.live)
            }
            if turn.stopped {
                Text("Stopped").font(ODFont.footnote).foregroundStyle(Theme.fg4)
            }
            if let action = turn.action {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised").font(.system(size: 11, weight: .semibold))
                        Text("Would ask to confirm").font(ODFont.sans(11.5, weight: .medium))
                    }
                    .foregroundStyle(Tone.amber.text)
                    Text(action.title).font(ODFont.sans(14, weight: .semibold)).foregroundStyle(Theme.fg)
                    if !action.summary.isEmpty { Text(action.summary).font(ODFont.footnote).foregroundStyle(Theme.fg2) }
                    Text("Not run in the playground").font(ODFont.sans(11.5)).foregroundStyle(Theme.fg4)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tone.amber.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Tone.amber.line, lineWidth: 1))
            }
            if turn.handoff {
                Label("Handed off to your team here", systemImage: "person.2")
                    .font(ODFont.sans(12.5, weight: .medium))
                    .foregroundStyle(Tone.amber.text)
            }
            if !turn.procedures.isEmpty {
                Label("Followed \(turn.procedures.map(\.name).joined(separator: ", "))", systemImage: "list.number")
                    .font(ODFont.sans(12.5))
                    .foregroundStyle(Theme.fg3)
            }
            if !turn.sources.isEmpty {
                AgentFlow(spacing: 6) {
                    ForEach(Array(turn.sources.enumerated()), id: \.offset) { _, source in
                        sourceChip(source)
                    }
                }
            }
            if !turn.live, turn.error == nil, !turn.text.isEmpty, saveTest != nil || improve != nil {
                HStack(spacing: 8) {
                    if let saveTest {
                        Button { saveTest(turn) } label: { Label("Save as test", systemImage: "checklist") }
                            .buttonStyle(ChipButtonStyle())
                    }
                    if let improve {
                        Button { improve(turn) } label: { Label("Improve answer", systemImage: "wand.and.stars") }
                            .buttonStyle(ChipButtonStyle(tone: .violet))
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func sourceChip(_ source: AgentSource) -> some View {
        let label = HStack(spacing: 4) {
            Image(systemName: source.symbol).font(.system(size: 10))
            Text(source.title.isEmpty ? "Untitled" : source.title).font(ODFont.sans(12)).lineLimit(1)
        }
        .foregroundStyle(Theme.fg2)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Theme.sunken, in: Capsule())
        if let url = source.url.flatMap(URL.init(string:)), url.scheme == "https" || url.scheme == "http" {
            Link(destination: url) { label }
        } else {
            label
        }
    }
}
