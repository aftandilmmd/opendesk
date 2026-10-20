import { execFileSync, spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const QA_DIR = join(dirname(fileURLToPath(import.meta.url)), "..");
export const ROOT = join(QA_DIR, "..");

export function git(...args: string[]): string {
  return execFileSync("git", args, { cwd: ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
}

export function tryGit(...args: string[]): string | undefined {
  const res = spawnSync("git", args, { cwd: ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  return res.status === 0 ? res.stdout.trim() : undefined;
}

export function hasCommit(sha: string): boolean {
  return tryGit("cat-file", "-e", `${sha}^{commit}`) !== undefined;
}

export function lines(s: string | undefined): string[] {
  return (s ?? "").split("\n").filter(Boolean);
}

// The files a branch changes: from where it left `base` to `ref`, like a pull request's file list.
export function changedFiles(base: string, ref = "HEAD"): string[] {
  return lines(git("diff", "--name-only", "--no-renames", `${base}...${ref}`));
}

// The default branch as this checkout knows it.
export function baseRef(): string {
  return tryGit("rev-parse", "--verify", "--quiet", "origin/main") ? "origin/main" : "main";
}

// Which of `files` read differently at `head` than at `from`, where `from` is the commit a
// QA run or recording was made at. "missing" when `from` is not in this history (rebased away).
export function staleFiles(from: string, head: string, files: readonly string[]): string[] | "missing" {
  if (from === head || !files.length) return [];
  if (!hasCommit(from)) return "missing";
  const out: string[] = [];
  // Chunked, so a pull request touching thousands of files stays under the argument limit.
  for (let i = 0; i < files.length; i += 500) {
    out.push(...lines(git("diff", "--name-only", "--no-renames", from, head, "--", ...files.slice(i, i + 500))));
  }
  return out;
}

// The files a QA run at `from` vouched for that `head` now has differently: the pull request's own
// files at either commit, so a rebase onto a newer main alone never makes a run stale.
export function staleSince(from: string, head: string, base: string, files: readonly string[]): string[] | "missing" {
  if (from === head) return [];
  if (!hasCommit(from)) return "missing";
  const own = new Set([...files, ...changedFiles(base, from)]);
  return staleFiles(from, head, [...own]);
}
