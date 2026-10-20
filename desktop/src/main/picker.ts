// The server picker: opendesk Cloud or your own server. Shown on first launch
// and from "Switch server". The picker page has no network access of its own;
// main checks the address (`<origin>/config.json`) and answers.

import { app, BrowserWindow, ipcMain } from "electron";
import { capturePicker } from "./devcapture";
import { join } from "node:path";
import { CLOUD_ORIGIN, isDev } from "./env";
import { normalizeAddress, resolveInstance } from "./origins";
import type { Instance } from "./store";
import { present } from "./window";

let picker: BrowserWindow | null = null;
let onChosen: ((i: Instance) => void) | null = null;
let onCancelled: (() => void) | null = null;
let current: Instance | undefined;

function fromPicker(e: Electron.IpcMainEvent | Electron.IpcMainInvokeEvent) {
  return !!picker && !picker.isDestroyed() && e.sender === picker.webContents && e.senderFrame === picker.webContents.mainFrame;
}

async function check(address: unknown) {
  const n = normalizeAddress(address);
  if ("error" in n) return { ok: false as const, error: n.error };
  const r = await resolveInstance(n.origin);
  if ("error" in r) return { ok: false as const, error: r.error, host: new URL(n.origin).host };
  return { ok: true as const, instance: r.instance, host: new URL(n.origin).host };
}

export function registerPickerIpc() {
  ipcMain.on("picker:info", (e) => {
    if (!fromPicker(e)) {
      e.returnValue = null;
      return;
    }
    e.returnValue = {
      platform: process.platform,
      cloudOrigin: CLOUD_ORIGIN,
      current: current?.appOrigin ?? null,
      canCancel: !!current,
    };
  });
  ipcMain.handle("picker:choose", async (e, address: unknown) => {
    if (!fromPicker(e)) return { ok: false, error: "invalid" };
    const r = await check(address);
    if (r.ok) {
      const cb = onChosen;
      onChosen = null;
      onCancelled = null;
      cb?.(r.instance);
      picker?.close();
    }
    return r;
  });
  ipcMain.on("picker:cancel", (e) => {
    if (!fromPicker(e)) return;
    picker?.close();
  });
}

export function showPicker(opts: { current?: Instance; parent?: BrowserWindow | null; onChosen: (i: Instance) => void; onCancelled?: () => void }) {
  current = opts.current;
  onChosen = opts.onChosen;
  onCancelled = opts.onCancelled ?? null;
  if (picker && !picker.isDestroyed()) {
    picker.focus();
    return;
  }
  const mac = process.platform === "darwin";
  picker = new BrowserWindow({
    width: 460,
    height: 600,
    resizable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    show: false,
    title: "opendesk",
    ...(mac
      ? { titleBarStyle: "hiddenInset" as const, vibrancy: "under-window" as const, visualEffectState: "followWindow" as const, backgroundColor: "#00000000" }
      : process.platform === "win32"
        ? { backgroundMaterial: "mica" as const, backgroundColor: "#00000000", autoHideMenuBar: true }
        : { autoHideMenuBar: true }),
    webPreferences: {
      preload: join(__dirname, "picker-preload.cjs"),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      webSecurity: true,
      spellcheck: false,
      webviewTag: false,
      navigateOnDragDrop: false,
    },
  });
  const wc = picker.webContents;
  wc.on("will-navigate", (e) => e.preventDefault());
  wc.setWindowOpenHandler(() => ({ action: "deny" }));
  picker.once("ready-to-show", () => picker && present(picker));
  picker.on("closed", () => {
    picker = null;
    const cb = onCancelled;
    onChosen = null;
    onCancelled = null;
    cb?.();
  });
  if (isDev) capturePicker(picker, () => app.quit());
  void picker.loadFile(join(__dirname, "picker", "index.html"));
}

export function pickerWindow() {
  return picker && !picker.isDestroyed() ? picker : null;
}
