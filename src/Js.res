// ─── Js.res ───────────────────────────────────────────────────────────────────
// Minimal JS interop. %raw only where ReScript has no equivalent syntax.

// ── Zero-cost cast ──────────────────────────────────────────────────────────

external cast: 'a => 'b = "%identity"

// ── typeof — use Typeof module from ReScript ────────────────────────────────

let isNull: unknown => bool = %raw(`function(v) { return v === null; }`)
let isUndefined: unknown => bool = %raw(`function(v) { return v === undefined; }`)
let isObject: unknown => bool = %raw(`function(v) { return typeof v === 'object' && v !== null; }`)
let isFunction: unknown => bool = %raw(`function(v) { return typeof v === 'function'; }`)
let isPromise: unknown => bool = %raw(`function(v) { return v instanceof Promise; }`)

// These stay %raw — ReScript has no `typeof` or `instanceof` operator for unknown values.
// But they're tiny inlineable one-liners, V8 handles them fine.

@scope("Array") @val external isArray: unknown => bool = "isArray"

// ── Object operations — @val externals ──────────────────────────────────────

@val external objectKeys: unknown => array<string> = "Object.keys"
@val external jsonStringify: unknown => string = "JSON.stringify"

// Dynamic property access — genuinely needs runtime, no static equivalent
let getProp: (unknown, string) => unknown = %raw(`function(o, k) { return o[k]; }`)
let callFn: unknown => unknown = %raw(`function(fn) { return fn(); }`)

// ── Symbol prefix operations ────────────────────────────────────────────────
// Symbol-keyed properties can't be accessed via ReScript — needs runtime.

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

// ── Reflect — @scope/@val zero-cost bindings ────────────────────────────────

@scope("Reflect") @val external reflectGet3: (unknown, string, unknown) => unknown = "get"
@scope("Reflect") @val external reflectSet3: (unknown, string, unknown) => bool = "set"

let reflectGet = (target: unknown, prop: string): unknown => reflectGet3(target, prop, target)

let reflectSet = (target: unknown, prop: string, value: unknown): unit =>
  reflectSet3(target, prop, value)->ignore

// ── Promise — @send zero-cost bindings ──────────────────────────────────────

@send external _then: (unknown, unknown => unit) => unknown = "then"
@send external _catch: (unknown, unknown => unit) => unknown = "catch"

let promiseThen = (p: unknown, ok: unknown => unit): unit => p->_then(ok)->ignore

let promiseThenCatch = (p: unknown, ok: unknown => unit, err: unknown => unit): unit =>
  p->_then(ok)->_catch(err)->ignore

// ── Regex ───────────────────────────────────────────────────────────────────

let digitRe = /^\d+$/
let isDigitString = (s: string): bool => digitRe->RegExp.test(s)

let trailingDigitsRe = /\d+$/
let replaceTrailingDigits = (s: string, replacement: string): string =>
  s->String.replaceRegExp(trailingDigitsRe, replacement)

let parseInt: string => float = %raw(`function(s) { return +(s); }`)

// ── Clone — needs %raw (instanceof checks, Object.create, recursive) ───────

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

// ── Map iteration ───────────────────────────────────────────────────────────

@send external mapForEach: (Map.t<'k, 'v>, ('v, 'k) => unit) => unit = "forEach"
