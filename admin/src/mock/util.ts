// Small helpers shared by the mock backend: a seeded RNG, ids and time.
//
// Every time is derived from NOW, read once when the mock loads (the QA harness
// freezes Date before that), and every random choice from the seeded PRNG below,
// so the seed and the ids are the same on every load.

const SEED = 0x6a09e667;
let rngState = SEED;

/** Starts the sequence over, so every seed() makes the same rows. */
export function reseed() {
  rngState = SEED;
}

/** Deterministic PRNG (mulberry32). */
export function rand(): number {
  rngState |= 0;
  rngState = (rngState + 0x6d2b79f5) | 0;
  let t = Math.imul(rngState ^ (rngState >>> 15), 1 | rngState);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

export function int(min: number, max: number): number {
  return Math.floor(rand() * (max - min + 1)) + min;
}

export function pick<T>(arr: readonly T[]): T {
  return arr[Math.floor(rand() * arr.length)];
}

export function chance(p: number): boolean {
  return rand() < p;
}

/** UUID-shaped and deterministic: the API's ids are UUIDs, and the panel links by them. */
export function uuid(): string {
  const hex = (n: number, len: number) => Math.floor(n).toString(16).padStart(len, "0").slice(-len);
  return `${hex(rand() * 0xffffffff, 8)}-${hex(rand() * 0xffff, 4)}-4${hex(rand() * 0xfff, 3)}-${hex((rand() * 0x3fff) | 0x8000, 4)}-${hex(rand() * 0xffffff, 6)}${hex(rand() * 0xffffff, 6)}`;
}

export function isUuid(s: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

export const MIN = 60_000;
export const HOUR = 60 * MIN;
export const DAY = 24 * HOUR;

export const NOW = Date.now();

export function ago(ms: number): string {
  return new Date(NOW - ms).toISOString();
}

export function iso(ms: number): string {
  return new Date(ms).toISOString();
}

/** The current time: Date.now(), which the harness freezes. */
export function nowIso(): string {
  return new Date().toISOString();
}

export function slugify(s: string): string {
  return (
    s
      .normalize("NFKD")
      .toLowerCase()
      .replace(/[̀-ͯ]/g, "")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 48) || "workspace"
  );
}

export function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** Rounds to cents. */
export function cents(n: number): number {
  return Math.round(n * 100) / 100;
}

/** Rounds to micro-dollars, as the API does. */
export function micro(n: number): number {
  return Math.round(n * 1e6) / 1e6;
}

/** The first of this month, UTC: the AI allowance's period. */
export function periodStart(now = Date.now()): Date {
  const d = new Date(now);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1));
}

export function periodEnd(now = Date.now()): Date {
  const d = new Date(now);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1));
}

/** Letters and digits without look-alikes, like the API's generated passwords. */
const UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const LOWER = "abcdefghijkmnpqrstuvwxyz";
const PASSWORD_ALPHABET = `${UPPER}${LOWER}23456789`;

/** A test account's password: four groups of six, upper and lower case and digits. */
export function generatePassword(): string {
  for (;;) {
    const pw = Array.from({ length: 4 }, () => Array.from({ length: 6 }, () => PASSWORD_ALPHABET[Math.floor(rand() * PASSWORD_ALPHABET.length)]).join("")).join("-");
    if (/[A-Z]/.test(pw) && /[a-z]/.test(pw) && /\d/.test(pw)) return pw;
  }
}
