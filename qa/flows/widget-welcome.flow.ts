import { expect, test } from "../lib/proof.ts";

test.use({ target: "widget" });

test("a new chat with the widget's own intro, or none at all", async ({ page, proof }) => {
  await proof.open(undefined, { key: "wk_offline", od_bot: "0" });
  await page.getByRole("button", { name: "Open chat" }).click();
  const chat = page.getByRole("dialog", { name: /^Chat with/ });
  await chat.getByRole("button", { name: "Send us a message" }).click();
  await expect(chat.getByText("Ask about orders, delivery or returns.", { exact: false })).toBeVisible();
  await proof.chapter("Chat intro", "The widget's own line under the greeting, and its offline message");
  await proof.dwell();
  await proof.shot("intro", { caption: "A new chat: the greeting, the widget's intro and its offline message", target: chat });

  await proof.open(undefined, { key: "wk_offline", od_bot: "0", od_welcome: "0" });
  await page.getByRole("button", { name: "Open chat" }).click();
  await chat.getByRole("button", { name: "Send us a message" }).click();
  await expect(chat.getByRole("textbox", { name: "Message" })).toBeVisible();
  await expect(chat.getByText("Ask about orders, delivery or returns.", { exact: false })).toBeHidden();
  await proof.chapter("No welcome", "Welcome text off: the chat opens empty");
  await proof.dwell();
  await proof.shot("empty", { caption: "Welcome text off: a new chat opens empty", target: chat });
});

test("the widget in Azerbaijani, and in a workspace's fixed language", async ({ page, proof }) => {
  await proof.open(undefined, { od_lang: "az", od_bot: "0" });
  await page.getByRole("button", { name: "Söhbəti aç" }).click();
  const chat = page.getByRole("dialog");
  await expect(chat.getByRole("button", { name: "Bizə mesaj göndərin" })).toBeVisible();
  await proof.chapter("Azerbaijani", "The widget's home and a new chat in Azərbaycan dili");
  await proof.dwell();
  await proof.shot("az-home", { caption: "Home in Azerbaijani", target: chat });

  await chat.getByRole("button", { name: "Bizə mesaj göndərin" }).click();
  await expect(chat.getByRole("textbox", { name: "Mesaj" })).toBeVisible();
  await proof.dwell();
  await proof.shot("az-chat", { caption: "A new chat in Azerbaijani", target: chat });

  await proof.open(undefined, { od_fixed_lang: "az", od_bot: "0" });
  await page.getByRole("button", { name: "Söhbəti aç" }).click();
  await expect(page.getByRole("dialog").getByRole("button", { name: "Bizə mesaj göndərin" })).toBeVisible();
  await proof.chapter("Fixed language", "An English browser, a workspace that shows Azerbaijani to everyone");
  await proof.dwell();
  await proof.shot("fixed", { caption: "The workspace's fixed language on an English browser", target: page.getByRole("dialog") });
});
