import { describe, expect, it } from "vitest";
import { clock, extensionFor, level, pickType } from "./voice";

describe("voice messages", () => {
  it("asks for the first type the browser records, else leaves the choice to it", () => {
    expect(pickType(() => true)).toBe("audio/webm;codecs=opus");
    expect(pickType((x) => x === "audio/mp4")).toBe("audio/mp4");
    expect(pickType((x) => x.startsWith("audio/ogg"))).toBe("audio/ogg;codecs=opus");
    expect(pickType(() => false)).toBeUndefined();
  });

  it("names a recording by an extension the server takes", () => {
    expect(extensionFor("audio/webm;codecs=opus")).toBe(".webm");
    expect(extensionFor("audio/ogg; codecs=opus")).toBe(".ogg");
    expect(extensionFor("audio/mp4")).toBe(".m4a");
    expect(extensionFor("audio/x-unknown")).toBeNull();
  });

  it("measures how loud the microphone is, so quiet speech still moves the wave", () => {
    expect(level(new Uint8Array(0))).toBe(0);
    expect(level(new Uint8Array(256).fill(128))).toBe(0);
    // Full scale is clipped to 1.
    expect(level(Uint8Array.from({ length: 256 }, (_, i) => (i % 2 ? 0 : 255)))).toBe(1);
    // Speech around a tenth of full scale fills about half the bar.
    const speech = level(Uint8Array.from({ length: 256 }, (_, i) => 128 + Math.round(13 * Math.sin(i / 4))));
    expect(speech).toBeGreaterThan(0.35);
    expect(speech).toBeLessThan(0.65);
  });

  it("shows time as m:ss", () => {
    expect(clock(0)).toBe("0:00");
    expect(clock(7.9)).toBe("0:07");
    expect(clock(75)).toBe("1:15");
    expect(clock(300)).toBe("5:00");
    expect(clock(Infinity)).toBe("0:00");
  });
});
