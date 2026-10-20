// Workspaces (internal/admin/workspaces.go): the list with its filters, one
// workspace, suspension, limit overrides, AI grants, Collab access and deletion.

import type { CollabAccess } from "@/lib/api/types";
import { adminOf, db, membersOf, membershipsOf, userById, workspaceById, type WorkspaceRec } from "../db";
import { HttpError, conflict, del, get, invalid, newestFirst, notFound, numOrNull, paginate, permit, post, put, ROLE_PERMISSIONS, s, stepUp, type Ctx } from "../router";
import { audit, auditWorkspace, complimentary, paid, workspaceRow, workspaceView } from "../shapes";
import { cents, micro, nowIso, uuid } from "../util";

function find(ctx: Ctx) {
  const w = workspaceById(ctx.params.id);
  if (!w) throw notFound("Workspace");
  return w;
}

const isPaid = (w: WorkspaceRec) => w.sub.plan !== "free" && paid(w.sub.status);

function matches(w: WorkspaceRec, filter: string): boolean {
  switch (filter) {
    case "suspended":
      return !!w.suspended_at;
    case "paid":
      return isPaid(w);
    case "free":
      return !isPaid(w) && !complimentary(w);
    case "collab":
      return (w.sub.plan === "collab" && isPaid(w)) || w.collab.access === "offered" || w.collab.access === "complimentary";
    case "test":
      return !!w.test;
    default:
      return true;
  }
}

/** Deletes a workspace like core.Ops: its members go; a test workspace takes its own test accounts along. */
export function removeWorkspace(w: WorkspaceRec): number {
  const uids = membersOf(w.id).map((m) => m.user_id);
  db.members = db.members.filter((m) => m.workspace_id !== w.id);
  db.workspaces = db.workspaces.filter((x) => x.id !== w.id);
  if (!w.test) return 0;
  let n = 0;
  for (const uid of uids) {
    const u = userById(uid);
    if (!u?.test_account || membershipsOf(uid).length || adminOf(uid)) continue;
    db.users = db.users.filter((x) => x.id !== uid);
    n++;
  }
  return n;
}

export function registerWorkspaces() {
  get("/v1/admin/workspaces", (ctx) => {
    permit(ctx, "read");
    const q = (ctx.query.get("q") ?? "").trim().toLowerCase();
    const filter = ctx.query.get("filter") ?? "";
    if (filter && !["suspended", "paid", "free", "collab", "test"].includes(filter)) throw invalid("filter must be suspended, paid, free, collab or test");
    const list = db.workspaces
      .filter(
        (w) =>
          !q ||
          w.id === q ||
          w.name.toLowerCase().includes(q) ||
          w.slug.includes(q) ||
          membersOf(w.id).some((m) => userById(m.user_id)?.email.toLowerCase().includes(q)),
      )
      .filter((w) => matches(w, filter))
      .sort(newestFirst);
    const page = paginate(ctx, list);
    return { data: page.data.map(workspaceRow), next_cursor: page.next_cursor };
  });

  get("/v1/admin/workspaces/:id", (ctx) => {
    permit(ctx, "read");
    return workspaceView(find(ctx));
  });

  post("/v1/admin/workspaces/:id/suspend", (ctx) => {
    const a = permit(ctx, "workspaces.suspend");
    const w = find(ctx);
    const reason = (s(ctx, "reason") ?? "").trim();
    if (!reason) throw invalid("Give a reason.");
    if (reason.length > 500) throw invalid("Keep the reason to 500 characters.");
    if (w.suspended_at) throw conflict("This workspace is already suspended.");
    w.suspended_at = nowIso();
    w.suspended_reason = reason;
    auditWorkspace(w, "workspace.suspended", "workspace", w.id);
    audit(a, "workspace.suspended", "workspace", w.id, { reason });
    return workspaceView(w);
  });

  post("/v1/admin/workspaces/:id/unsuspend", (ctx) => {
    const a = permit(ctx, "workspaces.suspend");
    const w = find(ctx);
    if (!w.suspended_at) throw conflict("This workspace is not suspended.");
    w.suspended_at = null;
    w.suspended_reason = "";
    auditWorkspace(w, "workspace.unsuspended", "workspace", w.id);
    audit(a, "workspace.unsuspended", "workspace", w.id);
    return workspaceView(w);
  });

  put("/v1/admin/workspaces/:id/limits", (ctx) => {
    const a = permit(ctx, "workspaces.limits");
    const w = find(ctx);
    const limits = {
      max_mailboxes: numOrNull(ctx, "max_mailboxes") ?? null,
      max_members: numOrNull(ctx, "max_members") ?? null,
      monthly_ai_usd: numOrNull(ctx, "monthly_ai_usd") ?? null,
    };
    for (const [k, v] of Object.entries(limits)) {
      if (v === null) continue;
      if (v < 0 || v > 100_000) throw invalid(`${k} must be between 0 and 100000`);
      if (k !== "monthly_ai_usd" && !Number.isInteger(v)) throw invalid(`${k} must be a whole number`);
    }
    if (limits.monthly_ai_usd !== null) limits.monthly_ai_usd = micro(limits.monthly_ai_usd);
    w.limits = limits;
    auditWorkspace(w, "workspace.limits_changed", "workspace", w.id, { ...limits });
    audit(a, "workspace.limits_changed", "workspace", w.id, { ...limits });
    return workspaceView(w);
  });

  post("/v1/admin/workspaces/:id/ai-grants", (ctx) => {
    const a = permit(ctx, "workspaces.limits");
    const w = find(ctx);
    const raw = ctx.body.amount_usd;
    const note = (s(ctx, "note") ?? "").trim();
    if (typeof raw !== "number" || raw < 0.01 || raw > 10_000) throw invalid("amount_usd must be between 0.01 and 10000");
    if (note.length > 200) throw invalid("Keep the note to 200 characters.");
    const amount = cents(raw);
    if (amount <= 0 || !note) throw invalid("Give an amount of at least $0.01 and a note.");
    w.ai.purchased_usd = micro(w.ai.purchased_usd + amount);
    auditWorkspace(w, "workspace.ai_granted", "workspace", w.id, { amount_usd: amount });
    audit(a, "workspace.ai_granted", "workspace", w.id, { amount_usd: amount, note, grant: uuid() });
    return workspaceView(w);
  });

  put("/v1/admin/workspaces/:id/collab", (ctx) => {
    const a = permit(ctx, "workspaces.limits");
    const w = find(ctx);
    const access = s(ctx, "access") as CollabAccess | undefined;
    if (access !== "none" && access !== "offered" && access !== "complimentary") throw invalid("access must be none, offered or complimentary");
    const note = (s(ctx, "note") ?? "").trim();
    if (note.length > 200) throw invalid("Keep the note to 200 characters.");
    let until: string | null = null;
    const rawUntil = s(ctx, "until");
    if (rawUntil && rawUntil.trim()) {
      if (access !== "complimentary") throw invalid("An end date applies to complimentary access only.");
      const t = Date.parse(rawUntil.trim());
      if (Number.isNaN(t) || !/^\d{4}-\d{2}-\d{2}T/.test(rawUntil.trim())) throw invalid("until must be an RFC 3339 time.");
      if (t <= Date.now()) throw invalid("until must be in the future.");
      until = new Date(t).toISOString();
    }
    w.collab = { access, until: access === "complimentary" ? until : null, note };
    auditWorkspace(w, "workspace.collab_changed", "workspace", w.id, { access, until: w.collab.until });
    audit(a, "workspace.collab_changed", "workspace", w.id, { access, until: w.collab.until, note });
    return workspaceView(w);
  });

  del("/v1/admin/workspaces/:id", (ctx) => {
    const a = permit(ctx, "read");
    const perms = ROLE_PERMISSIONS[a.admin.role];
    if (!perms.includes("workspaces.delete") && !perms.includes("workspaces.test")) throw new HttpError(403, "forbidden", "Your admin role does not allow this.");
    const w = find(ctx);
    if (!w.test && !perms.includes("workspaces.delete")) throw new HttpError(403, "forbidden", "Your admin role deletes test workspaces only.");
    stepUp(ctx);
    if ((s(ctx, "confirm_name") ?? "").trim() !== w.name) throw new HttpError(422, "confirm_name_mismatch", "Type the workspace name exactly to confirm.");
    const test = !!w.test;
    const n = removeWorkspace(w);
    audit(a, "workspace.deleted", "workspace", w.id, test ? { test: true, accounts_deleted: n } : {});
    return undefined;
  });
}

