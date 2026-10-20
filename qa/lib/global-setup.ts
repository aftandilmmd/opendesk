import { existsSync, mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { ARTIFACTS, QA_DIR, RUN_DIR } from "./env.ts";
import { git } from "./git.ts";
import { acquireRecordingLock, releaseRecordingLock } from "./lock.ts";

export type RunInfo = { sha: string; branch: string; dirty: boolean; startedAt: string };

// Keeps only this run's traces: earlier runs' output directories belong to processes that have exited.
function pruneOldResults(): void {
  const dir = join(ARTIFACTS, "test-results");
  if (!existsSync(dir)) return;
  for (const name of readdirSync(dir)) {
    const pid = Number(name.replace(/^run-/, ""));
    if (pid === process.pid) continue;
    try {
      process.kill(pid, 0);
    } catch {
      rmSync(join(dir, name), { recursive: true, force: true });
    }
  }
}

export default async function globalSetup(): Promise<void> {
  await acquireRecordingLock(QA_DIR);
  try {
    rmSync(RUN_DIR, { recursive: true, force: true });
    mkdirSync(RUN_DIR, { recursive: true });
    pruneOldResults();
  } catch (err) {
    releaseRecordingLock();
    throw err;
  }
  const run: RunInfo = {
    sha: git("rev-parse", "HEAD"),
    branch: git("rev-parse", "--abbrev-ref", "HEAD"),
    dirty: git("status", "--porcelain", "--untracked-files=no").length > 0,
    startedAt: new Date().toISOString(),
  };
  writeFileSync(join(RUN_DIR, "run.json"), JSON.stringify(run, null, 2));
}
