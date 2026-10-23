import { expect, test } from "../lib/proof.ts";

test.use({ target: "widget" });

test("open the chat widget on a customer's site", async ({ page, proof }) => {
  await proof.open();
  const launcher = page.getByRole("button", { name: "Open chat" });
  await expect(launcher).toBeVisible();
  await proof.chapter("Chat widget", "The launcher on a customer's page, then the open widget");
  await proof.shot("launcher", { caption: "The launcher on the host page" });

  await launcher.click();
  await expect(page.getByRole("dialog", { name: /^Chat with/ })).toBeVisible();
  await proof.dwell();
  await proof.shot("open", { caption: "The widget open" });
});

test("a reply the team takes back leaves the visitor's chat", async ({ page, proof }) => {
  await proof.open();
  await page.getByRole("button", { name: "Open chat" }).click();
  await page.getByRole("button", { name: /Exporting notebooks to PDF/ }).click();
  const reply = page.getByText("Glad that worked! Let us know if anything else comes up.");
  await expect(reply).toBeVisible();
  await proof.chapter("Taken back", "The team deletes its reply, or turns it into a note, and it leaves the chat");
  await proof.shot("before-take-back", { caption: "The conversation with the team's last reply" });

  await page.evaluate(() => window.dispatchEvent(new Event("opendesk-mock:take-back")));
  await expect(reply).toHaveCount(0);
  await expect(page.getByText("Perfect, that did it. Thanks!")).toBeVisible();
  await proof.dwell();
  await proof.shot("after-take-back", { caption: "The reply is gone from the visitor's chat at once" });
});
