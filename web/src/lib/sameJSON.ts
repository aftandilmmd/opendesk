// Whether two JSON values are equal whatever the order of their object keys. A record
// saved through the API and the same record arriving in a realtime event (stored as
// jsonb, which reorders keys) are the same value.

function canon(v: unknown): unknown {
  if (Array.isArray(v)) return v.map(canon);
  if (v && typeof v === "object") {
    const o = v as Record<string, unknown>;
    return Object.fromEntries(Object.keys(o).sort().map((k) => [k, canon(o[k])]));
  }
  return v;
}

export function sameJSON(a: unknown, b: unknown): boolean {
  return JSON.stringify(canon(a)) === JSON.stringify(canon(b));
}
