// opendesk desktop: an Electron shell around the instance's own web app
// (contracts/native.md, "Desktop shell").

import { app, BrowserWindow, ipcMain, session } from "electron";
import { join, resolve } from "node:path";
import { APP_ID, devArg, devInstanceUrl, isDev, PROTOCOL, sandboxDir } from "./env";
import { buildMenu } from "./menu";
import { cancelOAuth, finishOAuth, startOAuth } from "./oauth";
import { appPath, externalUrl, normalizeAddress, resolveInstance } from "./origins";
import { pickerWindow, registerPickerIpc, showPicker } from "./picker";
import { clearNotifications, setBadge, showNotification } from "./notify";
import { type Instance, store } from "./store";
import { setupDevCapture } from "./devcapture";
import { checkInBackground, checkNow, restartToUpdate, setUpdateChannel, startUpdater, updateChannel, type UpdateState, updateState } from "./updater";
import { applyTheme, createInstanceWindow, type InstanceWindow, openOutside, reveal } from "./window";

app.setName("opendesk");
if (process.platform === "win32") app.setAppUserModelId(APP_ID);
if (isDev) app.setPath("userData", sandboxDir ?? join(app.getPath("appData"), "opendesk-dev"));
if (sandboxDir) app.dock?.hide();

// One running copy: a second launch (or an opendesk:// link on Windows and
// Linux) hands its arguments to this one.
if (!app.requestSingleInstanceLock()) {
  app.quit();
  process.exit(0);
}

if (sandboxDir) {
  // A recording never takes opendesk:// links from the copy people use.
} else if (isDev && process.platform !== "darwin") {
  app.setAsDefaultProtocolClient(PROTOCOL, process.execPath, [resolve(process.argv[1] ?? ".")]);
} else {
  app.setAsDefaultProtocolClient(PROTOCOL);
}

let current: InstanceWindow | null = null;
let pendingLinks: string[] = [];
let quitting = false;

// ─── Deep links ──────────────────────────────────────────────────────────────

function handleLink(raw: string) {
  if (typeof raw !== "string" || raw.length > 4096 || !raw.toLowerCase().startsWith(`${PROTOCOL}://`)) return;
  if (!app.isReady()) {
    pendingLinks.push(raw);
    return;
  }
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    return;
  }
  // opendesk://auth/callback?code=…  and  opendesk://open?path=/tickets/…
  const target = `${u.hostname}${u.pathname}`.replace(/\/+$/, "");
  if (target === "auth/callback") {
    finishOAuth(u);
    reveal(current?.win);
    return;
  }
  if (target === "open" && current) {
    const p = appPath(u.searchParams.get("path"), current.instance.appOrigin);
    if (p) current.navigate(p);
    reveal(current.win);
    return;
  }
  reveal(current?.win ?? pickerWindow());
}

app.on("open-url", (e, url) => {
  e.preventDefault();
  handleLink(url);
});

app.on("second-instance", (_e, argv) => {
  const link = argv.find((a) => a.toLowerCase().startsWith(`${PROTOCOL}://`));
  if (link) handleLink(link);
  else reveal(current?.win ?? pickerWindow());
});

// ─── IPC from the instance page ──────────────────────────────────────────────

/** IPC is answered only for the instance window's top frame, on the instance's app origin. */
function fromInstance(e: Electron.IpcMainEvent | Electron.IpcMainInvokeEvent): InstanceWindow | null {
  const c = current;
  if (!c || c.win.isDestroyed() || e.sender !== c.win.webContents) return null;
  const frame = e.senderFrame;
  if (!frame || frame !== e.sender.mainFrame) return null;
  try {
    return new URL(frame.url).origin === c.instance.appOrigin ? c : null;
  } catch {
    return null;
  }
}

const str = (v: unknown, max: number) => (typeof v === "string" && v.length > 0 && v.length <= max ? v : undefined);

function registerIpc() {
  ipcMain.on("od:info", (e) => {
    e.returnValue = { version: app.getVersion(), platform: process.platform };
  });

  ipcMain.on("od:notify", (e, n: unknown) => {
    const c = fromInstance(e);
    if (!c || !n || typeof n !== "object") return;
    const o = n as Record<string, unknown>;
    const id = str(o.id, 200);
    const title = str(o.title, 300);
    if (!id || !title) return;
    const body = typeof o.body === "string" ? o.body.slice(0, 1000) : undefined;
    const path = o.path === undefined ? undefined : appPath(o.path, c.instance.appOrigin) ?? undefined;
    showNotification({ id, title, body, path }, (p) => {
      reveal(c.win);
      if (p && current === c) c.navigate(p);
    });
  });

  ipcMain.on("od:badge", (e, count: unknown) => {
    const c = fromInstance(e);
    if (!c || typeof count !== "number" || !Number.isInteger(count) || count < 0) return;
    setBadge(Math.min(count, 99_999), c.win);
  });

  ipcMain.handle("od:oauth", async (e, startUrl: unknown) => {
    const c = fromInstance(e);
    if (!c) return { error: "invalid_request" };
    const r = await startOAuth(startUrl, c.instance.apiOrigin);
    if (!("error" in r) || r.error !== "cancelled") reveal(c.win);
    return r;
  });

  ipcMain.on("od:open-external", (e, url: unknown) => {
    if (!fromInstance(e)) return;
    const safe = externalUrl(url);
    if (safe) openOutside(safe);
  });

  ipcMain.on("od:switch-server", (e) => {
    if (fromInstance(e)) switchServer();
  });

  // Updates: the state and channel are read synchronously by the preload; the
  // page can ask for a check, a restart into a downloaded update, or a channel.
  ipcMain.on("od:update-info", (e) => {
    e.returnValue = fromInstance(e) ? { state: updateState(), channel: updateChannel() } : { state: { status: "idle" }, channel: "stable" };
  });

  ipcMain.on("od:update-check", (e) => {
    if (fromInstance(e)) checkInBackground();
  });

  ipcMain.on("od:update-restart", (e) => {
    if (fromInstance(e)) restartToUpdate();
  });

  ipcMain.on("od:update-channel", (e, channel: unknown) => {
    if (!fromInstance(e) || (channel !== "stable" && channel !== "beta")) return;
    setUpdateChannel(channel);
  });

  ipcMain.on("od:theme", (e, pref: unknown) => {
    const c = fromInstance(e);
    if (!c || (pref !== "light" && pref !== "dark" && pref !== "system")) return;
    applyTheme(pref, c.win);
  });

  registerPickerIpc();
}

// ─── Session hardening ───────────────────────────────────────────────────────

function hardenSession() {
  const ses = session.defaultSession;
  ses.setUserAgent(`${ses.getUserAgent()} opendesk-desktop/${app.getVersion()}`);

  // Notifications and the clipboard, for the instance only. Nothing else.
  const allowed = new Set(["notifications", "clipboard-read", "clipboard-sanitized-write"]);
  const onInstance = (wc: Electron.WebContents | null, origin?: string) => {
    if (!current || !wc || wc !== current.win.webContents) return false;
    try {
      return new URL(origin || wc.getURL()).origin === current.instance.appOrigin;
    } catch {
      return false;
    }
  };
  ses.setPermissionRequestHandler((wc, permission, cb, details) => {
    cb(allowed.has(permission) && details.isMainFrame !== false && onInstance(wc, details.requestingUrl));
  });
  ses.setPermissionCheckHandler((wc, permission, origin) => allowed.has(permission) && onInstance(wc, origin));
  ses.setDevicePermissionHandler(() => false);
}

app.on("web-contents-created", (_e, wc) => {
  wc.on("will-attach-webview", (e) => e.preventDefault());
});

// ─── Instance window ─────────────────────────────────────────────────────────

function rebuildMenu() {
  buildMenu({
    switchServer,
    checkForUpdates: () => void checkNow(current?.win ?? null),
    restartToUpdate,
    updateState,
    updateChannel,
    setUpdateChannel,
    reload: () => {
      const c = current;
      if (!c || c.win.isDestroyed()) return void BrowserWindow.getFocusedWindow()?.webContents.reload();
      if (c.win.webContents.getURL().startsWith(c.instance.appOrigin)) c.win.webContents.reload();
      else void c.win.loadURL(`${c.instance.appOrigin}/`);
    },
  });
}

/** Update state and channel go to the page (its update banner) and the menu. */
function onUpdateState(state: UpdateState, statusChanged: boolean) {
  const c = current;
  if (c && !c.win.isDestroyed()) c.win.webContents.send("od:update", { state, channel: updateChannel() });
  // Progress ticks only change the page; the menu follows the status.
  if (statusChanged || state.status !== "downloading") rebuildMenu();
}

function open(instance: Instance) {
  if (current && !current.win.isDestroyed()) {
    if (current.instance.appOrigin === instance.appOrigin) {
      reveal(current.win);
      return;
    }
    const old = current;
    current = null;
    cancelOAuth();
    clearNotifications();
    setBadge(0, old.win);
    old.win.destroy();
  }
  const opened: InstanceWindow = createInstanceWindow(instance, {
    onClosed: () => {
      if (current === opened) current = null;
    },
  });
  current = opened;
  if (isDev) {
    // The CGWindowID on macOS, for `screencapture -l<id>` while developing.
    opened.win.once("ready-to-show", () => console.log(`window id: ${opened.win.getMediaSourceId()}`));
    setupDevCapture(opened, () => app.quit());
  }
}

function switchServer() {
  showPicker({
    current: current?.instance,
    onChosen: (i) => {
      store.setInstance(i);
      open(i);
    },
  });
}

async function start() {
  const dev = devInstanceUrl();
  if (dev) {
    const n = normalizeAddress(dev);
    if ("error" in n) {
      console.error(`OPENDESK_DESKTOP_URL: ${n.error}`);
    } else {
      // A Vite dev server answers any path with the app, so a missing config.json is fine here.
      const r = await resolveInstance(n.origin, { lenient: true });
      if ("instance" in r) return open(r.instance);
      console.error(`OPENDESK_DESKTOP_URL: ${r.error}`);
    }
  }
  const saved = store.instance();
  if (saved && devArg("picker") !== "1") return open(saved);
  showPicker({
    onChosen: (i) => {
      store.setInstance(i);
      open(i);
    },
    onCancelled: () => {
      if (!current && process.platform !== "darwin") app.quit();
    },
  });
}

app.whenReady().then(async () => {
  applyTheme(store.theme(), null);
  hardenSession();
  registerIpc();
  rebuildMenu();
  startUpdater(onUpdateState);
  await start();
  const links = pendingLinks;
  pendingLinks = [];
  links.forEach(handleLink);
  // Windows and Linux pass the link that launched the app on the command line.
  const argLink = process.argv.find((a) => a.toLowerCase().startsWith(`${PROTOCOL}://`));
  if (argLink) handleLink(argLink);
});

app.on("activate", () => {
  if (current && !current.win.isDestroyed()) return reveal(current.win);
  if (pickerWindow()) return reveal(pickerWindow());
  const saved = store.instance();
  if (saved) open(saved);
  else void start();
});

app.on("before-quit", () => {
  quitting = true;
  cancelOAuth();
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin" || quitting) app.quit();
});
