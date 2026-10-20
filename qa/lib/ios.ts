// iOS flows: the iPhone app's Debug build in demo mode (OPENDESK_DEMO=1, an in-memory backend with
// the same sample world as the web mock) on a simulator of the harness's own, `opendesk-qa`.
// Other simulators are never booted, shut down or touched. A flow moves between screens with deep
// links (`ios.open("/inbox/unassigned/1086")`), takes stills with `ios.shot`, and the whole flow
// is recorded with `simctl io recordVideo`. Demo mode takes links through its own channel (a file in
// the app's container and a Darwin notification), because `simctl openurl` raises a system prompt.
import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { test as base, expect, type TestInfo } from "@playwright/test";
import { ARTIFACTS, ROOT, RUN_DIR } from "./env.ts";
import type { FlowMeta, Shot } from "./proof.ts";
import { slugOf } from "./proof.ts";
import { fitVideo } from "./recorder.ts";

const DEVICE = "opendesk-qa";
const DEVICE_TYPE = process.env.QA_IOS_DEVICE_TYPE ?? "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro";
const BUNDLE = "sh.opendesk.app";
const DERIVED = join(ARTIFACTS, "ios-build");
const DEVELOPER_DIR = process.env.DEVELOPER_DIR ?? "/Applications/Xcode.app/Contents/Developer";
// SIMCTL_CHILD_ variables reach the launched app's environment: demo mode, no network, fixed clock.
const env = { ...process.env, DEVELOPER_DIR, SIMCTL_CHILD_OPENDESK_DEMO: "1" };

function run(cmd: string, args: string[], what: string, extra: Record<string, string> = {}): string {
  const res = spawnSync(cmd, args, { env: { ...env, ...extra }, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
  if (res.status !== 0) throw new Error(`${what} failed:\n${(res.stderr || res.stdout || "").trim().split("\n").slice(-30).join("\n")}`);
  return res.stdout;
}

const simctl = (args: string[], what: string) => run("xcrun", ["simctl", ...args], what);

type Device = { udid: string; state: string; name: string };

function findDevice(): Device | undefined {
  const all = JSON.parse(simctl(["list", "devices", "--json"], "listing simulators")) as { devices: Record<string, Device[]> };
  return Object.values(all.devices).flat().find((d) => d.name === DEVICE);
}

// Builds the Debug app for the simulator; incremental after the first build.
function buildApp(): string {
  console.log("qa: building the iPhone app (Debug, simulator)");
  run(
    "xcodebuild",
    ["-project", join(ROOT, "ios/Opendesk.xcodeproj"), "-scheme", "Opendesk", "-configuration", "Debug", "-sdk", "iphonesimulator", "-destination", `platform=iOS Simulator,name=${DEVICE}`, "-derivedDataPath", DERIVED, "-quiet", "build"],
    "xcodebuild",
  );
  const products = join(DERIVED, "Build/Products/Debug-iphonesimulator");
  const app = readdirSync(products).find((f) => f.endsWith(".app"));
  if (!app) throw new Error(`no .app in ${products}`);
  return join(products, app);
}

export type Sim = { udid: string };

export class Ios {
  readonly shots: Shot[] = [];
  readonly dir: string;
  private readonly udid: string;

  constructor(udid: string, dir: string) {
    this.udid = udid;
    this.dir = dir;
  }

  // Opens an app path: `/inbox/<folder>`, `/inbox/<folder>/<ticket id or number>`, `/views/<id>`,
  // `/notifications`, `/account`, `/ollie`.
  async open(path: string, settleMs = 1800): Promise<void> {
    const data = simctl(["get_app_container", this.udid, BUNDLE, "data"], "finding the app's container").trim();
    mkdirSync(join(data, "tmp"), { recursive: true });
    writeFileSync(join(data, "tmp", "opendesk-demo-open"), path);
    simctl(["spawn", this.udid, "notifyutil", "-p", "sh.opendesk.demo.open"], `opening ${path}`);
    await this.dwell(settleMs);
  }

  // A named still of the whole screen. Keep names stable: follow-up comments compare by name.
  async shot(name: string, opts: { caption?: string } = {}): Promise<void> {
    if (!/^[a-z0-9][a-z0-9-]*$/.test(name)) throw new Error(`shot name "${name}" must be kebab-case`);
    if (this.shots.some((s) => s.name === name)) throw new Error(`shot "${name}" taken twice in one flow`);
    if (!simctl(["spawn", this.udid, "launchctl", "list"], "listing processes").includes(`UIKitApplication:${BUNDLE}`)) {
      throw new Error(`the app is not running at shot "${name}" (it crashed, or the simulator restarted it); see ~/Library/Logs/DiagnosticReports`);
    }
    const file = join(this.dir, "shots", `${name}.png`);
    // The first frame two captures in a row agree on, so a transition is never caught half way.
    const tmp = `${file}.next.png`;
    simctl(["io", this.udid, "screenshot", "--type=png", file], `screenshot ${name}`);
    for (let i = 0; i < 15; i++) {
      await this.dwell(200);
      simctl(["io", this.udid, "screenshot", "--type=png", tmp], `screenshot ${name}`);
      const same = readFileSync(tmp).equals(readFileSync(file));
      renameSync(tmp, file);
      if (same) break;
    }
    rmSync(tmp, { force: true });
    this.shots.push({ name, file, caption: opts.caption ?? name });
  }

  // Lets the screen settle, or a result sit in the video long enough to be read.
  async dwell(ms = 1200): Promise<void> {
    await new Promise((r) => setTimeout(r, ms));
  }
}

export const test = base.extend<{ ios: Ios; start: string }, { sim: Sim }>({
  // `test.use({ start: "/inbox/unassigned" })`: the path the app opens on launch (the Mine folder otherwise).
  start: ["", { option: true }],
  sim: [
    async ({}, use) => {
      let device = findDevice();
      if (!device) {
        simctl(["create", DEVICE, DEVICE_TYPE], `creating the ${DEVICE} simulator`);
        device = findDevice()!;
      }
      const bootedHere = device.state !== "Booted";
      // Reduce Motion, which the app honours: idle animations (Ollie, live dots) hold still, so the
      // same build gives the same stills. Written before boot: changing it live restarts SpringBoard.
      const prefs = join(homedir(), "Library/Developer/CoreSimulator/Devices", device.udid, "data/Library/Preferences/com.apple.Accessibility.plist");
      if (bootedHere) run("defaults", ["write", prefs, "ReduceMotionEnabled", "-bool", "true"], "turning on Reduce Motion");
      if (bootedHere) simctl(["boot", device.udid], `booting ${DEVICE}`);
      simctl(["bootstatus", device.udid, "-b"], `waiting for ${DEVICE}`);
      const app = buildApp();
      simctl(["install", device.udid, app], "installing the app");
      // A clean, fixed status bar, so stills compare across runs.
      simctl(
        ["status_bar", device.udid, "override", "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100"],
        "the status bar override",
      );
      await use({ udid: device.udid });
      spawnSync("xcrun", ["simctl", "terminate", device.udid, BUNDLE], { env });
      if (bootedHere) spawnSync("xcrun", ["simctl", "shutdown", device.udid], { env });
    },
    { scope: "worker", timeout: 900_000 },
  ],
  ios: [
    async ({ sim, colorScheme, start }, use, info: TestInfo) => {
      const slug = slugOf(info);
      const dir = join(RUN_DIR, slug);
      mkdirSync(join(dir, "shots"), { recursive: true });
      // `test.use({ colorScheme: "dark" })` for the dark appearance, as in the browser flows.
      simctl(["ui", sim.udid, "appearance", colorScheme === "dark" ? "dark" : "light"], "setting the appearance");
      // English and a fixed locale, so dates read the same whatever the simulator's language.
      run(
        "xcrun",
        ["simctl", "launch", "--terminate-running-process", sim.udid, BUNDLE, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"],
        "launching the app",
        start ? { SIMCTL_CHILD_OPENDESK_DEMO_OPEN: start } : {},
      );
      const video = join(dir, "video.mp4");
      let recorder: ChildProcess | undefined = spawn("xcrun", ["simctl", "io", sim.udid, "recordVideo", "--codec=h264", "--force", video], { env, stdio: "ignore" });
      const ios = new Ios(sim.udid, dir);
      await ios.dwell(2500);

      await use(ios);

      await ios.dwell(600);
      // recordVideo finishes the file on SIGINT.
      const exited = new Promise((r) => recorder!.once("exit", r));
      recorder.kill("SIGINT");
      await exited;
      recorder = undefined;
      const stills = ios.shots.length > 0;
      const status = info.status === "passed" && !stills ? "failed" : info.status;
      const keep = existsSync(video) && status === "passed";
      if (keep) await fitVideo(video);
      const meta: FlowMeta = { slug, title: info.title, file: info.file, target: "ios", status, video: keep ? video : undefined, shots: ios.shots };
      writeFileSync(join(dir, "meta.json"), JSON.stringify(meta, null, 2));
      if (!stills && info.status === "passed") throw new Error(`"${info.title}" took no stills; every flow publishes at least one \`ios.shot\``);
    },
    { timeout: 120_000 },
  ],
});

export { expect };
