# entropyrs – AI reference

Reactive DOM library rewritten in ReScript 12. Same API as uentropy (TypeScript), faster via Registry architecture. No vDOM, no compiler, no JSX. Plain HTML + JS.

## Setup
```html
<script src="dist/entropy.min.js"></script>
<script>
  const en = UEntropy.default;
  en.prefix('x');         // optional, BEFORE init
  en.directive(...);      // optional, BEFORE init
  window.data = en.init(); // starts reactivity
  data.count = 0;         // assign keys AFTER init
</script>
```
ESM: `import en from 'entropyrs'`
Multi-instance: `const { createInstance } = UEntropy; const en = createInstance();`

## Core mechanics

`en.init()` returns a Proxy. Setting any key triggers a **Registry lookup** (`Map.get(key)`) for bound elements and calls their directive callbacks. No `querySelectorAll`, no DOM scanning.

**Registry vs querySelectorAll:** The TypeScript version runs `querySelectorAll('[en-mark="key"]')` on every reactive write — O(DOM). entropyrs maintains a live `Map<string, array<{el, directive, param}>>`. Elements register when created (clone, init scan) and unregister when removed. Lookup is O(1).

Always assign parent before children:
```js
data.user = {};        // parent first
data.user.name = '';   // then children
```

`window.data` needed for inline `onclick="data.x++"`. Local `const` fine with `addEventListener`.

## Directives

**`en-mark="key"`** — sets `textContent`. Objects → JSON. No template syntax inside.

**`en-model="key"`** — two-way binding. Types: number input→number, checkbox→boolean, radio/select→string, rest→string.

**`en-if="key"` / `en-ifnot="key"`** — MUST be on `<template>`. Moves content in/out of DOM.

**Lists** — use `#` as wildcard:
```html
<ul>
  <li en-mark="items.#">
    <strong en-mark="items.#.name"></strong>
  </li>
</ul>
```
```js
data.items = [{name:'Alice'}]; // set
data.items.push({name:'Bob'}); // appends one node
data.items.splice(1, 1);       // removes one node
data.items[0] = {name:'Eve'};  // updates in place
data.items = [...];            // DESTROYS + recreates all nodes
```
Shallow tracking: `push/splice/index` tracked. `map/filter/reduce` NOT — reassign result.

**`delete data.key`** — removes bound DOM element + unregisters from Registry.

**Custom directive** (BEFORE init):
```js
en.directive('color', ({ el, value, param, key, isDelete }) => {
  el.style.color = String(value);
});
// parametric (en-attr="key:href"):
en.directive('attr', ({ el, value, param }) => {
  if (param) el.setAttribute(param, String(value));
}, true);
```

## API

`en.init()` — returns reactive proxy. Idempotent.

`en.computed(fn)` — auto-reruns when dependencies change. Async supported (stale results discarded).
```js
data.sum = en.computed(() => data.a + data.b);
data.result = en.computed(async () => {
  const res = await fetch(`/api/${data.id}`);
  return res.json();
});
```

`en.watch(key, fn)` — calls `fn(newValue)` on key/children change.

`en.unwatch(key?, fn?)` — removes watchers. No args = remove all.

`en.batch(fn)` — queues all writes in `fn`, single DOM flush. Always use for bulk updates.

`en.prefix(str)` — changes `en-` prefix. BEFORE `init()`.

`en.directive(name, cb, isParametric?)` — registers custom directive. BEFORE `init()`. After init, existing DOM elements are automatically scanned for the new directive.

`en.register(...)` — registers `<template name="…">` as Web Components (Shadow DOM).

`en.load(files[])` — fetches external HTML, registers templates. Async.

`en.destroy()` — removes all listeners/watchers, clears Registry.

## Architecture (ReScript internals)

```
src/
├── EnDom.res    — typed DOM bindings (@send/@get/@set, abstract types)
├── Js.res       — minimal JS interop (unknown-based, no {..})
├── Types.res    — core types (context, directiveParams, registryEntry, etc.)
├── Registry.res — live element index (Map<key, entries>)
├── Context.res  — context factory
├── Utils.res    — getKey, getParam
├── Computed.res — dependency graph (setDependents, getDependentsOf)
├── Watchers.res — watch/unwatch/callWatchers
├── Directives.res — mark, model, registerDirective
├── DomQuery.res — getValue (key→value resolver)
├── DomComponent.res — Web Component registration
├── Core.res     — reactive engine (Proxy handler, update, callDirectives, batch)
├── Instance.res — public API
└── Entropy.res  — entry point + JS-compatible wrapper
```

**Key design decisions:**
- `unknown` for reactive values (not `any` or `{..}`)
- `EnDom.element` / `EnDom.document` / `EnDom.observer` as abstract types
- `let rec callDirectivesForLeaf and callDirectivesForObject and callDirectives and update` — mutual recursion, no ref indirection
- Registry replaces all `querySelectorAll` in the reactive update path
- Only `Proxy` handler and `class extends HTMLElement` remain as `%raw` — genuinely JS-only concepts

## Conflicts & limits
- `en-mark` + `en-model` on same element → don't
- `en-model` + `en.computed()` on same key → computed overwrites input → don't
- Array replace = full DOM destroy+recreate; mutate in place when possible
- No SSR, no key-based list reconciliation
- Computed tracking is key-based, not value-based
