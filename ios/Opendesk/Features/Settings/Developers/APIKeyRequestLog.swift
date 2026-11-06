import SwiftUI

// An API key's request log (`GET /v1/api-keys/{id}/requests`): what the key asked while
// "Record requests" was on, filtered by answer, date and ticket, and each request with what it
// sent and the answer.

enum APIKeyRequestStatus: String, CaseIterable, Hashable {
    case all, errors
    case ok = "2xx"
    case client = "4xx"
    case server = "5xx"

    var title: String {
        switch self {
        case .all: "All"
        case .errors: "Errors"
        default: rawValue
        }
    }
}

/// The log under a key's page: filters, then the requests, newest first, loading older ones on scroll.
struct APIKeyRequestLogSection: View {
    let key: APIKeyRecord
    @Binding var status: APIKeyRequestStatus
    @Binding var since: Date?
    let pager: DevPager<APIKeyRequestRecord>

    @Environment(AppEnvironment.self) private var env
    @State private var ticketInput = ""
    @State private var ticket = ""
    @State private var turningOn = false

    private var filtered: Bool { status != .all || since != nil || !ticket.isEmpty }

    /// Three children of the page's lazy stack: the filters, the rows, and the foot that loads
    /// older requests once scrolled to.
    @ViewBuilder
    var body: some View {
        filters
            .task(id: query) { await load() }
        list
        if pager.loaded, !pager.items.isEmpty {
            DevPagerFoot(hasMore: pager.hasMore, loading: pager.loadingMore, count: pager.items.count) { await pager.loadMore() }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Request log").padding(.horizontal, 4)
            Text("Requests kept for 90 days with safe diagnostics. Shared ticket writes include masked JSON when complete. Ticket visibility still applies.")
                .font(ODFont.footnote)
                .foregroundStyle(Theme.fg3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            if !key.recordRequests { recordingOff }
            AccountSegmented(options: APIKeyRequestStatus.allCases, selection: $status, label: \.title, height: 32)
            HStack(spacing: 8) {
                ticketField
                if let since {
                    Button {
                        Haptics.tap()
                        withAnimation(Motion.snappy) { self.since = nil }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Since \(Format.weekdayClock(since))").font(ODFont.sans(12.5, weight: .medium))
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.fg4)
                        }
                        .foregroundStyle(Theme.fg2)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(TapScaleStyle())
                    .accessibilityLabel("Show every date. Now since \(Format.fullDate(since))")
                }
            }
        }
    }

    private var recordingOff: some View {
        HStack(spacing: 10) {
            Text("Recording is off: this key's requests are not kept.")
                .font(ODFont.footnote)
                .foregroundStyle(Tone.amber.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                turnOn()
            } label: {
                ButtonLabel(title: "Turn on recording", busy: turningOn).foregroundStyle(Tone.amber.text)
            }
            .buttonStyle(ChipButtonStyle(tone: .amber))
            .disabled(turningOn)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Tone.amber.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    private var ticketField: some View {
        HStack(spacing: 6) {
            Image(systemName: "number").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.fg4)
            TextField(text: $ticketInput) { Text("Ticket: number or id").foregroundStyle(Theme.fg4) }
                .font(ODFont.mono(13.5))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { ticket = ticketInput.trimmingCharacters(in: .whitespaces) }
                .accessibilityLabel("Filter by ticket")
            if !ticketInput.isEmpty {
                Button {
                    ticketInput = ""
                    ticket = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.fg4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the ticket filter")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private var list: some View {
        if !pager.loaded {
            Panel { SkeletonRows(count: 4) }
        } else if let error = pager.error, pager.items.isEmpty {
            Panel {
                EmptyState(symbol: "exclamationmark.triangle", title: "Couldn't load the requests", message: error, actionTitle: "Try again") { Task { await pager.reload() } }
            }
        } else if pager.items.isEmpty {
            Panel {
                EmptyState(
                    symbol: "list.bullet.rectangle",
                    title: filtered ? "No request matches" : "No requests yet",
                    message: filtered ? nil : "Requests show here as soon as the key makes them."
                )
            }
        } else {
            Panel {
                ForEach(Array(pager.items.enumerated()), id: \.element.id) { index, request in
                    if index > 0 { Hairline(inset: 14) }
                    SettingsDetailLink(page: .apiKeys, id: "\(key.id)/requests/\(request.id)") {
                        APIKeyRequestRow(request: request)
                    }
                }
            }
            .motion(Motion.snappy, value: pager.items.map(\.id))
        }
    }

    private var query: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if status != .all { items.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if !ticket.isEmpty { items.append(URLQueryItem(name: "ticket", value: ticket)) }
        if let since { items.append(URLQueryItem(name: "since", value: since.devISO)) }
        return items
    }

    private func load() async {
        await pager.load(api: env.session.api, path: "v1/api-keys/\(key.id)/requests", query: query)
    }

    private func turnOn() {
        turningOn = true
        Task {
            do {
                try await APIKeysStore.shared.update(key.id, ["record_requests": .bool(true)])
                Haptics.success()
            } catch {
                env.toasts.show("Couldn't change recording", kind: .error)
            }
            turningOn = false
        }
    }
}

/// One request: when, the method and path, the answer's status and the ticket it touched.
struct APIKeyRequestRow: View {
    let request: APIKeyRequestRecord

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(request.method)
                        .font(ODFont.mono(12, weight: .semibold))
                        .foregroundStyle(Theme.fg2)
                    (Text(request.path).foregroundStyle(Theme.fg) + Text(request.query.isEmpty ? "" : "?\(request.query)").foregroundStyle(Theme.fg4))
                        .font(ODFont.mono(12.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    Text(Format.relShort(request.createdAt)).font(ODFont.mono(11.5)).foregroundStyle(Theme.fg3)
                    if let number = request.ticket?.number {
                        Text("· #\(number)").font(ODFont.mono(11.5, weight: .medium)).foregroundStyle(Tone.violet.text)
                    } else if !request.ticketRef.isEmpty {
                        Text("· \(request.ticketRef)").font(ODFont.mono(11.5)).foregroundStyle(Theme.fg3).lineLimit(1)
                    }
                    if request.replayed {
                        Text("· replayed").font(ODFont.sans(11.5)).foregroundStyle(Theme.fg4)
                    }
                }
            }
            Spacer(minLength: 6)
            DevCodePill(code: request.status)
            Chevron()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One recorded request: its facts, what it sent, and the answer to a failed one.
struct APIKeyRequestDetailView: View {
    let keyID: String
    let requestID: String

    @Environment(AppEnvironment.self) private var env
    @State private var request: APIKeyRequestRecord?
    @State private var error: String?

    var body: some View {
        AccountPage(title: "Request", spacing: 18) {
            if let request {
                content(request)
            } else if let error {
                ErrorState(title: "Couldn't load the requests", message: error) { Task { await load() } }
                    .padding(.top, 40)
            } else {
                Panel { SkeletonRows(count: 5) }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func content(_ r: APIKeyRequestRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DevCodePill(code: r.status)
                Text(r.method).font(ODFont.mono(14, weight: .semibold)).foregroundStyle(Theme.fg)
            }
            (Text(r.path).foregroundStyle(Theme.fg) + Text(r.query.isEmpty ? "" : "?\(r.query)").foregroundStyle(Theme.fg4))
                .font(ODFont.mono(14))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)

        if let ticket = r.ticket, ticket.number != nil {
            AccountSection {
                Button {
                    env.router.open(DeepLink.Target(link: .ticket(id: ticket.id, scope: nil), server: nil, workspaceID: nil))
                } label: {
                    AccountRow(symbol: "ticket", tone: .violet, title: "Ticket", subtitle: nil) {
                        HStack(spacing: 8) {
                            Text("#\(ticket.number ?? 0)").font(ODFont.mono(14, weight: .medium)).foregroundStyle(Tone.violet.text)
                            Chevron()
                        }
                    }
                }
                .buttonStyle(RowPressStyle())
                .accessibilityLabel("Open ticket #\(ticket.number ?? 0)")
            }
        }

        AccountSection {
            DevFacts(facts: facts(r))
        }

        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Sent").padding(.horizontal, 4)
            if let body = r.requestBody {
                DevCodeBlock(text: Self.pretty(body))
                if r.requestTruncated {
                    Text("Capture exceeded 64 KB. Only safe diagnostics are kept.").font(ODFont.footnote).foregroundStyle(Tone.amber.text).padding(.horizontal, 4)
                }
            } else {
                Text("No shared ticket JSON kept for this request.").font(ODFont.footnote).foregroundStyle(Theme.fg4).padding(.horizontal, 4)
            }
        }

        if let answer = r.responseBody {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Answer").padding(.horizontal, 4)
                DevCodeBlock(text: Self.pretty(answer))
                if r.responseTruncated {
                    Text("Capture exceeded 8 KB. Only safe diagnostics are kept.").font(ODFont.footnote).foregroundStyle(Tone.amber.text).padding(.horizontal, 4)
                }
            }
        }
        if r.status < 400 {
            Text("The answer to a successful request is not kept: the records it touched are above.")
                .font(ODFont.footnote)
                .foregroundStyle(Theme.fg4)
                .padding(.horizontal, 4)
        }
    }

    private func facts(_ r: APIKeyRequestRecord) -> [DevFacts.Fact] {
        var out: [DevFacts.Fact] = []
        if let at = r.createdAt { out.append(.init(label: "When", value: Format.fullDate(at))) }
        out.append(.init(label: "Duration", value: "\(r.durationMS) ms"))
        if r.ticket?.number == nil, !r.ticketRef.isEmpty { out.append(.init(label: "Ticket", value: r.ticketRef, mono: true)) }
        if let message = r.messageID { out.append(.init(label: "Message", value: message, mono: true)) }
        if let contact = r.contactID { out.append(.init(label: "Contact", value: contact, mono: true)) }
        if !r.idempotencyKey.isEmpty { out.append(.init(label: "Idempotency key", value: r.idempotencyKey, mono: true)) }
        if r.replayed { out.append(.init(label: "Replayed", value: "Yes: the same Idempotency-Key, answered with the first request's answer")) }
        if !r.requestID.isEmpty { out.append(.init(label: "Request id", value: r.requestID, mono: true)) }
        if !r.ip.isEmpty { out.append(.init(label: "IP address", value: r.ip, mono: true)) }
        if !r.userAgent.isEmpty { out.append(.init(label: "User agent", value: r.userAgent)) }
        if !r.contentType.isEmpty {
            out.append(.init(label: "Content", value: r.requestSize > 0 ? "\(r.contentType) · \(Int((Double(r.requestSize) / 1024).rounded())) KB" : r.contentType))
        }
        return out
    }

    private func load() async {
        do {
            request = try await env.session.api.get("v1/api-keys/\(keyID)/requests/\(requestID)")
            error = nil
        } catch {
            if !error.isCancellation { self.error = error.userMessage }
        }
    }

    /// A body as sent: JSON indented, anything else as it is.
    static func pretty(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed])
        else { return body }
        return String(decoding: out, as: UTF8.self)
    }
}

/// Code or JSON on a sunken panel, scrolling sideways.
struct DevCodeBlock: View {
    let text: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(ODFont.mono(12))
                .lineSpacing(2)
                .foregroundStyle(Theme.fg)
                .textSelection(.enabled)
                .fixedSize()
                .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}
