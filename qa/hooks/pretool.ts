// Claude Code PreToolUse hook (Bash): keeps every pull request on the path the QA gate checks.
// Exit 2 refuses the command and shows the agent why. Pure node, no install needed.
import { readFileSync } from "node:fs";
import { EXEMPT_LABEL } from "../lib/gate.ts";

type Input = { tool_name?: string; tool_input?: { command?: string } };

// A command that runs `tool`: at the start of the line or after a separator, past any `VAR=x`
// prefixes. Text that only mentions it (a heredoc, a commit message, docs) is not one.
function invokes(tool: string, args: string): RegExp {
  return new RegExp(String.raw`(^|[;&|(\n]|\$\()\s*(\w+=\S*\s+)*${tool}\s+${args}`, "m");
}
// The rest of that command, up to the next separator.
const REST = String.raw`[^;&|\n]*`;

const RULES: [RegExp, string][] = [
  [
    invokes("gh", String.raw`pr\s+create\b`),
    "Open pull requests with `pnpm share` in qa/ (after `pnpm qa`, and `pnpm proof <flow>` for a visible change). It creates the pull request with its QA and Proof sections; pass --title and --body-file for the title and description.",
  ],
  [invokes("gh", String.raw`pr\s+merge\b${REST}--admin\b`), "Merging past the merge queue's checks is for the maintainer. Leave the pull request to the queue."],
  [
    invokes("gh", String.raw`api\b(?=${REST}\b(rulesets|protection)\b)(?=${REST}(\s(-X|--method)[=\s]*(PUT|PATCH|POST|DELETE)\b|\s(-f|-F|--field|--raw-field|--input)\b))`),
    "Repository rulesets and branch protection are the maintainer's to change.",
  ],
  [
    invokes("(gh|curl)", `${REST}${EXEMPT_LABEL}`),
    `The \`${EXEMPT_LABEL}\` label is the maintainer's, applied in GitHub. Meet the gate instead: \`pnpm qa\`, \`pnpm proof\`, \`pnpm share\` (qa/README.md).`,
  ],
];

function main(): void {
  let input: Input;
  try {
    input = JSON.parse(readFileSync(0, "utf8")) as Input;
  } catch {
    return;
  }
  const cmd = input.tool_input?.command;
  if (input.tool_name !== "Bash" || !cmd) return;
  for (const [re, why] of RULES) {
    if (re.test(cmd)) {
      process.stderr.write(`Blocked by the QA hook (qa/hooks/pretool.ts): ${why}\n`);
      process.exit(2);
    }
  }
}

main();
