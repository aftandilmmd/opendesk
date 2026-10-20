# QA and proof

Every pull request is held to one rule (`lib/gate.ts`):

- a **QA section**: `pnpm qa` passed on the pull request's head commit
- for a change to something people see, a **Proof section**: stills of every surface it changes,
  and a walkthrough video wherever the surface has behaviour (everything but the site and docs),
  recorded after the last change to those files

CI's `Proof` check (`.github/workflows/proof.yml`) runs main's copy of the gate against the
pull request's commits and its current description, and re-runs whenever the description
changes. The Claude Code hooks in `.claude/settings.json` hold an agent to the same rule:
`gh pr create` is refused in favour of `pnpm share`, and an agent cannot finish while its open
pull request fails the gate.

## One-time setup

```bash
cd qa && pnpm install && pnpm doctor
```

`pnpm doctor` checks node 22.18+, ffmpeg with libx264, gh 2.99+ signed in, and that Playwright's
Chromium launches, and prints the fix for each miss. The `web/`, `site/` and `docs/` trees are
installed by the first recording that needs them.

## The loop

```bash
git commit ...                   # QA and proof vouch for a commit, never a dirty tree
pnpm qa                          # CI's checks for every area the branch changes
pnpm proof inbox                 # the flows for what you changed (when it is visible)
git push -u origin HEAD
pnpm share --title "feat: ..." --body-file /tmp/pr.md   # opens the PR with both sections
```

After a follow-up commit: push, `pnpm qa`, record again if a surface changed, `pnpm share`.
`share` replaces the sections in place and keeps the rest of the description. When the stills
changed since the last publish, it also comments with each changed still before and after.

`pnpm gate` prints what CI's `Proof` check will say about this branch's pull request.

## `pnpm qa`

Runs, for the areas the branch changes since it left `main`, the checks CI runs: gofmt, go vet,
go build and go test for the touched packages; typecheck, lint and the related vitest files in
`web/`, `admin/` and `desktop/`; the site and docs builds; mix format, compile and test in
`realtime/`; terraform fmt and validate; the installer checks; this harness's own tests.
Database tests skip unless `OPENDESK_TEST_DATABASE_URL` is set, and the QA section says so.
Logs go to `.artifacts/qa/logs/<sha>/`.

`--all` checks every area. `--dirty` allows uncommitted changes, for a run that cannot be shared.

## When proof is required

`lib/policy.ts` is the list, and there is no "small enough to skip":

| Surface | Files | Needs | Recorded with |
| --- | --- | --- | --- |
| app | `web/src`, `web/public`, `web/index.html`, `brand/` | stills and video | `pnpm proof` on the mock (`VITE_MOCK=1`) |
| widget | `web/widget/src`, `web/widget/demo.html` | stills and video | `pnpm proof` on the widget's demo page and mock |
| site | `site/src`, `site/public`, `brand/` | stills | `pnpm proof` on the astro dev server |
| docs | `docs/src` except `content/`, `docs/public` | stills | `pnpm proof` on the astro dev server |
| admin | `admin/src` | stills and video | `pnpm proof` on the admin mock (`VITE_MOCK=1`) |
| desktop | `desktop/src` | stills and video | `pnpm proof`: the Electron app in a sandbox run, on the app's mock |
| iOS | `ios/` Swift, assets and strings | stills and video | `pnpm proof`: the Debug build in demo mode on the `opendesk-qa` simulator |

Tests, the mocks (`web/src/mock/`, `admin/src/mock/`) and docs prose (`docs/src/content/`) never
need proof.

A maintainer can apply the `qa-exempt` label in GitHub to a pull request that cannot carry QA or
proof. Agents never apply it, and pull requests opened by bots are exempt.

## Writing a flow

Flows live in `flows/<area>.flow.ts`, one `test` per walkthrough. Extend the area's file when your
change lands in it; add one when it does not exist. Write the flow from the code you changed: you
know the routes, labels and fields.

```ts
import { expect, test } from "../lib/proof.ts";

test("assign a ticket from the queue", async ({ page, proof }) => {
  await proof.open("/inbox/unassigned");
  const tickets = page.getByRole("listbox", { name: "Tickets" });
  await expect(tickets.getByRole("option").first()).toBeVisible();
  await proof.chapter("Assign", "Take a ticket from the unassigned queue");
  await proof.shot("queue", { caption: "The unassigned queue" });

  await tickets.getByRole("button", { name: "Assign #1086 to me" }).click();
  await expect(page.getByText("Assigned to you")).toBeVisible();
  await proof.shot("assigned", { caption: "The ticket, now yours" });
});
```

- `proof.open(path?, params?)` opens a path on the flow's target (`/` by default; the widget's
  demo page for the widget)
- `proof.shot(name, { caption?, target?, ignore? })` saves a still. The name is kebab-case and is
  what follow-up comments compare by, so keep it stable. `target` shoots one element; `ignore`
  takes locators whose content changes on its own, skipped when comparing. Every flow takes at
  least one
- `proof.chapter(title, description?)` shows a title card in the video
- `proof.dwell(ms?)` holds a result on screen long enough to read
- `test.use({ target: "widget" })`, `"admin"`, `"site"`, `"docs"` or `"desktop"` for the other
  surfaces; `"web"` is the default. iOS flows have their own API (below)
- `test.use({ colorScheme: "dark" })` for the dark theme; shoot both when the change is about colour
- `test.use({ live: true })` keeps the mock's simulated customers, teammates and Ollie running
  (off by default so screens hold still); `test.use({ fixedClock: false })` lets time run

Conventions:

- `expect(...)` the content before every `chapter` and `shot`, so neither lands on a loading state
- locate by role and accessible name (`getByRole`, `getByLabel`, `getByText`), never CSS classes
- `pressSequentially(text, { delay: 60 })` where typing should be visible, `fill` where it should not
- no `waitForTimeout` except through `dwell`
- keep a walkthrough under about 30 seconds; split longer stories into tests
- the title reads as a sentence about what the reviewer sees; it heads the PR section
- when the mock lacks the state the change is about, extend `web/src/mock/` in the same pull request

When you need a selector you cannot read off the code, print the accessibility tree instead of
opening a browser:

```bash
pnpm aria /inbox/unassigned          # the app, whole page
pnpm aria /inbox/unassigned main     # one region, fewer tokens
pnpm aria admin:/jobs                # another target: widget, admin, site, docs
```

Then **read every still once** (they are PNGs under `.artifacts/run/<flow>/shots/`). The flow's
assertions say the page worked; only the still says it shows what the reviewer needs to see.

Stills are deterministic, so the same code gives pixel-identical stills and a follow-up comment
shows only what changed:

- the mocks run at the same fixed instant with the same random sequence
- `proof.open` on the app waits for its realtime connection (presence, live counts) before it returns
- a still is the first frame two captures in a row agree on, so motion in flight is waited out
- the site and docs record with reduced motion, since their showpiece animations loop forever
  (`test.use({ reducedMotion: "no-preference" })` when the motion is what changed); the iPhone
  simulator runs with Reduce Motion for the same reason

## The admin panel

`test.use({ target: "admin" })` records the admin panel on its mock (`admin/src/mock/`), signed in
as Ava Reyes, a super admin; `proof.open("/", { mock: "anon" })` starts signed out, and
`{ mock_role: "support" }` or `"viewer"` signs in with fewer permissions. A full page load re-seeds
the data, so after `open` move around inside the app (the sidebar) to keep a change on screen.
Lists are newest first: search (`/workspaces?q=halcyon`) for the seeded workspaces and users named
in `admin/src/mock/seed.ts`.

## The desktop app

`test.use({ target: "desktop" })` launches the desktop app's development build pointed at the app's
mock, in a sandbox run (`OPENDESK_DESKTOP_SANDBOX`, `desktop/src/main/env.ts`): its own throwaway
settings, no `opendesk://` handler, no OS notification, badge or Dock icon, and a window that is
invisible and click-through, so recording never disturbs the person at the machine. Playwright
drives the window's page like a tab, so a desktop flow reads like an app flow. Stills are the
page at the display's scale; the native title bar and material are not in them.

## The iPhone app

iOS flows import their own `test` and drive the Debug build in demo mode (`OPENDESK_DEMO=1`,
`ios/Opendesk/Core/Demo/`): signed in as Maya Chen in Margin, no network, a fixed clock. They run
on a simulator of the harness's own, `opendesk-qa`, created on first use and shut down afterwards;
no other simulator is ever booted, shut down or touched. The first run builds the app (`xcodebuild`
into `.artifacts/ios-build`, incremental after that); macOS with Xcode only.

```ts
import { test } from "../lib/ios.ts";

test.use({ start: "/inbox/unassigned" });

test("a live chat from the unassigned queue", async ({ ios }) => {
  await ios.shot("unassigned", { caption: "Unassigned, with live chats waiting" });
  await ios.open("/inbox/unassigned/1086");
  await ios.shot("ticket", { caption: "The live chat with Yusuf" });
});
```

- `start` is the path the app opens on launch; `ios.open(path)` moves to another while recording.
  Paths are the deep link paths (`/inbox/<folder>`, `/inbox/<folder>/<ticket id or number>`,
  `/views/<id>`, `/notifications`) plus `/account` and `/ollie`. Seeded tickets, views and their
  ids are listed at the top of `ios/Opendesk/Core/Demo/DemoSeed.swift`
- `ios.shot(name, { caption })` and `ios.dwell(ms)` work like their browser twins
- the whole flow is one screen recording; `test.use({ colorScheme: "dark" })` for dark mode
- there is no tapping: show a state by navigating to it, and seed it in demo mode when it does not
  exist yet (extend `DemoSeed.swift` in the same pull request)

## Anything else

Media captured some other way can go into the Proof section with
`pnpm share --add '<surface>:<file>#Caption'` (images png, jpg, gif; videos mp4, mov, webm; up to
10 MB each). Never attach a capture of the whole screen: it shows whatever else is open.

## Being frugal with the machine

Several agents share this machine. A machine-wide lock runs one recording (or `pnpm aria`) at a
time; a second one waits. Never fan recording out to subagents: they would only queue. Each run
starts the dev servers it needs on free ports and stops them when it ends; nothing stays running,
and nothing touches a dev server someone else started. Frames are spooled to disk while the
browser runs and encoded after it exits.

## When a flow fails

The list reporter prints the failing step and its locator. Failures keep a Playwright trace;
`pnpm exec playwright show-trace <trace.zip>` opens it. A dev server that will not start leaves
its log in `.artifacts/servers/<target>.log`. A failed flow's frames are dropped instead of
encoded (`QA_VIDEO_ON_FAIL=1` keeps them).

## Recording settings

1440x900 at 30 fps, H.264 CRF 18 (`slow` preset), yuv420p so every browser plays it. A clip over
10 MB is re-encoded smaller.

| Variable | Default | |
| --- | --- | --- |
| `QA_WIDTH`, `QA_HEIGHT` | `1440`, `900` | window and video size |
| `QA_FPS` | `30` | frame rate |
| `QA_CRF` | `18` | quality, lower is better and bigger |
| `QA_PRESET` | `slow` | x264 preset |
| `QA_ENCODE_THREADS` | `4` | encoder threads, which also bound its memory |
| `QA_SLOWMO` | `250` | ms between actions, so a viewer can follow |
| `QA_MAX_VIDEO_MB` | `10` | re-encode above this |
| `QA_VIDEO_ON_FAIL` | | `1` encodes failed flows too |
| `QA_LOCK_WAIT_MIN` | `30` | how long a recording waits for another to finish |

## Safety

The repository is public and so is everything attached to its pull requests. Recordings only ever
show the mocks' sample data on localhost (the harness refuses any other host). Never record
production or a customer workspace, and never attach media any other way than `pnpm share`: no
image hosts, no commits of screenshots, no other repositories. Everything the harness writes
stays under the ignored `.artifacts/`.
