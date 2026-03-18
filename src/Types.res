// ─── Types.res ────────────────────────────────────────────────────────────────
// Core types — proper ReScript types, no {..} soup.
//
// The reactive system handles arbitrary JS values via `unknown`.
// DOM elements use `EnDom.element`.
// No more jsObj — every field has a real type.

// ── Conditional directive type ──────────────────────────────────────────────

type conditionalType = If | IfNot

// ── Directive parameters ────────────────────────────────────────────────────

type directiveParams = {
  el: EnDom.element,
  value: unknown,
  key: string,
  isDelete: bool,
  parent: unknown, // the reactive parent (Proxy object)
  prop: string,
  param: option<string>,
}

type directive = directiveParams => unit

type directiveEntry = {
  cb: directive,
  isParametric: bool,
}

// ── Watcher ─────────────────────────────────────────────────────────────────

type watcher = unknown => unit

// ── Computed dependency graph edge ──────────────────────────────────────────

type computedDep = {
  key: string,
  computed: unknown, // the computed function
  parent: unknown, // parent reactive object
  prop: string,
}

// ── Dependency tracking state ───────────────────────────────────────────────

type depsState = {
  mutable isEvaluating: bool,
  currentSet: Set.t<string>,
  depMap: Map.t<string, array<computedDep>>,
  versions: Map.t<string, int>,
}

// ── Sync config (for conditional/clone sync) ────────────────────────────────

type syncConfig = {
  directive: string,
  el: EnDom.element,
  skipConditionals: bool,
  skipMark: bool,
}

// ── Element Registry types ───────────────────────────────────────────────────
// Defined here (not in Registry.res) to avoid circular dependency.

type registryEntry = {
  el: EnDom.element,
  directive: string,
  param: option<string>,
}

type registry = Map.t<string, array<registryEntry>>

// ── Context — central state for one instance ────────────────────────────────

type context = {
  mutable data: option<unknown>, // the reactive Proxy root
  mutable prefix: string,
  watchers: Map.t<string, array<watcher>>,
  directives: Map.t<string, directiveEntry>,
  deps: depsState,
  computedResultFns: WeakSet.t<unknown>,
  mutable batchQueue: option<array<unit => unit>>,
  mutable destroyed: bool,
  registry: registry, // live element index — replaces querySelectorAll
  mutable observer: option<EnDom.observer>,
}

// ── getValue result ─────────────────────────────────────────────────────────

type getValueResult = {
  value: unknown,
  parent: option<unknown>,
  prop: string,
}
