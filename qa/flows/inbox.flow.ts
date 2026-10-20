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
