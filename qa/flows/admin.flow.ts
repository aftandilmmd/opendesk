import { expect, test } from "../lib/proof.ts";

test.use({ target: "admin" });

test("find a past-due workspace from the admin overview", async ({ page, proof }) => {
  await proof.open("/");
  await expect(page.getByRole("heading", { name: "Overview" })).toBeVisible();
  await expect(page.getByText("$799.57")).toBeVisible();
  await proof.chapter("Admin panel", "The instance overview, then one workspace");
  await proof.shot("overview", { caption: "The instance overview" });

  await page.getByRole("navigation", { name: "Admin" }).getByRole("link", { name: /^Workspaces/ }).click();
  await page.getByRole("searchbox", { name: /Search by name/ }).pressSequentially("halcyon", { delay: 60 });
  await page.getByRole("link", { name: "Halcyon Studio" }).click();
  await expect(page.getByRole("heading", { name: /Halcyon Studio/ })).toBeVisible();
  await proof.dwell();
  await proof.shot("workspace", { caption: "Halcyon Studio, past due, with its mailbox in error" });
});
