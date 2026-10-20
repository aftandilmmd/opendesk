import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { test } from "node:test";

const HOOK = join(import.meta.dirname, "pretool.ts");

function blocked(command: string): boolean {
  const res = spawnSync("node", [HOOK], { input: JSON.stringify({ tool_name: "Bash", tool_input: { command } }), encoding: "utf8" });
  return res.status === 2;
}

test("refuses the commands that step around the gate", () => {
  assert.ok(blocked("gh pr create --title x --body y"));
  assert.ok(blocked("cd qa && gh pr create --fill"));
  assert.ok(blocked("GH_HOST=github.com gh pr create"));
  assert.ok(blocked("gh pr merge 5 --squash --admin"));
  assert.ok(blocked("gh pr edit 5 --add-label qa-exempt"));
  assert.ok(blocked("gh api repos/o/r/rulesets/1 -X PUT --input r.json"));
  assert.ok(blocked("gh api repos/o/r/branches/main/protection --method DELETE"));
});

test("lets everything else through, including text that only mentions those commands", () => {
  assert.ok(!blocked("gh pr view --json body"));
  assert.ok(!blocked("gh pr merge 5 --auto --squash"));
  assert.ok(!blocked("gh api repos/o/r/rulesets"));
  assert.ok(!blocked("git push -u origin HEAD"));
  assert.ok(!blocked("cd qa && pnpm share --title 'feat: x' --body-file pr.md"));
  assert.ok(!blocked("grep -rn qa-exempt qa/"));
  assert.ok(!blocked("python3 - <<'EOF'\ns = 'never `gh pr create`, never the qa-exempt label'\nEOF"));
  assert.ok(!blocked("git commit -m 'feat: block gh pr create in the QA hook'"));
});
