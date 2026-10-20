import { expect, test } from "../lib/proof.ts";

test("let visitors send voice messages from a chat widget", async ({ page, proof }) => {
  await proof.open("/settings/brands");
  await page.getByRole("link", { name: /^Margin Default/ }).click();
  await page.getByRole("tab", { name: /Chat widgets/ }).click();
  await page.getByRole("tabpanel").getByRole("link").first().click();
  const voice = page.getByRole("switch", { name: "Let visitors send voice messages" });
  await expect(voice).toBeVisible();
  await voice.scrollIntoViewIfNeeded();
  await proof.chapter("Voice messages", "Turn them on for a widget and set the longest recording");
  await proof.shot("voice-off", { caption: "Voice messages, off by default" });

  await voice.click();
  const length = page.getByLabel("Longest voice message");
  await expect(length).toBeVisible();
  await proof.shot("voice-on", { caption: "On, with the longest voice message in seconds" });

  await length.fill("90");
  await length.blur();
  await expect(length).toHaveValue("90");
  await proof.dwell();
  await proof.shot("voice-length", { caption: "The longest voice message set to 90 seconds" });
});
