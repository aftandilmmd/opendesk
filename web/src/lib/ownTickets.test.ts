import { describe, expect, it } from "vitest";
import { afterOwnCreations, createdHere, creatingTicket, wantsTicketSound } from "./ownTickets";
import { ticket } from "./test/fixtures";

describe("wantsTicketSound", () => {
  const none = () => false;
  it("plays for a new ticket someone else created, before its first message is known", () => {
    expect(wantsTicketSound(ticket({ last_customer_message_at: null }), "u1", none)).toBe(true);
    expect(wantsTicketSound(ticket({ channel: "api" }), "u1", none)).toBe(true);
    expect(wantsTicketSound(ticket({ assignee: { id: "u1", name: "Me", email: "me@example.com", avatar_url: null } }), "u1", none)).toBe(true);
  });
  it("stays quiet for chats, spam, closed tickets, someone else's and my own", () => {
    expect(wantsTicketSound(ticket({ channel: "chat" }), "u1", none)).toBe(false);
    expect(wantsTicketSound(ticket({ spam: true }), "u1", none)).toBe(false);
    expect(wantsTicketSound(ticket({ status: "solved" }), "u1", none)).toBe(false);
    expect(wantsTicketSound(ticket({ assignee: { id: "u2", name: "Maya", email: "maya@example.com", avatar_url: null } }), "u1", none)).toBe(false);
    expect(wantsTicketSound(ticket({ id: "t9" }), "u1", (id) => id === "t9")).toBe(false);
  });
});

describe("creatingTicket", () => {
  it("decides a ticket that arrives during a create once the request settles", async () => {
    let answer!: (t: { id: string }) => void;
    const request = creatingTicket(new Promise<{ id: string }>((r) => (answer = r)));
    const heard: boolean[] = [];
    // ticket.created arrives before the response.
    afterOwnCreations(() => heard.push(wantsTicketSound(ticket({ id: "mine-1" }), "u1")));
    expect(heard).toEqual([]);
    answer({ id: "mine-1" });
    await request;
    expect(createdHere("mine-1")).toBe(true);
    expect(heard).toEqual([false]);
    // With nothing being created, it decides at once.
    afterOwnCreations(() => heard.push(wantsTicketSound(ticket({ id: "theirs" }), "u1")));
    expect(heard).toEqual([false, true]);
  });
  it("lets waiting tickets through when a create fails", async () => {
    let fail!: (e: Error) => void;
    const request = creatingTicket(new Promise<{ id: string }>((_, r) => (fail = r)));
    const heard: string[] = [];
    afterOwnCreations(() => heard.push("decided"));
    fail(new Error("422"));
    await expect(request).rejects.toThrow("422");
    expect(heard).toEqual(["decided"]);
  });
});
