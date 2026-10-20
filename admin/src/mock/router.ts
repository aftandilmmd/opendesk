// Request routing for the mock transport: a route table, problem+json errors
// like the API's, the admin session and permission checks, and step-up.

import type { AdminPermission, AdminRole } from "@/lib/api/types";
import { adminOf, db, userById, type AdminRec, type UserRec } from "./db";
import { isRecord } from "./util";

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly detail: string,
  ) {
    super(detail);
  }
}

export const notFound = (what = "Resource") => new HttpError(404, "not_found", `${what} not found`);
export const invalid = (detail: string) => new HttpError(422, "validation_failed", detail);
export const conflict = (detail: string, code = "conflict") => new HttpError(409, code, detail);

export type Ctx = {
  method: string;
  path: string;
  params: Record<string, string>;
  query: URLSearchParams;
  body: Record<string, unknown>;
  headers: Headers;
};

export type Handler = (ctx: Ctx) => unknown | Promise<unknown>;

type Route = { method: string; parts: string[]; handler: Handler };

const routes: Route[] = [];

export function route(method: string, pattern: string, handler: Handler) {
  routes.push({ method, parts: pattern.split("/").filter(Boolean), handler });
}

export const get = (p: string, h: Handler) => route("GET", p, h);
export const post = (p: string, h: Handler) => route("POST", p, h);
export const patch = (p: string, h: Handler) => route("PATCH", p, h);
export const put = (p: string, h: Handler) => route("PUT", p, h);
export const del = (p: string, h: Handler) => route("DELETE", p, h);

/** Every registered route as "METHOD /path/:param", for the coverage test. */
export function routeList(): string[] {
  return routes.map((r) => `${r.method} /${r.parts.join("/")}`);
}

/** Mark a handler result as an explicit response. */
export function respond(status: number, body?: unknown) {
  return { __response: true as const, status, body };
}

function isResponseSpec(v: unknown): v is { __response: true; status: number; body?: unknown } {
  return isRecord(v) && v.__response === true;
}

function json(status: number, body: unknown, contentType = "application/json") {
  return new Response(body === undefined ? null : JSON.stringify(body), {
    status,
    headers: { "content-type": contentType, "x-request-id": `req_mock_${Math.random().toString(36).slice(2, 10)}` },
  });
}

const TITLES: Record<number, string> = { 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 409: "Conflict", 422: "Unprocessable Entity", 429: "Too Many Requests" };

function problem(e: HttpError) {
  return json(e.status, { status: e.status, title: TITLES[e.status] ?? "Error", detail: e.detail, code: e.code }, "application/problem+json");
}

function match(r: Route, method: string, parts: string[]): Record<string, string> | null {
  if (r.method !== method || r.parts.length !== parts.length) return null;
  const params: Record<string, string> = {};
  for (let i = 0; i < parts.length; i++) {
    const p = r.parts[i];
    if (p.startsWith(":")) params[p.slice(1)] = decodeURIComponent(parts[i]);
    else if (p !== parts[i]) return null;
  }
  return params;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Answers one request the way the API would. */
export async function dispatch(input: string, init: RequestInit): Promise<Response> {
  const method = (init.method ?? "GET").toUpperCase();
  const i = input.indexOf("/v1/");
  const rel = i >= 0 ? input.slice(i) : input;
  const [pathPart, qs = ""] = rel.split("?");
  const parts = pathPart.split("/").filter(Boolean);

  let body: Record<string, unknown> = {};
  if (typeof init.body === "string" && init.body) {
    try {
      const parsed: unknown = JSON.parse(init.body);
      body = isRecord(parsed) ? parsed : {};
    } catch {
      return problem(new HttpError(400, "validation_failed", "Body is not valid JSON"));
    }
  }

  await sleep(40 + Math.random() * 80);

  // Most specific first: static segments beat params.
  const hit = routes
    .map((r) => ({ r, params: match(r, method, parts) }))
    .filter((x): x is { r: Route; params: Record<string, string> } => x.params !== null)
    .sort((a, b) => Object.keys(a.params).length - Object.keys(b.params).length)[0];
  if (!hit) {
    console.error(`[admin mock] no route for ${method} ${pathPart}`);
    return problem(new HttpError(404, "not_found", `No mock route for ${method} ${pathPart}`));
  }

  try {
    const out = await hit.r.handler({ method, path: pathPart, params: hit.params, query: new URLSearchParams(qs), body, headers: new Headers(init.headers) });
    if (out instanceof Response) return out;
    if (isResponseSpec(out)) return out.body === undefined ? new Response(null, { status: out.status === 200 ? 204 : out.status }) : json(out.status, out.body);
    if (out === undefined) return new Response(null, { status: 204 });
    return json(method === "POST" && !pathPart.includes("/auth/") ? 201 : 200, out);
  } catch (e) {
    if (e instanceof HttpError) return problem(e);
    console.error("[admin mock] handler crashed", e);
    return problem(new HttpError(500, "server_error", "Internal error in mock handler"));
  }
}

// ─── Admins and permissions (internal/admin/admin.go) ─────────────────────

export const ROLE_PERMISSIONS: Record<AdminRole, AdminPermission[]> = {
  viewer: ["read"],
  support: ["read", "users.sessions", "users.suspend", "workspaces.suspend", "workspaces.limits", "workspaces.test", "jobs.manage"],
  super: [
    "read",
    "users.sessions",
    "users.suspend",
    "users.mfa",
    "users.delete",
    "workspaces.suspend",
    "workspaces.limits",
    "workspaces.test",
    "workspaces.delete",
    "jobs.manage",
    "admins.manage",
  ],
};

export type Acting = { user: UserRec; admin: AdminRec };

/** The signed-in admin behind a data call: a live session, still an admin, not suspended. */
export function acting(ctx: Ctx): Acting {
  const s = db.session;
  const bearer = (ctx.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!s || bearer !== s.token) throw new HttpError(401, "unauthenticated", "Sign in to the admin panel again.");
  const user = userById(s.userId);
  const admin = adminOf(s.userId);
  if (!user || !admin || user.suspended_at) throw new HttpError(401, "unauthenticated", "Sign in to the admin panel again.");
  return { user, admin };
}

/** The acting admin, when their role holds the permission. */
export function permit(ctx: Ctx, perm: AdminPermission): Acting {
  const a = acting(ctx);
  if (!ROLE_PERMISSIONS[a.admin.role].includes(perm)) throw new HttpError(403, "forbidden", "Your admin role does not allow this.");
  return a;
}

/** The code that always fails step-up and sign-in, to show the refusal. */
export const WRONG_CODE = "000000";

/** A current authenticator code (6 digits) or a recovery code; any is accepted but WRONG_CODE. */
export function codeOk(code: string): boolean {
  const v = code.trim();
  if (v === WRONG_CODE) return false;
  return /^\d{6}$/.test(v) || (v.length >= 8 && !/^\d+$/.test(v));
}

/** Step-up (contracts/admin.md "Step-up"): missing is 403 mfa_required, wrong 401 invalid_code. */
export function stepUp(ctx: Ctx) {
  const code = s(ctx, "code") ?? "";
  if (!code) throw new HttpError(403, "mfa_required", "Enter a code from your authenticator app.");
  if (!codeOk(code)) throw new HttpError(401, "invalid_code", "That code is not valid. Try a new one.");
}

// ─── Body and list helpers ────────────────────────────────────────────────

export function s(ctx: Ctx, key: string): string | undefined {
  const v = ctx.body[key];
  return typeof v === "string" ? v : undefined;
}

export function has(ctx: Ctx, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(ctx.body, key);
}

/** A number, null, or undefined when absent; 422 for anything else. */
export function numOrNull(ctx: Ctx, key: string): number | null | undefined {
  if (!has(ctx, key)) return undefined;
  const v = ctx.body[key];
  if (v === null) return null;
  if (typeof v === "number" && Number.isFinite(v)) return v;
  throw invalid(`${key} must be a number`);
}

/** Cursor pagination over an in-memory list; the cursor is an offset, opaque to the panel. */
export function paginate<T>(ctx: Ctx, items: T[], defaultLimit = 50) {
  const limit = Math.min(Math.max(Number(ctx.query.get("limit") ?? defaultLimit) || defaultLimit, 1), 100);
  const raw = ctx.query.get("cursor");
  const offset = raw ? Number(atobSafe(raw)) || 0 : 0;
  const data = items.slice(offset, offset + limit);
  const next = offset + limit < items.length ? btoa(String(offset + limit)) : null;
  return { data, next_cursor: next };
}

function atobSafe(v: string): string {
  try {
    return atob(v);
  } catch {
    throw invalid("cursor is not valid");
  }
}

/** Newest first, as the lists answer. */
export const newestFirst = <T extends { created_at: string }>(a: T, b: T) => b.created_at.localeCompare(a.created_at);
