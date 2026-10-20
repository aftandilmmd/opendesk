// OS notifications and the dock/taskbar badge.

import { app, type BrowserWindow, nativeImage, Notification } from "electron";
import { sandboxDir } from "./env";

// Shown notifications are kept referenced until clicked or closed, or Windows
// may collect them before the click arrives.
const live = new Map<string, Notification>();

export type NotifyInput = { id: string; title: string; body?: string; path?: string };

export function showNotification(n: NotifyInput, onClick: (path: string | undefined) => void) {
  if (sandboxDir) return console.log(`notification: ${n.title}${n.body ? `: ${n.body}` : ""}`);
  if (!Notification.isSupported()) return;
  live.get(n.id)?.close();
  // Silent: the app plays its own sounds, each on a switch the person controls.
  const note = new Notification({ title: n.title, body: n.body ?? "", silent: true });
  const forget = () => live.delete(n.id);
  note.on("click", () => {
    forget();
    onClick(n.path);
  });
  note.on("close", forget);
  note.on("failed", forget);
  live.set(n.id, note);
  while (live.size > 50) {
    const first = live.keys().next().value as string;
    live.get(first)?.close();
    live.delete(first);
  }
  note.show();
}

let overlay: Electron.NativeImage | null = null;

/** A small anti-aliased dot for the Windows taskbar overlay, drawn once. */
function overlayDot(): Electron.NativeImage {
  if (overlay) return overlay;
  const size = 32;
  const buf = Buffer.alloc(size * size * 4);
  const c = (size - 1) / 2;
  const r = size / 2 - 1.5;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const d = Math.hypot(x - c, y - c);
      const a = Math.max(0, Math.min(1, r - d + 0.5));
      const ring = Math.max(0, Math.min(1, r - 3 - d + 0.5));
      const i = (y * size + x) * 4;
      // BGRA: a white rim around the brand red, so it reads on any taskbar.
      const red = ring;
      buf[i] = Math.round(255 * (1 - red) + 0x31 * red);
      buf[i + 1] = Math.round(255 * (1 - red) + 0x31 * red);
      buf[i + 2] = Math.round(255 * (1 - red) + 0xe0 * red);
      buf[i + 3] = Math.round(255 * a);
    }
  }
  overlay = nativeImage.createFromBitmap(buf, { width: size, height: size, scaleFactor: 2 });
  return overlay;
}

let lastCount = -1;

export function setBadge(count: number, win: BrowserWindow | null) {
  if (sandboxDir || count === lastCount) return;
  lastCount = count;
  if (process.platform === "win32") {
    win?.setOverlayIcon(count > 0 ? overlayDot() : null, count > 0 ? `${count} unread` : "");
    return;
  }
  app.setBadgeCount(count);
}

export function clearNotifications() {
  for (const n of live.values()) n.close();
  live.clear();
}
