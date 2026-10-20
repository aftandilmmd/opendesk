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
