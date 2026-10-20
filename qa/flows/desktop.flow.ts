import { expect, test } from "../lib/proof.ts";

test.use({ target: "desktop" });

test("the inbox in the desktop app", async ({ page, proof }) => {
  await proof.open("/inbox/unassigned");
  const tickets = page.getByRole("listbox", { name: "Tickets" });
  await expect(tickets.getByRole("option").first()).toBeVisible();
  await proof.chapter("Desktop", "The inbox in the desktop window, then one ticket");
  await proof.shot("inbox", { caption: "The unassigned queue in the desktop window" });

  await tickets.getByRole("option", { name: /Pricing question/ }).click();
  await expect(page.getByRole("main").getByText("Is the Business plan billed per member").last()).toBeVisible();
  await proof.dwell();
  await proof.shot("ticket", { caption: "A ticket open in the desktop window" });
});
