// `pnpm gate`: holds a pull request to the QA rule (lib/gate.ts) and prints what is missing.
// CI runs it with --ci from main's copy, against the pull request's commits and its current description.
//
//   node scripts/gate.ts          this branch's open pull request
//   node scripts/gate.ts --ci     the pull request in GITHUB_EVENT_PATH (the Proof workflow)
import { spawnSync } from "node:child_process";
import { appendFileSync, readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { evaluate, report, type GateResult } from "../lib/gate.ts";
import { changedFiles, git, hasCommit, ROOT, staleSince } from "../lib/git.ts";

export type PrState = { number: number; body: string; labels: string[]; author: string; head: string; base: string };

function gh(args: string[]): string {
  const res = spawnSync("gh", args, { cwd: ROOT, encoding: "utf8" });
  if (res.status !== 0) throw new Error(`gh ${args.slice(0, 3).join(" ")} failed: ${(res.stderr ?? "").trim()}`);
  return res.stdout;
}

export function checkPr(pr: PrState): GateResult {
  if (!hasCommit(pr.head)) throw new Error(`the pull request's head ${pr.head.slice(0, 9)} is not in this checkout; fetch it first`);
  const base = `origin/${pr.base}`;
  return evaluate({
    files: changedFiles(base, pr.head),
    body: pr.body ?? "",
    labels: pr.labels,
    author: pr.author,
    head: pr.head,
    stale: (from, files) => staleSince(from, pr.head, base, files),
  });
}

// This branch's open pull request, or undefined when there is none (or gh is not signed in).
export function localPr(): PrState | undefined {
  const res = spawnSync("gh", ["pr", "view", "--json", "number,body,labels,headRefOid,baseRefName,author,state"], { cwd: ROOT, encoding: "utf8" });
  if (res.status !== 0) return undefined;
  const pr = JSON.parse(res.stdout) as { number: number; body: string; labels: { name: string }[]; headRefOid: string; baseRefName: string; author: { login: string }; state: string };
  if (pr.state !== "OPEN") return undefined;
  return { number: pr.number, body: pr.body, labels: pr.labels.map((l) => l.name), author: pr.author.login, head: pr.headRefOid, base: pr.baseRefName };
}

function ciPr(): PrState {
  const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH!, "utf8")) as { pull_request: { number: number; head: { sha: string }; base: { ref: string } } };
  const n = event.pull_request.number;
  // The description and labels as they are now, not as the event that started this run saw them.
  const pr = JSON.parse(gh(["api", `repos/${process.env.GITHUB_REPOSITORY}/pulls/${n}`])) as { body: string | null; labels: { name: string }[]; user: { login: string } };
  return { number: n, body: pr.body ?? "", labels: pr.labels.map((l) => l.name), author: pr.user.login, head: event.pull_request.head.sha, base: event.pull_request.base.ref };
}

function main(): void {
  const ci = process.argv.includes("--ci");
  const pr = ci ? ciPr() : localPr();
  if (!pr) {
    console.log("gate: this branch has no open pull request. `pnpm share` opens one with its QA and Proof sections.");
    return;
  }
  if (!ci) git("fetch", "--quiet", "origin", pr.base);
  const result = checkPr(pr);
  const text = report(result);
  console.log(text);
  if (ci && process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${text}\n\nThe rule and how to meet it: \`qa/README.md\`.\n`);
  if (!result.ok && !result.exempt) process.exit(1);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
