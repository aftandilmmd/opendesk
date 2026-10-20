/** @jsxImportSource preact */
// A live, interactive preview of the real widget for the dashboard's widget
// settings. It renders the same UI into a shadow root inside `host`, contained
// by it (a transformed wrapper is the containing block of the widget's fixed
// launcher and panel), talks to the in-memory mock backend, and follows config
// changes without remounting.
//
//   const p = mountPreview(el, { config, scene: "chat", dark });
//   p.update({ config: next });   // live, no flash
//   p.destroy();
//
// With `autoplay` (the marketing site) it plays a visitor's whole visit on a
// loop through the real UI: open, pick a suggestion, type the order, confirm
// the bot's action, close. It waits while the host is off screen, and the moment
// someone touches it the widget is theirs; left closed and idle, it plays again.

import { render } from "preact";
import { applyHostVars } from "./config";
import { Controller } from "./controller";
import { createMock } from "./mock";
import { Store } from "./store";
import { css } from "./styles";
import type { WidgetConfig } from "./types";
import { App } from "./ui";

export type PreviewScene = "launcher" | "home" | "chat" | "new";
export type PreviewOptions = { config: WidgetConfig; scene: PreviewScene; dark?: boolean; autoplay?: boolean };
export type PreviewHandle = { update(opts: Partial<PreviewOptions>): void; destroy(): void };
export type { WidgetConfig };

export function mountPreview(host: HTMLElement, opts: PreviewOptions): PreviewHandle {
  let cur: PreviewOptions = { ...opts };
  let alive = true;

  const wrap = document.createElement("div");
  wrap.setAttribute("data-opendesk-preview", "");
  // transform + contain make this box the containing block for position: fixed inside it.
  wrap.style.cssText = "position:absolute;inset:0;overflow:hidden;transform:translateZ(0);contain:layout paint;border-radius:inherit;";
  if (getComputedStyle(host).position === "static") host.style.position = "relative";
  host.appendChild(wrap);
  const shadow = wrap.attachShadow({ mode: "open" });
  const style = document.createElement("style");
  style.textContent = css;
  shadow.appendChild(style);
  const mount = document.createElement("div");
  shadow.appendChild(mount);

  // Replies name no bot, so they show the config's: the bot being edited, live.
  const mock = createMock({ seed: opts.autoplay ? "empty" : "preview", latency: 60, bot: null });
  const store = new Store({ preview: true, dark: opts.dark ?? null });
  const c = new Controller({ base: "https://preview.invalid", key: "wk_preview", fetcher: mock.fetch, socketFactory: mock.socket, persist: false, store });

  const applyConfig = (config: WidgetConfig) => {
    c.setConfig(config);
    const resolved = store.get().config;
    if (resolved) applyHostVars(wrap, resolved);
  };

  let ready = false;
  const applyScene = (scene: PreviewScene) => {
    if (scene === "launcher") {
      store.set({ open: false });
      return;
    }
    if (scene === "home") {
      store.set({ open: true, view: "home", active: null });
      return;
    }
    if (scene === "new") {
      store.set({ open: true });
      c.newConversation();
      return;
    }
    store.set({ open: true, view: "thread", active: mock.showcaseId });
    if (!ready) return; // boot opens it once the session is up
    void c.openConversation(mock.showcaseId).then(() => alive && mock.playShowcase());
  };

  const auto = opts.autoplay ? director(host, wrap, shadow, c, store, () => alive) : null;

  applyConfig(cur.config);
  if (!auto) applyScene(cur.scene);
  render(<App c={c} />, mount);
  void c.boot(cur.config).then(() => {
    if (!alive) return;
    ready = true;
    applyConfig(cur.config); // a config update may have landed while booting
    if (auto) auto.start();
    else applyScene(cur.scene);
  });

  return {
    update(next) {
      if (!alive) return;
      const prev = cur;
      cur = { ...cur, ...Object.fromEntries(Object.entries(next).filter(([, v]) => v !== undefined)) };
      if (next.config && next.config !== prev.config) applyConfig(next.config);
      if ("dark" in next) store.set({ dark: next.dark ?? null });
      if (next.scene && next.scene !== prev.scene) applyScene(next.scene);
    },
    destroy() {
      if (!alive) return;
      alive = false;
      auto?.stop();
      render(null, mount);
      c.stop();
      mock.dispose();
      wrap.remove();
    },
  };
}

// ── Autoplay ─────────────────────────────────────────────────────────────────

const VISIT = {
  pick: "Change my delivery address",
  order: "It's order #4821, please send it to 22 Baker Street, London.",
};

function director(host: HTMLElement, wrap: HTMLElement, root: ShadowRoot, c: Controller, store: Store, alive: () => boolean) {
  let run = 0; // bumped to cancel the running visit
  let visible = false;
  let taken = false; // someone is using it
  let idle: ReturnType<typeof setTimeout> | undefined;
  const wakers = new Set<() => void>();

  const io = new IntersectionObserver(([e]) => {
    visible = e.isIntersecting;
    if (visible) wakers.forEach((f) => f());
  });
  io.observe(host);

  class Cancelled extends Error {}
  class Stuck extends Error {}
  const check = (id: number) => {
    if (id !== run || !alive()) throw new Cancelled();
  };
  /** Wait `ms` of on-screen time. */
  const wait = async (id: number, ms: number) => {
    check(id);
    if (!visible) await new Promise<void>((r) => wakers.add(function w() { wakers.delete(w); r(); }));
    await new Promise((r) => setTimeout(r, ms));
    check(id);
  };
  /** Wait until `ok` holds, checking on every state change. */
  const until = (id: number, ok: () => boolean, ms = 15000) =>
    new Promise<void>((resolve, reject) => {
      const done = () => {
        if (id !== run || !alive()) return finish(new Cancelled());
        if (ok()) finish();
      };
      const finish = (err?: Error) => {
        off();
        clearInterval(poll);
        clearTimeout(limit);
        if (err) reject(err);
        else resolve();
      };
      const off = store.subscribe(done);
      const poll = setInterval(done, 120);
      const limit = setTimeout(() => finish(new Stuck()), ms);
      done();
    });
  const q = <T extends Element>(sel: string) => root.querySelector<T>(sel);
  const quiet = () => {
    const s = store.get();
    return Object.keys(s.live.replies).length === 0 && Object.keys(s.awaiting).length === 0;
  };

  async function visit(id: number) {
    await wait(id, 900);
    c.open();
    await until(id, () => !!q<HTMLButtonElement>(".sugg:not(:disabled)"));
    await wait(id, 1700);
    const pick = [...root.querySelectorAll<HTMLButtonElement>(".sugg")].find((b) => b.textContent?.trim() === VISIT.pick);
    pick?.click();
    // A widget with topics asks one first: take the first.
    await wait(id, 400);
    const topic = q<HTMLButtonElement>(".picker .topic:not(:disabled)");
    if (topic) {
      await wait(id, 900);
      topic.click();
      await wait(id, 400);
    }
    await until(id, quiet);
    await wait(id, 900);

    const ta = q<HTMLTextAreaElement>("textarea.input:not(.mirror)");
    if (!ta) throw new Cancelled();
    for (let i = 1; i <= VISIT.order.length; i++) {
      ta.value = VISIT.order.slice(0, i);
      ta.dispatchEvent(new Event("input", { bubbles: true }));
      await wait(id, 26 + ((i * 17) % 40));
    }
    await wait(id, 350);
    // Sent the way the send button does, without moving the page's focus.
    ta.value = "";
    ta.dispatchEvent(new Event("input", { bubbles: true }));
    void c.send(VISIT.order, []);

    await until(id, () => !!q<HTMLButtonElement>(".btn.solid:not(:disabled)"), 20000);
    await wait(id, 2200);
    q<HTMLButtonElement>(".btn.solid:not(:disabled)")?.click();
    await wait(id, 400);
    await until(id, quiet);
    await wait(id, 4200);
    c.close();
    await wait(id, 600);
    c.home();
    await wait(id, 2200);
  }

  async function loop() {
    const id = ++run;
    for (;;) {
      try {
        await visit(id);
      } catch (e) {
        if (e instanceof Cancelled) return;
        if (!(e instanceof Stuck)) throw e;
        // Something didn't arrive: start the visit over from a closed widget.
        c.close();
        c.home();
      }
    }
  }

  // A visitor's own pointer or key takes the widget over until it sits closed for a while.
  const take = (e: Event) => {
    if (!e.isTrusted || e.composedPath()[0] === wrap) return;
    if (!taken) {
      taken = true;
      run++;
    }
    rest();
  };
  const rest = () => {
    clearTimeout(idle);
    idle = setTimeout(function again() {
      if (!alive()) return;
      if (store.get().open) {
        idle = setTimeout(again, 8000);
        return;
      }
      taken = false;
      c.home();
      void loop();
    }, 9000);
  };
  wrap.addEventListener("pointerdown", take, true);
  wrap.addEventListener("keydown", take, true);

  return {
    start() {
      if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) {
        c.open();
        return;
      }
      void loop();
    },
    stop() {
      run++;
      clearTimeout(idle);
      io.disconnect();
      wakers.clear();
    },
  };
}
