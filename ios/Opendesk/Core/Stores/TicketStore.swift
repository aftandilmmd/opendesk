import Foundation
import Observation

/// An attachment picked in the composer, uploaded before sending.
struct PendingAttachment: Identifiable, Hashable, Sendable {
    enum State: Hashable, Sendable {
        case uploading
        case ready(id: String)
        case failed(String)
    }

    var id = UUID()
    var filename: String
    var mimeType: String
    var size: Int
    var state: State = .uploading
    var preview: Data?

    var attachmentID: String? {
        if case let .ready(id) = state { return id }
        return nil
    }
}

/// One entry of the thread: a message or an activity line.
enum ThreadItem: Identifiable, Hashable {
    case message(Message)
    case activity(Activity)

    var id: String {
        switch self {
        case let .message(message): "m-" + message.id
        case let .activity(activity): "a-" + activity.id
        }
    }

    var date: Date {
        switch self {
        case let .message(message): message.createdAt
        case let .activity(activity): activity.createdAt
        }
    }
}

/// The open ticket: its record, thread, Ollie's suggestions, and the actions on it.
@MainActor
@Observable
final class TicketStore {
    let ticketID: String
    private(set) var ticket: Ticket?
    private(set) var messages: [Message] = []
    private(set) var activities: [Activity] = []
    private(set) var suggestedReply: SuggestedReply?
    private(set) var loading = true
    private(set) var error: String?
    private(set) var notFound = false

    // Ollie
    private(set) var summarizing = false
    private(set) var drafting = false
    private(set) var triaging = false
    private(set) var aiError: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var listener: UUID?
    @ObservationIgnored private weak var realtime: RealtimeService?
    @ObservationIgnored private var messagesReload: Task<Void, Never>?

    init(ticketID: String, api: APIClient, seed: Ticket? = nil) {
        self.ticketID = ticketID
        self.api = api
        ticket = seed
    }

    /// The ticket's uuid once loaded (a link may open it by number).
    var resolvedID: String { ticket?.id ?? ticketID }

    var thread: [ThreadItem] {
        let shownActivities = activities.filter { !Self.hiddenActivityTypes.contains($0.type) }
        return (messages.map(ThreadItem.message) + shownActivities.map(ThreadItem.activity)).sorted { $0.date < $1.date }
    }

    /// Bookkeeping lines the web keeps to its full timeline.
    static let hiddenActivityTypes: Set<String> = ["custom_updated", "field_changed", "created", "message_created"]

    var summary: AISummary? {
        guard let raw = ticket?.custom["ai_summary"], !raw.isNull else { return nil }
        return try? raw.decode(AISummary.self)
    }

    var suggestions: [AISuggestion] { AISuggestion.all(in: ticket?.custom ?? [:]) }

    // MARK: Loading

    func start(realtime: RealtimeService) {
        self.realtime = realtime
        listener = realtime.subscribe { [weak self] update in self?.handle(update) }
        Task { await load() }
    }

    func stop() {
        realtime?.unsubscribe(listener)
        listener = nil
    }

    func load() async {
        loading = ticket == nil
        do {
            async let ticket: Ticket = api.get("v1/tickets/\(ticketID)")
            async let messages: Page<Message> = api.get("v1/tickets/\(ticketID)/messages", query: [URLQueryItem(name: "limit", value: "100")])
            async let activities: Page<Activity>? = try? api.get("v1/tickets/\(ticketID)/activities", query: [URLQueryItem(name: "limit", value: "100")])
            async let suggestion: SuggestedReplyEnvelope? = try? api.get("v1/tickets/\(ticketID)/ai/suggested-reply")
            self.ticket = try await ticket
            var all = try await messages
            // Long threads: follow the cursor so the latest messages are always there.
            var cursor = all.nextCursor
            var guardCount = 0
            while let next = cursor, guardCount < 10 {
                let page: Page<Message> = try await api.get("v1/tickets/\(ticketID)/messages", query: [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "cursor", value: next)])
                all.data += page.data
                cursor = page.nextCursor
                guardCount += 1
            }
            self.messages = all.data.filter { !$0.isHidden }.sorted { $0.createdAt < $1.createdAt }
            self.activities = (await activities)?.data ?? []
            self.suggestedReply = (await suggestion)?.suggestedReply.flatMap { $0.isPending ? $0 : nil }
            error = nil
            notFound = false
        } catch let error as APIError where error.status == 404 {
            notFound = true
        } catch {
            if !error.isCancellation { self.error = error.userMessage }
        }
        loading = false
    }

    private func reloadMessagesSoon() {
        messagesReload?.cancel()
        messagesReload = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            guard let page: Page<Message> = try? await self.api.get("v1/tickets/\(self.ticketID)/messages", query: [URLQueryItem(name: "limit", value: "100")]) else { return }
            let fresh = Dictionary(page.data.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var merged = self.messages.map { fresh[$0.id] ?? $0 }
            let known = Set(merged.map(\.id))
            merged += page.data.filter { !known.contains($0.id) }
            self.messages = merged.filter { !$0.isHidden }.sorted { $0.createdAt < $1.createdAt }
        }
    }

    // MARK: Realtime

    func handle(_ update: RealtimeUpdate) {
        switch update {
        case .resync:
            Task { await load() }
        case let .envelope(envelope):
            apply(envelope)
        }
    }

    private func apply(_ envelope: Envelope) {
        switch envelope.type {
        case "ticket.updated", "ticket.created":
            guard let fresh = envelope.member("ticket", as: Ticket.self), fresh.id == resolvedID else { return }
            ticket = fresh
        case "ticket.deleted":
            if envelope.string("ticket_id") == resolvedID { notFound = true }
        case "message.created", "message.updated":
            guard let message = envelope.member("message", as: Message.self),
                  (envelope.string("ticket_id") ?? message.ticketID) == resolvedID
            else { return }
            merge(message)
            if envelope.type == "message.created", message.kind == .reply, let pending = suggestedReply, pending.messageID != message.id {
                // A newer message means Ollie's suggestion no longer answers the latest one.
                suggestedReply = nil
            }
        case "activity.created":
            guard let activity = envelope.member("activity", as: Activity.self),
                  (envelope.string("ticket_id") ?? activity.ticketID) == resolvedID,
                  !activities.contains(where: { $0.id == activity.id })
            else { return }
            activities.append(activity)
        case "ai_suggested_reply.created", "ai_suggested_reply.updated":
            guard let suggestion = envelope.member("suggested_reply", as: SuggestedReply.self),
                  (envelope.string("ticket_id") ?? suggestion.ticketID) == resolvedID
            else { return }
            if suggestion.isPending {
                suggestedReply = suggestion
            } else if suggestedReply?.id == suggestion.id {
                suggestedReply = nil
            }
        default:
            break
        }
    }

    /// Merge by id. Chat replies arrive customer-safe (no recipients, no attachments), so a
    /// stored copy keeps its members, and a new partial one triggers a reload of the thread.
    private func merge(_ message: Message) {
        // A deleted message (or a note sent as a reply) leaves the thread.
        if message.isHidden {
            messages.removeAll { $0.id == message.id }
            return
        }
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = messages[index].merged(with: message)
            return
        }
        // Our own send can arrive before its POST answers: it takes the optimistic copy's place.
        if message.author.type == "user",
           let temp = messages.firstIndex(where: { $0.isLocal && $0.kind == message.kind && $0.author.user?.id == message.author.user?.id && $0.deliveryStatus != "failed" }) {
            messages[temp] = message
        } else {
            messages.append(message)
            messages.sort { $0.createdAt < $1.createdAt }
        }
        if message.isPartial { reloadMessagesSoon() }
    }

    // MARK: Actions

    func patch(_ change: TicketPatch, members: [Member], me: UserRef?) async throws {
        guard let current = ticket else { return }
        ticket = change.applied(to: current, me: me, members: members)
        do {
            ticket = try await api.patch("v1/tickets/\(ticketID)", body: change)
        } catch {
            ticket = current
            throw error
        }
    }

    func upload(data: Data, filename: String, mimeType: String) async throws -> Attachment {
        try await api.upload("v1/attachments", data: data, filename: filename, mimeType: mimeType)
    }

    /// Sends a reply or note from plain text; shows it at once and swaps in the server's copy.
    func send(kind: MessageKind, text: String, attachmentIDs: [String], status: TicketStatus?, author: UserRef) async throws {
        struct Body: Encodable, Sendable {
            let kind: MessageKind
            let body_html: String
            let attachment_ids: [String]?
            let status: TicketStatus?
        }
        let html = HTMLText.html(fromPlain: text)
        let local = Message(localID: "tmp-" + UUID().uuidString, ticketID: ticketID, kind: kind, html: html, text: text, author: author)
        messages.append(local)
        let body = Body(kind: kind, body_html: html, attachment_ids: attachmentIDs.isEmpty ? nil : attachmentIDs, status: status)
        do {
            let sent: Message = try await api.post("v1/tickets/\(ticketID)/messages", body: body, idempotencyKey: local.id)
            if let index = messages.firstIndex(where: { $0.id == local.id }) {
                if messages.contains(where: { $0.id == sent.id }) {
                    messages.remove(at: index)
                } else {
                    messages[index] = sent
                }
            }
            if let status, var current = ticket {
                current.status = status
                ticket = current
            }
        } catch {
            messages.removeAll { $0.id == local.id }
            throw error
        }
    }

    // MARK: Ollie

    func summarize() async {
        summarizing = true
        aiError = nil
        defer { summarizing = false }
        do {
            let summary: AISummary = try await api.post("v1/tickets/\(ticketID)/ai/summary")
            if var current = ticket, let value = try? JSONValue.from(summary) {
                current.custom["ai_summary"] = value
                ticket = current
            }
        } catch {
            aiError = error.userMessage
        }
    }

    func draft(instructions: String?) async -> String? {
        struct Body: Encodable, Sendable { let instructions: String? }
        drafting = true
        aiError = nil
        defer { drafting = false }
        do {
            let draft: AIDraft = try await api.post("v1/tickets/\(ticketID)/ai/draft", body: Body(instructions: instructions?.isEmpty == true ? nil : instructions))
            return draft.bodyText.isEmpty ? HTMLText.plain(from: draft.bodyHTML) : draft.bodyText
        } catch {
            aiError = error.userMessage
            return nil
        }
    }

    func triage(apply: Bool) async {
        struct Body: Encodable, Sendable { let apply: Bool }
        triaging = true
        aiError = nil
        defer { triaging = false }
        do {
            let _: JSONValue = try await api.post("v1/tickets/\(ticketID)/ai/triage", body: Body(apply: apply))
            if let fresh: Ticket = try? await api.get("v1/tickets/\(ticketID)") { ticket = fresh }
        } catch {
            aiError = error.userMessage
        }
    }

    /// Accepting a suggestion is setting the field; the server then drops the suggestion.
    func accept(_ suggestion: AISuggestion, members: [Member], me: UserRef?) async throws {
        var change = TicketPatch()
        switch suggestion.field {
        case .priority:
            guard let value = suggestion.value.string.flatMap(Priority.init(rawValue:)) else { return }
            change.priority = value
        case .severity:
            guard let value = suggestion.value.string.flatMap(Severity.init(rawValue:)) else { return }
            change.severity = .set(value)
        case .team:
            guard let value = suggestion.value.string else { return }
            change.teamID = .set(value)
        case .labels:
            let names = suggestion.value.array?.compactMap(\.string) ?? suggestion.value.string.map { [$0] } ?? []
            guard !names.isEmpty else { return }
            change.addTags = names
        case .spam:
            change.spam = true
        }
        try await patch(change, members: members, me: me)
    }

    func dismiss(_ suggestion: AISuggestion) async throws {
        if var current = ticket, var object = current.custom["ai_suggestions"]?.object {
            object[suggestion.field.rawValue] = nil
            current.custom["ai_suggestions"] = .object(object)
            ticket = current
        }
        try await api.delete("v1/tickets/\(ticketID)/ai/suggestions/\(suggestion.field.rawValue)")
    }

    func sendSuggestedReply() async throws {
        guard let suggestion = suggestedReply else { return }
        let sent: Message = try await api.post("v1/tickets/\(ticketID)/ai/suggested-reply/\(suggestion.id)/send")
        suggestedReply = nil
        merge(sent)
    }

    func discardSuggestedReply() async throws {
        guard let suggestion = suggestedReply else { return }
        suggestedReply = nil
        try await api.delete("v1/tickets/\(ticketID)/ai/suggested-reply/\(suggestion.id)")
    }

    /// The suggestion's text for the composer; the teammate sends it as their own reply.
    func takeSuggestedReply() -> String? {
        guard let suggestion = suggestedReply else { return nil }
        return HTMLText.plain(from: suggestion.bodyHTML)
    }
}
