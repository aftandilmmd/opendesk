import { describe, expect, it } from "vitest";
import { sameJSON } from "./sameJSON";

describe("sameJSON", () => {
  it("ignores the order of object keys, at any depth", () => {
    expect(sameJSON({ a: 1, b: { c: [{ x: 1, y: 2 }] } }, { b: { c: [{ y: 2, x: 1 }] }, a: 1 })).toBe(true);
  });
  it("still sees a changed value, a missing key and the order of a list", () => {
    expect(sameJSON({ a: 1 }, { a: 2 })).toBe(false);
    expect(sameJSON({ a: 1, b: 0 }, { a: 1 })).toBe(false);
    expect(sameJSON([1, 2], [2, 1])).toBe(false);
  });
});
