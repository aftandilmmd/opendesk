// Tickets created from this tab, so the new ticket sound plays only for tickets someone
// else created: a customer, a teammate or an integration. ticket.created names no
// creator and can arrive before the create request answers, so a ticket that arrives
// while this tab is creating one is decided once that request has settled.

import type { Ticket } from "./api/types";

const own = new Set<string>();
let pending = 0;
let waiting: (() => void)[] = [];

/** Wraps a create request of this tab; the ticket it returns counts as created here. */
export async function creatingTicket<T extends { id: string }>(request: Promise<T>): Promise<T> {
  pending++;
  try {
    const t = await request;
    own.add(t.id);
    return t;
  } finally {
    pending--;
    if (pending === 0) {
      const run = waiting;
      waiting = [];
      for (const f of run) f();
    }
  }
}

/** Runs f now, or once the create requests of this tab have settled. */
export function afterOwnCreations(f: () => void) {
  if (pending === 0) f();
  else waiting.push(f);
}

/** Whether this tab created the ticket. */
export function createdHere(id: string): boolean {
  return own.has(id);
}

/**
 * Whether a new ticket plays the ticket sound for me: not a chat (it alerts on its own),
 * not spam, not already solved or closed, unassigned or assigned to me, and not one I
 * created here. ticket.created carries the ticket as it was created, before its first
 * message, so nothing about its messages is known yet.
 */
export function wantsTicketSound(t: Ticket, me: string, mine: (id: string) => boolean = createdHere): boolean {
  if (t.channel === "chat" || t.spam || t.status === "solved" || t.status === "closed") return false;
  if (t.assignee && t.assignee.id !== me) return false;
  return !mine(t.id);
}
