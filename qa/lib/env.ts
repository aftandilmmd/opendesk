import { join } from "node:path";
import { QA_DIR, ROOT } from "./git.ts";

export { QA_DIR, ROOT };
export const ARTIFACTS = join(QA_DIR, ".artifacts");
export const RUN_DIR = join(ARTIFACTS, "run");
export const QA_RUNS = join(ARTIFACTS, "qa");

// A laptop-sized window: the app is dense, and wider frames are mostly empty margin on GitHub.
export const VIDEO = {
  width: Number(process.env.QA_WIDTH ?? 1440),
  height: Number(process.env.QA_HEIGHT ?? 900),
  fps: Number(process.env.QA_FPS ?? 30),
  crf: Number(process.env.QA_CRF ?? 18),
  preset: process.env.QA_PRESET ?? "slow",
};

// The repo is public and recordings are uploaded to it, so only a local dev server may be recorded.
export function assertLocal(url: string): void {
  const host = new URL(url).hostname;
  if (!["localhost", "127.0.0.1", "[::1]", "::1"].includes(host) && !host.endsWith(".localhost")) {
    throw new Error(`refusing to record ${url}: recordings are published to a public repo, so only a local dev server is allowed`);
  }
}
