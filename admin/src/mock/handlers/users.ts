// Users (internal/admin/users.go): the list, one user, and what an operator
// does to an account.

import { adminOf, db, membersOf, membershipsOf, userById, workspaceById } from "../db";
import { HttpError, conflict, get, invalid, newestFirst, notFound, paginate, permit, post, del, s, stepUp, type Ctx } from "../router";
import { audit, auditUserWorkspaces, userRow, userView } from "../shapes";
import { nowIso } from "../util";

function find(ctx: Ctx) {
  const u = userById(ctx.params.id);
  if (!u) throw notFound("User");
  return u;
}

function reason(ctx: Ctx): string {
  const r = (s(ctx, "reason") ?? "").trim();
  if (!r) throw invalid("Give a reason.");
  if (r.length > 500) throw invalid("Keep the reason to 500 characters.");
  return r;
}

/** Removes a user as the account's own deletion does: their memberships, and the workspaces they own alone. */
export function removeUser(uid: string) {
  for (const m of membershipsOf(uid)) {
    const others = membersOf(m.workspace_id).filter((x) => x.user_id !== uid);
    if (m.role === "owner" && others.length === 0) {
      db.workspaces = db.workspaces.filter((w) => w.id !== m.workspace_id);
    }
  }
  db.members = db.members.filter((m) => m.user_id !== uid && workspaceById(m.workspace_id));
  db.users = db.users.filter((u) => u.id !== uid);
}

export function registerUsers() {
  get("/v1/admin/users", (ctx) => {
    permit(ctx, "read");
    const q = (ctx.query.get("q") ?? "").trim().toLowerCase();
    const filter = ctx.query.get("filter") ?? "";
    if (filter && !["suspended", "admins", "unverified"].includes(filter)) throw invalid("filter must be suspended, admins or unverified");
    const list = db.users
      .filter((u) => !q || u.id === q || u.email.toLowerCase().includes(q) || u.name.toLowerCase().includes(q))
      .filter((u) => (filter === "suspended" ? !!u.suspended_at : filter === "admins" ? !!adminOf(u.id) : filter === "unverified" ? !u.email_verified : true))
      .sort(newestFirst);
    const page = paginate(ctx, list);
    return { data: page.data.map(userRow), next_cursor: page.next_cursor };
  });

  get("/v1/admin/users/:id", (ctx) => {
    permit(ctx, "read");
    return userView(find(ctx));
  });

  post("/v1/admin/users/:id/sessions/revoke", (ctx) => {
    const a = permit(ctx, "users.sessions");
    const u = find(ctx);
    const sid = s(ctx, "session_id");
    const data: Record<string, unknown> = { all: !sid };
    if (sid) {
      if (!u.sessions.some((x) => x.id === sid)) throw notFound("Session");
      u.sessions = u.sessions.filter((x) => x.id !== sid);
      data.session_id = sid;
    } else u.sessions = [];
    auditUserWorkspaces(u.id, "session.revoked", data);
    audit(a, "user.sessions_revoked", "user", u.id, data);
    return undefined;
  });

  post("/v1/admin/users/:id/verification-email", (ctx) => {
    const a = permit(ctx, "users.sessions");
    const u = find(ctx);
    if (u.email_verified) throw conflict("This email address is already confirmed.", "already_verified");
    audit(a, "user.verification_sent", "user", u.id);
    return undefined;
  });

  post("/v1/admin/users/:id/suspend", (ctx) => {
    const a = permit(ctx, "users.suspend");
    const u = find(ctx);
    const r = reason(ctx);
    if (u.id === a.user.id) throw conflict("You cannot suspend yourself.");
    if (adminOf(u.id)) throw conflict("Revoke this person's admin role before suspending them.");
    if (u.suspended_at) throw conflict("This user is already suspended.");
    u.suspended_at = nowIso();
    u.suspended_reason = r;
    u.sessions = [];
    auditUserWorkspaces(u.id, "user.suspended");
    audit(a, "user.suspended", "user", u.id, { reason: r });
    return userView(u);
  });

  post("/v1/admin/users/:id/unsuspend", (ctx) => {
    const a = permit(ctx, "users.suspend");
    const u = find(ctx);
    if (!u.suspended_at) throw conflict("This user is not suspended.");
    u.suspended_at = null;
    u.suspended_reason = "";
    auditUserWorkspaces(u.id, "user.unsuspended");
    audit(a, "user.unsuspended", "user", u.id);
    return userView(u);
  });

  post("/v1/admin/users/:id/mfa/disable", (ctx) => {
    const a = permit(ctx, "users.mfa");
    stepUp(ctx);
    const u = find(ctx);
    if (u.id === a.user.id) throw conflict("Turn off your own two-factor authentication in the app.");
    if (!u.totp_enabled) throw conflict("This user does not use two-factor authentication.", "mfa_not_enabled");
    u.totp_enabled = false;
    u.sessions = [];
    auditUserWorkspaces(u.id, "2fa.disabled");
    audit(a, "user.mfa_disabled", "user", u.id);
    return userView(u);
  });

  del("/v1/admin/users/:id", (ctx) => {
    const a = permit(ctx, "users.delete");
    stepUp(ctx);
    const u = find(ctx);
    if (u.id === a.user.id) throw conflict("Delete your own account in the app.");
    if ((s(ctx, "confirm_email") ?? "").trim().toLowerCase() !== u.email.toLowerCase())
      throw new HttpError(422, "confirm_email_mismatch", "Type the user's email address exactly to confirm.");
    if (adminOf(u.id)) throw conflict("Revoke this person's admin role before deleting their account.");
    const ownsShared = membershipsOf(u.id).some((m) => m.role === "owner" && membersOf(m.workspace_id).some((x) => x.user_id !== u.id));
    if (ownsShared) throw conflict("This user owns a workspace with other members. Transfer it or delete the workspace first.", "sole_owner");
    auditUserWorkspaces(u.id, "member.account_deleted");
    removeUser(u.id);
    audit(a, "user.deleted", "user", u.id);
    return undefined;
  });
}
