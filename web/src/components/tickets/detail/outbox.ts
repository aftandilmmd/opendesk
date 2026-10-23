import { create } from "zustand";
import { errorMessage } from "@/lib/api/client";
import { api, type SendMessageBody } from "@/lib/api/endpoints";
import type { Attachment, Message, Ticket, TicketDraft } from "@/lib/api/types";
import { qk } from "@/lib/queries";
import { queryClient as qc } from "@/lib/queryClient";
import { patchTicketEverywhere } from "@/lib/ticketCache";
import { i18n } from "@/i18n";
import { toast } from "@/components/ui/toast";
import { statusLabel } from "../bits";
import { applyPatch } from "../useTicketActions";

// A reply waits out the workspace's undo window (settings.undo_send_seconds) here, in the
// app and not on the server: nothing of it reaches the customer, an automation or a channel
// until it is sent. It lives outside the composer, so leaving the ticket keeps the countdown
// and the reply goes out, or comes back, wherever the agent is.

export const UNDO_SEND_DEFAULT = 5;
export const UNDO_SEND_CHOICES = [0, 5, 10, 20, 30] as const;

export type Upload = { key: string; file: File; status: "uploading" | "done" | "error"; attachment?: Attachment; preview?: string };

/** A reply taken back: what goes into its ticket's composer again. */
export type Unsent = {
  html: string;
  cc: string[];
  bcc: string[];
  mailboxId?: string;
  uploads: Upload[];
  /** The note this reply was made from (body.from_note_id): the server removes it as the reply is added. */
  fromNote?: string;
};

type Held = { temp: Message; body: SendMessageBody; unsent: Unsent; me: string; timer: ReturnType<typeof setTimeout>; toast: string | number };

const held = new Map<string, Held>();

/** When each held reply goes out, by its temporary message id. */
export const useHeld = create<Record<string, number>>(() => ({}));
/** Replies taken back, by ticket, until that ticket's composer takes them in. */
export const useUnsent = create<Record<string, Unsent>>(() => ({}));

function revoke(uploads: Upload[]) {
  uploads.forEach((u) => u.preview && URL.revokeObjectURL(u.preview));
}

/** Sends a reply or note now. The optimistic copy (temp) shows until the server's takes its place. */
export async function deliver(temp: Message, body: SendMessageBody, me: string, keepalive = false): Promise<boolean> {
  const tid = temp.ticket_id;
  qc.setQueryData<Message[]>(qk.messages(tid), (old) => old && [...old.filter((x) => x.id !== temp.id), temp]);
  const prevTicket = qc.getQueryData<Ticket>(qk.ticket(tid));
  if ((body.status || body.mailbox_id) && prevTicket)
    patchTicketEverywhere(qc, applyPatch(qc, prevTicket, { status: body.status, mailbox_id: body.mailbox_id }), me);
  // A reply going out clears the ticket's shared draft (contracts/api.md "Drafts").
  const prevDraft = body.kind === "reply" ? qc.getQueryData<TicketDraft | null>(qk.ticketDraft(tid)) : undefined;
  if (prevDraft) qc.setQueryData(qk.ticketDraft(tid), null);
  try {
    const m = await api.tickets.send(tid, body, keepalive);
    qc.setQueryData<Message[]>(qk.messages(tid), (old) => {
      if (!old) return old;
      // The note it was written from stays as a marker pointing at it.
      if (body.from_note_id) old = old.map((x) => (x.id === body.from_note_id ? { ...x, body_html: "", body_text: "", sent_as_reply_id: m.id } : x));
      // The socket may have delivered this message (and its delivery status) before
      // the response arrived; that copy is newer than the response.
      const live = old.find((x) => x.id === m.id);
      const rest = old.filter((x) => x.id !== temp.id && x.id !== m.id);
      return [...rest, live ?? m].sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at));
    });
    if (body.from_note_id) void qc.invalidateQueries({ queryKey: qk.activities(tid) });
    return true;
  } catch (e) {
    qc.setQueryData<Message[]>(qk.messages(tid), (old) =>
      old?.map((x) => (x.id === temp.id ? { ...x, delivery_status: "failed", delivery_error: errorMessage(e, "Not sent") } : x)),
    );
    if (prevTicket) patchTicketEverywhere(qc, prevTicket, me);
    if (prevDraft) qc.setQueryData(qk.ticketDraft(tid), prevDraft);
    return false;
  } finally {
    void qc.invalidateQueries({ queryKey: qk.counts });
  }
}

/** Holds a reply for `seconds` before sending it, with a way to take it back or keep it as a note. */
export function hold(temp: Message, body: SendMessageBody, unsent: Unsent, me: string, seconds: number) {
  if (seconds <= 0) {
    revoke(unsent.uploads);
    void deliver(temp, body, me);
    return;
  }
  const t = i18n.getFixedT(null, "inbox");
  const ms = seconds * 1000;
  const label = body.status
    ? t("outbox.sendingAndMark", { status: statusLabel[body.status].toLowerCase() })
    : t("outbox.sending");
  const id = toast.held(label, ms, { label: t("outbox.undo"), onClick: () => undo(temp.id) }, { label: t("outbox.asNote"), onClick: () => asNote(temp.id) });
  held.set(temp.id, { temp, body, unsent, me, timer: setTimeout(() => release(temp.id), ms), toast: id });
  useHeld.setState({ [temp.id]: Date.now() + ms });
  qc.setQueryData<Message[]>(qk.messages(temp.ticket_id), (old) => old && [...old, { ...temp, delivery_status: "scheduled" }]);
}

function take(tempId: string): Held | undefined {
  const h = held.get(tempId);
  if (!h) return undefined;
  held.delete(tempId);
  clearTimeout(h.timer);
  toast.dismiss(h.toast);
  useHeld.setState((s) => Object.fromEntries(Object.entries(s).filter(([k]) => k !== tempId)), true);
  return h;
}

/** Sends a held reply now. */
export function release(tempId: string, keepalive = false) {
  const h = take(tempId);
  if (!h) return;
  revoke(h.unsent.uploads);
  void deliver(h.temp, h.body, h.me, keepalive);
}

/** Takes a held reply back into its ticket's composer. */
export function undo(tempId: string) {
  const h = take(tempId);
  if (!h) return;
  qc.setQueryData<Message[]>(qk.messages(h.temp.ticket_id), (old) => old?.filter((x) => x.id !== tempId));
  useUnsent.setState({ [h.temp.ticket_id]: h.unsent });
}

/** Adds a held reply as an internal note instead: the customer never gets it. The status it
 * was to set went with answering the customer, so it stays as it is. A reply made from a
 * note leaves that note as it was. */
export function asNote(tempId: string) {
  const h = take(tempId);
  if (!h) return;
  revoke(h.unsent.uploads);
  if (h.unsent.fromNote) {
    qc.setQueryData<Message[]>(qk.messages(h.temp.ticket_id), (old) => old?.filter((x) => x.id !== tempId));
    return;
  }
  const note: Message = { ...h.temp, kind: "note", delivery_status: "none", to: [], cc: [], bcc: [], from_email: "", mailbox_id: null };
  void deliver(note, { kind: "note", body_html: h.body.body_html, attachment_ids: h.body.attachment_ids }, h.me);
}

if (typeof window !== "undefined") {
  // Leaving with a reply on hold asks first; leaving anyway sends it, as the agent meant.
  window.addEventListener("beforeunload", (e) => {
    if (held.size) e.preventDefault();
  });
  window.addEventListener("pagehide", () => {
    for (const id of [...held.keys()]) release(id, true);
  });
}
