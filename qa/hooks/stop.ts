// Claude Code Stop hook: an agent does not finish while its branch's open pull request fails the
// QA gate (stale or missing QA, missing proof). Pure node, no install needed.
//
// It blocks at most three times for the same pull request state, then lets the agent stop and tells
// the user, so an agent that cannot meet the gate (no network, a broken flow) does not loop.
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { report } from "../lib/gate.ts";
import { tryGit } from "../lib/git.ts";
import { checkPr, localPr } from "../scripts/gate.ts";

const MAX_BLOCKS = 3;

type Input = { session_id?: string };

function main(): void {
  let input: Input = {};
  try {
    input = JSON.parse(readFileSync(0, "utf8")) as Input;
  } catch {
    // Run by hand.
  }
  const branch = tryGit("rev-parse", "--abbrev-ref", "HEAD");
  if (!branch || branch === "HEAD" || branch === "main") return;
  // Only a pushed branch can have a pull request; this keeps gh off the network for local work.
  if (!tryGit("rev-parse", "--verify", "--quiet", `refs/remotes/origin/${branch}`)) return;
  const pr = localPr();
  if (!pr) return;
  let result;
  try {
    result = checkPr(pr);
  } catch {
    return;
  }
  if (result.ok || result.exempt) return;

  const local = tryGit("rev-parse", "HEAD");
  const unpushed = local && local !== pr.head ? `\n\nHEAD (${local.slice(0, 9)}) is not what the pull request shows (${pr.head.slice(0, 9)}): push, then \`pnpm qa\` and \`pnpm share\`.` : "";
  const reason = `Pull request #${pr.number} does not meet the QA gate yet, and CI's Proof check will fail the same way.\n\n${report(result)}${unpushed}\n\nThe loop is in qa/README.md: \`pnpm qa\`, \`pnpm proof <flow>\` for a visible change, \`pnpm share\`.`;

  const dir = join(tmpdir(), "opendesk-qa-stop");
  mkdirSync(dir, { recursive: true });
  const key = createHash("sha256").update(`${input.session_id ?? ""}:${pr.number}:${pr.head}:${pr.body}`).digest("hex").slice(0, 16);
  const file = join(dir, `${key}.count`);
  let count = 0;
  try {
    count = Number(readFileSync(file, "utf8")) || 0;
  } catch {
    // First time for this state.
  }
  writeFileSync(file, String(count + 1));
  if (count >= MAX_BLOCKS) {
    process.stdout.write(JSON.stringify({ systemMessage: `QA gate: #${pr.number} still fails after ${MAX_BLOCKS} attempts.\n${report(result)}` }));
    return;
  }
  process.stdout.write(JSON.stringify({ decision: "block", reason }));
}

main();
