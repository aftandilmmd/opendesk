import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { _electron, type ElectronApplication, type Page } from "@playwright/test";
import { ROOT, VIDEO } from "./env.ts";
import { ensureInstalled } from "./servers.ts";

let built = false;

// The desktop app's development build, pointed at the mock web app, in a sandbox run
// (OPENDESK_DESKTOP_SANDBOX, desktop/src/main/env.ts): its own throwaway settings, no opendesk://
// handler, no OS notifications, badge, Dock icon or focus, and windows the person at the machine
// cannot see or click. Playwright drives and records the window's page like a browser tab.
export async function launchDesktop(webURL: string): Promise<{ app: ElectronApplication; page: Page; close: () => Promise<void> }> {
  const dir = join(ROOT, "desktop");
  ensureInstalled("desktop");
  if (!built) {
    const res = spawnSync("node", ["scripts/build.mjs"], { cwd: dir, encoding: "utf8" });
    if (res.status !== 0) throw new Error(`the desktop build failed: ${res.stderr || res.stdout}`);
    built = true;
  }
  const electron = createRequire(join(dir, "package.json"))("electron") as string;
  const sandbox = mkdtempSync(join(tmpdir(), "opendesk-qa-desktop-"));
  const app = await _electron.launch({
    executablePath: electron,
    args: [dir],
    cwd: dir,
    env: { ...process.env, OPENDESK_DESKTOP_URL: webURL, OPENDESK_DESKTOP_SANDBOX: sandbox },
  });
  const close = async () => {
    await app.close().catch(() => {});
    rmSync(sandbox, { recursive: true, force: true });
  };
  try {
    // The instance window is the one on the web app's origin (the picker would be a file:// page).
    const deadline = Date.now() + 60_000;
    let page: Page | undefined;
    while (!(page = app.windows().find((w) => w.url().startsWith(webURL)))) {
      if (Date.now() > deadline) throw new Error(`the desktop app never opened ${webURL}; windows: ${app.windows().map((w) => w.url()).join(", ") || "none"}`);
      await new Promise((r) => setTimeout(r, 250));
    }
    await app.evaluate(({ BrowserWindow }, size) => {
      for (const w of BrowserWindow.getAllWindows()) w.setContentSize(size.width, size.height);
    }, { width: VIDEO.width, height: VIDEO.height });
    return { app, page, close };
  } catch (err) {
    await close();
    throw err;
  }
}
