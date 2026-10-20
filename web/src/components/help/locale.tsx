// Language for the customer-facing pages (help center, CSAT): `?lang=` first,
// then the visitor's browser, then the workspace default, then English. A
// workspace that fixes its language uses it for everyone.
// The agent app stays English, so the choice is undone on unmount.

import { useRouter, useRouterState } from "@tanstack/react-router";
import { Check, Globe } from "lucide-react";
import { Popover } from "radix-ui";
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { LOCALE_NAMES, pickLocale, resetLocale, setLocale, SUPPORTED, type Locale } from "@/i18n";
import { floatingPanel } from "@/components/ui/popover";
import { cn } from "@/lib/cn";

const STORE = "od-public-lang";

function langParam(search: unknown): string | null {
  const v = (search as Record<string, unknown> | undefined)?.lang;
  return typeof v === "string" ? v : null;
}

// A visitor's explicit choice outlives in-page links that drop `?lang=`.
function remembered(): string | null {
  try {
    return sessionStorage.getItem(STORE);
  } catch {
    return null;
  }
}
function remember(l: string) {
  try {
    sessionStorage.setItem(STORE, l);
  } catch {
    /* storage unavailable: the URL still carries it */
  }
}

/**
 * Picks and applies the page language once `ready` (the public data, which
 * carries the workspace default, has loaded or failed). Returns the locale and
 * whether its catalogs are in, so pages can hold back text until then.
 */
export function usePublicLocale(workspaceDefault: string | null | undefined, ready: boolean, fixed = false) {
  const fromUrl = useRouterState({ select: (s) => langParam(s.location.search) });
  useEffect(() => {
    if (fromUrl) remember(fromUrl);
  }, [fromUrl]);
  const explicit = fromUrl ?? remembered();
  const [applied, setApplied] = useState<Locale | null>(null);
  const lng = ready ? (fixed ? pickLocale({ explicit: workspaceDefault }) : pickLocale({ explicit, workspaceDefault })) : null;

  useEffect(() => {
    if (!lng) return;
    let live = true;
    void setLocale(lng, ["public", "common"]).then(() => live && setApplied(lng));
    return () => {
      live = false;
    };
  }, [lng]);

  useEffect(() => () => resetLocale(), []);

  return { locale: applied ?? lng ?? "en", loaded: !!lng && applied === lng };
}

/** A quiet footer control that rewrites `?lang=`. */
export function LanguageSwitcher({ current, className }: { current: Locale; className?: string }) {
  const { t } = useTranslation("public");
  const router = useRouter();
  const [open, setOpen] = useState(false);

  const choose = (l: Locale) => {
    setOpen(false);
    remember(l);
    const url = new URL(window.location.href);
    url.searchParams.set("lang", l);
    router.history.replace(url.pathname + url.search + url.hash);
  };

  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Popover.Trigger
        aria-label={t("footer.language")}
        className={cn("flex h-7 items-center gap-1.5 rounded-md px-2 text-xs text-fg-4 outline-none hover:bg-hover hover:text-fg-2 focus-visible:shadow-[0_0_0_2px_var(--focus)] data-[state=open]:bg-hover data-[state=open]:text-fg-2", className)}
      >
        <Globe className="size-3.5" />
        <span>{LOCALE_NAMES[current]}</span>
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content side="top" align="end" sideOffset={6} className={cn(floatingPanel, "max-h-[320px] w-[188px] overflow-y-auto p-1")}>
          <ul role="listbox" aria-label={t("footer.language")}>
            {SUPPORTED.map((l) => (
              <li key={l}>
                <button
                  type="button"
                  role="option"
                  aria-selected={l === current}
                  lang={l}
                  dir={l === "ar" ? "rtl" : "ltr"}
                  onClick={() => choose(l)}
                  className="flex h-8 w-full items-center gap-2 rounded-md px-2.5 text-start text-[13px] text-fg-2 outline-none hover:bg-hover hover:text-fg focus-visible:bg-hover"
                >
                  <span className="flex-1">{LOCALE_NAMES[l]}</span>
                  {l === current && <Check className="size-3.5 text-fg" />}
                </button>
              </li>
            ))}
          </ul>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
