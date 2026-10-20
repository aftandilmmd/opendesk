// Instance admins (internal/admin/admins.go): granted, changed and revoked by a
// super admin with a code; the last super admin stays.

import type { AdminRole } from "@/lib/api/types";
import { adminOf, db, userByEmail } from "../db";
import { HttpError, conflict, del, get, invalid, notFound, patch, permit, post, s, stepUp, type Ctx } from "../router";
import { adminView, audit } from "../shapes";
import { nowIso } from "../util";

const ROLES: AdminRole[] = ["viewer", "support", "super"];
const ORDER: Record<AdminRole, number> = { super: 0, support: 1, viewer: 2 };

function role(ctx: Ctx): AdminRole {
  const r = s(ctx, "role") as AdminRole | undefined;
  if (!r || !ROLES.includes(r)) throw invalid("role must be viewer, support or super");
  return r;
}

const supers = () => db.admins.filter((a) => a.role === "super").length;

export function registerAdmins() {
  get("/v1/admin/admins", (ctx) => {
    permit(ctx, "read");
    return [...db.admins].sort((a, b) => ORDER[a.role] - ORDER[b.role] || a.created_at.localeCompare(b.created_at)).map((a) => adminView(a.user_id));
  });

  post("/v1/admin/admins", (ctx) => {
    const a = permit(ctx, "admins.manage");
    stepUp(ctx);
    const r = role(ctx);
    const u = userByEmail(s(ctx, "email") ?? "");
    if (!u) throw new HttpError(404, "user_not_found", "No account uses this email address. The person signs up first.");
    if (adminOf(u.id)) throw conflict("This person is an admin already. Change their role instead.", "already_admin");
    if (u.suspended_at) throw conflict("This account is suspended. Restore it first.", "account_suspended");
    if (!u.totp_enabled) throw conflict("This person turns on two-factor authentication in the app first.", "admin_mfa_setup_required");
    db.admins.push({ user_id: u.id, role: r, granted_by: a.user.id, created_at: nowIso() });
    audit(a, "admin.granted", "admin", u.id, { role: r });
    return adminView(u.id);
  });

  patch("/v1/admin/admins/:id", (ctx) => {
    const a = permit(ctx, "admins.manage");
    stepUp(ctx);
    const r = role(ctx);
    if (ctx.params.id === a.user.id) throw conflict("You cannot change your own role.");
    const cur = adminOf(ctx.params.id);
    if (!cur) throw notFound("Admin");
    if (cur.role === "super" && r !== "super" && supers() <= 1) throw conflict("Keep at least one super admin.", "last_super");
    const from = cur.role;
    cur.role = r;
    audit(a, "admin.role_changed", "admin", cur.user_id, { from, to: r });
    return adminView(cur.user_id);
  });

  del("/v1/admin/admins/:id", (ctx) => {
    const a = permit(ctx, "admins.manage");
    stepUp(ctx);
    if (ctx.params.id === a.user.id) throw conflict("You cannot remove yourself. Another super admin can.");
    const cur = adminOf(ctx.params.id);
    if (!cur) throw notFound("Admin");
    if (cur.role === "super" && supers() <= 1) throw conflict("Keep at least one super admin.", "last_super");
    db.admins = db.admins.filter((x) => x.user_id !== cur.user_id);
    audit(a, "admin.revoked", "admin", cur.user_id, { role: cur.role });
    return undefined;
  });
}
