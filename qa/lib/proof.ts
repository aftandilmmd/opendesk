import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test as base, expect, type Locator, type Page, type TestInfo } from "@playwright/test";
import { assertLocal, RUN_DIR } from "./env.ts";
import { launchDesktop } from "./desktop.ts";
import { Recorder } from "./recorder.ts";
import { serve, stopAll, type Server } from "./servers.ts";

// What a flow records. "desktop" is the Electron app on the mock web app; iOS flows use lib/ios.ts.
export type Target = Server | "desktop" | "ios";
type BrowserTarget = Exclude<Target, "ios">;

export type Box = { x: number; y: number; width: number; height: number };
// `ignore` holds regions, in the still's own pixels, that comparisons skip.
export type Shot = { name: string; file: string; caption: string; ignore?: Box[] };

export type FlowMeta = {
  slug: string;
  title: string;
  file: string;
  target: Target;
  status: TestInfo["status"];
  // Spooled frames waiting for the end-of-run encode; `video` replaces it once encoded.
  frames?: string;
  video?: string;
  shots: Shot[];
};

// The same instant and the same random sequence on every run, so the mock seeds identical data and
// a follow-up's stills differ from the last publish only where the code changed.
const FIXED_TIME = new Date("2026-06-16T09:30:00Z");
const SEEDED_RANDOM = `(() => {
  let a = 0x0d5eed;
  Math.random = () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
})();`;

// The animated pointer, click ripples and action labels in the video; never in a still.
const ACTIONS = { cursor: "pointer", duration: 700, position: "top-right", style: { title: "font-size: 16px" } } as const;

// Where `open()` lands when given no path.
const HOME: Record<BrowserTarget, string> = { web: "/", widget: "/widget/demo.html", admin: "/", site: "/", docs: "/", desktop: "/" };

// Targets running a mock app, whose sample data the seeded random sequence keeps identical.
const MOCKED = new Set<BrowserTarget>(["web", "widget", "admin", "desktop"]);

export class Proof {
  readonly shots: Shot[] = [];
  readonly dir: string;
  private readonly page: Page;
  private readonly target: BrowserTarget;
  private readonly origin: string;
  private readonly live: boolean;

  constructor(page: Page, dir: string, target: BrowserTarget, origin: string, live: boolean) {
    this.page = page;
    this.dir = dir;
    this.target = target;
    this.origin = origin;
    this.live = live;
  }

  // Opens a path on the flow's target. On the app, the mock's simulated activity stays off
  // (`test.use({ live: true })` turns it on) so the screen holds still for the stills.
  async open(path = HOME[this.target], params: Record<string, string> = {}): Promise<void> {
    const url = new URL(path, this.origin);
    if ((this.target === "web" || this.target === "desktop") && this.live) url.searchParams.set("mock_live", "1");
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
    await this.page.goto(url.toString());
    if (this.target === "web" || this.target === "desktop") {
      // Presence and live counts arrive once the realtime connection is up; a still taken before
      // that would differ from run to run. Pages without the indicator (sign-in) skip the wait.
      const live = this.page.getByRole("status", { name: /^Live/ });
      if (await live.waitFor({ timeout: 8000 }).then(() => true, () => false)) await this.page.waitForTimeout(800);
    }
  }

  // A title card in the video, so a reviewer knows what the next few seconds show.
  async chapter(title: string, description?: string): Promise<void> {
    await this.page.screencast.showChapter(title, { description, duration: 1600 });
  }

  // A named still. Keep names stable: follow-up comments diff stills by name.
  // `ignore` names content that changes on its own (relative times, live counters): the still is
  // published as is, and those regions are skipped when it is compared with the previous publish.
  async shot(name: string, opts: { caption?: string; target?: Locator; ignore?: Locator[] } = {}): Promise<void> {
    if (!/^[a-z0-9][a-z0-9-]*$/.test(name)) throw new Error(`shot name "${name}" must be kebab-case`);
    if (this.shots.some((s) => s.name === name)) throw new Error(`shot "${name}" taken twice in one flow`);
    const file = join(this.dir, "shots", `${name}.png`);
    const origin = opts.target ? await opts.target.boundingBox() : { x: 0, y: 0 };
    const ignore: Box[] = [];
    for (const locator of opts.ignore ?? []) {
      for (const el of await locator.all()) {
        const b = await el.boundingBox();
        if (b && origin) ignore.push({ x: Math.floor(b.x - origin.x), y: Math.floor(b.y - origin.y), width: Math.ceil(b.width) + 1, height: Math.ceil(b.height) + 1 });
      }
    }
    const options = { animations: "disabled" as const, caret: "hide" as const };
    await this.page.screencast.hideOverlays();
    await this.page.screencast.hideActions();
    try {
      // CSS animations are stopped by `animations`; script-driven motion (springs, popovers sliding
      // in) is waited out: the still is the first frame that two captures in a row agree on.
      const take = () => (opts.target ? opts.target.screenshot(options) : this.page.screenshot(options));
      let still = await take();
      for (let i = 0; i < 20; i++) {
        await this.page.waitForTimeout(150);
        const next = await take();
        if (next.equals(still)) break;
        still = next;
      }
      writeFileSync(file, still);
    } finally {
      await this.page.screencast.showOverlays();
      await this.page.screencast.showActions(ACTIONS);
    }
    this.shots.push({ name, file, caption: opts.caption ?? name, ignore: ignore.length ? ignore : undefined });
  }

  // Lets a result sit on screen long enough to be read in the video.
  async dwell(ms = 1200): Promise<void> {
    await this.page.waitForTimeout(ms);
  }
}

export function slugOf(info: TestInfo): string {
  return info.titlePath
    .slice(1)
    .join(" ")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

export const test = base.extend<{ proof: Proof; target: BrowserTarget; live: boolean; fixedClock: boolean }, { servers: (t: Server) => Promise<string> }>({
  // `test.use({ target: "admin" })` for a flow on another surface: "widget", "admin", "site", "docs", "desktop".
  target: ["web", { option: true }],
  // `test.use({ live: true })` keeps the mock's simulated customers, teammates and Ollie running.
  live: [false, { option: true }],
  // `test.use({ fixedClock: false })` lets time run, for a flow about timers or countdowns.
  fixedClock: [true, { option: true }],
  servers: [
    async ({}, use) => {
      await use(serve);
      stopAll();
    },
    { scope: "worker" },
  ],
  // The site and docs loop showpiece animations (the hero's app window), so no still of them would
  // repeat; they honour reduced motion. `test.use({ reducedMotion: "no-preference" })` when the
  // motion is what changed.
  reducedMotion: async ({ target }, use) => use(target === "site" || target === "docs" ? "reduce" : "no-preference"),
  baseURL: async ({ target, servers }, use) => {
    const url = await servers(target === "desktop" ? "web" : target);
    assertLocal(url);
    await use(url);
  },
  // The desktop app's window instead of a browser tab; every other target gets a tab.
  page: async ({ target, context, baseURL }, use) => {
    if (target !== "desktop") return use(await context.newPage());
    const desktop = await launchDesktop(baseURL!);
    try {
      await use(desktop.page);
    } finally {
      await desktop.close();
    }
  },
  proof: [
    async ({ page, target, baseURL, live, fixedClock }, use, info) => {
      const slug = slugOf(info);
      const dir = join(RUN_DIR, slug);
      mkdirSync(join(dir, "shots"), { recursive: true });
      if (fixedClock) await page.clock.setFixedTime(FIXED_TIME);
      if (MOCKED.has(target)) await page.addInitScript(SEEDED_RANDOM);

      const frames = join(dir, "frames");
      const recorder = new Recorder(page, frames);
      await recorder.start();
      await page.screencast.showActions(ACTIONS);
      const proof = new Proof(page, dir, target, baseURL!, live);

      await use(proof);

      const captured = await recorder.stop();
      const stills = proof.shots.length > 0;
      const status = info.status === "passed" && !stills ? "failed" : info.status;
      // A failed flow is never published, so its frames are not worth encoding unless asked for.
      const keep = captured && (status === "passed" || process.env.QA_VIDEO_ON_FAIL === "1");
      if (!keep) rmSync(frames, { recursive: true, force: true });
      const meta: FlowMeta = { slug, title: info.title, file: info.file, target, status, frames: keep ? frames : undefined, shots: proof.shots };
      writeFileSync(join(dir, "meta.json"), JSON.stringify(meta, null, 2));
      if (!stills && info.status === "passed") throw new Error(`"${info.title}" took no stills; every flow publishes at least one \`proof.shot\``);
    },
    { auto: true },
  ],
});

export { expect };
