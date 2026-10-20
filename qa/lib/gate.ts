// The rule every pull request is held to: a QA run that covers its head commit, and recorded proof
// (stills, plus a walkthrough video where the surface has behaviour) for every surface it changes.
// Shared by the CI check, `pnpm gate` and the Claude Code Stop hook. Pure node.
import { parseProof, parseQa } from "./body.ts";
import { classify, UNENFORCED_KINDS, type Classified, type Kind } from "./policy.ts";

// A maintainer applies this in the GitHub UI when a pull request cannot carry QA or proof.
// Agents never apply it (the PreToolUse hook refuses).
export const EXEMPT_LABEL = "qa-exempt";

export type GateInput = {
  files: string[];
  body: string;
  labels: string[];
  author: string;
  head: string;
  // Files among `files` that read differently at `head` than at `from`; "missing" when `from` is gone.
  stale: (from: string, files: string[]) => string[] | "missing";
};

export type GateResult = { ok: boolean; exempt?: string; problems: string[]; notes: string[]; classified: Classified };

const short = (sha: string) => sha.slice(0, 9);

function list(files: string[], max = 6): string {
  const shown = files.slice(0, max).map((f) => `\`${f}\``);
  return files.length > max ? `${shown.join(", ")} and ${files.length - max} more` : shown.join(", ");
}

function staleProblem(what: string, from: string, stale: string[] | "missing", fix: string): string | undefined {
  if (stale === "missing") return `${what} was made at \`${short(from)}\`, which is no longer in this branch's history (rebased or force-pushed). ${fix}`;
  if (stale.length) return `${what} was made at \`${short(from)}\`, and these files changed after it: ${list(stale)}. ${fix}`;
  return undefined;
}

export function evaluate(input: GateInput): GateResult {
  const classified = classify(input.files);
  const result: GateResult = { ok: true, problems: [], notes: [], classified };

  for (const k of UNENFORCED_KINDS) {
    if (classified.kinds.has(k)) result.notes.push(`Touches ${k} (${list(classified.kinds.get(k)!, 3)}), which the harness cannot record yet; review those screens by hand.`);
  }
  if (input.author.endsWith("[bot]")) return { ...result, exempt: `opened by ${input.author}` };
  if (input.labels.includes(EXEMPT_LABEL)) return { ...result, exempt: `labelled \`${EXEMPT_LABEL}\`` };

  const qa = parseQa(input.body);
  if (!qa) {
    result.problems.push("The description has no QA section. Run `pnpm qa` in `qa/`, then `pnpm share`.");
  } else {
    if (qa.result !== "pass") result.problems.push(`The QA run at \`${short(qa.sha)}\` did not pass. Fix what failed, commit, run \`pnpm qa\` again, then \`pnpm share\`.`);
    const p = staleProblem("The QA run", qa.sha, input.stale(qa.sha, input.files), "Run `pnpm qa` and `pnpm share` again.");
    if (p) result.problems.push(p);
  }

  if (!classified.required.length) {
    result.ok = !result.problems.length;
    return result;
  }

  const proof = parseProof(input.body);
  const surfaces = classified.required.join(", ");
  if (!proof) {
    result.problems.push(`This changes what people see (${surfaces}), and the description has no Proof section. Record it with \`pnpm proof <flow>\` in \`qa/\` (qa/README.md "When proof is required"), then \`pnpm share\`.`);
  } else {
    const missing: Kind[] = classified.required.filter((k) => !proof.kinds.includes(k));
    for (const k of missing) {
      result.problems.push(`The proof does not cover ${k}, which this changes (${list(classified.kinds.get(k)!, 3)}). Record a flow for it and \`pnpm share\` again.`);
    }
    if (proof.stills < 1) result.problems.push("The Proof section has no screenshots.");
    if (classified.video.length && proof.videos < 1) {
      result.problems.push(`The Proof section has no walkthrough video, which ${classified.video.join(", ")} changes need. \`pnpm share\` attaches the flow videos unless they were left out.`);
    }
    if (proof.unresolved) result.problems.push(`${proof.unresolved} attachment(s) in the Proof section never uploaded (a local \`./\` path is still there). Run \`pnpm share\` again.`);
    const ui = [...classified.kinds.entries()].filter(([k]) => classified.required.includes(k)).flatMap(([, f]) => f);
    // Only a change to something the proof shows makes it stale.
    const stale = input.stale(proof.sha, ui);
    const shown = stale === "missing" ? stale : stale.filter((f) => classify([f]).required.length > 0);
    const p = staleProblem("The proof", proof.sha, shown, "Record again and `pnpm share`.");
    if (p) result.problems.push(p);
  }
  result.ok = !result.problems.length;
  return result;
}

export function report(r: GateResult): string {
  const lines: string[] = [];
  const surfaces = r.classified.required.length ? r.classified.required.join(", ") : "none";
  if (r.exempt) lines.push(`QA gate: exempt (${r.exempt}).`);
  else if (r.ok) lines.push(`QA gate: passed. Surfaces needing proof: ${surfaces}.`);
  else {
    lines.push(`QA gate: failed. Surfaces needing proof: ${surfaces}.`, "");
    for (const p of r.problems) lines.push(`- ${p}`);
  }
  if (r.notes.length) lines.push("", ...r.notes.map((n) => `- ${n}`));
  return lines.join("\n");
}
