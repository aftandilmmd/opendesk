// Records to the admin API's shapes (contracts/admin.md "Shapes"), with the
// plan and entitlements resolved the way internal/plan does with billing on,
// and the audit rows every action writes.

import type {
  AdminAuditLog,
  AdminMe,
  AdminTestWorkspace,
  AdminUser,
  AdminUserRow,
  AdminWorkspace,
  AdminWorkspaceRow,
  AuditLog,
  InstanceAdmin,
  Plan,
} from "@/lib/api/types";
import { adminOf, db, membersOf, membershipsOf, userById, workspaceById, type AdminAuditRec, type UserRec, type WorkspaceRec } from "./db";
import { ROLE_PERMISSIONS, type Acting } from "./router";
import { micro, nowIso, periodEnd, periodStart, uuid } from "./util";

export const INSTANCE: AdminMe["instance"] = {
  version: "v1.9.2",
  commit: "4f9c2e1a7b3d5f60c8e2a9b1d4f7c3e5a6b8d0f2",
  billing_enabled: true,
  ai_enabled: true,
  app_url: "https://app.opendesk.example",
  api_url: "https://api.opendesk.example",
  self_hosted: false,
};

// internal/plan's numbers.
const FREE = { mailboxes: 1, members: 1, ai: 0.5 };
const PRO_AI_PER_SEAT = 10;
const COLLAB_AI_PER_SEAT = 20;

export const paid = (status: string) => status === "active" || status === "trialing" || status === "past_due";

export function complimentary(w: WorkspaceRec, now = Date.now()): boolean {
  return w.collab.access === "complimentary" && (!w.collab.until || Date.parse(w.collab.until) > now);
}

/** Members who are not viewers, at least one: what Stripe bills. */
export function billedSeats(w: WorkspaceRec): number {
  return Math.max(
    membersOf(w.id).filter((m) => m.role !== "viewer").length,
    1,
  );
}

/** The plan as the entitlements resolve it: complimentary Collab is collab. */
export function planOf(w: WorkspaceRec): Plan {
  if (complimentary(w)) return "collab";
  if (w.sub.plan !== "free" && paid(w.sub.status)) return w.sub.plan;
  return "free";
}

export function entitlements(w: WorkspaceRec) {
  const seats = Math.max(w.sub.seats, 1);
  let e: { max_mailboxes: number; max_members: number; monthly_ai_usd: number; unlimited_ai: boolean; collab: boolean };
  if (w.sub.plan === "collab" && paid(w.sub.status)) e = { max_mailboxes: 0, max_members: 0, monthly_ai_usd: COLLAB_AI_PER_SEAT * seats, unlimited_ai: false, collab: true };
  else if (w.sub.plan === "pro" && paid(w.sub.status)) e = { max_mailboxes: 0, max_members: 0, monthly_ai_usd: PRO_AI_PER_SEAT * seats, unlimited_ai: false, collab: false };
  else e = { max_mailboxes: FREE.mailboxes, max_members: FREE.members, monthly_ai_usd: FREE.ai, unlimited_ai: false, collab: false };
  if (!e.collab && complimentary(w)) e = { ...e, max_mailboxes: 0, max_members: 0, monthly_ai_usd: COLLAB_AI_PER_SEAT * billedSeats(w), collab: true };
  if (w.limits.max_mailboxes !== null) e.max_mailboxes = w.limits.max_mailboxes;
  if (w.limits.max_members !== null) e.max_members = w.limits.max_members;
  if (w.limits.monthly_ai_usd !== null) e.monthly_ai_usd = w.limits.monthly_ai_usd;
  return e;
}

// ─── Users ─────────────────────────────────────────────────────────────────

export function userRow(u: UserRec): AdminUserRow {
  return {
    id: u.id,
    email: u.email,
    name: u.name,
    avatar_url: u.avatar_url,
    email_verified: u.email_verified,
    totp_enabled: u.totp_enabled,
    has_password: u.has_password,
    workspace_count: membershipsOf(u.id).length,
    admin_role: adminOf(u.id)?.role ?? null,
    suspended_at: u.suspended_at,
    last_seen_at: u.last_seen_at,
    created_at: u.created_at,
  };
}

export function userView(u: UserRec): AdminUser {
  return {
    ...userRow(u),
    suspended_reason: u.suspended_reason,
    identities: [...u.identities].sort((a, b) => a.created_at.localeCompare(b.created_at)),
    passkeys: u.passkeys,
    memberships: membershipsOf(u.id)
      .sort((a, b) => a.created_at.localeCompare(b.created_at))
      .map((m) => {
        const w = workspaceById(m.workspace_id)!;
        return { workspace: { id: w.id, name: w.name, slug: w.slug }, role: m.role, created_at: m.created_at };
      }),
    sessions: [...u.sessions].sort((a, b) => b.last_used_at.localeCompare(a.last_used_at)).slice(0, 50),
  };
}

// ─── Workspaces ────────────────────────────────────────────────────────────

export function workspaceRow(w: WorkspaceRec): AdminWorkspaceRow {
  return {
    id: w.id,
    name: w.name,
    slug: w.slug,
    avatar_url: w.avatar_url,
    members: membersOf(w.id).length,
    plan: planOf(w),
    status: w.sub.status,
    suspended_at: w.suspended_at,
    last_activity_at: w.last_activity_at,
    created_at: w.created_at,
    test: !!w.test,
    test_expires_at: w.test?.expires_at ?? null,
    sample_data: w.test ? structuredClone(w.test.sample) : { status: "none", size: "", kinds: [], counts: null, batches: 0, started_at: null, seeded_at: null, error: "" },
  };
}

const ROLE_ORDER = { owner: 0, admin: 1, agent: 2, viewer: 3 } as const;

export function workspaceView(w: WorkspaceRec): AdminWorkspace {
  const e = entitlements(w);
  const included = w.ai.included_used_usd;
  const month = w.ai.by_feature.slice().sort((a, b) => b.charged_usd - a.charged_usd || a.feature.localeCompare(b.feature));
  return {
    ...workspaceRow(w),
    suspended_reason: w.suspended_reason,
    members_list: membersOf(w.id)
      .sort((a, b) => ROLE_ORDER[a.role] - ROLE_ORDER[b.role] || a.created_at.localeCompare(b.created_at))
      .map((m) => {
        const u = userById(m.user_id)!;
        return { user: { id: u.id, email: u.email, name: u.name }, role: m.role, created_at: m.created_at };
      }),
    pending_invitations: w.pending_invitations,
    counts: { ...w.counts },
    mailboxes: w.mailboxes.map((m) => ({ ...m })),
    entitlements: { max_mailboxes: e.max_mailboxes, max_members: e.max_members, monthly_ai_usd: e.monthly_ai_usd, unlimited_ai: e.unlimited_ai },
    limits: { ...w.limits },
    subscription: { ...w.sub, billed_seats: billedSeats(w) },
    collab: { ...w.collab, enabled: e.collab, accounts: w.collab_accounts },
    ai: {
      remaining_usd: micro(Math.max(e.monthly_ai_usd - included, 0) + w.ai.purchased_usd),
      monthly_usd: e.monthly_ai_usd,
      included_used_usd: micro(included),
      purchased_usd: micro(w.ai.purchased_usd),
      unlimited: e.unlimited_ai,
      period_start: periodStart().toISOString(),
      period_end: periodEnd().toISOString(),
      month: {
        charged_usd: micro(month.reduce((n, f) => n + f.charged_usd, 0)),
        provider_cost_usd: micro(month.reduce((n, f) => n + f.provider_cost_usd, 0)),
        calls: month.reduce((n, f) => n + f.calls, 0),
        by_feature: month.map((f) => ({ ...f })),
      },
    },
    recent_audit: w.audit.slice(0, 20),
  };
}

export function testWorkspaceView(w: WorkspaceRec): AdminTestWorkspace {
  const t = w.test!;
  const ownerM = membersOf(w.id)
    .filter((m) => m.role === "owner")
    .sort((a, b) => a.created_at.localeCompare(b.created_at))[0];
  const owner = ownerM ? userById(ownerM.user_id) : undefined;
  const by = t.created_by ? userById(t.created_by) : undefined;
  return {
    workspace: { id: w.id, name: w.name, slug: w.slug },
    owner: owner ? { id: owner.id, email: owner.email, name: owner.name, test_account: owner.test_account, password_expires_at: owner.password_expires_at } : null,
    created_by: by ? { id: by.id, email: by.email } : null,
    reason: t.reason,
    plan: t.plan,
    test_expires_at: t.expires_at,
    sample_data: structuredClone(t.sample),
    members: membersOf(w.id).length,
    suspended_at: w.suspended_at,
    created_at: w.created_at,
  };
}

// ─── Admins ────────────────────────────────────────────────────────────────

export function meOf(uid: string): AdminMe {
  const u = userById(uid)!;
  const role = adminOf(uid)!.role;
  return { id: u.id, email: u.email, name: u.name, role, permissions: [...ROLE_PERMISSIONS[role]], instance: { ...INSTANCE } };
}

/** InstanceAdmin with totp_enabled, which the API sends too. */
export function adminView(uid: string): InstanceAdmin & { totp_enabled: boolean } {
  const a = adminOf(uid)!;
  const u = userById(uid)!;
  const g = a.granted_by ? userById(a.granted_by) : undefined;
  return {
    user: { id: u.id, email: u.email, name: u.name },
    role: a.role,
    granted_by: g ? { id: g.id, email: g.email } : null,
    totp_enabled: u.totp_enabled,
    created_at: a.created_at,
  };
}

// ─── Audit ─────────────────────────────────────────────────────────────────

export function auditView(e: AdminAuditRec): AdminAuditLog {
  return structuredClone(e);
}

/** An admin audit row by the acting admin, newest first. */
export function audit(by: Acting | null, action: string, targetType: AdminAuditRec["target_type"], targetId: string | null, data: Record<string, unknown> = {}) {
  db.audit.unshift({
    id: uuid(),
    actor: by ? { type: "admin", id: by.user.id, email: by.user.email } : { type: "system", id: null, email: "system" },
    action,
    target_type: targetType,
    target_id: targetId,
    data,
    ip: by ? db.ip : "",
    created_at: nowIso(),
  });
}

/** The workspace's own audit log gets the operator's actions too, with no actor user. */
export function auditWorkspace(w: WorkspaceRec, action: string, entityType: string, entityId: string | null, data: Record<string, unknown> = {}) {
  const row: AuditLog = {
    id: uuid(),
    actor: { type: "system", user: null, api_key_id: null },
    action,
    entity_type: entityType,
    entity_id: entityId,
    data: { ...data, actor: "instance_admin" },
    ip: db.ip,
    created_at: nowIso(),
  };
  w.audit.unshift(row);
}

/** The same, in every workspace of a user. */
export function auditUserWorkspaces(uid: string, action: string, data: Record<string, unknown> = {}) {
  for (const m of membershipsOf(uid)) {
    const w = workspaceById(m.workspace_id);
    if (w) auditWorkspace(w, action, "user", uid, data);
  }
}
