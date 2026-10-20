import { describe, expect, it } from "vitest";
import { clock, extensionFor, pickType } from "./voice";

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

  it("shows time as m:ss", () => {
    expect(clock(0)).toBe("0:00");
    expect(clock(7.9)).toBe("0:07");
    expect(clock(75)).toBe("1:15");
    expect(clock(300)).toBe("5:00");
    expect(clock(Infinity)).toBe("0:00");
  });
});
