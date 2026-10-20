// `pnpm doctor`: checks what QA and recording need on this machine, and prints the fix for each miss.
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { ROOT } from "../lib/env.ts";

type Row = { what: string; ok: boolean; fix?: string; detail?: string };
const rows: Row[] = [];

function run(cmd: string, args: string[]): { ok: boolean; out: string } {
  const res = spawnSync(cmd, args, { encoding: "utf8" });
  return { ok: res.status === 0, out: `${res.stdout ?? ""}${res.stderr ?? ""}`.trim() };
}

const [major, minor] = process.versions.node.split(".").map(Number);
rows.push({ what: "node 22.18+", ok: major > 22 || (major === 22 && minor >= 18), detail: process.versions.node, fix: "install node 22.18 or newer (it runs the .ts scripts directly)" });

const ff = run("ffmpeg", ["-hide_banner", "-encoders"]);
rows.push({ what: "ffmpeg with libx264", ok: ff.ok && ff.out.includes("libx264"), fix: "brew install ffmpeg (or apt install ffmpeg)" });

const ghv = run("gh", ["--version"]);
const ghVer = ghv.out.match(/gh version (\d+)\.(\d+)/);
rows.push({ what: "gh 2.99+ (pr --attach)", ok: !!ghVer && (Number(ghVer[1]) > 2 || Number(ghVer[2]) >= 99), detail: ghVer?.[0], fix: "brew upgrade gh" });
rows.push({ what: "gh signed in", ok: run("gh", ["auth", "status"]).ok, fix: "gh auth login" });

const pw = run("pnpm", ["exec", "playwright", "--version"]);
rows.push({ what: "qa/ dependencies", ok: pw.ok, fix: "pnpm install (in qa/)" });
const chromium = spawnSync("node", ["-e", "import('@playwright/test').then(async ({chromium}) => { const b = await chromium.launch({ channel: 'chromium' }); await b.close(); })"], { encoding: "utf8" });
rows.push({ what: "Playwright's Chromium launches", ok: chromium.status === 0, fix: "pnpm exec playwright install chromium (in qa/)" });

for (const dir of ["web", "site", "docs"]) {
  // Recording installs a missing tree on first use, so this is only informational.
  rows.push({ what: `${dir}/ dependencies`, ok: true, detail: existsSync(join(ROOT, dir, "node_modules")) ? "installed" : "installed on the first recording that needs them" });
}

let bad = 0;
for (const r of rows) {
  if (!r.ok) bad++;
  console.log(`${r.ok ? "ok  " : "MISS"} ${r.what}${r.detail ? ` (${r.detail})` : ""}${r.ok ? "" : `: ${r.fix}`}`);
}
process.exit(bad ? 1 : 0);
