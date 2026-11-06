import Charts
import SwiftUI

/// Settings › Plan and billing, read only: the plan, its limits, the AI balance and what the
/// workspace's AI was used for (web `Billing.tsx`). Nothing here buys, changes or links to a
/// plan. A self-hosted instance has no billing and no limits.
struct BillingSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store = BillingSettingsStore()

    private var admin: Bool { env.session.isAdmin }

    var body: some View {
        AccountPage(title: "Plan and billing") {
            if let billing = store.billing {
                if billing.selfHosted {
                    selfHosted
                } else {
                    plan(billing)
                    if billing.limit(members: true).limited || billing.limit(members: false).limited { limits(billing) }
                    aiBalance(billing)
                }
                if admin { usage }
            } else if store.forbidden {
                Panel {
                    EmptyState(symbol: "lock", title: "Only admins can see this", message: "The plan, its limits and AI usage are shown to the workspace's admins.")
                }
            } else if let error = store.error {
                ErrorState(message: error) { Task { await store.load(admin: admin) } }
            } else {
                WSLoading(rows: 4)
            }
        }
        .refreshable { await store.load(admin: admin) }
        .task {
            store.attach(env.session.api)
            await store.load(admin: admin)
        }
        .onChange(of: store.days) { _, _ in
            Task { await store.loadUsage() }
        }
    }

    // MARK: Plan

    private var selfHosted: some View {
        Panel {
            HStack(alignment: .top, spacing: 12) {
                AccountIconTile(symbol: "server.rack", tone: .green, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Self-hosted: unlimited").font(ODFont.sans(16.5, weight: .semibold)).foregroundStyle(Theme.fg)
                    Text("This instance has no billing. Every workspace has unlimited mailboxes, members and AI, using the instance\u{2019}s own AI provider key.")
                        .font(ODFont.sans(13.5))
                        .foregroundStyle(Theme.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    private func plan(_ billing: WSBilling) -> some View {
        VStack(spacing: 12) {
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        AccountIconTile(symbol: Self.planSymbol(billing.plan), tone: Self.planTone(billing.plan), size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current plan").font(ODFont.sans(12.5, weight: .medium)).foregroundStyle(Theme.fg3)
                            Text(Self.planName(billing.plan)).font(ODFont.sans(19, weight: .semibold)).foregroundStyle(Theme.fg)
                        }
                        Spacer(minLength: 8)
                        if let status = Self.status(billing) {
                            TonePill(text: status.title, tone: status.tone, height: 22)
                        }
                    }
                    if let line = periodLine(billing) {
                        Text(line).font(ODFont.sans(13.5)).foregroundStyle(Theme.fg3)
                    }
                }
                .padding(14)
                if billing.hasSubscription && billing.seats > 0 {
                    Hairline(inset: 0)
                    WSSummaryStrip(items: [
                        .init(label: "Members", value: "\(billing.usedMembers)"),
                        .init(label: "Seats", value: "\(Swift.max(billing.seats, billing.billedSeats))"),
                        .init(label: "Mailboxes", value: "\(billing.usedMailboxes)"),
                    ])
                }
            }
            if billing.status == "past_due" || billing.status == "unpaid" {
                Notice(text: "The last payment for this workspace didn\u{2019}t go through.", tone: .amber, symbol: "exclamationmark.triangle")
            }
            if billing.complimentary {
                Notice(
                    text: billing.collab?.until.map { "Collab is included for this workspace until \(Format.fullDate($0))." } ?? "Collab is included for this workspace.",
                    tone: .violet, symbol: "gift"
                )
            }
        }
    }

    private func periodLine(_ billing: WSBilling) -> String? {
        guard billing.hasSubscription, let end = billing.currentPeriodEnd else { return nil }
        if billing.status == "trialing" { return "Trial ends \(Format.fullDate(end))." }
        return billing.cancelAtPeriodEnd ? "Ends \(Format.fullDate(end))." : "Renews \(Format.fullDate(end))."
    }

    private func limits(_ billing: WSBilling) -> some View {
        AccountSection(title: "Limits", footer: "Limits count members, pending invitations and connected mailboxes.") {
            limitRow("Members", symbol: "person.2", billing.limit(members: true))
            AccountDivider()
            limitRow("Mailboxes", symbol: "tray.2", billing.limit(members: false))
        }
    }

    private func limitRow(_ title: String, symbol: String, _ limit: WSBilling.Limit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountRow(symbol: symbol, tone: limit.atLimit ? .amber : .gray, title: title, subtitle: limit.over ? "Over the limit" : limit.atLimit ? "At the limit" : nil) {
                Text(limit.limited ? "\(limit.used) of \(limit.max)" : "\(limit.used), unlimited")
                    .font(ODFont.sans(14.5, weight: .medium))
                    .foregroundStyle(Theme.fg2)
                    .monospacedDigit()
            }
            if limit.limited {
                WSMeter(value: Double(limit.used), max: Double(limit.max), tone: limit.atLimit ? .amber : .blue)
                    .padding(.leading, 56)
                    .padding(.trailing, 14)
                    .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func aiBalance(_ billing: WSBilling) -> some View {
        let ai = billing.ai
        AccountSection(title: "AI", footer: ai.unlimited ? nil : ai.periodEnd.map { "The monthly allowance starts again \(Format.fullDate($0))." }) {
            if ai.unlimited {
                AccountRow(symbol: "sparkles", tone: .violet, title: "Unlimited AI", subtitle: "This workspace\u{2019}s AI has no spending limit.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Balance").font(ODFont.sans(12.5, weight: .medium)).foregroundStyle(Theme.fg3)
                            Text(WSUSD.format(Swift.max(0, ai.remainingUSD)))
                                .font(ODFont.sans(22, weight: .semibold))
                                .foregroundStyle(billing.aiLow ? Tone.amber.text : Theme.fg)
                                .monospacedDigit()
                        }
                        Spacer()
                        Text("\(WSUSD.format(ai.usedUSD)) used this month")
                            .font(ODFont.sans(13))
                            .foregroundStyle(Theme.fg3)
                            .monospacedDigit()
                    }
                    WSMeter(value: ai.usedUSD, max: Swift.max(ai.monthlyUSD + ai.purchasedUSD, ai.usedUSD, 0.01), tone: billing.aiLow ? .amber : .violet)
                    Text("Monthly allowance \(WSUSD.format(ai.monthlyUSD))\(ai.purchasedUSD > 0 ? ", plus \(WSUSD.format(ai.purchasedUSD)) of credit" : "").")
                        .font(ODFont.footnote)
                        .foregroundStyle(Theme.fg3)
                    if billing.aiLow {
                        Text(ai.remainingUSD <= 0
                            ? "The AI balance is used up. AI features pause until the allowance starts again."
                            : "The AI balance is running low.")
                            .font(ODFont.footnote)
                            .foregroundStyle(Tone.amber.text)
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: Usage

    private var usage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel("AI usage")
                Spacer()
            }
            AccountSegmented(options: [7, 30, 90], selection: $store.days) { "\($0) days" }
            if let usage = store.usage {
                usageBody(usage)
            } else if let error = store.usageError {
                Panel { ErrorState(message: error) { Task { await store.loadUsage() } } }
            } else {
                Panel { SkeletonRows(count: 3) }
            }
        }
    }

    @ViewBuilder
    private func usageBody(_ usage: WSUsage) -> some View {
        Panel {
            WSSummaryStrip(items: [
                .init(label: "Cost", value: WSUSD.format(usage.totalUSD)),
                .init(label: "Requests", value: usage.totalCalls.formatted()),
                .init(label: "Own key", value: usage.ownKeyCalls.formatted(), hint: usage.ownKeyCalls > 0 ? "Not counted" : nil),
            ])
            if usage.byDay.contains(where: { $0.usd > 0 }) {
                Hairline(inset: 0)
                Chart(usage.byDay) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Cost", day.usd))
                        .foregroundStyle(Tone.violet.solid)
                        .cornerRadius(2)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Theme.lineSoft)
                        AxisValueLabel { if let usd = value.as(Double.self) { Text(WSUSD.format(usd)).font(ODFont.sans(10)) } }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(ODFont.sans(10))
                    }
                }
                .frame(height: 150)
                .padding(14)
                .accessibilityLabel("AI cost by day")
            }
        }
        if usage.totalCalls == 0 {
            Panel {
                EmptyState(symbol: "sparkles", title: "No AI use yet", message: "Summaries, drafts, triage and Ollie\u{2019}s answers show up here as the team uses them.")
            }
        } else {
            breakdown("By feature", usage.byFeature)
            breakdown("By member", usage.byMember)
            breakdown("By model", usage.byModel)
        }
    }

    @ViewBuilder
    private func breakdown(_ title: String, _ rows: [WSUsage.Row]) -> some View {
        let sorted = rows.sorted { ($0.usd, $0.calls) > ($1.usd, $1.calls) }
        if !sorted.isEmpty {
            let top = sorted.map(\.usd).max() ?? 0
            AccountSection(title: title) {
                ForEach(Array(sorted.enumerated()), id: \.element.key) { index, row in
                    if index > 0 { AccountDivider(tiles: false) }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(row.label).font(ODFont.sans(14.5)).foregroundStyle(Theme.fg).lineLimit(1)
                            if row.ownKey { TonePill(text: "Own key", tone: .gray) }
                            Spacer(minLength: 8)
                            Text(wsPlural(row.calls, "1 request", "\(row.calls.formatted()) requests"))
                                .font(ODFont.sans(12.5))
                                .foregroundStyle(Theme.fg4)
                            Text(WSUSD.format(row.usd, precise: true))
                                .font(ODFont.sans(14, weight: .medium))
                                .foregroundStyle(Theme.fg2)
                                .monospacedDigit()
                                .frame(minWidth: 56, alignment: .trailing)
                        }
                        if top > 0 {
                            WSMeter(value: row.usd, max: top, tone: .violet)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: Names

    static func planName(_ plan: String) -> String {
        switch plan {
        case "free": "Free"
        case "pro": "Pro"
        case "collab": "Collab"
        case "self_hosted": "Self-hosted"
        default: plan.capitalized
        }
    }

    static func planSymbol(_ plan: String) -> String {
        switch plan {
        case "pro": "star"
        case "collab": "envelope.open"
        default: "circle.dashed"
        }
    }

    static func planTone(_ plan: String) -> Tone {
        switch plan {
        case "pro": .blue
        case "collab": .violet
        default: .gray
        }
    }

    static func status(_ billing: WSBilling) -> (title: String, tone: Tone)? {
        if billing.complimentary { return ("Included", .violet) }
        switch billing.status {
        case "active": return billing.cancelAtPeriodEnd ? ("Ending", .amber) : ("Active", .green)
        case "trialing": return ("Trial", .blue)
        case "past_due": return ("Past due", .amber)
        case "unpaid": return ("Unpaid", .red)
        case "incomplete": return ("Incomplete", .amber)
        case "canceled": return ("Canceled", .gray)
        default: return nil
        }
    }

    struct Detail: View {
        let id: String

        var body: some View {
            BillingSettings()
        }
    }
}

// MARK: - Store

@MainActor
@Observable
final class BillingSettingsStore {
    private(set) var billing: WSBilling?
    private(set) var usage: WSUsage?
    private(set) var error: String?
    private(set) var usageError: String?
    private(set) var forbidden = false
    var days = 30

    @ObservationIgnored private var api: APIClient?

    func attach(_ api: APIClient) { self.api = api }

    func load(admin: Bool) async {
        guard let api else { return }
        do {
            billing = try await api.get("v1/billing")
            error = nil
            forbidden = false
        } catch let failure as APIError where failure.status == 403 {
            forbidden = true
        } catch {
            if !error.isCancellation, billing == nil { self.error = error.userMessage }
        }
        if admin { await loadUsage() }
    }

    func loadUsage() async {
        guard let api else { return }
        let to = AppClock.now
        let from = Calendar.current.date(byAdding: .day, value: -days, to: to) ?? to
        let format = Date.ISO8601FormatStyle()
        do {
            usage = try await api.get("v1/billing/usage", query: [
                URLQueryItem(name: "from", value: from.formatted(format)),
                URLQueryItem(name: "to", value: to.formatted(format)),
            ])
            usageError = nil
        } catch {
            if !error.isCancellation { usageError = error.userMessage }
        }
    }
}
