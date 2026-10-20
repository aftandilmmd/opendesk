import assert from "node:assert/strict";
import { test } from "node:test";
import { parseProof, parseQa, PROOF_END, proofStart, QA_END, qaStart, replaceSection } from "./body.ts";
import { EXEMPT_LABEL, evaluate, type GateInput } from "./gate.ts";
import { classify, kindOf } from "./policy.ts";

const A = "a".repeat(40);
const B = "b".repeat(40);
const IMG = "![Inbox](https://github.com/user-attachments/assets/0f6c1a2b-1111-4222-8333-944455556666)";
const VID = "https://github.com/user-attachments/assets/1f6c1a2b-1111-4222-8333-944455556666";

const qa = (sha = A, result = "pass") => `${qaStart(sha, result)}\n## QA\n${QA_END}`;
const proof = (sha = A, kinds = "web", inner = `${IMG}\n\n${VID}\n`) => `${proofStart(sha, kinds.split(",") as never)}\n## Proof\n${inner}${PROOF_END}`;

function input(over: Partial<GateInput>): GateInput {
  return { files: [], body: "", labels: [], author: "someone", head: A, stale: () => [], ...over };
}

test("kinds: app code is web, mock and tests are not", () => {
  assert.equal(kindOf("web/src/components/inbox/List.tsx"), "web");
  assert.equal(kindOf("web/src/lib/api/client.ts"), "web");
  assert.equal(kindOf("web/src/mock/seed.ts"), undefined);
  assert.equal(kindOf("web/src/lib/time.test.ts"), undefined);
  assert.equal(kindOf("web/widget/src/ui.tsx"), "widget");
  assert.equal(kindOf("web/widget/src/mock.ts"), undefined);
  assert.equal(kindOf("docs/src/content/docs/api.mdx"), undefined);
  assert.equal(kindOf("docs/src/components/Hero.astro"), "docs");
  assert.equal(kindOf("site/src/pages/index.astro"), "site");
  assert.equal(kindOf("ios/OpenDesk/Views/InboxView.swift"), "ios");
  assert.equal(kindOf("ios/OpenDeskTests/InboxTests.swift"), undefined);
  assert.equal(kindOf("internal/core/auth.go"), undefined);
});

test("classify: brand tokens touch the app and the site; every surface's video rule", () => {
  const c = classify(["brand/tokens.css", "admin/src/pages/Users.tsx", "desktop/src/main/tray.ts", "ios/Opendesk/Features/Inbox/InboxView.swift", "internal/x.go"]);
  assert.deepEqual(c.required, ["web", "site", "desktop", "ios", "admin"]);
  assert.deepEqual(c.video, ["web", "desktop", "ios", "admin"]);
  assert.equal(kindOf("admin/src/mock/seed.ts"), undefined);
});

test("body: sections parse, count stills and videos, and flag unuploaded references", () => {
  const body = `Some text\n\n${qa()}\n\n${proof(A, "web,site", `${IMG}\n\n${VID}\n\n![x](./qa/.artifacts/publish/a.png)\n./qa/.artifacts/publish/a.mp4\n`)}`;
  assert.deepEqual(parseQa(body), { sha: A, result: "pass", text: "\n## QA\n" });
  const p = parseProof(body)!;
  assert.deepEqual(p.kinds, ["web", "site"]);
  assert.equal(p.stills, 1);
  assert.equal(p.videos, 1);
  assert.equal(p.unresolved, 2);
});

test("body: replaceSection keeps the description and swaps only the section", () => {
  const body = `Intro\n\n${qa(A)}\n\nOutro`;
  const next = replaceSection(body, "<!-- opendesk-qa:start", QA_END, qa(B));
  assert.ok(next.startsWith("Intro\n\n"));
  assert.ok(next.endsWith("\n\nOutro"));
  assert.equal(parseQa(next)!.sha, B);
  assert.equal(parseQa(replaceSection("Intro", "<!-- opendesk-qa:start", QA_END, qa(B)))!.sha, B);
});

test("gate: every pull request needs a passing, current QA section", () => {
  assert.match(evaluate(input({ files: ["internal/x.go"] })).problems.join(), /no QA section/);
  assert.match(evaluate(input({ files: ["internal/x.go"], body: qa(A, "fail") })).problems.join(), /did not pass/);
  assert.match(evaluate(input({ files: ["internal/x.go"], body: qa(B), stale: () => ["internal/x.go"] })).problems.join(), /changed after it/);
  assert.match(evaluate(input({ files: ["internal/x.go"], body: qa(B), stale: () => "missing" })).problems.join(), /no longer in this branch/);
  assert.equal(evaluate(input({ files: ["internal/x.go"], body: qa() })).ok, true);
});

test("gate: a visible change needs stills, a video where it behaves, for every surface, made after the last UI edit", () => {
  const files = ["web/src/pages/Inbox.tsx", "site/src/pages/index.astro"];
  assert.match(evaluate(input({ files, body: qa() })).problems.join(), /no Proof section/);
  assert.match(evaluate(input({ files, body: `${qa()}\n${proof(A, "web")}` })).problems.join(), /does not cover site/);
  assert.match(evaluate(input({ files, body: `${qa()}\n${proof(A, "web,site", `${IMG}\n`)}` })).problems.join(), /no walkthrough video/);
  assert.match(evaluate(input({ files, body: `${qa()}\n${proof(A, "web,site", `${VID}\n`)}` })).problems.join(), /no screenshots/);
  const stale = evaluate(input({ files, body: `${qa()}\n${proof(B, "web,site")}`, stale: (from) => (from === B ? ["web/src/pages/Inbox.tsx"] : []) }));
  assert.match(stale.problems.join(), /The proof was made/);
  assert.equal(evaluate(input({ files, body: `${qa()}\n${proof(A, "web,site")}` })).ok, true);
  // A later change to code nobody sees leaves the proof current (QA still has to be run again).
  const later = evaluate(input({ files, body: `${qa(B)}\n${proof(B, "web,site")}`, stale: () => ["internal/x.go"] }));
  assert.equal(later.problems.length, 1);
  assert.match(later.problems[0], /The QA run/);
});

test("gate: site and docs need stills only", () => {
  assert.equal(evaluate(input({ files: ["docs/src/components/Hero.astro"], body: `${qa()}\n${proof(A, "docs", `${IMG}\n`)}` })).ok, true);
});

test("gate: the maintainer's label and bots are exempt", () => {
  assert.ok(evaluate(input({ files: ["web/src/a.tsx"], labels: [EXEMPT_LABEL] })).exempt);
  assert.ok(evaluate(input({ files: ["web/src/a.tsx"], author: "dependabot[bot]" })).exempt);
});
