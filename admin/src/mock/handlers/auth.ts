// Sign-in and the session (contracts/admin.md "Sign-in and sessions"): email and
// any password, then any 6-digit code or recovery code ("000000" is always
// wrong). The refresh "cookie" is the signed-in admin held in memory.

import { adminOf, db, userByEmail, userById } from "../db";
import { HttpError, acting, codeOk, get, post, s, type Ctx } from "../router";
import { audit, meOf } from "../shapes";
import { uuid } from "../util";

/** An access token's lifetime, as the API's: 10 minutes. */
const EXPIRES_IN = 600;

function authResult() {
  const sess = db.session!;
  return { access_token: sess.token, expires_in: EXPIRES_IN, admin: meOf(sess.userId) };
}

/** Starts a session for an admin, as a sign-in would. */
export function signIn(userId: string) {
  db.session = { userId, token: `mock_admin_${uuid()}` };
}

export function signOut() {
  db.session = null;
}

const by = (userId: string) => ({ user: userById(userId)!, admin: adminOf(userId)! });

export function registerAuth() {
  post("/v1/admin/auth/login", (ctx: Ctx) => {
    const email = (s(ctx, "email") ?? "").trim();
    const password = s(ctx, "password") ?? "";
    if (!email || !password) throw new HttpError(422, "validation_failed", "Enter your email and password.");
    const u = userByEmail(email);
    if (!u || !u.has_password) throw new HttpError(401, "invalid_credentials", "The email or password is incorrect.");
    const a = adminOf(u.id);
    if (!a) throw new HttpError(403, "not_admin", "This account is not an admin of this instance.");
    if (u.suspended_at) throw new HttpError(403, "account_suspended", "This account is suspended.");
    if (!u.totp_enabled) throw new HttpError(403, "admin_mfa_setup_required", "Turn on two-factor authentication in your account's security settings, then sign in again.");
    const token = `mfa_${uuid()}`;
    db.pendingMfa.set(token, u.id);
    return { mfa_token: token };
  });

  post("/v1/admin/auth/mfa", (ctx: Ctx) => {
    const token = s(ctx, "mfa_token") ?? "";
    const code = (s(ctx, "code") ?? "").trim();
    const uid = db.pendingMfa.get(token);
    if (!uid || !adminOf(uid)) throw new HttpError(401, "invalid_mfa_token", "Your sign-in attempt expired. Start again.");
    if (!codeOk(code)) {
      audit(by(uid), "login.failed", "admin", uid, { method: "totp" });
      throw new HttpError(401, "invalid_code", "That code is not valid. Try a new one.");
    }
    db.pendingMfa.delete(token);
    signIn(uid);
    audit(by(uid), "login", "admin", uid, { factor: /^\d{6}$/.test(code) ? "totp" : "recovery" });
    return authResult();
  });

  post("/v1/admin/auth/refresh", () => {
    const sess = db.session;
    if (!sess) throw new HttpError(401, "unauthenticated", "Your admin session has ended. Sign in again.");
    const u = userById(sess.userId);
    if (!u || u.suspended_at) {
      signOut();
      throw new HttpError(403, "account_suspended", "This account is suspended.");
    }
    if (!adminOf(sess.userId)) {
      signOut();
      throw new HttpError(403, "not_admin", "This account is not an admin of this instance.");
    }
    return authResult();
  });

  post("/v1/admin/auth/logout", () => {
    const sess = db.session;
    if (sess && adminOf(sess.userId)) audit(by(sess.userId), "logout", "admin", sess.userId);
    signOut();
    return undefined;
  });

  get("/v1/admin/me", (ctx) => meOf(acting(ctx).user.id));
}
