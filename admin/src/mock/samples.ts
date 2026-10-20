// Sample data batches in test workspaces (contracts/admin.md "Test workspaces"):
// what a batch adds, and the background job that adds it. In the mock a batch
// runs for a few seconds, then lands with internal/sample's volumes.

import type { AdminSampleCounts, SampleKind, SampleSize } from "@/lib/api/types";
import { VOLUMES } from "@/lib/testWorkspaces";
import { db, workspaceById, type UserRec, type WorkspaceRec } from "./db";
import { FIRST, LAST } from "./content";
import { nowIso, pick, slugify, uuid } from "./util";

export const SIZES: SampleSize[] = ["small", "realistic", "large"];
export const KINDS: SampleKind[] = ["tickets", "chat", "kb", "team", "collab", "history"];

/** How long a batch runs in the mock. */
export const BATCH_MS = 4000;

export function emptyCounts(): AdminSampleCounts {
  return { members: 0, teams: 0, contacts: 0, companies: 0, tickets: 0, messages: 0, chats: 0, articles: 0, collections: 0, mail_accounts: 0, mail_threads: 0, views: 0, saved_replies: 0 };
}

/** What one batch of a size and kinds adds. */
export function batchCounts(size: SampleSize, kinds: SampleKind[]): AdminSampleCounts {
  const v = VOLUMES[size];
  const c = emptyCounts();
  if (kinds.includes("tickets")) {
    c.tickets += v.tickets;
    c.messages += v.tickets * 4;
    c.contacts += v.contacts;
    c.companies += v.companies;
    if (v.extras) {
      c.views += 4;
      c.saved_replies += 6;
    }
  }
  if (kinds.includes("chat")) {
    c.chats += v.chats;
    c.messages += v.chats * 7;
  }
  if (kinds.includes("kb")) {
    c.articles += v.articles;
    c.collections += v.collections;
  }
  if (kinds.includes("team")) {
    c.members += v.members;
    c.teams += v.teams;
  }
  if (kinds.includes("collab")) {
    c.mail_accounts += v.mailAccounts;
    c.mail_threads += v.mailThreads;
  }
  if (kinds.includes("history")) {
    const solved = Math.round(v.tickets * 0.6);
    c.tickets += solved;
    c.messages += solved * 3;
  }
  return c;
}

export function addCounts(a: AdminSampleCounts | null, b: AdminSampleCounts): AdminSampleCounts {
  const out = { ...(a ?? emptyCounts()) };
  for (const k of Object.keys(b) as (keyof AdminSampleCounts)[]) out[k] += b[k];
  return out;
}

/** Generated teammates: test accounts on .invalid addresses, with no password. */
function addTeammates(w: WorkspaceRec, n: number) {
  const domain = `${slugify(w.name)}.invalid`;
  for (let i = 0; i < n; i++) {
    const first = pick(FIRST);
    const last = pick(LAST);
    const email = `${slugify(first)}.${slugify(last)}.${db.users.length}@${domain}`;
    const u: UserRec = {
      id: uuid(),
      email,
      name: `${first} ${last}`,
      avatar_url: null,
      email_verified: true,
      totp_enabled: false,
      has_password: false,
      suspended_at: null,
      suspended_reason: "",
      last_seen_at: null,
      created_at: nowIso(),
      test_account: true,
      password_expires_at: null,
      identities: [],
      passkeys: 0,
      sessions: [],
    };
    db.users.push(u);
    db.members.push({ workspace_id: w.id, user_id: u.id, role: i === 0 ? "admin" : "agent", created_at: nowIso() });
  }
}

/** Lands a batch: its counts join the workspace's, and the job completes. */
export function landBatch(w: WorkspaceRec, size: SampleSize, kinds: SampleKind[], jobId: number | null) {
  const t = w.test;
  if (!t || t.sample.status !== "running") return;
  const c = batchCounts(size, kinds);
  t.sample = { ...t.sample, status: "done", counts: addCounts(t.sample.counts, c), seeded_at: nowIso(), error: "" };
  w.counts.tickets += c.tickets;
  w.counts.open_tickets += Math.round(c.tickets * 0.35);
  w.counts.contacts += c.contacts;
  w.counts.kb_articles += c.articles;
  w.collab_accounts += c.mail_accounts;
  w.last_activity_at = nowIso();
  addTeammates(w, c.members);
  const job = jobId === null ? undefined : db.jobs.find((j) => j.id === jobId);
  if (job && job.state === "running") Object.assign(job, { state: "completed", finalized_at: nowIso() });
}

/** Starts a batch in the background: the job, the running status, and its landing after BATCH_MS. */
export function startBatch(w: WorkspaceRec, size: SampleSize, kinds: SampleKind[]) {
  const t = w.test!;
  const now = nowIso();
  const batch = t.sample.batches + 1;
  t.sample = { ...t.sample, status: "running", size, kinds: [...kinds], batches: batch, started_at: now, error: "" };
  const id = db.nextJobId++;
  db.jobs.push({
    id,
    kind: "admin.seed_test_workspace",
    queue: "default",
    state: "running",
    attempt: 1,
    max_attempts: 1,
    args: { workspace_id: w.id, size, kinds: [...kinds], batch },
    last_error: null,
    errors: 0,
    created_at: now,
    scheduled_at: now,
    attempted_at: now,
    finalized_at: null,
  });
  running.set(w.id, { size, kinds: [...kinds], jobId: id });
  setTimeout(() => finishBatch(w.id), BATCH_MS);
}

const running = new Map<string, { size: SampleSize; kinds: SampleKind[]; jobId: number }>();

function finishBatch(wid: string) {
  const r = running.get(wid);
  running.delete(wid);
  const w = workspaceById(wid);
  if (r && w) landBatch(w, r.size, r.kinds, r.jobId);
}

/** Lands every running batch now (window.__odAdminMock.finishSamples). */
export function finishAll() {
  for (const wid of [...running.keys()]) finishBatch(wid);
}
