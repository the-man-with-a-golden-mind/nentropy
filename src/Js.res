// ─── Js.res ───────────────────────────────────────────────────────────────────
// Minimal JS interop — only things that genuinely need FFI.
// No {..}, no jsObj — uses `unknown` for dynamic values, proper types elsewhere.

// ── Zero-cost casts ─────────────────────────────────────────────────────────

external cast: 'a => 'b = "%identity"

// ── typeof / instanceof ─────────────────────────────────────────────────────

let typeof_: unknown => string = %raw(`function(v) { return typeof v; }`)
let isNull: unknown => bool = %raw(`function(v) { return v === null; }`)
let isObject: unknown => bool = %raw(`function(v) { return typeof v === 'object' && v !== null; }`)
let isFunction: unknown => bool = %raw(`function(v) { return typeof v === 'function'; }`)
let isUndefined: unknown => bool = %raw(`function(v) { return v === undefined; }`)

@scope("Array") @val external isArray: unknown => bool = "isArray"
let isPromise: unknown => bool = %raw(`function(v) { return v instanceof Promise; }`)

// ── Object operations ───────────────────────────────────────────────────────

@val external objectKeys: unknown => array<string> = "Object.keys"
@val external jsonStringify: unknown => string = "JSON.stringify"

let getProp: (unknown, string) => unknown = %raw(`function(o, k) { return o[k]; }`)

let callFn: unknown => unknown = %raw(`function(fn) { return fn(); }`)

// ── Symbol (one global instance) ────────────────────────────────────────────

let enPrefixSym: Symbol.t = %raw(`Symbol.for("@en/prefix")`)

let hasPrefix: unknown => bool = %raw(`
  function(v) { return typeof v === 'object' && v !== null && Symbol.for("@en/prefix") in v; }
`)

let getPrefix: unknown => string = %raw(`
  function(obj) { return obj[Symbol.for("@en/prefix")] || ""; }
`)

let setPrefix: (unknown, string) => unit = %raw(`
  function(obj, val) {
    Object.defineProperty(obj, Symbol.for("@en/prefix"), {
      value: val, enumerable: false, writable: true, configurable: true
    });
  }
`)

// ── Reflect ─────────────────────────────────────────────────────────────────

let reflectGet: (unknown, string) => unknown = %raw(`
  function(t, p) { return Reflect.get(t, p, t); }
`)

let reflectSet: (unknown, string, unknown) => unit = %raw(`
  function(t, p, v) { Reflect.set(t, p, v); }
`)

// ── Promise ─────────────────────────────────────────────────────────────────

let promiseThen: (unknown, unknown => unit) => unit = %raw(`
  function(p, fn) { p.then(fn); }
`)

let promiseThenCatch: (unknown, unknown => unit, unknown => unit) => unit = %raw(`
  function(p, ok, err) { p.then(ok).catch(err); }
`)

// ── Regex ───────────────────────────────────────────────────────────────────

let digitRe = /^\d+$/
let isDigitString = (s: string): bool => digitRe->RegExp.test(s)

// ── Clone ───────────────────────────────────────────────────────────────────

let clone: 'a => 'a = %raw(`
  function clone(t) {
    if (t === null || typeof t !== 'object') return t;
    if (Array.isArray(t)) return t.map(clone);
    if (t instanceof Date) return new Date(t.getTime());
    if (t instanceof RegExp) return new RegExp(t.source, t.flags);
    if (t instanceof Map) return new Map([...t].map(kv => [clone(kv[0]), clone(kv[1])]));
    if (t instanceof Set) return new Set([...t].map(clone));
    var r = Object.create(Object.getPrototypeOf(t));
    for (var k of Object.keys(t)) r[k] = clone(t[k]);
    return r;
  }
`)

// ── Map with key iteration ──────────────────────────────────────────────────

@send external mapForEach: (Map.t<'k, 'v>, ('v, 'k) => unit) => unit = "forEach"
