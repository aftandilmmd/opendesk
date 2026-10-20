import { expect, test } from "../lib/proof.ts";

test.use({ target: "docs" });

test("the docs home page", async ({ page, proof }) => {
  await proof.open("/");
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await proof.shot("home", { caption: "Docs home" });
});
