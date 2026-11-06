import SwiftUI

// A webhook's form (new or edit) and the signing secret a new one gets, shown once with how to
// check a delivery's signature.

struct WebhookFormSheet: View {
    /// nil for a new webhook.
    let hook: WebhookRecord?
    /// After a new webhook's secret is put away: its page, where it is verified.
    var onDone: ((WebhookRecord) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var description = ""
    @State private var events: [String] = ["ticket.created", "ticket.updated", "message.created"]
    @State private var enabled = true
    @State private var privateTeams: [String] = []
    @State private var headers = ""
    @State private var replaceHeaders = true
    @State private var urlError: String?
    @State private var headersError: String?
    @State private var error: String?
    @State private var busy = false
    @State private var created: CreatedWebhook?
    @State private var ready = false

    private var all: Bool { WebhookEvents.all.allSatisfy(events.contains) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let created {
                    WebhookSecretView(secret: created.secret) {
                        dismiss()
                        onDone?(created.hook)
                    }
                } else {
                    form
                }
            }
            .padding(22)
            .motion(Motion.snappy, value: error)
            .motion(Motion.smooth, value: created == nil)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.surface)
        .interactiveDismissDisabled(created != nil)
        .onAppear(perform: fill)
    }

    @ViewBuilder
    private var form: some View {
        AccountSheetHeader(
            title: hook == nil ? "New webhook" : "Edit webhook",
            subtitle: "opendesk sends a signed POST with the event envelope to this URL.",
            closeLabel: "Cancel"
        ) { dismiss() }

        VStack(alignment: .leading, spacing: 6) {
            DevFieldLabel(title: "Endpoint URL")
            TextField(text: $url) { Text("https://example.com/hooks/opendesk").foregroundStyle(Theme.fg4) }
                .font(ODFont.mono(14.5))
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: url) { _, _ in urlError = nil }
                .padding(.horizontal, 13)
                .frame(height: 46)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(urlError == nil ? Theme.line : Tone.red.line, lineWidth: 1))
            FormError(text: urlError)
        }

        ODTextField(label: "Description (optional)", text: Binding(get: { description }, set: { description = String($0.prefix(200)) }), prompt: "Sync tickets to the data warehouse", submitLabel: .done)

        headersField

        eventsField

        Panel {
            AccountToggleRow(title: "Active", subtitle: "Paused webhooks keep their settings but receive nothing.", isOn: $enabled)
        }

        DevPrivateTeamsField(value: $privateTeams, grants: hook?.privateTeams ?? [])

        FormError(text: error)
        Button(action: submit) { ButtonLabel(title: hook == nil ? "Create webhook" : "Save webhook", busy: busy) }
            .buttonStyle(InkButtonStyle())
            .disabled(busy)
    }

    @ViewBuilder
    private var headersField: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hook, !hook.headerNames.isEmpty {
                Text("Configured headers: \(hook.headerNames.joined(separator: ", ")). Their values are hidden.")
                    .font(ODFont.footnote)
                    .foregroundStyle(Theme.fg3)
            }
            if hook != nil {
                Panel {
                    AccountToggleRow(title: "Replace custom headers", isOn: $replaceHeaders)
                }
            }
            if replaceHeaders {
                AccountTextEditor(label: "Custom headers (optional)", text: $headers, prompt: "Authorization: Bearer …\nX-Account-ID: acme", minHeight: 90, mono: true)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: headers) { _, _ in headersError = nil }
                if let headersError {
                    FormError(text: headersError)
                } else {
                    Text("One Header: value per line. Values are encrypted and never shown again.")
                        .font(ODFont.footnote)
                        .foregroundStyle(Theme.fg3)
                }
            }
        }
    }

    private var eventsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Events").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
                Text("\(all ? WebhookEvents.all.count : events.count)/\(WebhookEvents.all.count)")
                    .font(ODFont.mono(11.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.fg4)
                Spacer()
                WebhookTriCheck(title: "All events", state: all ? .all : events.isEmpty ? .none : .some) {
                    events = all ? [] : WebhookEvents.all
                }
            }
            Panel {
                ForEach(Array(WebhookEvents.groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { Hairline(inset: 14) }
                    let on = group.events.filter(events.contains).count
                    VStack(alignment: .leading, spacing: 8) {
                        WebhookTriCheck(title: group.label, state: on == group.events.count ? .all : on > 0 ? .some : .none, bold: true) {
                            toggle(group.events, on: on < group.events.count)
                        }
                        .accessibilityLabel("All \(group.label.lowercased()) events")
                        FlowLayout(spacing: 6) {
                            ForEach(group.events, id: \.self) { event in
                                DevCheckChip(title: event, on: events.contains(event), mono: true) {
                                    toggle([event], on: !events.contains(event))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
            }
        }
    }

    private func toggle(_ group: [String], on: Bool) {
        withAnimation(Motion.snappy) {
            if on {
                events += group.filter { !events.contains($0) }
            } else {
                events.removeAll { group.contains($0) }
            }
        }
    }

    private func fill() {
        guard !ready else { return }
        ready = true
        guard let hook else { return }
        url = hook.url
        description = hook.description
        events = WebhookEvents.expand(hook.events)
        enabled = hook.enabled
        privateTeams = hook.privateTeamIDs
        replaceHeaders = false
    }

    private func submit() {
        error = nil
        headersError = nil
        urlError = Self.validate(url)
        guard urlError == nil else { return Haptics.error() }
        guard !events.isEmpty else {
            Haptics.error()
            error = "Choose at least one event."
            return
        }
        var custom: [String: String]?
        if replaceHeaders {
            guard let parsed = Self.parseHeaders(headers) else {
                Haptics.error()
                headersError = "Enter one Header: value pair on each line."
                return
            }
            custom = parsed
        }
        let teamsChanged = privateTeams != (hook?.privateTeamIDs ?? [])
        let form = WebhooksStore.Form(
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            events: events,
            enabled: enabled,
            headers: custom,
            privateTeamIDs: teamsChanged ? privateTeams : nil
        )
        busy = true
        Task {
            do {
                if let hook {
                    try await WebhooksStore.shared.update(hook.id, form.body)
                    Haptics.success()
                    dismiss()
                } else {
                    let made = try await WebhooksStore.shared.create(form)
                    Haptics.success()
                    created = made
                }
            } catch {
                if !error.isCancellation {
                    Haptics.error()
                    self.error = error.userMessage
                }
            }
            busy = false
        }
    }

    /// http is accepted only for a local receiver; the server allows it on development instances only.
    static func validate(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), let host = url.host(percentEncoded: false), !host.isEmpty else {
            return "Enter a full URL, like https://example.com/hooks/opendesk."
        }
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let loopback = bare.split(separator: ".").count == 4 && bare.hasPrefix("127.") && bare.split(separator: ".").allSatisfy { Int($0) != nil }
        let local = bare == "localhost" || bare == "::1" || loopback
        if scheme != "https" && !(scheme == "http" && local) { return "Use an https:// URL." }
        return nil
    }

    /// "Name: value" per line, each name once; nil when a line isn't one.
    static func parseHeaders(_ raw: String) -> [String: String]? {
        var out: [String: String] = [:]
        for line in raw.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let colon = line.firstIndex(of: ":"), colon > line.startIndex else { return nil }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty, out[name] == nil else { return nil }
            out[name] = value
        }
        return out
    }
}

/// A check for a group: all, some or none of it.
struct WebhookTriCheck: View {
    enum Mark { case all, some, none }

    let title: String
    let state: Mark
    var bold = false
    let toggle: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: state == .all ? "checkmark.circle.fill" : state == .some ? "minus.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(state == .none ? Theme.fg4 : Theme.fg)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(ODFont.sans(bold ? 14.5 : 13, weight: bold ? .semibold : .medium))
                    .foregroundStyle(bold ? Theme.fg : Theme.fg2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(state == .all ? "All" : state == .some ? "Some" : "None")
    }
}

/// A new webhook's signing secret, once, and how to check the signature on each delivery.
struct WebhookSecretView: View {
    let secret: String
    let done: () -> Void

    private let verify = """
    const [t, v1] = header.split(",").map((p) => p.split("=")[1]);
    const expected = hmacSha256Hex(secret, `${t}.${rawBody}`);
    const ok = timingSafeEqual(expected, v1) && Math.abs(Date.now() / 1000 - Number(t)) < 300;
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AccountSheetHeader(title: "Signing secret", subtitle: "Copy it now. You won't see it again.", closeLabel: "Done", close: done)
            DevSecretPanel(secret: secret, warning: "You won't see it again. Store it with the receiver that checks signatures.")
            VStack(alignment: .leading, spacing: 10) {
                Text("Every delivery carries a signature header. Verify it before trusting the body:")
                    .font(ODFont.callout)
                    .foregroundStyle(Theme.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                DevCopyField(value: "OD-Signature: t=<unix>,v1=<hex hmac_sha256(secret, \"<t>.<body>\")>", multiline: true)
                DevCopyField(value: verify, multiline: true)
                (Text("Deliveries also include ") + Text("OD-Event-Id").font(ODFont.mono(12)).foregroundStyle(Theme.fg2)
                    + Text(" and ") + Text("OD-Event-Type").font(ODFont.mono(12)).foregroundStyle(Theme.fg2)
                    + Text(". Use the event id to ignore retries you've already handled."))
                    .font(ODFont.footnote)
                    .foregroundStyle(Theme.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("I've saved it", action: done)
                .buttonStyle(InkButtonStyle())
        }
    }
}
