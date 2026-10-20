import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import { existsSync, mkdirSync, openSync, readFileSync } from "node:fs";
import { createServer } from "node:net";
import { join } from "node:path";
import { ARTIFACTS, ROOT } from "./env.ts";

// The dev servers flows record against, each this worktree's own, on a free port.
// None of them needs a backend: the app, the widget and the admin panel run on in-memory mocks.
export type Server = "web" | "widget" | "admin" | "site" | "docs";

type Spec = { dir: string; args: (port: number) => string[]; env?: Record<string, string>; ready: string };

const SPECS: Record<Server, Spec> = {
  // VITE_MOCK=1 is `pnpm dev:mock`: an in-memory API and gateway seeded with sample data.
  // VITE_MOCK_QUIET=1 keeps its simulated activity off unless a flow opens with ?mock_live=1.
  web: { dir: "web", args: (p) => ["exec", "vite", "--port", String(p), "--strictPort", "--host", "127.0.0.1"], env: { VITE_MOCK: "1", VITE_MOCK_QUIET: "1" }, ready: "/" },
  admin: { dir: "admin", args: (p) => ["exec", "vite", "--port", String(p), "--strictPort", "--host", "127.0.0.1"], env: { VITE_MOCK: "1" }, ready: "/" },
  widget: { dir: "web", args: (p) => ["exec", "vite", "--config", "vite.widget.config.ts", "--port", String(p), "--strictPort", "--host", "127.0.0.1"], ready: "/widget/demo.html" },
  // --ignore-lock keeps astro in the foreground (it backgrounds itself under an agent) and clear of
  // the lock file of a dev server someone else is running in the same tree.
  site: { dir: "site", args: (p) => ["exec", "astro", "dev", "--ignore-lock", "--port", String(p), "--host", "127.0.0.1"], ready: "/" },
  docs: { dir: "docs", args: (p) => ["exec", "astro", "dev", "--ignore-lock", "--port", String(p), "--host", "127.0.0.1"], ready: "/" },
};

const running = new Map<Server, { url: string; child: ChildProcess }>();

function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const s = createServer();
    s.unref();
    s.on("error", reject);
    s.listen(0, "127.0.0.1", () => {
      const { port } = s.address() as { port: number };
      s.close(() => resolve(port));
    });
  });
}

// Waits for the server to print where it listens (astro moves to the next port when one is taken,
// so the port asked for is not always the one it got), then for that address to answer.
async function waitReady(ready: string, child: ChildProcess, log: string, timeoutMs = 120_000): Promise<string> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error(`the dev server exited with ${child.exitCode} before it answered; its log is ${log}`);
    const origin = readFileSync(log, "utf8").replace(/\x1b\[[0-9;]*m/g, "").match(/http:\/\/127\.0\.0\.1:\d+/)?.[0];
    if (origin) {
      try {
        if ((await fetch(`${origin}${ready}`, { signal: AbortSignal.timeout(5000) })).ok) return origin;
      } catch {
        // Not answering yet.
      }
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`the dev server did not answer within ${timeoutMs / 1000}s; its log is ${log}`);
}

export function ensureInstalled(dir: string): void {
  if (existsSync(join(ROOT, dir, "node_modules"))) return;
  console.log(`qa: installing ${dir}/ dependencies (first recording in this worktree)`);
  const res = spawnSync("pnpm", ["install", "--frozen-lockfile"], { cwd: join(ROOT, dir), stdio: "inherit" });
  if (res.status !== 0) throw new Error(`pnpm install failed in ${dir}/`);
}

// Starts the target's dev server once per run and returns its origin.
export async function serve(target: Server): Promise<string> {
  const have = running.get(target);
  if (have) return have.url;
  const spec = SPECS[target];
  ensureInstalled(spec.dir);
  if (target === "site") spawnSync("node", ["scripts/prebuild.mjs"], { cwd: join(ROOT, "site"), stdio: "ignore" });
  const port = await freePort();
  mkdirSync(join(ARTIFACTS, "servers"), { recursive: true });
  const log = join(ARTIFACTS, "servers", `${target}.log`);
  const out = openSync(log, "w");
  // Its own process group, so stopping it also stops what pnpm started under it.
  const child = spawn("pnpm", spec.args(port), {
    cwd: join(ROOT, spec.dir),
    env: { ...process.env, ...spec.env, BROWSER: "none", NO_COLOR: "1" },
    stdio: ["ignore", out, out],
    detached: true,
  });
  running.set(target, { url: "", child });
  const url = await waitReady(spec.ready, child, log);
  running.set(target, { url, child });
  return url;
}

export function stopAll(): void {
  for (const { child } of running.values()) {
    if (child.pid && child.exitCode === null) {
      try {
        process.kill(-child.pid, "SIGTERM");
      } catch {
        // Already gone.
      }
    }
  }
  running.clear();
}

process.on("exit", stopAll);
