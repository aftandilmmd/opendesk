import { expect, test } from "../lib/proof.ts";

test("a new unassigned ticket in the notifications panel", async ({ page, proof }) => {
  await proof.open("/inbox/unassigned");
  await expect(page.getByRole("listbox", { name: "Tickets" }).getByRole("option").first()).toBeVisible();
  await proof.chapter("New tickets", "Nobody is assigned, so the team hears about it");

  await page.getByRole("button", { name: /^Notifications/ }).click();
  const note = page.getByRole("button", { name: /New ticket from/ }).first();
  await expect(note).toBeVisible();
  await proof.dwell();
  await proof.shot("panel", { caption: "A new ticket nobody is assigned to, in the notifications panel" });

  await note.click();
  await expect(page).toHaveURL(/\/inbox\/unassigned\//);
  await proof.dwell();
  await proof.shot("opened", { caption: "It opens in Unassigned" });
});

test("choose who hears about new unassigned tickets", async ({ page, proof }) => {
  await proof.open("/settings/assignment");
  const section = page.getByRole("heading", { name: "New unassigned tickets" });
  await expect(section).toBeVisible();
  await section.scrollIntoViewIfNeeded();
  await proof.chapter("Assignment", "Who is notified about a new ticket nobody is assigned to");
  await proof.shot("setting", { caption: "Automatic: everyone on small teams, only leads when more than 5 people would be notified" });

  const picker = page.getByRole("combobox", { name: "Notify about new unassigned tickets" });
  await picker.click();
  const leads = page.getByRole("option", { name: /Leads/ });
  await expect(leads).toBeVisible();
  await proof.shot("options", { caption: "Automatic, everyone on the team, leads and admins, or off" });

  await leads.click();
  await expect(picker).toContainText(/Leads/);
  await proof.dwell();
  await proof.shot("leads", { caption: "Only leads and admins hear about new tickets" });

  await proof.open("/settings/notifications");
  const row = page.getByRole("row", { name: /^New tickets/ });
  await expect(row).toBeVisible();
  await row.scrollIntoViewIfNeeded();
  await expect(row.getByRole("switch", { name: "New tickets: Phone" })).toBeChecked();
  await proof.chapter("Notifications", "Each person still decides where it reaches them");
  await proof.shot("preferences", { caption: "New tickets: phone and desktop on, email off by default" });
});
