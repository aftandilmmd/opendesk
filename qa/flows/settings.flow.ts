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

test("write a widget's chat intro and open new chats without a welcome", async ({ page, proof }) => {
  await proof.open("/settings/brands");
  await page.getByRole("link", { name: /^Margin Default/ }).click();
  await page.getByRole("tab", { name: /Chat widgets/ }).click();
  await page.getByRole("tabpanel").getByRole("link").first().click();
  const intro = page.getByLabel("Chat intro");
  await expect(intro).toBeVisible();
  // A new chat opens on the welcome when it asks for no email or topic first.
  await page.getByRole("switch", { name: "Ask for an email first" }).click();
  for (const name of ["Billing and plans", "Technical help", "Legal and privacy"]) await page.getByRole("button", { name: `Remove ${name}` }).click();
  await intro.scrollIntoViewIfNeeded();
  const nudge = page.getByRole("button", { name: "Not now" });
  if (await nudge.isVisible()) await nudge.click();
  await proof.chapter("Chat intro", "The line under the greeting when a visitor starts a new chat");
  await intro.click();
  await intro.pressSequentially("Ask about orders, delivery or returns.", { delay: 40 });
  const preview = page.locator("[data-opendesk-preview]").getByText("Ask about orders, delivery or returns.");
  await expect(preview).toBeVisible();
  await proof.dwell();
  await proof.shot("chat-intro", { caption: "The chat intro, and the preview on a new chat showing it under the greeting" });

  const welcome = page.getByRole("switch", { name: "Welcome text in a new chat" });
  await expect(welcome).toBeChecked();
  await welcome.click();
  await expect(welcome).not.toBeChecked();
  await intro.focus();
  await expect(preview).toBeHidden();
  await proof.dwell();
  await proof.shot("welcome-off", { caption: "Welcome text off: a new chat opens empty" });
});

test("pick Azerbaijani and show customer pages in it for everyone", async ({ page, proof }) => {
  await proof.open("/settings/workspace");
  const language = page.getByRole("button", { name: "English" });
  await expect(language).toBeVisible();
  const nudge = page.getByRole("button", { name: "Not now" });
  if (await nudge.isVisible()) await nudge.click();
  await language.scrollIntoViewIfNeeded();
  await proof.chapter("Customer language", "Azerbaijani joins the list, and one language can go to every visitor");
  const search = page.getByPlaceholder("Search languages");
  await expect(async () => {
    if (!(await search.isVisible())) await language.click();
    await expect(search).toBeVisible({ timeout: 3000 });
  }).toPass({ timeout: 20000 });
  await search.pressSequentially("Az", { delay: 80 });
  const az = page.getByRole("option", { name: /Azərbaycan dili/ });
  await expect(az).toBeVisible();
  await proof.shot("languages", { caption: "Azərbaycan dili in the customer languages, found by searching" });

  await az.click();
  const fixed = page.getByRole("switch", { name: "Use for everyone" });
  await expect(page.getByText(/in Azərbaycan dili for every visitor/)).toBeVisible();
  await fixed.click();
  await expect(fixed).toBeChecked();
  await proof.dwell();
  await proof.shot("fixed", { caption: "Azərbaycan dili, used for every visitor whatever their browser language" });
});

test("a survey in the workspace's fixed language", async ({ page, proof }) => {
  await proof.open("/csat", { mock_locale: "az" });
  await page.evaluate(() => (location.hash = "t=demo"));
  await page.reload();
  await expect(page.getByRole("heading", { name: "Söhbətiniz necə keçdi?" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Dil" })).toBeHidden();
  await proof.chapter("Satisfaction survey", "In the workspace's language for everyone, with no language menu");
  await proof.dwell();
  await proof.shot("csat-fixed", { caption: "The survey in Azerbaijani on an English browser, without the language menu" });
});
