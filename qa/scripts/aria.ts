// `pnpm aria <path> [selector]`: prints a page's accessibility tree, for writing a flow's locators
// without opening a browser and reading screenshots.
//
//   node scripts/aria.ts /inbox              the app's inbox (mock mode)
//   node scripts/aria.ts /inbox main         one region, fewer tokens
//   node scripts/aria.ts site:/pricing/      another target: widget, admin, site, docs
import { chromium } from "@playwright/test";
import { VIDEO } from "../lib/env.ts";
import { acquireRecordingLock, releaseRecordingLock } from "../lib/lock.ts";
import { serve, stopAll, type Server } from "../lib/servers.ts";

const [spec, selector = "body"] = process.argv.slice(2);
if (!spec) {
  console.error("usage: pnpm aria [target:]<path> [selector]");
  process.exit(1);
}
const m = spec.match(/^(web|widget|admin|site|docs):(.*)$/);
const target = (m?.[1] ?? "web") as Server;
const path = m ? m[2] : spec;

await acquireRecordingLock(`aria ${spec}`);
try {
  const origin = await serve(target);
  const url = new URL(path || "/", origin);
  const browser = await chromium.launch({ channel: "chromium" });
  const page = await browser.newPage({ viewport: { width: VIDEO.width, height: VIDEO.height } });
  await page.goto(url.toString(), { waitUntil: "networkidle", timeout: 90_000 });
  console.log(await page.locator(selector).first().ariaSnapshot());
  await browser.close();
} finally {
  stopAll();
  releaseRecordingLock();
}
