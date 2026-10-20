// The instance window: the instance's own web app in a frameless, translucent
// window (vibrancy on macOS, mica on Windows 11, opaque on Linux).

import { app, BrowserWindow, clipboard, Menu, nativeTheme, screen, shell, type WebContents } from "electron";
import { join } from "node:path";
import { devArg, isDev, sandboxDir } from "./env";
import { appPath, externalUrl } from "./origins";
import { type Bounds, type Instance, store, type ThemePref } from "./store";

/** Matches the web app's header (48px): the traffic lights sit centred in it. */
const HEADER = 48;
const TRAFFIC_LIGHTS = { x: 18, y: 17 };

const CHROME = { light: "#f5f5f5", dark: "#141416" } as const;

export type InstanceWindow = {
  win: BrowserWindow;
  instance: Instance;
  /** Send an app path to the page (deep links, notification clicks); queued until the page loads. */
  navigate(path: string): void;
};

function dark() {
  return nativeTheme.shouldUseDarkColors;
}

/** Window bounds that still land on a connected display. */
function restoreBounds(saved: Bounds | undefined): Bounds {
  const fallback = { width: 1320, height: 860 };
  if (!saved) return fallback;
  const b = { width: Math.max(saved.width, 900), height: Math.max(saved.height, 600) };
  if (saved.x === undefined || saved.y === undefined) return { ...b, maximized: saved.maximized };
  const visible = screen.getAllDisplays().some((d) => {
    const a = d.workArea;
    return saved.x! + 80 < a.x + a.width && saved.x! + b.width - 80 > a.x && saved.y! >= a.y - 10 && saved.y! + 40 < a.y + a.height;
  });
  return visible ? { ...b, x: saved.x, y: saved.y, maximized: saved.maximized } : { ...b, maximized: saved.maximized };
}

function chromeOptions(): Electron.BrowserWindowConstructorOptions {
  if (process.platform === "darwin") {
    return {
      titleBarStyle: "hiddenInset",
      trafficLightPosition: TRAFFIC_LIGHTS,
      vibrancy: "sidebar",
      visualEffectState: "followWindow",
      backgroundColor: "#00000000",
    };
  }
  if (process.platform === "win32") {
    return {
      titleBarStyle: "hidden",
      titleBarOverlay: { color: "#00000000", symbolColor: dark() ? "#f7f7f7" : "#0a0a0a", height: HEADER },
      backgroundMaterial: "mica",
      backgroundColor: "#00000000",
    };
  }
  return { backgroundColor: dark() ? CHROME.dark : CHROME.light, autoHideMenuBar: true };
}

/** Keeps the native chrome (vibrancy appearance, Windows caption buttons) on the page's theme. */
export function applyTheme(pref: ThemePref, win: BrowserWindow | null) {
  nativeTheme.themeSource = pref;
  store.setTheme(pref);
  if (!win || win.isDestroyed()) return;
  if (process.platform === "win32") {
    win.setTitleBarOverlay({ color: "#00000000", symbolColor: dark() ? "#f7f7f7" : "#0a0a0a", height: HEADER });
  } else if (process.platform === "linux") {
    win.setBackgroundColor(dark() ? CHROME.dark : CHROME.light);
  }
}

/** Opens a link outside the app in the default browser: https only (mailto for addresses). */
export function openOutside(url: string) {
  if (url.startsWith("mailto:") && url.length < 2048) {
    void shell.openExternal(url);
    return;
  }
  const safe = externalUrl(url);
  if (safe) void shell.openExternal(safe);
}

function isAllowed(url: string, instance: Instance) {
  try {
    const o = new URL(url).origin;
    return o === instance.appOrigin || o === instance.apiOrigin;
  } catch {
    return false;
  }
}

function contextMenu(wc: WebContents, p: Electron.ContextMenuParams) {
  const items: Electron.MenuItemConstructorOptions[] = [];
  if (p.misspelledWord) {
    for (const s of p.dictionarySuggestions.slice(0, 4)) items.push({ label: s, click: () => wc.replaceMisspelling(s) });
    if (p.dictionarySuggestions.length) items.push({ type: "separator" });
  }
  if (p.linkURL && /^(https?|mailto):/i.test(p.linkURL)) {
    items.push({ label: "Open link in browser", click: () => openOutside(p.linkURL) });
    items.push({ label: "Copy link", click: () => clipboard.writeText(p.linkURL) });
    items.push({ type: "separator" });
  }
  if (p.isEditable) {
    items.push({ role: "undo", enabled: p.editFlags.canUndo }, { role: "redo", enabled: p.editFlags.canRedo }, { type: "separator" });
    items.push({ role: "cut", enabled: p.editFlags.canCut }, { role: "copy", enabled: p.editFlags.canCopy }, { role: "paste", enabled: p.editFlags.canPaste });
    items.push({ role: "selectAll" });
  } else if (p.selectionText) {
    items.push({ role: "copy" });
  }
  if (isDev) items.push({ type: "separator" }, { label: "Inspect", click: () => wc.inspectElement(p.x, p.y) });
  while (items.length && items[items.length - 1].type === "separator") items.pop();
  if (items.length) Menu.buildFromTemplate(items).popup();
}

export function createInstanceWindow(instance: Instance, opts: { onClosed: () => void }): InstanceWindow {
  const saved = restoreBounds(store.bounds(instance.appOrigin));
  const win = new BrowserWindow({
    ...saved,
    minWidth: 900,
    minHeight: 600,
    show: false,
    title: "opendesk",
    ...chromeOptions(),
    webPreferences: {
      preload: join(__dirname, "preload.cjs"),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      nodeIntegrationInSubFrames: false,
      webSecurity: true,
      allowRunningInsecureContent: false,
      webviewTag: false,
      navigateOnDragDrop: false,
      spellcheck: true,
      safeDialogs: true,
      // An invisible sandbox window still paints every frame for the recorder.
      backgroundThrottling: !sandboxDir,
    },
  });
  if (saved.maximized) win.maximize();

  const wc = win.webContents;
  let loaded = false;
  let queued: string | null = null;
  let retry: NodeJS.Timeout | null = null;

  const navigate = (path: string) => {
    const p = appPath(path, instance.appOrigin);
    if (!p) return;
    if (loaded && wc.getURL().startsWith(instance.appOrigin)) wc.send("od:navigate", p);
    else queued = p;
  };

  // In-window navigation stays on the instance's app and API origins; every
  // other link opens in the default browser.
  wc.on("will-navigate", (e, url) => {
    if (isAllowed(url, instance)) return;
    e.preventDefault();
    openOutside(url);
  });
  wc.on("will-redirect", (e) => {
    if (!e.isMainFrame || isAllowed(e.url, instance)) return;
    e.preventDefault();
    openOutside(e.url);
  });
  wc.setWindowOpenHandler(({ url }) => {
    openOutside(url);
    return { action: "deny" };
  });
  wc.on("context-menu", (_e, p) => contextMenu(wc, p));

  // Full screen hides the macOS traffic lights; the page fills their space.
  const sendFullScreen = () => {
    if (loaded && !win.isDestroyed()) wc.send("od:fullscreen", win.isFullScreen());
  };
  win.on("enter-full-screen", sendFullScreen);
  win.on("leave-full-screen", sendFullScreen);

  wc.on("did-finish-load", () => {
    if (!wc.getURL().startsWith(instance.appOrigin)) return;
    loaded = true;
    sendFullScreen();
    if (queued) {
      wc.send("od:navigate", queued);
      queued = null;
    }
  });
  // Offline or the server is down: a quiet local page, and a retry until it is back.
  wc.on("did-fail-load", (_e, code, _desc, url, isMainFrame) => {
    if (!isMainFrame || code === -3 || !url.startsWith(instance.appOrigin)) return;
    loaded = false;
    void win.loadFile(join(__dirname, "picker", "offline.html"), { query: { host: new URL(instance.appOrigin).host } });
    if (retry) clearTimeout(retry);
    retry = setTimeout(() => !win.isDestroyed() && void win.loadURL(`${instance.appOrigin}/`), 8000);
  });

  win.once("ready-to-show", () => present(win));

  let saveTimer: NodeJS.Timeout | null = null;
  const saveBounds = () => {
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      if (win.isDestroyed() || win.isMinimized() || win.isFullScreen()) return;
      const maximized = win.isMaximized();
      const b = maximized ? store.bounds(instance.appOrigin) ?? win.getNormalBounds() : win.getBounds();
      store.setBounds(instance.appOrigin, { x: b.x, y: b.y, width: b.width, height: b.height, maximized });
    }, 400);
  };
  win.on("resize", saveBounds);
  win.on("move", saveBounds);
  win.on("maximize", saveBounds);
  win.on("unmaximize", saveBounds);
  win.on("closed", () => {
    if (retry) clearTimeout(retry);
    opts.onClosed();
  });

  // Development: a theme to start in, for screenshots of both.
  const theme = devArg("theme");
  if (theme === "light" || theme === "dark") {
    wc.once("did-finish-load", () => {
      void wc.executeJavaScript(`localStorage.setItem("od-theme", ${JSON.stringify(theme)}); location.reload();`);
    });
  }

  void win.loadURL(`${instance.appOrigin}/`);
  return { win, instance, navigate };
}

/** Shows a new window; in a sandbox run, without the person at the machine seeing or reaching it. */
export function present(win: BrowserWindow) {
  if (!sandboxDir) return win.show();
  win.setOpacity(0);
  win.setIgnoreMouseEvents(true);
  win.showInactive();
}

/** Focuses a window, restoring it first. */
export function reveal(win: BrowserWindow | null | undefined) {
  if (!win || win.isDestroyed()) return;
  if (sandboxDir) return present(win);
  if (win.isMinimized()) win.restore();
  if (!win.isVisible()) win.show();
  win.focus();
  if (process.platform === "darwin") app.focus({ steal: true });
}
