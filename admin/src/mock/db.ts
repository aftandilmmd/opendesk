// The in-memory database behind mock mode: the rows the admin API reads, kept
// close to the tables internal/admin queries (users, members, workspaces with
// their subscription, instance_admins, river_job, admin_audit_logs).

import type {
  AdminLimits,
  AdminMailbox,
  AdminRole,
  AdminSampleData,
  AdminSession,
  AdminJob,
  AuditLog,
  CollabAccess,
  Role,
  TestPlan,
} from "@/lib/api/types";

export type UserRec = {
  id: string;
  email: string;
  name: string;
  avatar_url: string | null;
  email_verified: boolean;
  totp_enabled: boolean;
  has_password: boolean;
  suspended_at: string | null;
  suspended_reason: string;
  last_seen_at: string | null;
  created_at: string;
  /** A test workspace's generated owner or teammate (contracts/admin.md "Test workspaces"). */
  test_account: boolean;
  password_expires_at: string | null;
  identities: { provider: string; email: string; created_at: string }[];
  passkeys: number;
  /** Live app sessions, any order. */
  sessions: AdminSession[];
};

export type MemberRec = { workspace_id: string; user_id: string; role: Role; created_at: string };

/** The workspace's subscriptions row (a free workspace has one too, status "none"). */
export type SubRec = {
  plan: "free" | "pro" | "collab";
  status: string;
  interval: "month" | "year";
  seats: number;
  current_period_end: string | null;
  cancel_at_period_end: boolean;
  stripe_customer_id: string | null;
  stripe_subscription_id: string | null;
};

export type AiFeatureRec = { feature: string; charged_usd: number; provider_cost_usd: number; calls: number };

export type TestRec = {
  expires_at: string | null;
  reason: string;
  plan: TestPlan;
  created_by: string | null;
  sample: AdminSampleData;
};

export type WorkspaceRec = {
  id: string;
  name: string;
  slug: string;
  avatar_url: string | null;
  created_at: string;
  last_activity_at: string | null;
  suspended_at: string | null;
  suspended_reason: string;
  sub: SubRec;
  limits: AdminLimits;
  collab: { access: CollabAccess; until: string | null; note: string };
  collab_accounts: number;
  counts: { tickets: number; open_tickets: number; contacts: number; kb_articles: number; api_keys: number; webhooks: number; brands: number };
  pending_invitations: number;
  mailboxes: AdminMailbox[];
  /** This period's AI: the allowance used, purchased usage left, and the calls by feature. */
  ai: { included_used_usd: number; purchased_usd: number; by_feature: AiFeatureRec[] };
  /** The workspace's own audit log, newest first. */
  audit: AuditLog[];
  /** Set on a test workspace. */
  test: TestRec | null;
};

export type AdminRec = { user_id: string; role: AdminRole; granted_by: string | null; created_at: string };

export type AdminAuditRec = {
  id: string;
  actor: { type: "admin" | "cli" | "system"; id: string | null; email: string };
  action: string;
  target_type: "user" | "workspace" | "admin" | "job" | "instance";
  target_id: string | null;
  data: Record<string, unknown>;
  ip: string;
  created_at: string;
};

export type Updates = {
  current: string;
  previous_version: string;
  running_since: string;
  latest: { version: string; url: string; published_at: string | null };
  checked_at: string;
  auto: { reported: boolean; enabled: boolean; last_run_at: string | null; last_result: "none" | "current" | "updated" | "skipped" | "failed"; last_detail: string };
};

export const db = {
  users: [] as UserRec[],
  members: [] as MemberRec[],
  workspaces: [] as WorkspaceRec[],
  admins: [] as AdminRec[],
  jobs: [] as AdminJob[],
  audit: [] as AdminAuditRec[],
  /** The share of the AI charged each of the last 30 days gets, oldest first. */
  aiWeights: [] as number[],
  updates: null as unknown as Updates,
  /** Who is signed in to the panel; null when signed out. */
  session: null as null | { userId: string; token: string },
  /** Sign-ins between the password and the code. */
  pendingMfa: new Map<string, string>(),
  nextJobId: 1,
  /** The acting admin's address for audit rows (where the panel's requests come from). */
  ip: "203.0.113.24",
};

export const userById = (id: string) => db.users.find((u) => u.id === id);
export const userByEmail = (email: string) => db.users.find((u) => u.email.toLowerCase() === email.trim().toLowerCase());
export const workspaceById = (id: string) => db.workspaces.find((w) => w.id === id);
export const adminOf = (uid: string) => db.admins.find((a) => a.user_id === uid);
export const membersOf = (wid: string) => db.members.filter((m) => m.workspace_id === wid);
export const membershipsOf = (uid: string) => db.members.filter((m) => m.user_id === uid);
