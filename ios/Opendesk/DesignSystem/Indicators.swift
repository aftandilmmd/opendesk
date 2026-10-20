import SwiftUI

// One family of indicators for status, priority, severity, SLA and channel,
// drawn on the web's 16pt grid with a 1.5 stroke (web components/indicators).

private let stroke: CGFloat = 1.5

/// Rings that fill as the ticket moves along, in the status tone.
struct StatusIcon: View {
    let status: TicketStatus
    var size: CGFloat = 14

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 16
            let color = status.tone.solid
            func circle(_ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: (8 - r) * s, y: (8 - r) * s, width: 2 * r * s, height: 2 * r * s))
            }
            switch status {
            case .open:
                context.stroke(circle(5.75), with: .color(color), lineWidth: stroke * s)
                context.fill(circle(2.25), with: .color(color))
            case .pending:
                context.stroke(circle(5.75), with: .color(color), lineWidth: stroke * s)
                var half = Path()
                half.move(to: CGPoint(x: 8 * s, y: 4.25 * s))
                half.addArc(center: CGPoint(x: 8 * s, y: 8 * s), radius: 3.75 * s, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
                half.closeSubpath()
                context.fill(half, with: .color(color))
            case .onHold:
                context.stroke(circle(5.75), with: .color(color), style: StrokeStyle(lineWidth: stroke * s, dash: [2.4 * s, 1.9 * s]))
                var bars = Path()
                bars.move(to: CGPoint(x: 6.6 * s, y: 6 * s)); bars.addLine(to: CGPoint(x: 6.6 * s, y: 10 * s))
                bars.move(to: CGPoint(x: 9.4 * s, y: 6 * s)); bars.addLine(to: CGPoint(x: 9.4 * s, y: 10 * s))
                context.stroke(bars, with: .color(color), style: StrokeStyle(lineWidth: stroke * s, lineCap: .round))
            case .solved, .closed:
                context.fill(circle(6.5), with: .color(color))
                var check = Path()
                check.move(to: CGPoint(x: 5.4 * s, y: 8.2 * s))
                check.addLine(to: CGPoint(x: 7.2 * s, y: 9.95 * s))
                check.addLine(to: CGPoint(x: 10.7 * s, y: 6.25 * s))
                context.stroke(check, with: .color(Theme.surface), style: StrokeStyle(lineWidth: stroke * s, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(status.title)
    }
}

/// Three signal bars that rise and warm with priority; urgent is a filled square with an exclamation.
struct PriorityIcon: View {
    let priority: Priority
    var size: CGFloat = 14

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 16
            if priority == .urgent {
                let box = Path(roundedRect: CGRect(x: 1.5 * s, y: 1.5 * s, width: 13 * s, height: 13 * s), cornerRadius: 3 * s)
                context.fill(box, with: .color(Tone.red.solid))
                var bang = Path()
                bang.move(to: CGPoint(x: 8 * s, y: 4.6 * s)); bang.addLine(to: CGPoint(x: 8 * s, y: 8.7 * s))
                context.stroke(bang, with: .color(.white), style: StrokeStyle(lineWidth: 1.75 * s, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: 7 * s, y: 10.1 * s, width: 2 * s, height: 2 * s)), with: .color(.white))
                return
            }
            let level = priority == .low ? 1 : priority == .normal ? 2 : 3
            for i in 0 ..< 3 {
                let rect = CGRect(x: (2.25 + CGFloat(i) * 4.25) * s, y: (10 - CGFloat(i) * 3.5) * s, width: 3 * s, height: (4 + CGFloat(i) * 3.5) * s)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.9 * s), with: .color(i < level ? priority.tone.solid : Theme.lineStrong))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(priority.title) priority")
    }
}

/// A compact mono chip, "S1" to "S4", in the level's tone.
struct SeverityChip: View {
    let severity: Severity

    var body: some View {
        Text(severity.short)
            .font(ODFont.mono(10, weight: .semibold))
            .foregroundStyle(severity.tone.text)
            .frame(minWidth: 22, minHeight: 16)
            .padding(.horizontal, 3)
            .background(severity.tone.soft, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityLabel(severity.title)
    }
}

/// A soft tinted pill with an optional leading glyph.
struct TonePill<Leading: View>: View {
    let text: String
    let tone: Tone
    var height: CGFloat = 20
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(spacing: 4) {
            leading()
            Text(text)
                .font(ODFont.sans(11.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tone.text)
        .padding(.leading, 5)
        .padding(.trailing, 7)
        .frame(height: height)
        .background(tone.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
    }
}

extension TonePill where Leading == EmptyView {
    init(text: String, tone: Tone, height: CGFloat = 20) {
        self.init(text: text, tone: tone, height: height, leading: { EmptyView() })
    }
}

struct StatusPill: View {
    let status: TicketStatus

    var body: some View {
        TonePill(text: status.title, tone: status.tone) { StatusIcon(status: status, size: 12) }
    }
}

struct PriorityPill: View {
    let priority: Priority

    var body: some View {
        TonePill(text: priority.title, tone: priority.tone) { PriorityIcon(priority: priority, size: 12) }
    }
}

/// SLA only when it matters: due soon or breached, with the time left (or over).
struct SLAPill: View {
    let state: SLAState
    var now: Date = AppClock.now

    var body: some View {
        let left = state.due.timeIntervalSince(now) / 60
        let label = left < 0 ? "\(Format.minutes(-left)) over" : Format.minutes(left)
        let tone: Tone? = state.kind == .breached ? .red : state.kind == .dueSoon ? .amber : nil
        HStack(spacing: 4) {
            Circle().fill(tone?.solid ?? Tone.green.solid).frame(width: 6, height: 6)
            Text(label).font(ODFont.mono(10.5)).monospacedDigit()
        }
        .foregroundStyle(tone?.text ?? Theme.fg3)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(tone?.soft ?? .clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityLabel(state.isFirstResponse ? "First response \(label)" : "Resolution \(label)")
    }
}

/// A label: a coloured dot and its name.
struct LabelChip: View {
    let name: String
    var color: String?
    var removable = false
    var onRemove: (() -> Void)?

    var body: some View {
        let tone = Tone(label: color)
        HStack(spacing: 5) {
            Circle().fill(tone.solid).frame(width: 7, height: 7)
            Text(name).font(ODFont.sans(11.5, weight: .medium)).lineLimit(1)
            if removable {
                Button { onRemove?() } label: {
                    Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(name)")
            }
        }
        .foregroundStyle(Theme.fg2)
        .padding(.horizontal, 7)
        .frame(height: 21)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Marks a ticket from the website chat widget, so it is never mistaken for email.
struct LiveChatBadge: View {
    var urgent = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bubble.left.fill").font(.system(size: 8.5))
            Text("Live chat").font(ODFont.sans(10.5, weight: .medium))
        }
        .foregroundStyle(urgent ? Tone.red.text : Tone.blue.text)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(urgent ? Tone.red.soft : Tone.blue.soft, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// A pulsing dot, still under Reduce Motion.
struct PingDot: View {
    var color: Color
    var size: CGFloat = 6
    @State private var ping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle().fill(color).frame(width: size, height: size)
                    .scaleEffect(ping ? 2.4 : 1)
                    .opacity(ping ? 0 : 0.7)
            }
            Circle().fill(color).frame(width: size, height: size)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { ping = true }
        }
    }
}

/// "Waiting 3m 12s" (urgent red, ticking) or "<bot> is replying" (calm violet).
struct WaitPill: View {
    let wait: ChatWait
    var compact = false
    /// The bot writing the live reply (`ai.reply.started`), when one is streaming.
    var botName: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            switch wait.state {
            case .ollie:
                HStack(spacing: 5) {
                    PingDot(color: Tone.violet.solid)
                    Text("\(botName.flatMap { $0.isEmpty ? nil : $0 } ?? "Ollie") is replying").font(ODFont.sans(11, weight: .medium))
                }
                .foregroundStyle(Tone.violet.text)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Tone.violet.soft, in: Capsule())
            case .urgent:
                let elapsed = ChatWait.format(AppClock.now(at: context.date).timeIntervalSince(wait.since))
                HStack(spacing: 5) {
                    PingDot(color: .white)
                    Text(compact ? elapsed : "Waiting \(elapsed)")
                        .font(ODFont.mono(compact ? 10.5 : 11, weight: .medium))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Tone.red.solid, in: Capsule())
                .accessibilityLabel("Customer waiting for \(elapsed)")
            }
        }
    }
}

/// `#1234` in mono.
struct TicketNumber: View {
    let number: Int

    var body: some View {
        Text(verbatim: "#\(number)")
            .font(ODFont.mono(11.5))
            .monospacedDigit()
            .foregroundStyle(Theme.fg3)
    }
}
