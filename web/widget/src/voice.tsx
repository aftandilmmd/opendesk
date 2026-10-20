/** @jsxImportSource preact */
// Voice messages: the visitor records up to the widget's longest voice message, listens
// back, then sends the recording as a file or deletes it. MediaRecorder records in the
// type the browser makes (WebM, Ogg or MP4 audio); the server checks its bytes like any
// upload.

import type { ComponentChildren } from "preact";
import { useEffect, useRef, useState } from "preact/hooks";
import { t } from "./i18n";
import { Pause, Play } from "./icons";

/** A finished recording, waiting to be sent. */
export type Recording = { file: File; url: string; seconds: number };

// In order of preference, each with the extension the server's file types know it by.
const TYPES: [string, string][] = [
  ["audio/webm;codecs=opus", ".webm"],
  ["audio/webm", ".webm"],
  ["audio/mp4", ".m4a"],
  ["audio/ogg;codecs=opus", ".ogg"],
  ["audio/ogg", ".ogg"],
];

/** Whether this browser can record here. */
export function canRecord(): boolean {
  return typeof MediaRecorder !== "undefined" && !!navigator.mediaDevices?.getUserMedia;
}

/** The type to ask the recorder for: the first the browser supports, else its own choice. */
export function pickType(supported: (type: string) => boolean): string | undefined {
  return TYPES.find(([type]) => supported(type))?.[0];
}

/** The file extension of a recorded type; null for a type the server would not take. */
export function extensionFor(type: string): string | null {
  const base = type.split(";")[0].trim().toLowerCase();
  return TYPES.find(([x]) => x.split(";")[0] === base)?.[1] ?? null;
}

/** Seconds as m:ss. */
export function clock(seconds: number): string {
  const s = Math.max(0, Math.floor(Number.isFinite(seconds) ? seconds : 0));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

/** Bars in the live wave while recording. */
export const WAVE_BARS = 32;

/** How loud a slice of 8-bit samples is, 0..1: its RMS, lifted so speech fills the bar. */
export function level(samples: Uint8Array): number {
  if (!samples.length) return 0;
  let sum = 0;
  for (const b of samples) sum += ((b - 128) / 128) ** 2;
  return Math.min(1, Math.sqrt(Math.sqrt(sum / samples.length)) * 1.6);
}

type Meter = { read: () => number; running: () => boolean; close: () => void };

/**
 * An audio context made while the click still counts as one (Safari refuses to start it
 * after the permission prompt); null without Web Audio.
 */
function audioContext(): AudioContext | null {
  const AC = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  try {
    return AC ? new AC() : null;
  } catch {
    return null;
  }
}

/** Reads the stream's loudness. The analyser feeds a muted output, as Safari processes only connected nodes. */
function meter(ctx: AudioContext, stream: MediaStream): Meter | null {
  try {
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 512;
    const mute = ctx.createGain();
    mute.gain.value = 0;
    ctx.createMediaStreamSource(stream).connect(analyser);
    analyser.connect(mute).connect(ctx.destination);
    void ctx.resume().catch(() => {});
    const buf = new Uint8Array(analyser.fftSize);
    return {
      read: () => {
        analyser.getByteTimeDomainData(buf);
        return level(buf);
      },
      running: () => ctx.state === "running",
      close: () => void ctx.close().catch(() => {}),
    };
  } catch {
    void ctx.close().catch(() => {});
    return null;
  }
}

const quiet = () => new Array<number>(WAVE_BARS).fill(0);

/**
 * Records from the microphone for at most max seconds. Stops on stop() or when the time
 * is up, and hands the recording to onDone. Leaving while recording drops it.
 */
export function useRecorder(max: number, onDone: (r: Recording) => void) {
  const [phase, setPhase] = useState<"idle" | "asking" | "recording">("idle");
  const [elapsed, setElapsed] = useState(0);
  const [error, setError] = useState("");
  // The live wave, newest on the right; null where the browser can't measure the sound.
  const [levels, setLevels] = useState<number[] | null>(null);
  const rec = useRef<MediaRecorder | null>(null);
  const sound = useRef<Meter | null>(null);
  const mounted = useRef(true);
  const done = useRef(onDone);
  done.current = onDone;

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      sound.current?.close();
      const r = rec.current;
      rec.current = null;
      if (r?.state === "recording") r.stop();
    };
  }, []);

  const stop = () => {
    if (rec.current?.state === "recording") rec.current.stop();
  };

  // Stops without keeping the recording.
  const cancel = () => {
    const r = rec.current;
    rec.current = null;
    if (r?.state === "recording") r.stop();
    setPhase("idle");
    setElapsed(0);
    setLevels(null);
  };

  const start = async () => {
    if (phase !== "idle") return;
    setError("");
    setPhase("asking");
    const ctx = audioContext();
    let stream: MediaStream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch (e) {
      void ctx?.close().catch(() => {});
      setPhase("idle");
      setError(t((e as DOMException)?.name === "NotAllowedError" ? "micBlocked" : "micFailed"));
      return;
    }
    const m = ctx ? meter(ctx, stream) : null;
    const release = () => {
      stream.getTracks().forEach((tr) => tr.stop());
      m?.close();
    };
    if (!mounted.current) return release();
    const type = pickType((x) => MediaRecorder.isTypeSupported(x));
    let r: MediaRecorder;
    try {
      r = new MediaRecorder(stream, type ? { mimeType: type } : undefined);
    } catch {
      release();
      setPhase("idle");
      setError(t("micFailed"));
      return;
    }
    const chunks: Blob[] = [];
    const began = Date.now();
    let timer = 0;
    r.ondataavailable = (e) => {
      if (e.data.size) chunks.push(e.data);
    };
    r.onstop = () => {
      clearInterval(timer);
      release();
      const kept = rec.current === r;
      rec.current = null;
      if (sound.current === m) sound.current = null;
      if (!kept) return;
      setPhase("idle");
      setElapsed(0);
      setLevels(null);
      const mime = r.mimeType || type || "";
      const ext = extensionFor(mime);
      const blob = new Blob(chunks, { type: mime.split(";")[0] });
      if (!ext || !blob.size) return setError(t("micFailed"));
      const seconds = Math.min(max, (Date.now() - began) / 1000);
      const file = new File([blob], t("voiceFileName") + ext, { type: blob.type });
      done.current({ file, url: URL.createObjectURL(blob), seconds });
    };
    rec.current = r;
    sound.current = m;
    r.start(250);
    setPhase("recording");
    setLevels(m ? quiet() : null);
    timer = window.setInterval(() => {
      const s = (Date.now() - began) / 1000;
      setElapsed(Math.min(s, max));
      // A context the browser keeps suspended hears nothing: after a second, the plain bar instead.
      if (m?.running()) setLevels((l) => [...(l ?? quiet()).slice(1), m.read()]);
      else if (m && s > 1) setLevels(null);
      if (s >= max && r.state === "recording") r.stop();
    }, 100);
  };

  return { phase, elapsed, error, levels, start, stop, cancel };
}

/** A play button, a progress track and the time, for a recording or a sent voice message; action sits at the end. */
export function VoicePlayer({ src, seconds, action }: { src: string; seconds?: number; action?: ComponentChildren }) {
  const audio = useRef<HTMLAudioElement>(null);
  const probing = useRef(false);
  const [playing, setPlaying] = useState(false);
  const [at, setAt] = useState(0);
  const [length, setLength] = useState(seconds ?? 0);

  // A recorded WebM has no duration until played through; seeking far past the end
  // makes the browser find it.
  const onMeta = () => {
    const a = audio.current;
    if (!a || seconds) return;
    if (Number.isFinite(a.duration)) return setLength(a.duration);
    probing.current = true;
    a.currentTime = 1e7;
  };

  const onTime = () => {
    const a = audio.current;
    if (!a) return;
    if (probing.current) {
      probing.current = false;
      if (Number.isFinite(a.duration)) setLength(a.duration);
      a.currentTime = 0;
      return;
    }
    setAt(a.currentTime);
  };

  const toggle = () => {
    const a = audio.current;
    if (!a) return;
    if (a.paused) void a.play().catch(() => setPlaying(false));
    else a.pause();
  };

  const seek = (e: MouseEvent) => {
    const a = audio.current;
    const box = (e.currentTarget as HTMLElement).getBoundingClientRect();
    if (!a || !length || !box.width) return;
    const ratio = Math.min(1, Math.max(0, (e.clientX - box.left) / box.width));
    const rtl = getComputedStyle(e.currentTarget as HTMLElement).direction === "rtl";
    a.currentTime = (rtl ? 1 - ratio : ratio) * length;
    setAt(a.currentTime);
  };

  const pct = length ? Math.min(100, (at / length) * 100) : 0;
  return (
    <div class={`voice${playing ? " playing" : ""}`}>
      <button type="button" class="voice-play" aria-label={t(playing ? "pauseVoice" : "playVoice")} onClick={toggle}>
        {playing ? Pause() : Play()}
      </button>
      <div class="voice-track" aria-hidden="true" onClick={seek}>
        <span style={{ width: `${pct}%` }} />
      </div>
      <span class="voice-time">{clock(playing || at > 0 ? at : length)}</span>
      {action}
      <audio
        ref={audio}
        src={src}
        preload="metadata"
        onLoadedMetadata={onMeta}
        onTimeUpdate={onTime}
        onPlay={() => setPlaying(true)}
        onPause={() => setPlaying(false)}
        onEnded={() => {
          setPlaying(false);
          setAt(0);
        }}
      />
    </div>
  );
}
