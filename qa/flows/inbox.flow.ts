import { expect, test } from "../lib/proof.ts";

test("open a ticket from the unassigned queue", async ({ page, proof }) => {
  await proof.open("/inbox/unassigned");
  const tickets = page.getByRole("listbox", { name: "Tickets" });
  await expect(tickets.getByRole("option").first()).toBeVisible();
  await proof.chapter("Inbox", "The unassigned queue, then one ticket beside it");
  await proof.shot("unassigned", { caption: "The unassigned queue" });

  await tickets.getByRole("option", { name: /Pricing question/ }).click();
  await expect(page.getByRole("main").getByText("Is the Business plan billed per member").last()).toBeVisible();
  await proof.dwell();
  await proof.shot("ticket", { caption: "A ticket open beside the queue" });
});

test("change the contact on a ticket", async ({ page, proof }) => {
  await proof.open("/inbox/unassigned");
  const tickets = page.getByRole("listbox", { name: "Tickets" });
  const exportTicket = tickets.getByRole("option", { name: /Can't export notebook to PDF/ });
  await expect(exportTicket).toBeVisible();
  await exportTicket.click();

  const main = page.getByRole("main");
  await expect(page.getByRole("heading", { name: "Can't export notebook to PDF" })).toBeVisible();
  const ollieNotice = page.getByRole("button", { name: "Not now" });
  if (await ollieNotice.isVisible()) await ollieNotice.click();
  const changeContact = main.getByRole("button", { name: "Change contact" });
  await expect(changeContact).toBeVisible();
  await changeContact.click();

  const search = page.getByRole("combobox", { name: "Search contacts" });
  await expect(search).toBeVisible();
  await search.pressSequentially("Dana", { delay: 60 });
  const dana = page.getByRole("option", { name: /Dana Whitfield/ });
  await expect(dana).toBeVisible();
  await proof.chapter("Change contact", "Find another contact and make them the ticket's customer");
  await proof.shot("contact-picker", { caption: "Search results for the new contact" });

  await dana.click();
  await expect(main.getByText("Dana Whitfield", { exact: true }).last()).toBeVisible();
  await expect(main.getByText(/changed the contact from .* to Dana Whitfield/)).toBeVisible();
  await main.getByRole("heading", { name: "Contact", exact: true }).scrollIntoViewIfNeeded();
  await proof.dwell();
  await proof.shot("contact-changed", { caption: "Dana Whitfield is the customer now, and the timeline records the change" });
});

test("a live chat keeps the visitor who started it", async ({ page, proof }) => {
  await proof.open("/inbox/unassigned/1086");
  await expect(page.getByRole("heading", { name: "Pricing question" })).toBeVisible();
  const main = page.getByRole("main");
  const contact = main.getByRole("heading", { name: "Contact", exact: true });
  await contact.scrollIntoViewIfNeeded();
  await expect(contact).toBeVisible();
  await expect(main.getByRole("button", { name: "Change contact" })).toHaveCount(0);
  await proof.dwell();
  await proof.shot("chat-contact", { caption: "A live chat's contact has no Change contact button" });
});

test("an agent edits and deletes an internal note", async ({ page, proof }) => {
  await proof.open("/inbox/unassigned/1086");
  await expect(page.getByRole("heading", { name: "Pricing question" })).toBeVisible();
  await proof.chapter("Add an internal note", "Write a team-only note on a ticket");

  await page.getByRole("radio", { name: "Note" }).click();
  await page.getByRole("textbox", { name: "Note" }).fill("Follow-up on the billing question.");
  await page.getByRole("button", { name: "Add note", exact: true }).click();

  const note = page.getByRole("article", { name: "Note from Maya Chen" });
  await expect(note.getByText("Follow-up on the billing question.", { exact: true })).toBeVisible();
  await note.getByRole("button", { name: "Note actions" }).click();
  await page.getByRole("menuitem", { name: "Edit note" }).click();
  const ollieNotice = page.getByRole("button", { name: "Not now" });
  if (await ollieNotice.isVisible()) await ollieNotice.click();
  const edit = note.getByRole("textbox", { name: "Edit note" });
  await edit.fill("Confirmed billing is per workspace, ");
  await edit.pressSequentially("@pri", { delay: 60 });
  const mentions = page.getByRole("listbox", { name: "Mention a teammate" });
  await expect(mentions.getByText("Priya Raman")).toBeVisible();
  await proof.shot("note-edit-mention", { caption: "Editing the note, with @mentions as in the composer" });
  await page.keyboard.press("Enter");
  await expect(edit.getByText("@Priya Raman")).toBeVisible();
  await note.getByRole("button", { name: "Save" }).click();
  await expect(note.getByText("Confirmed billing is per workspace,", { exact: false })).toBeVisible();
  await expect(note.getByText("@Priya Raman")).toBeVisible();
  await expect(note.getByText("Edited", { exact: true })).toBeVisible();
  await proof.chapter("Edit the note", "Correct the note, mention a teammate and see its edited marker");
  await proof.dwell();
  await proof.shot("note-edited", { target: note, caption: "The corrected note with its mention, marked as edited" });

  await note.getByRole("button", { name: "Note actions" }).click();
  await page.getByRole("menuitem", { name: "Delete note" }).click();
  const dialog = page.getByRole("alertdialog");
  await expect(dialog.getByText("The note is hidden from the conversation. Admins can still read it and bring it back.")).toBeVisible();
  await proof.chapter("Delete the note", "Confirm deletion and see the note leave a marker in the timeline");
  await dialog.getByRole("button", { name: "Delete", exact: true }).click();
  const activity = page.getByText("Maya Chen deleted an internal note", { exact: true });
  await expect(activity).toBeVisible();
  const marker = page.getByRole("article", { name: "Deleted message from Maya Chen" });
  await expect(marker).toBeVisible();
  if (await ollieNotice.isVisible()) await ollieNotice.click();
  await proof.dwell();
  await proof.shot("note-deleted", { caption: "The deleted note stays as a marker, recorded in the timeline" });
});

test("a reply drafted over MCP waits in the composer, to edit and send as your own", async ({ page, proof }) => {
  await proof.open("/inbox/mine/1072");
  await expect(page.getByRole("heading", { name: "SSO login loops back to sign-in page" })).toBeVisible();
  const ollieNotice = page.getByRole("button", { name: "Not now" });

  const bar = page.getByRole("status", { name: "Shared draft" });
  await expect(bar).toContainText("Draft by Claude");
  const reply = page.getByRole("textbox", { name: "Reply" });
  await expect(reply).toContainText("Hi Dana,");
  await expect(reply).toContainText("added the new certificate fingerprint");
  if (await ollieNotice.isVisible()) await ollieNotice.click();
  await proof.chapter("A draft waits on the ticket", "An AI agent staged it over MCP; the team sees the same text in the composer");
  await proof.shot("shared-draft-in-composer", { caption: "The draft an AI agent staged over MCP, already in the reply box, with who staged it" });

  await reply.click();
  await page.keyboard.press("End");
  await page.keyboard.press("Enter");
  await page.keyboard.type("Best, Maya", { delay: 60 });
  await expect(reply).toContainText("Best, Maya");
  await proof.chapter("Edit and send as yourself", "The reply goes out as Maya's, and the draft is gone for everyone");
  await page.getByRole("button", { name: "Send", exact: true }).click();

  const sent = page.getByRole("article", { name: "Message from Maya Chen" }).last();
  await expect(sent.getByText("Best, Maya", { exact: false })).toBeVisible();
  await expect(bar).toHaveCount(0);
  if (await ollieNotice.isVisible()) await ollieNotice.click();
  await proof.dwell();
  await proof.shot("shared-draft-sent", { caption: "Sent as Maya's own reply; the shared draft is cleared" });
});

test("a draft staged while you are writing waits with Use it, and can be discarded", async ({ page, proof }) => {
  await proof.open("/inbox/mine/1068");
  await expect(page.getByRole("heading", { name: "Refund for duplicate annual charge" })).toBeVisible();
  const ollieNotice = page.getByRole("button", { name: "Not now" });

  const reply = page.getByRole("textbox", { name: "Reply" });
  await reply.click();
  await page.keyboard.type("Hi Tomás, sorry for the wait.", { delay: 40 });
  if (await ollieNotice.isVisible()) await ollieNotice.click();
  await proof.chapter("A draft arrives while you write", "An AI agent stages one over MCP; your own text stays, the draft waits");
  // The mock's stand-in for an AI client calling the MCP tool draft_reply.
  await page.evaluate(() => {
    const mock = (window as unknown as { __odMock?: { draft: (ticket: string, text: string) => void } }).__odMock;
    mock?.draft(
      "1068",
      "Hi Tomás,\n\nSorry for the silence. The refund of €4,320 was issued on our side on the day I wrote, and the payment provider confirms it left for your bank on the next business day. Banks usually show it within 5 to 10 business days, so it should appear on your statement this week.\n\nIf it is not there by Friday, send me the last four digits of the card and I will chase it with the provider.",
    );
  });
  const bar = page.getByRole("status", { name: "Shared draft" });
  await expect(bar).toContainText("Claude drafted a reply");
  await expect(bar.getByRole("button", { name: "Use it" })).toBeVisible();
  await expect(reply).toContainText("sorry for the wait.");
  await proof.shot("shared-draft-waiting", { caption: "Your own text stays; the draft waits above the composer with Use it" });

  await bar.getByRole("button", { name: "Use it" }).click();
  const dialog = page.getByRole("alertdialog");
  await expect(dialog.getByText("The draft by Claude replaces what you have written.")).toBeVisible();
  await dialog.getByRole("button", { name: "Replace", exact: true }).click();
  await expect(reply).toContainText("confirms it left for your bank");
  await expect(bar).toContainText("Draft by Claude");
  await proof.chapter("Take it, or discard it", "Use it puts the draft in the reply box; Discard removes it for everyone");
  await proof.shot("shared-draft-taken", { caption: "The draft replaced your text and is in the reply box" });

  await bar.getByRole("button", { name: "Discard" }).click();
  await expect(bar).toHaveCount(0);
  await expect(reply).not.toContainText("confirms it left for your bank");
  await proof.dwell();
  await proof.shot("shared-draft-discarded", { caption: "Discarded: the bar is gone and the reply box is empty again" });
});

test("play a visitor's voice message in a live chat", async ({ page, proof }) => {
  await proof.open("/inbox/unassigned");
  const tickets = page.getByRole("listbox", { name: "Tickets" });
  await tickets.getByRole("option", { name: /Feature request: nested tags/ }).click();
  const main = page.getByRole("main");
  const voice = main.getByLabel("Voice message.wav", { exact: true });
  await expect(voice).toBeVisible();
  await expect(main.getByRole("link", { name: "Download Voice message.wav" })).toBeVisible();
  await proof.chapter("Voice messages", "A visitor's recording plays in the thread, with a download link");
  await voice.scrollIntoViewIfNeeded();
  await proof.dwell();
  await proof.shot("voice-message", { caption: "The visitor's voice message under their messages" });
});
