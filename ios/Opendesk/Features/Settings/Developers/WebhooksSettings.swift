import SwiftUI

/// Settings › Webhooks: the workspace's endpoints with their health and last delivery, pause and
/// resume, a new one with its signing secret shown once, and each webhook's page (`Detail`):
/// verification, its events and its recent deliveries. Admins only, as on the web.
struct WebhooksSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var editing: WebhookEdit?
    @State private var confirm: AccountConfirm?

    private var store: WebhooksStore { WebhooksStore.shared }

    var body: some View {
        if env.session.isAdmin {
            page
        } else {
            DevNoAccess(title: "Webhooks", what: "webhooks")
        }
    }

    private var page: some View {
        let hooks = store.hooks
        return AccountPage(title: "Webhooks", spacing: 18) {
            Text("Get a signed HTTPS request whenever something changes. Failed deliveries are retried with backoff.")
                .font(ODFont.footnote)
                .foregroundStyle(Theme.fg3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            if !hooks.isEmpty { summary(hooks) }
            if !store.loaded {
                Panel { SkeletonRows(count: 3) }
            } else if let error = store.error, hooks.isEmpty {
                ErrorState(message: error) { Task { await load() } }
            } else if hooks.isEmpty {
                empty
            } else {
                AccountSection(title: Format.plural(hooks.count, "endpoint")) {
                    ForEach(Array(hooks.enumerated()), id: \.element.id) { index, hook in
                        if index > 0 { Hairline(inset: 56) }
                        row(hook)
                    }
                }
                .motion(Motion.snappy, value: hooks.map(\.id))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = WebhookEdit(hook: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New webhook")
            }
        }
        .sheet(item: $editing) { edit in
            WebhookFormSheet(hook: edit.hook) { created in
                env.router.openSetting(.webhooks, id: created.id)
            }
            .presentationDetents([.large])
            .presentationCornerRadius(Theme.Radius.sheet)
        }
        .accountConfirm($confirm)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await store.load(env.session)
        await store.loadAllDeliveries()
    }

    private func summary(_ hooks: [WebhookRecord]) -> some View {
        let healths = hooks.map(store.health)
        let attempts = hooks.flatMap { (store.deliveries[$0.id] ?? []).filter { $0.status != .pending } }
        let failed = attempts.filter { $0.status == .failed }.count
        let rate = attempts.isEmpty ? nil : Int((Double(attempts.count - failed) / Double(attempts.count) * 100).rounded())
        let count = { (state: WebhookHealth) in healths.filter { $0 == state }.count }
        return DevSummaryStrip(items: [
            .init(label: "Active", value: String(count(.active)), tone: count(.active) > 0 ? .green : nil),
            .init(label: "Failing", value: String(count(.failing)), tone: count(.failing) > 0 ? .red : nil),
            .init(label: "Paused", value: String(count(.paused)), tone: count(.paused) > 0 ? .amber : nil),
            .init(
                label: "Delivered",
                value: rate.map { "\($0)%" } ?? "–",
                hint: attempts.isEmpty ? "No attempts yet" : "Of the last \(Format.plural(attempts.count, "attempt"))"
            ),
        ])
    }

    private var empty: some View {
        Panel {
            VStack(spacing: 6) {
                EmptyState(
                    symbol: "point.3.connected.trianglepath.dotted",
                    title: "No webhooks yet",
                    message: "Send ticket and contact events to your own systems as they happen.",
                    actionTitle: "New webhook"
                ) { editing = WebhookEdit(hook: nil) }
                VStack(alignment: .leading, spacing: 8) {
                    tip("checkmark.shield", "Every delivery is signed with your secret")
                    tip("arrow.clockwise", "Failed deliveries retry with backoff")
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Theme.fg3).frame(width: 18)
            Text(text).font(ODFont.footnote).foregroundStyle(Theme.fg2)
        }
    }

    private func row(_ hook: WebhookRecord) -> some View {
        let health = store.health(hook)
        let last = store.deliveries[hook.id]?.first
        return HStack(alignment: .top, spacing: 12) {
            AccountIconTile(symbol: "point.3.connected.trianglepath.dotted", tone: health.tileTone)
            VStack(alignment: .leading, spacing: 5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hook.url).font(ODFont.mono(13)).foregroundStyle(Theme.fg).lineLimit(1).truncationMode(.middle)
                    Text(hook.description.isEmpty ? "No description" : hook.description)
                        .font(ODFont.footnote)
                        .foregroundStyle(Theme.fg3)
                        .lineLimit(1)
                }
                .opacity(hook.enabled ? 1 : 0.6)
                HStack(spacing: 8) {
                    DevStatePill(text: health.title, tone: health.tone)
                    DevMonoChip(text: WebhookEvents.summary(hook.events))
                    if let last {
                        HStack(spacing: 4) {
                            Circle().fill(last.status.tone.solid).frame(width: 6, height: 6)
                            Text(Format.relShort(last.createdAt)).font(ODFont.mono(11.5)).foregroundStyle(Theme.fg3)
                        }
                        .accessibilityLabel("Last delivery \(last.status.title.lowercased()), \(Format.fullDate(last.createdAt))")
                    } else {
                        Text("Never").font(ODFont.sans(11.5)).foregroundStyle(Theme.fg4)
                    }
                }
                DevGrantedTeams(grants: hook.privateTeams)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Toggle("Webhook \(hook.url) active", isOn: Binding(get: { hook.enabled }, set: { setEnabled(hook, $0) }))
                    .labelsHidden()
                    .tint(Tone.green.solid)
                    .scaleEffect(0.85, anchor: .trailing)
                Menu {
                    Button("Edit", systemImage: "pencil") { editing = WebhookEdit(hook: hook) }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { askDelete(hook) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.fg3)
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Webhook actions")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { env.router.openSetting(.webhooks, id: hook.id) }
        .accessibilityAction(named: "Open") { env.router.openSetting(.webhooks, id: hook.id) }
    }

    private func setEnabled(_ hook: WebhookRecord, _ on: Bool) {
        Task {
            do {
                try await store.setEnabled(hook.id, on)
            } catch {
                env.toasts.show("Couldn't update the webhook", kind: .error)
            }
        }
    }

    private func askDelete(_ hook: WebhookRecord) {
        confirm = AccountConfirm(title: "Delete this webhook?", message: "Deliveries to \(hook.url) stop right away.", confirmTitle: "Delete webhook") {
            do {
                try await store.remove(hook.id)
                Haptics.success()
            } catch {
                env.toasts.show("Couldn't delete the webhook", kind: .error)
            }
        }
    }

    // MARK: Detail

    struct Detail: View {
        let id: String

        var body: some View {
            WebhookDetailView(hookID: id)
        }
    }
}

struct WebhookEdit: Identifiable {
    let id = UUID()
    var hook: WebhookRecord?
}

/// A webhook's page: its state and switch, a test event, verification while the address hasn't
/// answered its challenge, delivery stats, its events and its last 50 deliveries.
struct WebhookDetailView: View {
    let hookID: String

    private enum Filter: String, CaseIterable { case all, failed }

    @Environment(AppEnvironment.self) private var env
    @State private var filter: Filter = .all
    @State private var editing: WebhookEdit?
    @State private var confirm: AccountConfirm?
    @State private var testing = false

    private var store: WebhooksStore { WebhooksStore.shared }

    var body: some View {
        if !env.session.isAdmin {
            DevNoAccess(title: "Webhook", what: "webhooks")
        } else {
            let hook = store.hook(hookID)
            AccountPage(title: "Webhook", spacing: 20) {
                if let hook {
                    content(hook)
                } else if store.loaded {
                    EmptyState(symbol: "point.3.connected.trianglepath.dotted", title: "Webhook not found", message: "It may have been deleted.", actionTitle: "Back to webhooks") { back() }
                        .padding(.top, 40)
                } else {
                    Panel { SkeletonRows(count: 4) }
                }
            }
            .toolbar {
                if let hook {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Edit", systemImage: "pencil") { editing = WebhookEdit(hook: hook) }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) { askDelete(hook) }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Webhook actions")
                    }
                }
            }
            .sheet(item: $editing) { edit in
                WebhookFormSheet(hook: edit.hook)
                    .presentationDetents([.large])
                    .presentationCornerRadius(Theme.Radius.sheet)
            }
            .accountConfirm($confirm)
            .task {
                if !store.loaded { await store.load(env.session) }
                await store.loadDeliveries(hookID)
            }
            .refreshable {
                await store.load(env.session)
                await store.loadDeliveries(hookID)
            }
        }
    }

    @ViewBuilder
    private func content(_ hook: WebhookRecord) -> some View {
        let all = store.deliveries[hook.id] ?? []
        let health = WebhookHealth(hook, deliveries: all)

        VStack(alignment: .leading, spacing: 6) {
            Text(hook.url)
                .font(ODFont.mono(16, weight: .medium))
                .foregroundStyle(Theme.fg)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !hook.description.isEmpty {
                Text(hook.description).font(ODFont.callout).foregroundStyle(Theme.fg3)
            }
        }
        .padding(.horizontal, 4)

        AccountSection {
            AccountRow(symbol: "dot.radiowaves.left.and.right", tone: health.tone, title: "Webhook active") {
                HStack(spacing: 10) {
                    DevStatePill(text: health.title, tone: health.tone)
                    Toggle("Webhook active", isOn: Binding(get: { hook.enabled }, set: { setEnabled(hook, $0) }))
                        .labelsHidden()
                        .tint(Tone.green.solid)
                }
            }
            AccountDivider()
            Button(action: { test(hook) }) {
                AccountRow(symbol: "paperplane", title: "Send test event", subtitle: hook.verified ? nil : "Verify the address first.") {
                    if testing { ProgressView().controlSize(.small) } else { Chevron() }
                }
            }
            .buttonStyle(RowPressStyle())
            .disabled(!hook.enabled || !hook.verified || testing)
            .opacity(!hook.enabled || !hook.verified ? 0.5 : 1)
        }

        if !hook.verified {
            WebhookVerifySection(hook: hook)
        }

        stats(all)

        AccountSection(
            title: "Events",
            footer: hook.allEvents ? "Every event in the catalog, including new ones." : "\(Format.plural(hook.events.count, "event")) subscribed"
        ) {
            FlowLayout(spacing: 5) {
                if hook.allEvents {
                    DevMonoChip(text: "All events")
                } else {
                    ForEach(hook.events, id: \.self) { DevMonoChip(text: $0) }
                }
            }
            .padding(14)
        }

        if !hook.headerNames.isEmpty || !hook.privateTeams.isEmpty {
            AccountSection {
                if !hook.headerNames.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Custom headers").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg3)
                        FlowLayout(spacing: 5) { ForEach(hook.headerNames, id: \.self) { DevMonoChip(text: $0) } }
                        Text("Their values are hidden.").font(ODFont.footnote).foregroundStyle(Theme.fg4)
                    }
                    .padding(14)
                }
                if !hook.headerNames.isEmpty && !hook.privateTeams.isEmpty { Hairline(inset: 14) }
                if !hook.privateTeams.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Private teams this sees").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg3)
                        DevGrantedTeams(grants: hook.privateTeams)
                    }
                    .padding(14)
                }
            }
        }

        deliveries(all, hook: hook)

        Button { askDelete(hook) } label: { Label("Delete webhook", systemImage: "trash") }
            .buttonStyle(OutlineButtonStyle(tint: Tone.red.text))
    }

    private func stats(_ all: [WebhookDeliveryRecord]) -> some View {
        let done = all.filter { $0.status != .pending }
        let failed = all.filter { $0.status == .failed }.count
        let rate = done.isEmpty ? nil : Int((Double(done.count - failed) / Double(done.count) * 100).rounded())
        let timed = all.compactMap(\.durationMS)
        let avg = timed.isEmpty ? nil : Int((Double(timed.reduce(0, +)) / Double(timed.count)).rounded())
        return DevSummaryStrip(items: [
            .init(label: "Delivered", value: rate.map { "\($0)%" } ?? "–", tone: rate.map { $0 >= 95 ? .green : $0 >= 80 ? .amber : .red }),
            .init(label: "Failed", value: String(failed), tone: failed > 0 ? .red : nil),
            .init(label: "Avg response", value: avg.map { "\($0) ms" } ?? "–"),
            .init(label: "Last delivery", value: all.first.map { Format.relShort($0.createdAt) } ?? "–", hint: all.first?.eventType),
        ])
    }

    @ViewBuilder
    private func deliveries(_ all: [WebhookDeliveryRecord], hook: WebhookRecord) -> some View {
        let failed = all.filter { $0.status == .failed }.count
        let rows = all.filter { filter == .all || $0.status == .failed }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Recent deliveries")
                if store.deliveriesLoading.contains(hook.id) { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, 4)
            Text("The last 50 attempts. Failures are retried automatically.")
                .font(ODFont.footnote)
                .foregroundStyle(Theme.fg3)
                .padding(.horizontal, 4)
            AccountSegmented(options: Filter.allCases, selection: $filter, label: { value in
                value == .all ? "All" : failed > 0 ? "Failed \(failed)" : "Failed"
            }, height: 32)
            Panel {
                if store.deliveries[hook.id] == nil {
                    SkeletonRows(count: 4)
                } else if rows.isEmpty {
                    if filter == .failed {
                        EmptyState(symbol: "checkmark.circle", title: "No failed deliveries", message: "Everything recent went through.")
                    } else {
                        EmptyState(symbol: "paperplane", title: "No deliveries yet", message: "Send a test event to check your endpoint.")
                    }
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, delivery in
                        if index > 0 { Hairline(inset: 14) }
                        WebhookDeliveryRow(delivery: delivery)
                    }
                }
            }
            .motion(Motion.snappy, value: rows.map(\.id))
        }
    }

    private func setEnabled(_ hook: WebhookRecord, _ on: Bool) {
        Task {
            do {
                try await store.setEnabled(hook.id, on)
            } catch {
                env.toasts.show("Couldn't update the webhook", kind: .error)
            }
        }
    }

    private func test(_ hook: WebhookRecord) {
        testing = true
        Task {
            do {
                try await store.test(hook.id)
                Haptics.success()
                env.toasts.show("Test event sent. webhook.test is on its way.", kind: .success)
            } catch {
                Haptics.error()
                env.toasts.show(Toast(message: "Couldn't send the test event: \(error.userMessage)", kind: .error), seconds: 4.5)
            }
            testing = false
        }
    }

    private func askDelete(_ hook: WebhookRecord) {
        confirm = AccountConfirm(title: "Delete this webhook?", message: "Deliveries to \(hook.url) stop right away.", confirmTitle: "Delete webhook") {
            do {
                try await store.remove(hook.id)
                Haptics.success()
                env.toasts.show("Webhook deleted", kind: .success)
                back()
            } catch {
                env.toasts.show("Couldn't delete the webhook", kind: .error)
            }
        }
    }

    private func back() {
        if !env.router.accountPath.isEmpty { env.router.accountPath.removeLast() }
    }
}

/// One delivery: its state, the event, the response code, how long it took, attempts and when.
struct WebhookDeliveryRow: View {
    let delivery: WebhookDeliveryRecord

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(delivery.eventType).font(ODFont.mono(12.5)).foregroundStyle(Theme.fg).lineLimit(1)
                HStack(spacing: 6) {
                    DevStatePill(text: delivery.status.title, tone: delivery.status.tone)
                    if let duration = delivery.durationMS {
                        Text("\(duration) ms").font(ODFont.mono(11.5)).monospacedDigit().foregroundStyle(Theme.fg3)
                    }
                    Text(delivery.attempts == 1 ? "1 attempt" : "\(delivery.attempts) attempts")
                        .font(ODFont.sans(11.5))
                        .foregroundStyle(delivery.attempts > 1 ? Tone.amber.text : Theme.fg4)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                DevCodePill(code: delivery.responseCode)
                Text(Format.relShort(delivery.createdAt)).font(ODFont.mono(11.5)).foregroundStyle(Theme.fg3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// An address that has not answered its verification challenge: enter the challenge it got,
/// or send a new one.
struct WebhookVerifySection: View {
    let hook: WebhookRecord

    @Environment(AppEnvironment.self) private var env
    @State private var code = ""
    @State private var verifying = false
    @State private var resending = false

    var body: some View {
        AccountSection(title: "Verify this address") {
            VStack(alignment: .leading, spacing: 12) {
                Text("No events go out until the address shows it wants them. opendesk sent it a webhook.verification event with a challenge. Answer that request with the challenge as the response body and it is verified at once, or enter the challenge it received here.")
                    .font(ODFont.footnote)
                    .foregroundStyle(Theme.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(text: $code) { Text("whv_...").foregroundStyle(Theme.fg4) }
                    .font(ODFont.mono(14.5))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(verify)
                    .accessibilityLabel("Challenge")
                    .padding(.horizontal, 13)
                    .frame(height: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                HStack(spacing: 10) {
                    Button(action: verify) { ButtonLabel(title: "Verify", busy: verifying) }
                        .buttonStyle(InkButtonStyle(height: 42))
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || verifying)
                    Button(action: resend) {
                        ZStack {
                            Text("Send a new challenge").opacity(resending ? 0 : 1)
                            if resending { ProgressView().controlSize(.small) }
                        }
                    }
                    .buttonStyle(OutlineButtonStyle(height: 42))
                    .disabled(resending)
                }
            }
            .padding(14)
        }
    }

    private func verify() {
        let challenge = code.trimmingCharacters(in: .whitespaces)
        guard !challenge.isEmpty, !verifying else { return }
        verifying = true
        Task {
            do {
                let hook = try await WebhooksStore.shared.verify(hook.id, code: challenge)
                if hook.verified {
                    Haptics.success()
                    env.toasts.show("Webhook verified", kind: .success)
                }
            } catch {
                Haptics.error()
                env.toasts.show(Toast(message: "Couldn't verify the webhook: \(error.userMessage)", kind: .error), seconds: 4.5)
            }
            verifying = false
        }
    }

    private func resend() {
        resending = true
        Task {
            do {
                let hook = try await WebhooksStore.shared.verify(hook.id, code: nil)
                if hook.verified {
                    Haptics.success()
                    env.toasts.show("Webhook verified", kind: .success)
                } else {
                    env.toasts.show(Toast(message: "New challenge sent. Enter it here once it arrives."), seconds: 4.5)
                }
            } catch {
                Haptics.error()
                env.toasts.show(Toast(message: "Couldn't verify the webhook: \(error.userMessage)", kind: .error), seconds: 4.5)
            }
            resending = false
        }
    }
}
