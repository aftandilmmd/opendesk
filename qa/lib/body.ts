// The QA and Proof sections of a pull request description: how `pnpm share` writes them and
// how the gate reads them back. Pure node, like policy.ts.
import { isKind, type Kind } from "./policy.ts";

export const QA_START = "<!-- opendesk-qa:start";
export const QA_END = "<!-- opendesk-qa:end -->";
export const PROOF_START = "<!-- opendesk-proof:start";
export const PROOF_END = "<!-- opendesk-proof:end -->";

// GitHub stores every uploaded image and video under this prefix.
const ASSET = String.raw`https://github\.com/user-attachments/assets/[0-9A-Za-z-]+`;
const IMAGE_MD = new RegExp(String.raw`!\[[^\]]*\]\(${ASSET}\)`, "g");
const IMAGE_TAG = new RegExp(String.raw`<img\b[^>]*\bsrc="${ASSET}"`, "g");
// gh leaves a video as its bare URL on its own line, which GitHub renders as a player.
const VIDEO_LINE = new RegExp(String.raw`^\s*${ASSET}\s*$`, "gm");
const VIDEO_TAG = new RegExp(String.raw`<video\b[^>]*\bsrc="${ASSET}"`, "g");
// A reference gh did not replace: the upload failed or the file was never attached.
const LOCAL_REF = /\]\(\.\/[^)]*\)|^\s*\.\/\S+\.(mp4|mov|webm|png|jpe?g)\s*$/gm;

export type QaSection = { sha: string; result: string; text: string };
export type ProofSection = { sha: string; kinds: Kind[]; stills: number; videos: number; unresolved: number; text: string };

function section(body: string, start: string, end: string): { attrs: Record<string, string>; text: string } | undefined {
  const i = body.indexOf(start);
  if (i < 0) return undefined;
  const close = body.indexOf("-->", i);
  const j = body.indexOf(end, i);
  if (close < 0 || j < 0) return undefined;
  const attrs: Record<string, string> = {};
  for (const m of body.slice(i + start.length, close).matchAll(/([a-z]+)=(\S+)/g)) attrs[m[1]] = m[2];
  return { attrs, text: body.slice(close + 3, j) };
}

const count = (text: string, re: RegExp) => (text.match(re) ?? []).length;

export function parseQa(body: string): QaSection | undefined {
  const s = section(body, QA_START, QA_END);
  if (!s || !/^[0-9a-f]{40}$/.test(s.attrs.sha ?? "")) return undefined;
  return { sha: s.attrs.sha, result: s.attrs.result ?? "", text: s.text };
}

export function parseProof(body: string): ProofSection | undefined {
  const s = section(body, PROOF_START, PROOF_END);
  if (!s || !/^[0-9a-f]{40}$/.test(s.attrs.sha ?? "")) return undefined;
  const kinds = (s.attrs.kinds ?? "").split(",").filter(isKind);
  return {
    sha: s.attrs.sha,
    kinds,
    stills: count(s.text, IMAGE_MD) + count(s.text, IMAGE_TAG),
    videos: count(s.text, VIDEO_LINE) + count(s.text, VIDEO_TAG),
    unresolved: count(s.text, LOCAL_REF),
    text: s.text,
  };
}

export function qaStart(sha: string, result: string): string {
  return `${QA_START} sha=${sha} result=${result} -->`;
}

export function proofStart(sha: string, kinds: readonly Kind[]): string {
  return `${PROOF_START} sha=${sha} kinds=${kinds.join(",")} -->`;
}

// Replaces one section in place, or appends it; everything else in the description is kept.
export function replaceSection(body: string, start: string, end: string, next: string): string {
  const i = body.indexOf(start);
  const j = i < 0 ? -1 : body.indexOf(end, i);
  if (i < 0 || j < 0) return `${body.trimEnd()}${body.trim() ? "\n\n" : ""}${next.trim()}\n`;
  return `${body.slice(0, i)}${next.trim()}${body.slice(j + end.length)}`;
}
