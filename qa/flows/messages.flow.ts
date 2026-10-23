import type { Page } from "@playwright/test";
import { expect, test } from "../lib/proof.ts";

/** Writes in the reply box and presses its Send button. */
async function reply(page: Page, text: string) {
  const box = page.getByRole("textbox", { name: "Reply", exact: true });
  await box.click();
  await box.pressSequentially(text, { delay: 30 });
  await page.getByRole("button", { name: "Send", exact: true }).last().click();
}

/** Adds an internal note from the reply box. */
async function note(page: Page, text: string) {
  await page.getByRole("radio", { name: "Note", exact: true }).click();
  const box = page.getByRole("textbox", { name: "Note", exact: true });
  await box.click();
  await box.pressSequentially(text, { delay: 30 });
  await page.getByRole("button", { name: "Add note", exact: true }).last().click();
}

test("a reply waits a few seconds, to take back or turn into an internal note", async ({ page, proof }) => {
  await proof.open("/inbox/unassigned/1071");
  await expect(page.getByRole("heading", { name: "Can't export notebook to PDF" })).toBeVisible();
  await proof.chapter("Undo send", "A reply waits before it goes out, with a way back");

  await reply(page, "Internal: check the export logs with engineering first.");
  const held = page.getByRole("article", { name: "Message from Maya Chen" }).last();
  await expect(held.getByText(/Sending in \d+s/)).toBeVisible();
  await proof.shot("held", { caption: "The reply on hold: its countdown, and turn into internal note, undo and send now" });

  await held.getByRole("button", { name: "Undo", exact: true }).click();
  await expect(page.getByRole("textbox", { name: "Reply", exact: true })).toContainText("check the export logs");
  await proof.shot("undone", { caption: "Undo puts the reply back in the reply box, and nothing was sent" });

  await page.getByRole("button", { name: "Send", exact: true }).last().click();
  await page.getByRole("article", { name: "Message from Maya Chen" }).last().getByRole("button", { name: "Turn into internal note" }).click();
  const made = page.getByRole("article", { name: "Note from Maya Chen" }).last();
  await expect(made.getByText("check the export logs", { exact: false })).toBeVisible();
  await proof.dwell();
  await proof.shot("made-note", { target: made, caption: "Turned into an internal note: the customer never got it" });
});

test("a reply that mentions a teammate asks before it goes out", async ({ page, proof }) => {
  await proof.open("/inbox/unassigned/1071");
  await expect(page.getByRole("heading", { name: "Can't export notebook to PDF" })).toBeVisible();
  await proof.chapter("Mentions", "Naming a teammate in a reply is usually a note written in the wrong box");

  await reply(page, "@Priya can you look at the export logs?");
  const warn = page.getByRole("alert").filter({ hasText: "This reply mentions Priya Raman" });
  await expect(warn).toBeVisible();
  await proof.shot("mention-warning", { caption: "The reply waits: it mentions Priya, and the customer would read it" });

  await warn.getByRole("button", { name: "Turn into internal note" }).click();
  const made = page.getByRole("article", { name: "Note from Maya Chen" }).last();
  await expect(made.getByText("can you look at the export logs", { exact: false })).toBeVisible();
  await proof.dwell();
  await proof.shot("mention-note", { target: made, caption: "Added as an internal note instead" });
});

test("turn a note into a reply, with a marker where the note was", async ({ page, proof }) => {
  await proof.open("/inbox/unassigned/1071");
  await expect(page.getByRole("heading", { name: "Can't export notebook to PDF" })).toBeVisible();
  await proof.chapter("Note to reply", "A note written for the team goes to the customer after all");

  await note(page, "Hi Elena, the fix for large exports ships tomorrow.");
  const written = page.getByRole("article", { name: "Note from Maya Chen" }).last();
  await expect(written.getByText("the fix for large exports", { exact: false })).toBeVisible();
  await written.getByRole("button", { name: "Note actions" }).click();
  await expect(page.getByRole("menuitem", { name: "Turn into a reply" })).toBeVisible();
  await proof.shot("note-menu", { caption: "Turn into a reply, first in the note's menu" });

  await page.getByRole("menuitem", { name: "Turn into a reply" }).click();
  await expect(page.getByText("This note goes to the customer as a reply.", { exact: false })).toBeVisible();
  await proof.shot("note-in-reply-box", { caption: "The note in the reply box, saying it goes to the customer and the note is replaced" });

  await page.getByRole("button", { name: "Send", exact: true }).last().click();
  await page.getByRole("article", { name: "Message from Maya Chen" }).last().getByRole("button", { name: "Send now" }).click();
  const marker = page.getByRole("article", { name: "Note from Maya Chen, sent as a reply" });
  await expect(marker).toBeVisible();
  await expect(page.getByRole("article", { name: "Message from Maya Chen" }).last().getByText("the fix for large exports", { exact: false })).toBeVisible();
  await proof.dwell();
  await proof.shot("sent-as-reply", { caption: "The reply at the end, and where the note was, a marker with Show reply" });
});

test("turn a sent chat reply into an internal note", async ({ page, proof }) => {
  await proof.open("/inbox/unassigned/1081");
  await expect(page.getByRole("heading", { name: "Request: dark mode for the web clipper" })).toBeVisible();
  await proof.chapter("Take back a chat reply", "A chat reply already sent leaves the customer's chat and stays as a note");

  await reply(page, "Internal: dark mode is on the roadmap, no date to promise.");
  await page.getByRole("article", { name: "Message from Maya Chen" }).last().getByRole("button", { name: "Send now" }).click();
  const sent = page.getByRole("article", { name: "Message from Maya Chen" }).last();
  await expect(sent.getByRole("button", { name: "Send now" })).toHaveCount(0);
  await sent.getByRole("button", { name: "Message actions" }).click();
  await page.getByRole("menuitem", { name: "Turn into internal note" }).click();
  const dialog = page.getByRole("alertdialog");
  await expect(dialog.getByText("They may already have read it.", { exact: false })).toBeVisible();
  await proof.shot("retract-confirm", { caption: "Turning a sent chat reply into a note, and what that means for the customer" });

  await dialog.getByRole("button", { name: "Turn into note", exact: true }).click();
  await expect(page.getByText("Maya Chen turned a sent reply into an internal note")).toBeVisible();
  await proof.dwell();
  await proof.shot("retracted", { caption: "The reply is an internal note now, recorded in the timeline" });
});

test("delete a message, read and restore it as an admin, or delete it permanently", async ({ page, proof }) => {
  await proof.open("/inbox/unassigned/1071");
  await expect(page.getByRole("heading", { name: "Can't export notebook to PDF" })).toBeVisible();
  await proof.chapter("Delete", "A deleted message leaves a marker; admins can read, restore or purge it");

  const customer = page.getByRole("article", { name: "Message from Elena Rossi" }).first();
  await customer.getByRole("button", { name: "Message actions" }).click();
  await page.getByRole("menuitem", { name: "Delete message" }).click();
  await page.getByRole("alertdialog").getByRole("button", { name: "Delete", exact: true }).click();
  const marker = page.getByRole("article", { name: "Deleted message from Elena Rossi" });
  await expect(marker).toBeVisible();
  await proof.shot("deleted", { target: marker, caption: "The marker: who deleted the message, with show, delete permanently and restore" });

  await marker.getByRole("button", { name: "Show" }).click();
  await expect(marker.getByText("When I export", { exact: false })).toBeVisible();
  await proof.shot("deleted-shown", { target: marker, caption: "An admin reads what it said" });

  await marker.getByRole("button", { name: "Delete permanently" }).click();
  const dialog = page.getByRole("alertdialog");
  await expect(dialog.getByText("cannot be restored", { exact: false })).toBeVisible();
  await proof.shot("purge-confirm", { caption: "Deleting it permanently: text, files and the original email go for good" });

  await dialog.getByRole("button", { name: "Delete permanently" }).click();
  await expect(marker.getByText("Content removed for good")).toBeVisible();
  await proof.dwell();
  await proof.shot("purged", { target: marker, caption: "The marker stays, its content removed for good" });
});

test("a deleted note comes back when an admin restores it", async ({ page, proof }) => {
  await proof.open("/inbox/unassigned/1071");
  await expect(page.getByRole("heading", { name: "Can't export notebook to PDF" })).toBeVisible();
  await proof.chapter("Restore", "A deleted note, brought back");

  await note(page, "The customer pasted a card number above, removing.");
  const written = page.getByRole("article", { name: "Note from Maya Chen" }).last();
  await written.getByRole("button", { name: "Note actions" }).click();
  await page.getByRole("menuitem", { name: "Delete note" }).click();
  await page.getByRole("alertdialog").getByRole("button", { name: "Delete", exact: true }).click();
  const marker = page.getByRole("article", { name: "Deleted message from Maya Chen" });
  await expect(marker.getByText("Maya Chen deleted their note")).toBeVisible();
  await proof.shot("note-deleted-marker", { target: marker, caption: "Maya deleted her note: a marker stays" });

  await marker.getByRole("button", { name: "Restore" }).click();
  await expect(page.getByRole("article", { name: "Note from Maya Chen" }).last().getByText("pasted a card number", { exact: false })).toBeVisible();
  await expect(page.getByText("Maya Chen restored a deleted message")).toBeVisible();
  await proof.dwell();
  await proof.shot("note-restored", { caption: "The note back in place, and the restore in the timeline" });
});
