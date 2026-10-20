import { describe, expect, it } from "vitest";
import { FILE_TYPES, FILE_TYPE_GROUPS, fileTypeExtensions } from "./fileTypes";

describe("widget file types", () => {
  it("lists each type once, in a known group", () => {
    const ids = FILE_TYPES.map((f) => f.id);
    expect(new Set(ids).size).toBe(ids.length);
    expect(FILE_TYPES.every((f) => FILE_TYPE_GROUPS.includes(f.group) && f.extensions.every((e) => /^\.[a-z0-9]+$/.test(e)))).toBe(true);
    expect(ids).not.toContain("svg");
  });

  it("gives the extensions of the picked types in catalog order", () => {
    expect(fileTypeExtensions(["pdf", "jpg", "nope"])).toEqual([".jpg", ".jpeg", ".pdf"]);
  });
});
