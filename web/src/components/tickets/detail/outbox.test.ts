import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Message } from "@/lib/api/types";
import { qk } from "@/lib/queries";
import { queryClient } from "@/lib/queryClient";

const send = vi.fn();
vi.mock("@/lib/api/endpoints", () => ({ api: { tickets: { send: (...a: unknown[]) => send(...a) } } }));
vi.mock("@/components/ui/toast", () => ({ toast: { held: () => "toast", dismiss: () => {} } }));

const { asNote, hold, release, undo, useHeld, useUnsent } = await import("./outbox");

const temp = (id: string): Message =>
  ({
    id,
    ticket_id: "t1",
    kind: "reply",
    direction: "outbound",
    author: { type: "user", user: { id: "u1", name: "Maya", email: "maya@x.test", avatar_url: null }, contact: null },
    body_html: "<p>hi</p>",
    to: ["c@x.test"],
    cc: ["cc@x.test"],
    bcc: [],
    attachments: [],
    delivery_status: "pending",
    created_at: new Date().toISOString(),
  }) as unknown as Message;

const body = { kind: "reply" as const, body_html: "<p>hi</p>", cc: ["cc@x.test"], status: "solved" as const, mailbox_id: "mb2" };
const unsent = { html: "<p>hi</p>", cc: ["cc@x.test"], bcc: [], uploads: [] };
const list = () => queryClient.getQueryData<Message[]>(qk.messages("t1")) ?? [];

describe("outbox", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    send.mockReset();
    send.mockImplementation((_t: string, b: { kind: string }) => Promise.resolve({ ...temp("m1"), kind: b.kind, delivery_status: "sent" }));
    queryClient.setQueryData<Message[]>(qk.messages("t1"), []);
    useUnsent.setState({}, true);
  });
  afterEach(() => vi.useRealTimers());

  it("holds a reply and sends nothing until its window ends", async () => {
    hold(temp("tmp-a"), body, unsent, "u1", 10);
    expect(list()[0].delivery_status).toBe("scheduled");
    expect(useHeld.getState()["tmp-a"]).toBeGreaterThan(Date.now());
    vi.advanceTimersByTime(9_000);
    expect(send).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1_000);
    expect(send).toHaveBeenCalledWith("t1", body, false);
    await vi.advanceTimersByTimeAsync(0);
    expect(list().map((m) => m.id)).toEqual(["m1"]);
    expect(useHeld.getState()["tmp-a"]).toBeUndefined();
  });

  it("takes an undone reply back to its composer, unsent", () => {
    hold(temp("tmp-b"), body, unsent, "u1", 10);
    undo("tmp-b");
    vi.advanceTimersByTime(20_000);
    expect(send).not.toHaveBeenCalled();
    expect(list()).toEqual([]);
    expect(useUnsent.getState().t1).toEqual(unsent);
  });

  it("adds a held reply as a note, without recipients, address or status", () => {
    hold(temp("tmp-c"), body, unsent, "u1", 10);
    asNote("tmp-c");
    expect(send).toHaveBeenCalledWith("t1", { kind: "note", body_html: "<p>hi</p>", attachment_ids: undefined }, false);
    expect(list()[0]).toMatchObject({ kind: "note", delivery_status: "none", cc: [], to: [] });
    vi.advanceTimersByTime(20_000);
    expect(send).toHaveBeenCalledTimes(1);
  });

  it("sends at once with no window, and on demand", () => {
    hold(temp("tmp-d"), body, unsent, "u1", 0);
    expect(send).toHaveBeenCalledTimes(1);
    hold(temp("tmp-e"), body, unsent, "u1", 30);
    release("tmp-e");
    expect(send).toHaveBeenCalledTimes(2);
    release("tmp-e");
    expect(send).toHaveBeenCalledTimes(2);
  });

  it("keeps the note a reply was made from when the reply becomes a note, and sends its id with the reply", async () => {
    queryClient.setQueryData<Message[]>(qk.messages("t1"), [{ ...temp("n1"), kind: "note" }]);
    const fromNote = { ...unsent, fromNote: "n1" };
    hold(temp("tmp-f"), body, fromNote, "u1", 10);
    asNote("tmp-f");
    expect(send).not.toHaveBeenCalled();
    expect(list().map((m) => m.id)).toEqual(["n1"]);
    hold(temp("tmp-g"), body, fromNote, "u1", 10);
    undo("tmp-g");
    expect(useUnsent.getState().t1.fromNote).toBe("n1");
    const withNote = { ...body, from_note_id: "n1" };
    hold(temp("tmp-h"), withNote, fromNote, "u1", 10);
    vi.advanceTimersByTime(10_000);
    await vi.advanceTimersByTimeAsync(0);
    expect(send).toHaveBeenCalledWith("t1", withNote, false);
    expect(list().map((m) => [m.id, m.sent_as_reply_id ?? null])).toEqual([
      ["n1", "m1"],
      ["m1", null],
    ]);
  });
});
