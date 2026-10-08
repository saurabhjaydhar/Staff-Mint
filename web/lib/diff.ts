// Flattened before/after diff for the audit log view.

export interface DiffEntry {
  path: string;
  before: unknown;
  after: unknown;
  kind: "added" | "removed" | "changed" | "same";
}

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** Flatten nested objects to dotted paths. Arrays are compared as whole values. */
export function flatten(value: unknown, prefix = "", out: Record<string, unknown> = {}): Record<string, unknown> {
  if (isPlainObject(value)) {
    const keys = Object.keys(value);
    if (keys.length === 0 && prefix) out[prefix] = {};
    for (const k of keys) flatten(value[k], prefix ? `${prefix}.${k}` : k, out);
  } else if (prefix) {
    out[prefix] = value;
  } else if (value !== undefined && value !== null) {
    out["(value)"] = value;
  }
  return out;
}

function same(a: unknown, b: unknown): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

export function diffObjects(before: unknown, after: unknown, includeSame = false): DiffEntry[] {
  const a = flatten(before);
  const b = flatten(after);
  const paths = [...new Set([...Object.keys(a), ...Object.keys(b)])].sort();
  const out: DiffEntry[] = [];
  for (const path of paths) {
    const inA = path in a;
    const inB = path in b;
    let kind: DiffEntry["kind"];
    if (inA && !inB) kind = "removed";
    else if (!inA && inB) kind = "added";
    else kind = same(a[path], b[path]) ? "same" : "changed";
    if (kind === "same" && !includeSame) continue;
    out.push({ path, before: a[path], after: b[path], kind });
  }
  return out;
}

export function showValue(v: unknown): string {
  if (v === undefined) return "";
  if (typeof v === "string") return v;
  return JSON.stringify(v);
}
