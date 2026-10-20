// `pnpm share`: writes the QA section, and the Proof section where the branch changes a surface,
// into this branch's pull request, opening the pull request first if there is none.
// The Proof section always holds the current stills and videos; when a follow-up changes them, a
// comment shows each changed still before and after.
//
//   node scripts/share.ts                          publish (opens the PR from the one commit's subject)
//   node scripts/share.ts --title "feat: ..."      the PR title, when the branch has several commits
//   node scripts/share.ts --body-file pr.md        the description above the sections (or --body "...")
//   node scripts/share.ts --add ios:shot.png#Caption   media captured outside the harness (repeatable)
//   node scripts/share.ts --dry-run                write the body and print the gh command, upload nothing
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { basename, extname, join, relative, resolve } from "node:path";
import pixelmatch from "pixelmatch";
import pngjs from "pngjs";
import { PROOF_END, PROOF_START, QA_END, QA_START, parseProof, proofStart, qaStart, replaceSection } from "../lib/body.ts";
import { ARTIFACTS, QA_RUNS, ROOT, RUN_DIR } from "../lib/env.ts";
import { evaluate, report } from "../lib/gate.ts";
import { baseRef, changedFiles, git, staleFiles, staleSince, tryGit } from "../lib/git.ts";
import { classify, isKind, RECORDED_KINDS, type Kind } from "../lib/policy.ts";
import type { RunInfo } from "../lib/global-setup.ts";
import type { Box, FlowMeta } from "../lib/proof.ts";
import type { QaRun } from "./qa.ts";

const { PNG } = pngjs;
const MAX_ATTACHMENTS = 50;
const VIDEO_EXT = new Set([".mp4", ".mov", ".webm"]);
const IMAGE_EXT = new Set([".png", ".jpg", ".jpeg", ".gif"]);
const KIND_LABEL: Record<Kind, string> = { web: "App", widget: "Chat widget", site: "Site", docs: "Docs", desktop: "Desktop app", ios: "iPhone app", admin: "Admin panel" };

type Added = { kind: Kind; file: string; caption: string; video: boolean };
type Pr = { number: number; body: string; url: string; state: string };
type Still = { key: string; file: string; caption: string; ignore?: Box[] };
type Baseline = { sha: string; runStartedAt?: string; stills: Record<string, string>; ignore?: Record<string, Box[]> };

const argv = process.argv.slice(2);
const flags = new Set<string>();
const opts: { title?: string; body?: string; bodyFile?: string; add: string[] } = { add: [] };
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  const next = () => argv[++i] ?? die(`${a} needs a value`);
  if (a === "--title") opts.title = next();
  else if (a === "--body") opts.body = next();
  else if (a === "--body-file") opts.bodyFile = next();
  else if (a === "--add") opts.add.push(next());
  else if (a === "--dry-run") flags.add(a);
  else die(`unknown flag ${a}`);
}

function die(msg: string): never {
  console.error(`share: ${msg}`);
  process.exit(1);
}

function gh(args: string[], input?: string): { ok: boolean; out: string; err: string } {
  const res = spawnSync("gh", args, { cwd: ROOT, encoding: "utf8", input });
  return { ok: res.status === 0, out: res.stdout ?? "", err: (res.stderr ?? "").trim() };
}

const short = (sha: string) => sha.slice(0, 9);
const sentence = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
const image = (alt: string, ref: string) => `![${alt.replace(/[[\]]/g, "")}](${ref})`;

// Files are attached under the exact path the body references, which gh rewrites to the upload.
class Attachments {
  readonly dir = join(ARTIFACTS, "publish");
  readonly paths: string[] = [];
  constructor() {
    rmSync(this.dir, { recursive: true, force: true });
    mkdirSync(this.dir, { recursive: true });
  }
  add(src: string, name: string): string {
    const dest = join(this.dir, name);
    copyFileSync(src, dest);
    const ref = `./${relative(ROOT, dest)}`;
    this.paths.push(ref);
    return ref;
  }
}

function loadQa(head: string): QaRun {
  const file = join(QA_RUNS, "latest.json");
  if (!existsSync(file)) die("no QA run yet. Run `pnpm qa` first");
  const qa = JSON.parse(readFileSync(file, "utf8")) as QaRun;
  if (qa.dirty) die("the last QA run was made with uncommitted changes. Commit, then `pnpm qa` again");
  if (qa.sha !== head) die(`the last QA run is from ${short(qa.sha)} but HEAD is ${short(head)}. Run \`pnpm qa\` again`);
  if (qa.result !== "pass") die("the last QA run failed. Fix what failed, commit, and `pnpm qa` again");
  return qa;
}

function loadRun(head: string): { run: RunInfo; flows: FlowMeta[] } | undefined {
  const runFile = join(RUN_DIR, "run.json");
  if (!existsSync(runFile)) return undefined;
  const run = JSON.parse(readFileSync(runFile, "utf8")) as RunInfo;
  const flows = readdirSync(RUN_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory() && existsSync(join(RUN_DIR, d.name, "meta.json")))
    .map((d) => JSON.parse(readFileSync(join(RUN_DIR, d.name, "meta.json"), "utf8")) as FlowMeta)
    .sort((a, b) => a.slug.localeCompare(b.slug));
  if (run.sha !== head) {
    console.warn(`share: the last recording is from ${short(run.sha)}, not HEAD (${short(head)}); it is not used`);
    return undefined;
  }
  if (run.dirty) die("the last recording was made with uncommitted changes. Commit, then record again");
  const failed = flows.filter((f) => f.status !== "passed");
  if (failed.length) die(`flows failed in the last recording, fix them and record again: ${failed.map((f) => f.title).join(", ")}`);
  const unencoded = flows.filter((f) => f.frames);
  if (unencoded.length) die(`the recording ended before its videos were encoded (${unencoded.map((f) => f.title).join(", ")}); record again`);
  return flows.length ? { run, flows } : undefined;
}

function parseAdded(): Added[] {
  return opts.add.map((spec) => {
    const m = spec.match(/^([a-z]+):(.+?)(?:#(.*))?$/);
    if (!m || !isKind(m[1])) die(`--add takes <kind>:<file>[#caption], kind one of web, widget, site, docs, desktop, ios, admin; got "${spec}"`);
    const file = resolve(process.cwd(), m[2]);
    if (!existsSync(file)) die(`--add: no such file ${file}`);
    const ext = extname(file).toLowerCase();
    if (!VIDEO_EXT.has(ext) && !IMAGE_EXT.has(ext)) die(`--add: ${file} is neither an image (png, jpg, gif) nor a video (mp4, mov, webm)`);
    if (statSync(file).size > 10 * 1024 * 1024) die(`--add: ${file} is over 10 MB; GitHub refuses larger attachments`);
    return { kind: m[1], file, caption: m[3] ?? basename(file, ext), video: VIDEO_EXT.has(ext) };
  });
}

function currentPr(): Pr | undefined {
  const res = gh(["pr", "view", "--json", "number,body,url,state"]);
  if (!res.ok) return undefined;
  const pr = JSON.parse(res.out) as Pr;
  return pr.state === "OPEN" ? pr : undefined;
}

function qaSection(qa: QaRun, flows: FlowMeta[] | undefined): string {
  const lines = [qaStart(qa.sha, qa.result), "## QA", "", `\`pnpm qa\` at \`${short(qa.sha)}\`, ${qa.files} file(s) changed since \`${qa.base}\`.`, ""];
  if (qa.checks.length) {
    lines.push("| Area | Check | Result |", "| --- | --- | --- |");
    for (const c of qa.checks) lines.push(`| ${c.area} | \`${c.cmd.replace(/\|/g, "\\|").slice(0, 120)}\` | ${c.ok ? "passed" : "failed"}${c.summary ? `, ${c.summary}` : ""} (${c.seconds.toFixed(0)}s) |`);
  } else {
    lines.push("No checked area changed.");
  }
  if (flows?.length) lines.push("", `Proof flows: ${flows.length} passed (${flows.map((f) => f.title).join("; ")}).`);
  if (qa.unchecked.length) lines.push("", `Not checked locally: ${qa.unchecked.join(", ")}.`);
  lines.push(QA_END);
  return lines.join("\n");
}

function proofSection(sha: string, kinds: Kind[], flows: FlowMeta[], added: Added[], files: Attachments): string {
  const lines = [proofStart(sha, kinds), "## Proof", "", `Recorded at \`${short(sha)}\` on the in-memory mocks and the iPhone app's demo mode, with sample data.`, ""];
  for (const flow of flows) {
    lines.push(`### ${KIND_LABEL[flow.target]}: ${sentence(flow.title)}`, "");
    for (const shot of flow.shots) lines.push(`**${shot.caption}**`, "", image(shot.caption, files.add(shot.file, `${flow.slug}-${shot.name}.png`)), "");
    if (flow.video && existsSync(flow.video)) lines.push("Walkthrough:", "", files.add(flow.video, `${flow.slug}.mp4`), "");
  }
  for (const k of new Set(added.map((a) => a.kind))) {
    lines.push(`### ${KIND_LABEL[k]}`, "");
    added.forEach((a, i) => {
      if (a.kind !== k) return;
      const ref = files.add(a.file, `added-${i}-${basename(a.file).replace(/[^a-zA-Z0-9.-]+/g, "-")}`);
      lines.push(`**${a.caption}**`, "", a.video ? ref : image(a.caption, ref), "");
    });
  }
  lines.push(PROOF_END);
  return lines.join("\n");
}

function differs(a: string, b: string, ignore: Box[]): boolean {
  const x = PNG.sync.read(readFileSync(a));
  const y = PNG.sync.read(readFileSync(b));
  if (x.width !== y.width || x.height !== y.height) return true;
  for (const img of [x, y]) {
    for (const bx of ignore) {
      for (let row = Math.max(0, bx.y); row < Math.min(img.height, bx.y + bx.height); row++) {
        img.data.fill(0, (row * img.width + Math.max(0, bx.x)) * 4, (row * img.width + Math.min(img.width, bx.x + bx.width)) * 4);
      }
    }
  }
  const changed = pixelmatch(x.data, y.data, undefined, x.width, x.height, { threshold: 0.1 });
  return changed > Math.max(40, x.width * x.height * 0.0002);
}

function stillsOf(flows: FlowMeta[]): Still[] {
  return flows.flatMap((f) => f.shots.map((s) => ({ key: `${f.slug}__${s.name}`, file: s.file, caption: `${sentence(f.title)}: ${s.caption}`, ignore: s.ignore })));
}

function saveBaseline(file: string, sha: string, runStartedAt: string | undefined, stills: Still[]): void {
  const dir = join(file, "..", "stills");
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  const out: Baseline = { sha, runStartedAt, stills: {}, ignore: {} };
  for (const s of stills) {
    out.stills[s.key] = join(dir, `${s.key}.png`);
    copyFileSync(s.file, out.stills[s.key]);
    if (s.ignore) out.ignore![s.key] = s.ignore;
  }
  writeFileSync(file, JSON.stringify(out, null, 2));
}

// gh replaces each `./path` the body references with its upload. Any it appended instead of
// replacing (it does that for a reference it does not recognise) are moved back into place, in order.
function settle(pr: number, sent: string, refs: string[]): void {
  const now = gh(["pr", "view", String(pr), "--json", "body", "-q", ".body"]);
  if (!now.ok) die(`could not read the description back: ${now.err}`);
  let body = now.out.replace(/\n$/, "");
  const pending = refs.filter((r) => body.includes(r));
  if (!pending.length) return;
  const asset = /https:\/\/github\.com\/user-attachments\/assets\/[0-9A-Za-z-]+/g;
  const before = new Set(sent.match(asset) ?? []);
  const tailStart = body.indexOf(PROOF_END) + PROOF_END.length;
  const tail = body.slice(tailStart);
  const appended = (tail.match(asset) ?? []).filter((u) => !before.has(u));
  if (appended.length < pending.length) die(`${pending.length} attachment(s) did not upload (${pending.join(", ")}). Run \`pnpm share\` again`);
  // Drop the appended lines, then put each upload where its reference is.
  let rest = tail;
  for (const u of appended) rest = rest.replace(new RegExp(`^.*${u.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}.*$\\n?`, "m"), "");
  body = body.slice(0, tailStart) + rest.replace(/\s+$/, "");
  pending.forEach((ref, i) => (body = body.split(ref).join(appended[i])));
  const res = gh(["pr", "edit", String(pr), "--body-file", "-"], `${body}\n`);
  if (!res.ok) die(`could not move the uploads into the Proof section: ${res.err}`);
}

function main(): void {
  const head = git("rev-parse", "HEAD");
  const branch = git("rev-parse", "--abbrev-ref", "HEAD");
  if (branch === "main" || branch === "HEAD") die("share publishes a branch's pull request; this checkout is on main or detached");
  const qa = loadQa(head);
  const base = baseRef();
  const files = changedFiles(base);
  const classified = classify(files);
  const added = parseAdded();
  const recorded = loadRun(head);
  const pr = currentPr();
  const prevBody = pr?.body ?? "";
  const prevProof = parseProof(prevBody);

  if (!flags.has("--dry-run")) {
    if (!tryGit("branch", "-r", "--contains", head)) die(`HEAD (${short(head)}) is not pushed. \`git push -u origin HEAD\` first, so reviewers and CI see the commit`);
  }

  // Which surfaces need proof, and whether the description's current proof still covers them.
  const required = classified.required;
  const uiFiles = required.flatMap((k) => classified.kinds.get(k)!);
  const prevStale = prevProof ? staleFiles(prevProof.sha, head, uiFiles) : "missing";
  const prevCovers = !!prevProof && prevStale !== "missing" && !prevStale.length && required.every((k) => prevProof.kinds.includes(k));
  const baselineFile = pr ? join(ARTIFACTS, "published", `pr-${pr.number}`, "state.json") : "";
  const baseline = baselineFile && existsSync(baselineFile) ? (JSON.parse(readFileSync(baselineFile, "utf8")) as Baseline) : undefined;
  const freshRecording = !!recorded && recorded.run.startedAt !== baseline?.runStartedAt;
  const publishProof = added.length > 0 || freshRecording || (required.length > 0 && !prevCovers);

  const flows = recorded?.flows ?? [];
  const covered = new Set<Kind>([...flows.map((f) => f.target as Kind), ...added.map((a) => a.kind)]);
  if (publishProof) {
    const missing = required.filter((k) => !covered.has(k));
    for (const k of missing) {
      const how =
        k === "ios"
          ? "record an iOS flow (`import { test } from \"../lib/ios.ts\"`) and `pnpm proof <flow>`"
          : RECORDED_KINDS.has(k)
            ? `record a flow with \`test.use({ target: "${k}" })\` and \`pnpm proof <flow>\``
            : `capture it and pass \`--add ${k}:<file>\``;
      console.error(`share: this changes ${k} (${classified.kinds.get(k)!.slice(0, 3).join(", ")}) and there is no proof of it at HEAD: ${how}`);
    }
    if (missing.length) process.exit(1);
    const needVideo = classified.video.filter((k) => !flows.some((f) => f.target === k && f.video) && !added.some((a) => a.kind === k && a.video));
    if (needVideo.length) {
      die(`${needVideo.join(", ")} changes need a walkthrough video and the proof has none. Record a flow (it encodes one), or --add a screen recording`);
    }
  }

  const files_ = new Attachments();
  let body = opts.bodyFile ? readFileSync(resolve(process.cwd(), opts.bodyFile), "utf8") : (opts.body ?? prevBody);
  if ((opts.bodyFile || opts.body) && prevBody) {
    // A new description replaces the text above the sections; the sections are rebuilt below.
    for (const [s, e] of [[QA_START, QA_END], [PROOF_START, PROOF_END]] as const) {
      const m = prevBody.indexOf(s);
      if (m >= 0 && !body.includes(s)) body = replaceSection(body, s, e, prevBody.slice(m, prevBody.indexOf(e, m) + e.length));
    }
  }
  body = replaceSection(body, QA_START, QA_END, qaSection(qa, recorded?.flows));
  const kinds = [...covered];
  if (publishProof && (flows.length || added.length)) {
    body = replaceSection(body, PROOF_START, PROOF_END, proofSection(head, kinds, flows, added, files_));
  } else if (!required.length && prevProof && !freshRecording) {
    // Nothing visible changes any more; the old section would only mislead.
    const i = body.indexOf(PROOF_START);
    if (i >= 0) body = `${body.slice(0, i).trimEnd()}${body.slice(body.indexOf(PROOF_END, i) + PROOF_END.length)}`;
  }
  if (files_.paths.length > MAX_ATTACHMENTS) die(`${files_.paths.length} attachments is over gh's limit of ${MAX_ATTACHMENTS}; record fewer flows`);
  const bodyFile = join(files_.dir, "body.md");
  writeFileSync(bodyFile, `${body.trim()}\n`);

  let args: string[];
  if (pr) {
    args = ["pr", "edit", String(pr.number), "--body-file", bodyFile];
  } else {
    let title = opts.title;
    if (!title) {
      const subjects = git("log", "--format=%s", `${base}..HEAD`).split("\n").filter(Boolean);
      if (subjects.length !== 1) die(`the branch has ${subjects.length} commits; pass --title "feat: ..." for the pull request`);
      title = subjects[0];
    }
    args = ["pr", "create", "--base", base.replace(/^origin\//, ""), "--head", branch, "--title", title, "--body-file", bodyFile];
  }
  for (const p of files_.paths) args.push("--attach", p);

  if (flags.has("--dry-run")) {
    console.log(readFileSync(bodyFile, "utf8"));
    console.log(`\n(dry run) gh ${args.join(" ")}`);
    return;
  }
  const res = spawnSync("gh", args, { cwd: ROOT, stdio: "inherit" });
  if (res.status !== 0) die("gh failed; nothing was recorded as published");
  const published = pr ?? currentPr();
  if (!published) die("the pull request was not found after gh created it");
  if (files_.paths.length) settle(published.number, readFileSync(bodyFile, "utf8"), files_.paths);

  // A follow-up that changes the stills gets a before/after comment, so a reviewer sees what moved.
  const stateFile = join(ARTIFACTS, "published", `pr-${published.number}`, "state.json");
  if (publishProof && flows.length) {
    const stills = stillsOf(flows);
    if (baseline) comment(published.number, baseline, stills, head);
    saveBaseline(stateFile, head, recorded?.run.startedAt, stills);
  }

  const final = gh(["pr", "view", String(published.number), "--json", "body", "-q", ".body"]).out;
  const gate = evaluate({ files, body: final, labels: [], author: "", head, stale: (from, f) => staleSince(from, head, base, f) });
  console.log(`share: published to ${published.url}`);
  console.log(report(gate));
  if (!gate.ok) process.exit(1);
}

function comment(pr: number, base: Baseline, stills: Still[], head: string): void {
  const files = new Attachments();
  const lines = [`### Proof update: \`${short(base.sha)}..${short(head)}\``, ""];
  const subjects = tryGit("log", "--format=%s", "--max-count=20", `${base.sha}..${head}`)?.split("\n").filter(Boolean) ?? [];
  for (const s of subjects) lines.push(`- ${s}`);
  if (subjects.length) lines.push("");
  let changed = 0;
  let unchanged = 0;
  for (const s of stills) {
    const before = base.stills[s.key];
    const name = s.key.replace(/[^a-z0-9-]+/g, "-");
    if (!before || !existsSync(before)) {
      lines.push(`**${s.caption}** (new)`, "", image(s.caption, files.add(s.file, `${name}.png`)), "");
      changed++;
    } else if (differs(before, s.file, [...(base.ignore?.[s.key] ?? []), ...(s.ignore ?? [])])) {
      const b = files.add(before, `before-${name}.png`);
      const a = files.add(s.file, `${name}.png`);
      lines.push(`**${s.caption}** (changed)`, "", "| Before | After |", "| --- | --- |", `| ${image(`${s.caption}, before`, b)} | ${image(`${s.caption}, after`, a)} |`, "");
      changed++;
    } else unchanged++;
  }
  if (!changed) {
    console.log(`share: no still changed since ${short(base.sha)}; no comment posted`);
    return;
  }
  if (unchanged) lines.push(`Unchanged: ${unchanged} screen${unchanged === 1 ? "" : "s"}. The description's Proof section has every current still and video.`);
  const bodyFile = join(files.dir, "comment.md");
  writeFileSync(bodyFile, `${lines.join("\n").trimEnd()}\n`);
  const args = ["pr", "comment", String(pr), "--body-file", bodyFile];
  for (const p of files.paths.slice(0, MAX_ATTACHMENTS)) args.push("--attach", p);
  const res = spawnSync("gh", args, { cwd: ROOT, stdio: "inherit" });
  if (res.status !== 0) console.warn("share: the before/after comment did not post; the description is up to date");
}

main();
