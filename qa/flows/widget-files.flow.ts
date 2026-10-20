import { expect, test } from "../lib/proof.ts";

test("turn files off for a chat widget, or limit them to some types", async ({ page, proof }) => {
  await proof.open("/settings/brands");
  await page.getByRole("link", { name: /^Margin Default/ }).click();
  await page.getByRole("tab", { name: /Chat widgets/ }).click();
  await page.getByRole("tabpanel").getByRole("link").first().click();
  const files = page.getByRole("switch", { name: "Let visitors send files" });
  await expect(files).toBeVisible();
  await files.scrollIntoViewIfNeeded();
  const any = page.getByRole("radio", { name: "Any file" });
  await expect(any).toBeChecked();
  await proof.chapter("Files from visitors", "On by default, taking any file but programs and scripts");
  await proof.shot("files-on", { caption: "Files on, any file but programs and scripts" });

  await page.getByRole("radio", { name: "Only these types" }).click();
  const types = page.getByRole("button", { name: "Pick file types" });
  await expect(types).toBeVisible();
  await expect(page.getByText("Pick at least one file type, or accept any file.")).toBeVisible();
  await types.click();
  await expect(page.getByRole("option").first()).toBeVisible();
  await proof.shot("file-types", { caption: "The file types to allow, by group" });
  await page.getByRole("option", { name: /\.pdf/ }).click();
  await page.getByRole("option", { name: /\.png/ }).click();
  await page.keyboard.press("Escape");
  await expect(types).toHaveText(".png .pdf");
  await proof.dwell();
  await proof.shot("some-types", { caption: "Only PNG images and PDFs" });

  await files.click();
  await expect(types).toBeHidden();
  await proof.dwell();
  await proof.shot("files-off", { caption: "Files off: the widget takes no attachments" });
});

test.describe("widget", () => {
  test.use({ target: "widget" });

  // Only the widget on screen. The text stays in the DOM: the recorder starts at the first text.
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      document.addEventListener("DOMContentLoaded", () => {
        document.head.insertAdjacentHTML("beforeend", "<style>main { opacity: 0; }</style>");
      });
    });
  });

  test("refuse a file type the widget does not allow", async ({ page, proof }) => {
    await proof.open(undefined, { key: "wk_files" });
    await page.getByRole("button", { name: "Open chat" }).click();
    const chat = page.getByRole("dialog", { name: /^Chat with/ });
    await chat.getByRole("button", { name: "Send us a message" }).click();
    const attach = chat.getByRole("button", { name: "Attach files" });
    await expect(attach).toBeVisible();
    await proof.chapter("Allowed file types", "A program is left out, with a note saying why");
    await proof.shot("composer", { caption: "The composer with Attach files", target: chat });

    const chooser = page.waitForEvent("filechooser");
    await attach.click();
    await (await chooser).setFiles({ name: "setup.exe", mimeType: "application/octet-stream", buffer: Buffer.from("MZ") });
    await expect(chat.getByText("setup.exe can't be sent here. Try another file type.")).toBeVisible();
    await proof.dwell();
    await proof.shot("refused", { caption: "setup.exe refused, nothing attached", target: chat });
  });

  test("a widget with files off has no attach button", async ({ page, proof }) => {
    await proof.open(undefined, { key: "wk_nofiles" });
    await page.getByRole("button", { name: "Open chat" }).click();
    const chat = page.getByRole("dialog", { name: /^Chat with/ });
    await chat.getByRole("button", { name: "Send us a message" }).click();
    await expect(chat.getByRole("button", { name: "Send" })).toBeVisible();
    await expect(chat.getByRole("button", { name: "Attach files" })).toBeHidden();
    await proof.chapter("Files off", "The composer takes text only");
    await proof.shot("no-attach", { caption: "No attach button with files off", target: chat });
  });
});
