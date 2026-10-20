// Widget settings (admin) and the public widget config (contracts/api.md "Widget").

import type { Widget, WidgetConfig, WidgetSettings } from "@/lib/api/types";
import { db, userRef, type WsData } from "../db";
import { publish } from "../gateway";
import { HttpError, forbidden, get, invalid, patch } from "../router";
import { defaultHelpUrl } from "@/lib/helpCenter";
import { defaultBrand, helpPageUrl, legacyWidget, syncLegacyWidget, widgetOut } from "../teams";
import { hasControl, isRecord, nowIso, oneLine, uuid } from "../util";
import { aiOff } from "./ai";
import { widgetBot } from "../bots";
import { ALL_FILE_TYPES, fileTypeExtensions } from "@/components/widget/fileTypes";

type Check = (v: unknown) => unknown;

const bool = (key: string): Check => (v) => {
  if (typeof v !== "boolean") throw invalid(`${key} must be true or false`);
  return v;
};
const oneOf = <T extends string>(key: string, options: readonly T[]): Check => (v) => {
  if (typeof v !== "string" || !options.includes(v as T)) throw invalid(`${key} must be ${options.slice(0, -1).join(", ")} or ${options[options.length - 1]}`);
  return v;
};
const offset = (key: string): Check => (v) => {
  if (typeof v !== "number" || !Number.isInteger(v) || v < 0 || v > 200) throw invalid(`${key} must be a whole number of pixels from 0 to 200`);
  return v;
};

/** Trimmed, whitespace collapsed, no <, > or control characters. */
function cleanText(key: string, v: unknown, max: number, min = 0): string {
  if (typeof v !== "string") throw invalid(`${key} must be text`);
  const s = oneLine(v);
  if (/[<>]/.test(s) || hasControl(s)) throw invalid(`${key} can't contain < or > or control characters`);
  if (s.length > max) throw invalid(`${key} can be at most ${max} characters`);
  if (s.length < min) throw invalid(`${key} must be at least ${min} characters`);
  return s;
}
const text = (key: string, max: number): Check => (v) => cleanText(key, v, max);

const CHECKS: Partial<Record<keyof WidgetSettings, Check>> = {
  enabled: bool("enabled"),
  require_email: bool("require_email"),
  show_team: bool("show_team"),
  sound: bool("sound"),
  attachments: bool("attachments"),
  voice_messages: bool("voice_messages"),
  voice_max_seconds: (v) => {
    if (typeof v !== "number" || !Number.isInteger(v) || v < 5 || v > 300) throw invalid("voice_max_seconds must be a whole number of seconds from 5 to 300");
    return v;
  },
  attachment_types: (v) => {
    if (!Array.isArray(v) || v.some((x) => typeof x !== "string" || !ALL_FILE_TYPES.includes(x))) throw invalid("attachment_types must be file types of the catalog");
    return ALL_FILE_TYPES.filter((id) => v.includes(id));
  },
  greeting: (v) => {
    if (typeof v !== "string") throw invalid("greeting must be text");
    const s = v.replace(/\r\n/g, "\n").trim();
    if (s.length > 300) throw invalid("Keep the greeting under 300 characters");
    if (/[<>]/.test(s) || hasControl(s, true)) throw invalid("The greeting must be plain text, without < or >");
    return s;
  },
  allowed_origins: (v) => {
    if (!Array.isArray(v) || v.some((x) => typeof x !== "string")) throw invalid("allowed_origins must be a list of origins");
    const list = (v as string[]).map((x) => x.trim().replace(/\/+$/, "")).filter(Boolean);
    if (list.length > 20) throw invalid("Add at most 20 allowed origins");
    for (const o of list) if (!/^https?:\/\/[^/\s]+$/.test(o)) throw invalid(`${o} is not a valid origin (like https://example.com)`);
    return [...new Set(list)];
  },
  color: (v) => {
    if (typeof v !== "string" || (v !== "" && !/^#[0-9a-fA-F]{6}$/.test(v))) throw invalid("color must be a hex colour like #4f46e5, or empty for the brand colour");
    return v.toLowerCase();
  },
  theme: oneOf("theme", ["auto", "light", "dark"] as const),
  position: oneOf("position", ["right", "left"] as const),
  offset_x: offset("offset_x"),
  offset_y: offset("offset_y"),
  launcher: oneOf("launcher", ["icon", "label"] as const),
  launcher_label: text("launcher_label", 24),
  radius: oneOf("radius", ["square", "soft", "round"] as const),
  title: text("title", 40),
  subtitle: text("subtitle", 80),
  suggestions: (v) => {
    if (!Array.isArray(v)) throw invalid("suggestions must be a list");
    const list = v.map((x) => cleanText("Each suggestion", x, 60)).filter(Boolean);
    if (list.length > 4) throw invalid("Add at most 4 suggestions");
    for (const s of list) if (s.length < 2) throw invalid("Each suggestion must be 2 to 60 characters");
    return list;
  },
};

function requireAdmin(ws: WsData) {
  const r = ws.members.find((m) => m.user_id === db.meId)?.role;
  if (r !== "owner" && r !== "admin") throw forbidden("Only admins can change the widget");
}

/** Validates every given key first, so a refused patch changes nothing. */
export function widgetPatch(body: Record<string, unknown>): Partial<WidgetSettings> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(body)) {
    const check = CHECKS[k as keyof WidgetSettings];
    if (check) out[k] = check(v);
  }
  return out as Partial<WidgetSettings>;
}

/** Whether hours allow chat now: the team's own hours, else the workspace's; always open without hours. */
function openNow(ws: WsData, teamId: string | null): boolean {
  const team = teamId ? ws.teams.find((t) => t.id === teamId) : undefined;
  const h = team?.business_hours ?? { ...ws.routing.hours, timezone: ws.workspace.settings.timezone ?? "UTC" };
  if (!h.enabled) return true;
  try {
    const parts = new Intl.DateTimeFormat("en-GB", { timeZone: h.timezone, weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(new Date());
    const get = (k: string) => parts.find((p) => p.type === k)?.value ?? "";
    const day = get("weekday").slice(0, 3).toLowerCase() as keyof typeof h.schedule;
    const at = Number(get("hour")) * 60 + Number(get("minute"));
    const m = (v: string) => Number(v.slice(0, 2)) * 60 + Number(v.slice(3));
    return (h.schedule[day] ?? []).some((r) => at >= m(r.start) && at < m(r.end));
  } catch {
    return true;
  }
}

export function widgetConfig(ws: WsData, widget?: Widget): WidgetConfig {
  const row = widget ?? legacyWidget(ws);
  const w = row?.settings ?? ws.widget;
  const brand = ws.brands.find((b) => b.id === row?.brand_id) ?? defaultBrand(ws);
  const wsSettings = ws.workspace.settings;
  const rank = { online: 0, away: 1, offline: 2 } as const;
  const teamMembers = row?.team_id ? new Set(ws.teams.find((t) => t.id === row.team_id)?.members.filter((m) => m.role !== "observer").map((m) => m.user_id)) : null;
  const team = w.show_team
    ? ws.members
        .filter((m) => m.role !== "viewer" && (!teamMembers || teamMembers.has(m.user_id)))
        .sort((a, b) => rank[a.availability ?? "online"] - rank[b.availability ?? "online"])
        .slice(0, 3)
        .map((m) => {
          const u = userRef(m.user_id);
          return { name: (u?.name ?? "").split(" ")[0], avatar_url: u?.avatar_url ?? null };
        })
    : [];
  const helpOn = brand ? brand.help_center.enabled : !!wsSettings.help_center_enabled;
  return {
    workspace_name: brand?.name ?? ws.workspace.name,
    brand_color: w.color || brand?.color || wsSettings.brand_color || null,
    greeting: w.greeting,
    help_center_url: helpOn ? (brand ? helpPageUrl(brand) : defaultHelpUrl(ws.workspace.slug)) : null,
    require_email: w.require_email,
    locale: brand?.locale || wsSettings.locale || null,
    avatar_url: row?.images.avatar ?? ws.workspace.images.widget_avatar ?? brand?.images.logo ?? ws.workspace.avatar_url,
    launcher_icon_url: row?.images.launcher ?? ws.workspace.images.widget_launcher,
    theme: w.theme,
    position: w.position,
    offset_x: w.offset_x,
    offset_y: w.offset_y,
    launcher: w.launcher,
    launcher_label: w.launcher_label,
    radius: w.radius,
    title: w.title,
    subtitle: w.subtitle,
    suggestions: [...w.suggestions],
    sound: w.sound,
    attachments: w.attachments ?? true,
    attachment_extensions: !(w.attachments ?? true) ? [] : w.attachment_types?.length ? fileTypeExtensions(w.attachment_types) : null,
    voice_messages: w.voice_messages ?? false,
    voice_max_seconds: w.voice_max_seconds ?? 60,
    team,
    ai_answers: !aiOff() && ws.ai.enabled && ws.ai.widget_answers,
    bot: widgetBot(ws, row?.id),
    topics: (w.topics ?? []).map((t) => ({ id: t.id, label: t.label })),
    open: openNow(ws, row?.team_id ?? null),
    offline_message: w.offline_message ?? "",
    brand: { name: brand?.name ?? ws.workspace.name, color: brand?.color || wsSettings.brand_color || null },
  };
}

export function registerWidget() {
  // Kept: the default brand's first widget (contracts/teams.md).
  get("/v1/widget/settings", (ctx) => legacyWidget(ctx.ws)?.settings ?? ctx.ws.widget);

  patch("/v1/widget/settings", (ctx) => {
    requireAdmin(ctx.ws);
    if (!isRecord(ctx.body)) throw invalid("Body must be an object");
    const changes = widgetPatch(ctx.body);
    const row = legacyWidget(ctx.ws);
    if (row) {
      row.settings = { ...row.settings, ...changes };
      row.updated_at = nowIso();
      syncLegacyWidget(ctx.ws);
      publish(ctx.ws, "widget.updated", { widget: widgetOut(ctx.ws, row) });
    } else ctx.ws.widget = { ...ctx.ws.widget, ...changes };
    ctx.ws.audit.unshift({
      id: uuid(),
      actor: { type: "user", user: userRef(db.meId), api_key_id: null },
      action: "widget.settings_updated",
      entity_type: "workspace",
      entity_id: ctx.ws.workspace.id,
      data: { keys: Object.keys(changes) },
      ip: "84.152.33.17",
      created_at: nowIso(),
    });
    return ctx.ws.widget;
  });

  // Public: the widget asks with any widget's key, so any workspace may answer.
  get("/v1/widget/config", (ctx) => {
    const key = ctx.query.get("key");
    if (!key) return widgetConfig(ctx.ws);
    for (const ws of db.workspaces) {
      const w = ws.widgets.find((x) => x.key === key);
      if (w) return widgetConfig(ws, w);
      if (ws.workspace.widget_key === key) return widgetConfig(ws);
    }
    throw new HttpError(404, "not_found", "No widget uses this key");
  });
}
