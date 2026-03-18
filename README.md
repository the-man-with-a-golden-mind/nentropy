# nentropy

> uentropy rewritten in [ReScript 12](https://rescript-lang.org) — same API, faster architecture.

A small reactive DOM library. No virtual DOM, no compiler, no JSX. Plain HTML with a few extra attributes and plain JavaScript.

Built on a **Registry architecture** — every reactive update is an O(1) Map lookup instead of `querySelectorAll` over the whole document. The original TypeScript uentropy scans the DOM on every write; entropyrs maintains a live index of bound elements, making it significantly faster at scale.

```html
<span en-mark="count">0</span>
<button onclick="data.count++">+</button>

<script src="dist/entropy.min.js"></script>
<script>
  window.data = UEntropy.default.init();
  data.count = 0;
</script>
```

## AI reference

[Full AI reference for LLMs](docs/ai.md) — condensed API + architecture for code generation.

## Why ReScript?

- **Pattern matching** for directive dispatch, input classification, conditional logic
- **Variant types** for `If | IfNot`, `Checkbox | Radio | NumberInput | SelectElement | TextLike`
- **`let rec ... and ...`** mutual recursion — `callDirectives ↔ update ↔ callDirectivesForArray` are direct static calls, no ref indirection
- **`@send` / `@get` / `@set`** compile to direct property access — zero wrapper overhead
- **Abstract types** (`Dom.element`, `Dom.document`, `Dom.observer`) instead of `any` / `{..}`
- **RS12 regex literals** (`/^\d+$/`) — no escaping, no `new RegExp()` per call
- **Registry** — architectural improvement not present in the TypeScript version

## Installation

Drop the IIFE build into your HTML:

```html
<script src="dist/entropy.min.js"></script>
<script>
  const en = UEntropy.default;
  window.data = en.init();
</script>
```

ESM import:

```js
import en from 'entropyrs';
const data = en.init();
```

Build from source:

```bash
npm install
npm run build    # rescript build + esbuild bundle
npm test         # 60 tests via vitest
```

## How it works

`en.init()` returns a `Proxy` wrapping an empty object. Setting any property triggers a **Registry lookup** for elements bound to that key, then calls their directive callbacks. No DOM scanning, no diffing — just a `set` trap and a `Map.get`.

**Important:** assign parent objects before accessing nested keys.

```js
const data = en.init();
data.user = { name: 'Alice', age: 30 };  // parent first
data.user.name = 'Bob';                   // then children
```

**`window.data` vs `const data`:** examples use `window.data` so that inline `onclick="data.count++"` handlers work. With `addEventListener`, a local `const` is fine.

**Initialization order:**

```js
en.prefix('x');           // 1. optional, BEFORE init()
en.directive('color', …); // 2. optional, BEFORE init()
const data = en.init();   // 3. starts reactivity
data.count = 0;           // 4. assign keys AFTER init()
```

## Directives

### `en-mark`

Sets `textContent`. Objects are serialised to JSON.

```html
<span en-mark="user.name"></span>
<pre en-mark="config"></pre>
```

### `en-model`

Two-way binding. Keeps a reactive key and an input in sync.

```html
<input en-model="name" />
<input type="number" en-model="qty" />
<input type="checkbox" en-model="agreed" />

<input type="radio" en-model="size" value="S" name="size" /> S
<input type="radio" en-model="size" value="M" name="size" /> M

<select en-model="country">
  <option value="pl">Poland</option>
  <option value="de">Germany</option>
</select>

<textarea en-model="bio"></textarea>
```

| Element | Event | Data type |
|---|---|---|
| `input` (text, email, …) | `input` | string |
| `input[type=number]` | `input` | number |
| `input[type=checkbox]` | `change` | boolean |
| `input[type=radio]` | `change` | string |
| `select` | `change` | string |
| `textarea` | `input` | string |

### `en-if` / `en-ifnot`

Must be on a `<template>`. Moves content in/out of DOM based on truthiness.

```html
<template en-if="isLoggedIn">
  <nav>…</nav>
</template>

<template en-ifnot="isLoggedIn">
  <a href="/login">Sign in</a>
</template>
```

### Lists

Use `#` as a wildcard for the item template:

```html
<ul>
  <li en-mark="items.#"></li>
</ul>
```

```js
data.items = ['one', 'two', 'three'];
data.items.push('four');         // appends one item
data.items.splice(1, 1);        // removes one item
data.items[0] = 'updated';      // updates in place
data.items = ['a', 'b'];        // replaces all (destroys + recreates DOM)
```

Object arrays — nest keys with `#`:

```html
<ul>
  <li en-mark="users.#">
    <strong en-mark="users.#.name"></strong>
    <span en-mark="users.#.email"></span>
  </li>
</ul>
```

```js
data.users = [
  { name: 'Alice', email: 'alice@example.com' },
  { name: 'Bob',   email: 'bob@example.com'   },
];
```

### Custom directives

Register before `en.init()`:

```js
// simple: en-color="theme.primary"
en.directive('color', ({ el, value }) => {
  el.style.color = String(value);
});

// parametric: en-attr="key:href"
en.directive('attr', ({ el, value, param }) => {
  if (param) el.setAttribute(param, String(value));
}, true);
```

Callback receives: `el`, `value`, `key`, `param`, `isDelete`, `parent`, `prop`.

### Events

No built-in event directive. Use inline handlers or `addEventListener`:

```html
<button onclick="data.count++">+</button>
```

```js
document.getElementById('btn').addEventListener('click', () => data.count++);
```

For lists, use event delegation:

```js
document.querySelector('ul').addEventListener('click', e => {
  const btn = e.target.closest('[data-remove]');
  if (!btn) return;
  data.todos = data.todos.filter(t => t.id !== +btn.dataset.remove);
});
```

## API

### `en.init()` — returns reactive proxy (idempotent)

### `en.computed(fn)` — reactive derived value

```js
data.first    = 'Jane';
data.last     = 'Doe';
data.fullName = en.computed(() => `${data.first} ${data.last}`);
```

Async:

```js
data.post = en.computed(async () => {
  const res = await fetch(`/api/posts/${data.postId}`);
  return res.json();
});
```

### `en.watch(key, fn)` — fires on key/children change

```js
en.watch('cart', () => recalcTotal());
en.watch('user.name', name => console.log(name));
```

### `en.unwatch(key?, fn?)` — removes watchers

### `en.batch(fn)` — single DOM flush for multiple writes

```js
en.batch(() => {
  data.loading = false;
  data.results = items;
  data.total   = items.length;
});
```

### `en.prefix(str)` — change attribute prefix (before `init()`)

### `en.directive(name, cb, isParametric?)` — register custom directive (before `init()`)

### `en.register(...)` — register `<template name="...">` as Web Components

### `en.load(files)` — fetch and register external templates

### `en.destroy()` — tear down instance

## Multiple instances

```js
const enA = UEntropy.createInstance();
const enB = UEntropy.createInstance();
enA.prefix('widget-a');
enB.prefix('widget-b');
const dataA = enA.init();
const dataB = enB.init();
// completely isolated
```

## Examples

Open any file in `examples/` in a browser:

| # | File | What it shows |
|---|------|---------------|
| 01 | [Counter](examples/01-counter.html) | Minimal reactive counter |
| 02 | [Todos](examples/02-todos.html) | CRUD list with filters |
| 03 | [Async computed](examples/03-async-computed.html) | Fetch + loading states |
| 04 | [Components](examples/04-components.html) | Web Components via `en.register` |
| 05 | [Multiple instances](examples/05-multiple-instances.html) | Isolated widgets |
| 06 | [Benchmark](examples/06-benchmark.html) | 5000-row performance vs Preact |
| 07 | [Routing](examples/07-routing.html) | Hash-based SPA router |
| 08 | [Model](examples/08-model.html) | All `en-model` input types |
| 09 | [Feature test](examples/09-feature-test.html) | Comprehensive directive tests |
| 10 | [Happy-dom proof](examples/10-happydom-proof.html) | Node.js DOM compat |
| 11 | [Virtual Excel](examples/11-virtual-excel.html) | 10K-cell virtual scroll spreadsheet |
| 12 | [Crypto Excel](examples/12-crypto-excel.html) | CoinGecko live data + uPlot charts |

## Architecture (vs TypeScript version)

The key architectural difference is the **Element Registry**:

| | TypeScript (uentropy) | ReScript (entropyrs) |
|---|---|---|
| Element lookup | `querySelectorAll('[en-mark="key"]')` on every write | `Map.get(key)` — O(1) |
| Registration | none — scans DOM each time | elements register on create, unregister on remove |
| Cache | optional `elementCache` + MutationObserver | no cache needed — registry is the source of truth |
| Scale | slows linearly with DOM size | constant time regardless of DOM size |

This is why the 5000-row benchmark shows a significant difference.

## Limits

- **No key-based list reconciliation.** Array reassignment destroys and recreates all DOM nodes. Mutate in place when possible.
- **Reactive arrays are shallow.** `push`/`splice`/`[index]` tracked. `map`/`filter`/`reduce` are not — reassign the result.
- **No SSR.** Reads and writes the live DOM.
- **Computed tracking is key-based.** Re-runs when any key it read is set, regardless of value change.
- **`en-mark` + `en-model` on same element conflict.** Use separate elements.
- **`en-model` + `en.computed()` on same key conflict.** Computed overwrites user input.

> UEntropy was heavily inspired by the amazing work of **Alan** ([@18alantom](https://github.com/18alantom)) and his 🍓: https://github.com/18alantom/strawberry



## License

MIT
