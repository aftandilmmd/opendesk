import SwiftUI

/// One ticket in the list, as the web's compact row: status and priority in
/// a left column, contact and time on top, subject, then the preview and
/// pills. Awaiting a reply reads bolder; a waiting chat washes red.
struct TicketRow: View {
    let ticket: Ticket
    var viewers: [PresenceViewer] = []
    var agentOn = false
    var hideAssignee = false
    /// The bot streaming a reply on this chat right now, if any.
    var replyingBot: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: AppClock.now(at: context.date))
        }
    }

    private func content(now: Date) -> some View {
        let wait = ChatWait.of(ticket, agentOn: agentOn, now: now)
        let urgent = wait?.state == .urgent && ticket.assignee == nil
        let unread = ticket.awaitingReply || wait != nil
        let sla = SLAState.of(ticket, now: now)
        let aiSet = ticket.custom["ai_decisions"]?["fields"]?["priority"]?["applied"]?.bool ?? (ticket.custom["ai_triaged_at"] != nil)

        return HStack(alignment: .top, spacing: 11) {
            VStack(spacing: 8) {
                StatusIcon(status: ticket.status, size: 15)
                ZStack(alignment: .topTrailing) {
                    PriorityIcon(priority: ticket.priority, size: 15)
                    if aiSet {
                        OllieMark(size: 9, eyes: false)
                            .offset(x: 5, y: -5)
                            .accessibilityLabel("Set by Ollie")
                    }
                }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(ticket.contactName)
                        .font(ODFont.sans(14, weight: unread ? .semibold : .regular))
                        .foregroundStyle(unread ? Theme.fg : Theme.fg2)
                        .lineLimit(1)
                    if ticket.channel == .chat {
                        LiveChatBadge(urgent: urgent)
                    } else if ticket.channel != .email {
                        Image(systemName: ticket.channel.symbol).font(.system(size: 10)).foregroundStyle(Theme.fg3)
                    }
                    if !viewers.isEmpty {
                        PresenceStack(viewers: viewers, size: 16)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer(minLength: 4)
                    if !hideAssignee, let assignee = ticket.assignee {
                        Avatar(name: assignee.displayName, url: assignee.avatarURL, seed: assignee.id, size: 18)
                    }
                    Text(Format.relShort(ticket.lastMessageAt, now: now))
                        .font(ODFont.mono(11))
                        .monospacedDigit()
                        .foregroundStyle(Theme.fg3)
                }

                HStack(spacing: 6) {
                    if let severity = ticket.severity { SeverityChip(severity: severity) }
                    Text(ticket.displaySubject)
                        .font(ODFont.sans(14, weight: unread ? .medium : .regular))
                        .foregroundStyle(Theme.fg)
                        .lineLimit(1)
                }

                if !ticket.lastMessagePreview.isEmpty {
                    Text(ticket.lastMessagePreview)
                        .font(ODFont.sans(13))
                        .foregroundStyle(Theme.fg3)
                        .lineLimit(2)
                }

                HStack(spacing: 5) {
                    TicketNumber(number: ticket.number)
                    if let wait { WaitPill(wait: wait, compact: true, botName: replyingBot) }
                    if let sla, sla.kind != .onTrack { SLAPill(state: sla, now: now) }
                    if ticket.isSnoozed, let until = ticket.snoozedUntil {
                        TonePill(text: Calendar.current.isDate(until, inSameDayAs: now) ? "Until \(Format.clock(until))" : "Until \(Format.shortDate(until, now: now))", tone: .violet) {
                            Image(systemName: "alarm").font(.system(size: 9))
                        }
                    }
                    ForEach(ticket.tags.prefix(2)) { tag in
                        LabelChip(name: tag.name, color: tag.color)
                    }
                    if ticket.tags.count > 2 {
                        Text("+\(ticket.tags.count - 2)").font(ODFont.mono(10.5)).foregroundStyle(Theme.fg3)
                    }
                }
                .padding(.top, 3)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .background {
            if urgent {
                HStack(spacing: 0) {
                    Rectangle().fill(Tone.red.solid).frame(width: 2.5)
                    Tone.red.soft
                }
            }
        }
        .overlay(alignment: .bottom) { Hairline(inset: 40) }
        .livePulse(ticket.updatedAt)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(unread ? "Waiting for a reply" : "")
    }
}
