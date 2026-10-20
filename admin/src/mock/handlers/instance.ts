// The instance (internal/admin/summary.go, health.go, updates.go, audit.go):
// the overview's numbers, the health page, the release check and the admin
// audit log. The figures come from the in-memory rows, so actions show in them.

import type { AdminHealth, AdminSummary, AdminUpdates, HealthStatus } from "@/lib/api/types";
import { db } from "../db";
import { get, invalid, paginate, permit, post } from "../router";
import { auditView, INSTANCE, paid } from "../shapes";
import { DAY, NOW, isUuid, micro, nowIso } from "../util";
import { jobStats } from "./jobs";

const within = (iso: string | null, ms: number) => !!iso && Date.parse(iso) > Date.now() - ms;

function summary(): AdminSummary {
  // Test workspaces and test accounts stay out of the counts.
  const users = db.users.filter((u) => !u.test_account);
  const workspaces = db.workspaces.filter((w) => !w.test);
  const subs = db.workspaces.filter((w) => w.sub.plan !== "free" && paid(w.sub.status));
  const charged = db.workspaces.reduce((n, w) => n + w.ai.by_feature.reduce((m, f) => m + f.charged_usd, 0), 0);
  const cost = db.workspaces.reduce((n, w) => n + w.ai.by_feature.reduce((m, f) => m + f.provider_cost_usd, 0), 0);
  const calls = db.workspaces.reduce((n, w) => n + w.ai.by_feature.reduce((m, f) => m + f.calls, 0), 0);

  // The month's charges spread over its days by weight; the days before it at the same pace.
  const today = new Date(new Date().toISOString().slice(0, 10) + "T00:00:00Z").getTime();
  const days = Array.from({ length: 30 }, (_, i) => today - (29 - i) * DAY);
  const month = new Date(today).getUTCMonth();
  const inMonth = days.map((d) => new Date(d).getUTCMonth() === month);
  const monthWeight = db.aiWeights.reduce((n, w, i) => n + (inMonth[i] ? w : 0), 0) || 1;
  const perWeight = charged / monthWeight;

  return {
    users: {
      total: users.length,
      new_7d: users.filter((u) => within(u.created_at, 7 * DAY)).length,
      new_30d: users.filter((u) => within(u.created_at, 30 * DAY)).length,
      active_7d: users.filter((u) => within(u.last_seen_at, 7 * DAY)).length,
    },
    workspaces: {
      total: workspaces.length,
      new_7d: workspaces.filter((w) => within(w.created_at, 7 * DAY)).length,
      new_30d: workspaces.filter((w) => within(w.created_at, 30 * DAY)).length,
      active_7d: workspaces.filter((w) => within(w.last_activity_at, 7 * DAY)).length,
      suspended: workspaces.filter((w) => w.suspended_at).length,
    },
    billing: {
      enabled: true,
      paid_workspaces: subs.length,
      billed_seats: subs.reduce((n, w) => n + w.sub.seats, 0),
      past_due: subs.filter((w) => w.sub.status === "past_due").length,
    },
    ai: { month_charged_usd: micro(charged), month_provider_cost_usd: micro(cost), month_calls: calls },
    daily: days.map((d, i) => {
      const end = d + DAY;
      const inDay = (iso: string) => {
        const t = Date.parse(iso);
        return t >= d && t < end;
      };
      return {
        date: new Date(d).toISOString().slice(0, 10),
        signups: users.filter((u) => inDay(u.created_at)).length,
        workspaces: workspaces.filter((w) => inDay(w.created_at)).length,
        ai_charged_usd: micro(Math.round(perWeight * (db.aiWeights[i] ?? 1) * 100) / 100),
      };
    }),
  };
}

function updates(): AdminUpdates {
  const u = db.updates;
  const available = u.latest.version !== u.current;
  return {
    check: true,
    current: u.current,
    latest: { ...u.latest },
    available,
    major: false,
    checked_at: u.checked_at,
    error: "",
    previous_version: u.previous_version,
    running_since: u.running_since,
    auto: { ...u.auto },
  };
}

function health(): AdminHealth {
  const st = jobStats();
  const dayAgo = Date.now() - DAY;
  const waiting = db.jobs.filter((j) => j.state === "available");
  // Measured against the seed's clock: the mock has no worker to fall behind.
  const oldest = waiting.length ? Math.max(0, Math.round((NOW - Math.min(...waiting.map((j) => Date.parse(j.scheduled_at)))) / 1000)) : null;
  const queues = new Map<string, { queue: string; available: number; running: number; retryable: number }>();
  for (const j of db.jobs) {
    if (!["available", "running", "retryable"].includes(j.state)) continue;
    const q = queues.get(j.queue) ?? { queue: j.queue, available: 0, running: 0, retryable: 0 };
    q[j.state as "available" | "running" | "retryable"]++;
    queues.set(j.queue, q);
  }
  const h: Omit<AdminHealth, "checks"> = {
    version: INSTANCE.version,
    commit: INSTANCE.commit,
    role: "api",
    started_at: db.updates.running_since,
    database: { ok: true, latency_ms: 3, schema_version: 639, dirty: false, pool: { total: 12, idle: 9, in_use: 3, max: 40 } },
    nats: { ok: true, embedded: false },
    relay: { unpublished: 2, oldest_unpublished_s: 1 },
    jobs: {
      available: st.states.available,
      running: st.states.running,
      retryable: st.states.retryable,
      scheduled: st.states.scheduled,
      discarded_24h: db.jobs.filter((j) => j.state === "discarded" && j.finalized_at && Date.parse(j.finalized_at) > dayAgo).length,
      oldest_available_s: oldest,
      by_queue: [...queues.values()].sort((a, b) => a.queue.localeCompare(b.queue)),
    },
    mail: { driver: "ses", inbound_failed_24h: 0, inbound_pending: 3, mailboxes_in_error: db.workspaces.reduce((n, w) => n + w.mailboxes.filter((m) => m.status === "error").length, 0) },
    webhooks: { failing_24h: 0 },
    config: {
      billing: true,
      ai_provider: "anthropic",
      decisions_provider: "jev",
      embeddings: "openai",
      storage: "s3",
      signup_enabled: true,
      mailbox_imap: false,
      mailbox_system_send: false,
      push: "relay",
      help_domain: "help.opendesk.example",
    },
    updates: updates(),
  };
  return { ...h, checks: checks(h) };
}

/** internal/admin/health.go checks(): the numbers turned into what needs attention. */
function checks(h: Omit<AdminHealth, "checks">): AdminHealth["checks"] {
  const out: AdminHealth["checks"] = [];
  const add = (name: string, status: HealthStatus, detail: string) => out.push({ name, status, detail });
  add("Database", "ok", `Schema version ${h.database.schema_version}, ping ${h.database.latency_ms} ms.`);
  add("NATS", "ok", "Connected.");
  add("Event relay", "ok", h.relay.unpublished ? `${h.relay.unpublished} events on their way.` : "Every event is published.");
  const age = h.jobs.oldest_available_s ?? 0;
  if (age > 15 * 60) add("Background jobs", "fail", `${h.jobs.available} jobs wait, the oldest for ${Math.round(age / 60)}m. Is a worker running?`);
  else if (age > 2 * 60) add("Background jobs", "warn", `${h.jobs.available} jobs wait, the oldest for ${Math.round(age / 60)}m.`);
  else if (h.jobs.discarded_24h > 0) add("Background jobs", "warn", `${h.jobs.discarded_24h} jobs gave up in the last 24 hours.`);
  else add("Background jobs", "ok", `${h.jobs.available} waiting, ${h.jobs.running} running, ${h.jobs.retryable} to retry.`);
  add("Platform mail", "ok", `Sending with ${h.mail.driver}.`);
  if (h.mail.mailboxes_in_error > 0) add("Mailboxes", "warn", `${h.mail.mailboxes_in_error} ${h.mail.mailboxes_in_error === 1 ? "mailbox cannot" : "mailboxes cannot"} connect.`);
  else add("Mailboxes", "ok", "Every mailbox connects.");
  add("Webhooks", "ok", "No failed deliveries in the last 24 hours.");
  const u = h.updates;
  if (u.available && u.latest) add("Updates", "ok", `${u.latest.version} is out (this instance runs ${u.current}). It installs at the next automatic update.`);
  else add("Updates", "ok", `This instance runs the newest release, ${u.current}. Automatic updates are on.`);
  return out;
}

export function registerInstance() {
  get("/v1/admin/summary", (ctx) => {
    permit(ctx, "read");
    return summary();
  });

  get("/v1/admin/health", (ctx) => {
    permit(ctx, "read");
    return health();
  });

  post("/v1/admin/updates/check", (ctx) => {
    permit(ctx, "read");
    db.updates.checked_at = nowIso();
    return updates();
  });

  get("/v1/admin/audit", (ctx) => {
    permit(ctx, "read");
    const action = ctx.query.get("action") ?? "";
    const target = ctx.query.get("target_id") ?? "";
    const actor = ctx.query.get("actor_id") ?? "";
    if (actor && !isUuid(actor)) throw invalid("actor_id must be a user id");
    const list = db.audit.filter((e) => (!action || e.action === action) && (!target || e.target_id === target) && (!actor || e.actor.id === actor));
    const page = paginate(ctx, list);
    return { data: page.data.map(auditView), next_cursor: page.next_cursor };
  });
}

