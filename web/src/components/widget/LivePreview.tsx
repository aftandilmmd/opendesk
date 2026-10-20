// The real chat widget, live, inside the widget settings page. The widget
// bundle (Preact, web/widget) exports `mountPreview`, which renders the same UI
// into a shadow root inside our box against its in-memory backend. It is
// loaded on demand (a glob import keeps it out of the app's type program and
// out of the main bundle) and follows every draft change through `update`,
// never remounting.

import { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import type { WidgetConfig } from "@/lib/api/types";
import { cn } from "@/lib/cn";

export type PreviewScene = "launcher" | "home" | "chat" | "new";
type PreviewOptions = { config: WidgetConfig; scene: PreviewScene; dark?: boolean };
type PreviewHandle = { update(opts: Partial<PreviewOptions>): void; destroy(): void };
type PreviewModule = { mountPreview(host: HTMLElement, opts: PreviewOptions): PreviewHandle };

const loaders = import.meta.glob<PreviewModule>("../../../widget/src/preview.tsx");
const load = Object.values(loaders)[0] as (() => Promise<PreviewModule>) | undefined;

export function LivePreview({ config, scene, dark, className }: { config: WidgetConfig; scene: PreviewScene; dark: boolean; className?: string }) {
  const { t } = useTranslation("settingsDev");
  const host = useRef<HTMLDivElement>(null);
  const handle = useRef<PreviewHandle | null>(null);
  const latest = useRef<PreviewOptions>({ config, scene, dark });
  latest.current = { config, scene, dark };
  const [state, setState] = useState<"loading" | "ready" | "failed">(load ? "loading" : "failed");

  // Mount once; later changes go through update().
  useEffect(() => {
    if (!load || !host.current) return;
    let alive = true;
    const el = host.current;
    load()
      .then((m) => {
        if (!alive) return;
        handle.current = m.mountPreview(el, latest.current);
        setState("ready");
      })
      .catch(() => alive && setState("failed"));
    return () => {
      alive = false;
      handle.current?.destroy();
      handle.current = null;
    };
  }, []);

  useEffect(() => {
    handle.current?.update({ config, scene, dark });
  }, [config, scene, dark]);

  return (
    <div
      className={cn(
        "relative overflow-hidden rounded-xl border border-line shadow-xs transition-colors duration-200",
        dark ? "bg-[#17181b]" : "bg-[#f4f4f2]",
        className,
      )}
    >
      <FakeSite dark={dark} />
      <div ref={host} className="absolute inset-0" aria-label={t("widget.previewLabel")} role="region" />
      {state === "loading" && (
        <div className="pointer-events-none absolute bottom-5 right-5 size-12 animate-pulse-soft rounded-full bg-fg-4/30 motion-reduce:animate-none" aria-hidden />
      )}
      {state === "failed" && (
        <div className="absolute inset-0 flex items-center justify-center p-6 text-center">
          <div className="max-w-[240px] rounded-lg border border-line bg-surface px-4 py-3 text-[12.5px] text-fg-3 shadow-xs">{t("widget.previewFailed")}</div>
        </div>
      )}
    </div>
  );
}

/** A faint stand-in for the customer's site behind the widget. */
function FakeSite({ dark }: { dark: boolean }) {
  const bar = dark ? "bg-white/[0.06]" : "bg-black/[0.06]";
  const block = dark ? "bg-white/[0.035]" : "bg-black/[0.035]";
  return (
    <div className="pointer-events-none absolute inset-0 flex flex-col gap-5 p-5" aria-hidden>
      <div className="flex items-center gap-3">
        <div className={cn("size-5 rounded-md", bar)} />
        <div className={cn("h-2 w-16 rounded-full", bar)} />
        <div className="ml-auto flex gap-2.5">
          <div className={cn("h-2 w-10 rounded-full", bar)} />
          <div className={cn("h-2 w-10 rounded-full", bar)} />
          <div className={cn("h-2 w-10 rounded-full", bar)} />
        </div>
      </div>
      <div className="mt-6 flex flex-col gap-2.5">
        <div className={cn("h-4 w-3/5 rounded-md", bar)} />
        <div className={cn("h-4 w-2/5 rounded-md", bar)} />
        <div className={cn("mt-2 h-2 w-4/5 rounded-full", block)} />
        <div className={cn("h-2 w-3/4 rounded-full", block)} />
      </div>
      <div className="mt-4 grid grid-cols-3 gap-3">
        <div className={cn("h-24 rounded-lg", block)} />
        <div className={cn("h-24 rounded-lg", block)} />
        <div className={cn("h-24 rounded-lg", block)} />
      </div>
    </div>
  );
}
