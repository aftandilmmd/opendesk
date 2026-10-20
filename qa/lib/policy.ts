// Which changed files need recorded proof on a pull request, and what kind.
// One table, read by `pnpm qa`, `pnpm share`, the CI gate and the Claude Code hooks,
// so all four always agree. Pure node: the gate and the hooks run it without `pnpm install`.

// A surface someone can see. Each has its own way to record proof (qa/README.md "When proof is required").
export type Kind = "web" | "widget" | "site" | "docs" | "desktop" | "ios" | "admin";

type Rule = { kind: Kind; include: RegExp; exclude?: RegExp };

const TESTS = /(\.test\.[cm]?[jt]sx?|\.spec\.[cm]?[jt]sx?|\.d\.ts)$/;

// First match wins.
const RULES: Rule[] = [
  { kind: "widget", include: /^web\/widget\/(src\/|demo\.html$)/, exclude: new RegExp(`${TESTS.source}|^web/widget/src/mock\\.ts$`) },
  // The mock backend changes what the screens show in mock mode only, never in the product.
  { kind: "web", include: /^web\/(src\/|public\/|index\.html$)/, exclude: new RegExp(`${TESTS.source}|^web/src/mock/`) },
  { kind: "admin", include: /^admin\/(src\/|public\/|index\.html$)/, exclude: new RegExp(`${TESTS.source}|^admin/src/mock/`) },
  { kind: "site", include: /^site\/(src\/|public\/|astro\.config\.mjs$)/, exclude: TESTS },
  // Docs prose is reviewed as text; the docs chrome (components, styles, sidebar) is a surface.
  { kind: "docs", include: /^docs\/(src\/|public\/|astro\.config\.mjs$)/, exclude: new RegExp(`${TESTS.source}|^docs/src/content/`) },
  { kind: "desktop", include: /^desktop\/src\//, exclude: TESTS },
  { kind: "ios", include: /^ios\/.*\.(swift|xcassets\/.*|storyboard|xib|strings|xcstrings)$/, exclude: /Tests?\// },
];

// The shared design tokens are every surface's palette.
const BRAND = /^brand\//;

// Surfaces where a change is to how something behaves as well as how it looks: a walkthrough video
// is required too.
export const VIDEO_KINDS: ReadonlySet<Kind> = new Set<Kind>(["web", "widget", "admin", "desktop", "ios"]);

// Surfaces the harness records itself (`pnpm proof`). Anything else is captured outside it and
// published with `pnpm share --add <kind>:<file>`.
export const RECORDED_KINDS: ReadonlySet<Kind> = new Set<Kind>(["web", "widget", "admin", "site", "docs", "desktop", "ios"]);

// Surfaces whose proof the gate does not require (none today): a surface with nothing to record
// against goes here, and the gate names it for the reviewer instead of failing.
export const UNENFORCED_KINDS: ReadonlySet<Kind> = new Set<Kind>([]);

export const KINDS: readonly Kind[] = ["web", "widget", "site", "docs", "desktop", "ios", "admin"];

export function kindOf(file: string): Kind | undefined {
  for (const r of RULES) {
    if (r.include.test(file) && !r.exclude?.test(file)) return r.kind;
  }
  return undefined;
}

export type Classified = {
  // Every surface the change touches, with the files that put it there.
  kinds: Map<Kind, string[]>;
  // The surfaces whose proof is required.
  required: Kind[];
  // Of those, the ones that also need a walkthrough video.
  video: Kind[];
};

export function classify(files: readonly string[]): Classified {
  const kinds = new Map<Kind, string[]>();
  const add = (k: Kind, f: string) => kinds.set(k, [...(kinds.get(k) ?? []), f]);
  for (const f of files) {
    if (BRAND.test(f)) {
      add("web", f);
      add("site", f);
      continue;
    }
    const k = kindOf(f);
    if (k) add(k, f);
  }
  const required = KINDS.filter((k) => kinds.has(k) && !UNENFORCED_KINDS.has(k));
  return { kinds, required, video: required.filter((k) => VIDEO_KINDS.has(k)) };
}

export function isKind(s: string): s is Kind {
  return (KINDS as readonly string[]).includes(s);
}
