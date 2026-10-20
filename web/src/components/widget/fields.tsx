// Pieces of the widget settings editor: the accent colour field, the home
// screen suggestions list, text checks matching the server's, and the mapping
// from a settings draft to the WidgetConfig the preview renders.

import { Check, Plus, Trash2 } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button";
import { TextInput } from "@/components/ui/input";
import { Tooltip } from "@/components/ui/tooltip";
import { SortableList } from "@/components/settings2/Sortable";
import type { Bot, Member, WidgetBot, WidgetConfig, WidgetSettings, Workspace } from "@/lib/api/types";
import { OLLIE_LOOK } from "@/lib/botlook";
import { cn } from "@/lib/cn";

export const LIMITS = { greeting: 300, launcher_label: 24, title: 40, subtitle: 80, suggestion: 60, suggestions: 4, origins: 20 } as const;

/** Text settings refuse markup and control characters (contracts/api.md). */
// eslint-disable-next-line no-control-regex
export const hasMarkup = (s: string) => /[<>\u0000-\u0008\u000b-\u001f\u007f]/.test(s);
export const HEX = /^#[0-9a-f]{6}$/i;

/** Trimmed, with runs of whitespace collapsed, like the server stores it. */
export const tidy = (s: string) => s.trim().replace(/\s+/g, " ");

const PRESETS = ["#111111", "#2563eb", "#4f46e5", "#7c3aed", "#db2777", "#dc2626", "#ea580c", "#16a34a", "#0d9488"];

/** "" is the workspace brand colour; otherwise a #rrggbb swatch or custom value. */
export function ColorField({ value, onChange, brand }: { value: string; onChange: (v: string) => void; brand: string | null | undefined }) {
  const { t } = useTranslation("settingsDev");
  const [text, setText] = useState<string | null>(null);
  const shown = text ?? (value || brand || "");
  const bad = text !== null && text !== "" && !HEX.test(text.startsWith("#") ? text : `#${text}`);
  const commit = (s: string) => {
    const v = s.trim();
    if (!v) {
      setText(null);
      return onChange("");
    }
    const hex = v.startsWith("#") ? v : `#${v}`;
    if (HEX.test(hex)) {
      onChange(hex.toLowerCase());
      setText(null);
    }
  };
  const swatch = (c: string | null, label: string, on: boolean, pick: () => void) => (
    <Tooltip key={label} content={label}>
      <button
        type="button"
        role="radio"
        aria-checked={on}
        aria-label={label}
        onClick={pick}
        className={cn(
          "relative flex size-7 items-center justify-center rounded-full border border-black/10 outline-none transition-transform duration-100 hover:scale-105 focus-visible:shadow-[0_0_0_2px_var(--surface),0_0_0_4px_var(--focus)] motion-reduce:transition-none",
          on && "shadow-[0_0_0_2px_var(--surface),0_0_0_3.5px_var(--fg)]",
          !c && "bg-[conic-gradient(from_45deg,#f4f4f5_0_25%,#d4d4d8_0_50%,#f4f4f5_0_75%,#d4d4d8_0)] bg-[length:8px_8px]",
        )}
        style={c ? { background: c } : undefined}
      >
        {on && <Check className="size-3.5" style={{ color: c ? readableOn(c) : "#111" }} strokeWidth={2.5} />}
      </button>
    </Tooltip>
  );
  return (
    <div className="flex flex-col gap-2.5">
      <div role="radiogroup" aria-label={t("widget.color")} className="flex flex-wrap items-center gap-2">
        {swatch(brand || null, brand ? t("widget.colorBrand", { hex: brand }) : t("widget.colorBrandNone"), value === "", () => onChange(""))}
        <span className="mx-0.5 h-5 w-px bg-line" aria-hidden />
        {PRESETS.map((c) => swatch(c, c, value.toLowerCase() === c, () => onChange(c)))}
      </div>
      <div className="flex items-center gap-2">
        <label className="relative flex size-8 shrink-0 cursor-pointer items-center justify-center overflow-hidden rounded-md border border-line shadow-xs" style={{ background: HEX.test(shown) ? shown : undefined }}>
          <span className="sr-only">{t("widget.colorPick")}</span>
          <input type="color" className="absolute inset-0 cursor-pointer opacity-0" value={HEX.test(shown) ? shown : "#111111"} onChange={(e) => onChange(e.target.value.toLowerCase())} />
        </label>
        <TextInput
          inputSize="sm"
          className="mono w-[120px]"
          value={shown}
          invalid={bad}
          maxLength={7}
          placeholder="#rrggbb"
          aria-label={t("widget.colorHex")}
          onFocus={() => setText(value)}
          onChange={(e) => setText(e.target.value)}
          onBlur={() => text !== null && (bad ? setText(null) : commit(text))}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              if (text !== null) commit(text);
            }
          }}
        />
        <span className="text-xs text-fg-3">{value ? t("widget.colorCustom") : t("widget.colorFromBrand")}</span>
      </div>
    </div>
  );
}

export function readableOn(hex: string): string {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim());
  if (!m) return "#ffffff";
  const n = parseInt(m[1], 16);
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((c) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.45 ? "#0a0a0a" : "#ffffff";
}

export function suggestionProblem(s: string): "short" | "long" | "markup" | null {
  const v = tidy(s);
  if (v.length < 2) return "short";
  if (v.length > LIMITS.suggestion) return "long";
  if (hasMarkup(v)) return "markup";
  return null;
}

/** Up to four prompts on the home screen, edited in place and reordered by drag or keyboard. */
export function SuggestionsEditor({ value, onChange }: { value: string[]; onChange: (v: string[]) => void }) {
  const { t } = useTranslation("settingsDev");
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  // Stable ids by position so rows keep focus while typing.
  const items = value.map((v, i) => ({ id: `s${i}`, v }));
  const full = value.length >= LIMITS.suggestions;
  const add = () => {
    const p = suggestionProblem(text);
    if (p) return setError(t(`widget.suggestion_${p}`));
    if (value.some((x) => x.toLowerCase() === tidy(text).toLowerCase())) return setError(t("widget.suggestionDuplicate"));
    onChange([...value, tidy(text)]);
    setText("");
    setError(null);
  };
  return (
    <div className="flex flex-col gap-2">
      {value.length > 0 && (
        <SortableList
          items={items}
          handleLabel={(it) => t("widget.suggestionMove", { text: it.v })}
          onReorder={(ids) => onChange(ids.map((id) => value[Number(id.slice(1))]))}
          className="overflow-hidden rounded-md border border-line"
          renderRow={(it, handle, i) => {
            const p = it.v ? suggestionProblem(it.v) : "short";
            return (
              <div className="flex items-center gap-1.5 border-b border-line-soft bg-surface px-1.5 py-1 last:border-0">
                {handle}
                <input
                  value={it.v}
                  maxLength={LIMITS.suggestion + 10}
                  aria-label={t("widget.suggestionN", { n: i + 1 })}
                  aria-invalid={!!p || undefined}
                  onChange={(e) => onChange(value.map((x, j) => (j === i ? e.target.value : x)))}
                  className={cn("h-7 min-w-0 flex-1 rounded-sm bg-transparent px-1.5 text-[12.5px] text-fg outline-none focus:bg-sunken", p && "text-danger-fg")}
                />
                {p && <span className="shrink-0 text-[11px] text-danger-fg">{t(`widget.suggestion_${p}`)}</span>}
                <Button square size="xs" variant="ghost" aria-label={t("widget.suggestionRemove", { text: it.v })} onClick={() => onChange(value.filter((_, j) => j !== i))}>
                  <Trash2 />
                </Button>
              </div>
            );
          }}
        />
      )}
      <div className="flex gap-2">
        <TextInput
          inputSize="sm"
          value={text}
          disabled={full}
          invalid={!!error}
          maxLength={LIMITS.suggestion + 10}
          placeholder={full ? t("widget.suggestionsFull") : t("widget.suggestionPlaceholder")}
          aria-label={t("widget.suggestionAdd")}
          onChange={(e) => {
            setText(e.target.value);
            setError(null);
          }}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              add();
            }
          }}
        />
        <Button size="sm" icon={<Plus className="size-3.5" />} onClick={add} disabled={full || !text.trim()}>
          {t("widget.add")}
        </Button>
      </div>
      <div className="flex min-h-4 items-start justify-between gap-3">
        {error ? (
          <p role="alert" className="animate-rise-in text-xs text-danger-fg">
            {error}
          </p>
        ) : (
          <p className="text-[12px] text-fg-4">{!value.length ? t("widget.suggestionsEmpty") : null}</p>
        )}
        <span className="mono shrink-0 text-[11px] tabular-nums text-fg-4">
          {value.length} / {LIMITS.suggestions}
        </span>
      </div>
    </div>
  );
}

/** The default bot before the bots load. */
export const OLLIE_BOT: WidgetBot = { id: null, name: "Ollie", role: "", avatar_url: "", look: OLLIE_LOOK, greeting: "" };

/** A bot as the widget config carries it (contracts/bots.md). */
export function widgetBotOf(b: Bot): WidgetBot {
  return { id: b.id, name: b.name, role: b.role, avatar_url: b.avatar_url, look: b.look, greeting: b.personality.greeting };
}

/** What GET /v1/widget/config would answer for this draft (contracts/api.md). */
export function toWidgetConfig(d: WidgetSettings, ws: Workspace | null, members: Member[] | undefined, aiAnswers: boolean, bot?: WidgetBot | null): WidgetConfig {
  const presenceRank = { online: 0, away: 1, offline: 2 } as const;
  const team = d.show_team
    ? (members ?? [])
        .filter((m) => m.role !== "viewer")
        .sort((a, b) => presenceRank[a.presence] - presenceRank[b.presence])
        .slice(0, 3)
        .map((m) => ({ name: m.user.name.split(/\s+/)[0] || m.user.name, avatar_url: m.user.avatar_url }))
    : [];
  return {
    workspace_name: ws?.name ?? "",
    brand_color: d.color || ws?.settings.brand_color || null,
    greeting: d.greeting,
    help_center_url: null,
    require_email: d.require_email,
    locale: ws?.settings.locale || null,
    avatar_url: ws?.images?.widget_avatar ?? ws?.avatar_url ?? null,
    launcher_icon_url: ws?.images?.widget_launcher ?? null,
    theme: d.theme,
    position: d.position,
    offset_x: d.offset_x,
    offset_y: d.offset_y,
    launcher: d.launcher,
    launcher_label: tidy(d.launcher_label),
    radius: d.radius,
    title: tidy(d.title),
    subtitle: tidy(d.subtitle),
    suggestions: d.suggestions.map(tidy).filter((s) => s.length >= 2),
    sound: d.sound,
    attachments: d.attachments,
    team,
    ai_answers: aiAnswers,
    bot: bot ?? OLLIE_BOT,
  };
}
