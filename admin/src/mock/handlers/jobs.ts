// Background jobs (internal/admin/jobs.go): River's jobs by state and kind,
// retried and cancelled by hand. A retried job runs a moment later and completes.

import type { AdminJob, AdminJobStats } from "@/lib/api/types";
import { JOB_STATES } from "@/lib/api/types";
import { db } from "../db";
import { conflict, get, invalid, notFound, paginate, permit, post, type Ctx } from "../router";
import { audit } from "../shapes";
import { DAY, nowIso } from "../util";

/** How long a retried job waits, then runs, in the mock. */
const PICKED_UP_MS = 1200;
const RUNS_MS = 1800;

export function jobStats(): AdminJobStats {
  const states: Record<string, number> = Object.fromEntries(JOB_STATES.map((s) => [s, 0]));
  for (const j of db.jobs) states[j.state] = (states[j.state] ?? 0) + 1;
  const dayAgo = Date.now() - DAY;
  const kinds = new Map<string, AdminJobStats["kinds"][number]>();
  for (const j of db.jobs) {
    if (!["available", "running", "retryable", "discarded"].includes(j.state)) continue;
    const k = kinds.get(j.kind) ?? { kind: j.kind, available: 0, running: 0, retryable: 0, discarded_24h: 0 };
    if (j.state === "available") k.available++;
    else if (j.state === "running") k.running++;
    else if (j.state === "retryable") k.retryable++;
    else if (j.finalized_at && Date.parse(j.finalized_at) > dayAgo) k.discarded_24h++;
    kinds.set(j.kind, k);
  }
  return {
    states,
    kinds: [...kinds.values()].sort((a, b) => b.retryable - a.retryable || b.discarded_24h - a.discarded_24h || b.available - a.available || a.kind.localeCompare(b.kind)),
  };
}

function find(ctx: Ctx): AdminJob {
  const id = Number(ctx.params.id);
  const j = Number.isInteger(id) && id > 0 ? db.jobs.find((x) => x.id === id) : undefined;
  if (!j) throw notFound("Job");
  return j;
}

/** A retried job is picked up, runs, and completes. */
function run(j: AdminJob) {
  setTimeout(() => {
    if (j.state !== "available") return;
    Object.assign(j, { state: "running", attempt: j.attempt + 1, attempted_at: nowIso() });
    setTimeout(() => {
      if (j.state === "running") Object.assign(j, { state: "completed", finalized_at: nowIso() });
    }, RUNS_MS);
  }, PICKED_UP_MS);
}

export function registerJobs() {
  get("/v1/admin/jobs", (ctx) => {
    permit(ctx, "read");
    const state = ctx.query.get("state") || "retryable";
    if (!(JOB_STATES as readonly string[]).includes(state)) throw invalid("state is not a job state");
    const kind = ctx.query.get("kind") ?? "";
    const queue = ctx.query.get("queue") ?? "";
    const list = db.jobs.filter((j) => j.state === state && (!kind || j.kind === kind) && (!queue || j.queue === queue)).sort((a, b) => b.id - a.id);
    const page = paginate(ctx, list);
    return { data: page.data.map((j) => structuredClone(j)), next_cursor: page.next_cursor };
  });

  get("/v1/admin/jobs/stats", (ctx) => {
    permit(ctx, "read");
    return jobStats();
  });

  post("/v1/admin/jobs/:id/retry", (ctx) => {
    const a = permit(ctx, "jobs.manage");
    const j = find(ctx);
    if (!["retryable", "discarded", "cancelled"].includes(j.state)) throw conflict("Only a retryable, discarded or cancelled job can be run again.");
    const from = j.state;
    // River runs it now; one out of attempts gets one more.
    Object.assign(j, { state: "available", scheduled_at: nowIso(), finalized_at: null, max_attempts: Math.max(j.max_attempts, j.attempt + 1) });
    run(j);
    audit(a, "job.retried", "job", String(j.id), { from });
    return structuredClone(j);
  });

  post("/v1/admin/jobs/:id/cancel", (ctx) => {
    const a = permit(ctx, "jobs.manage");
    const j = find(ctx);
    if (["completed", "cancelled", "discarded"].includes(j.state)) throw conflict("This job has already finished.");
    const from = j.state;
    Object.assign(j, { state: "cancelled", finalized_at: nowIso() });
    audit(a, "job.cancelled", "job", String(j.id), { from });
    return structuredClone(j);
  });
}
