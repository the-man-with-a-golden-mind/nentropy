---
name: entropyrs project status
description: ReScript 12 rewrite of uentropy reactive DOM library — architecture, optimizations, known issues
type: project
---

ReScript 12 rewrite of uentropy at /Users/michalmajchrzak/Projects/entropyrs.

**Why:** Registry-based element lookup (O(1) Map) replaces querySelectorAll (O(DOM)) in the reactive update path. RS wins 8/10 Node.js benchmarks but browser benchmark.html uses the OLD TS bundle from ../entropy/dist/ which doesn't have the registry optimization — so it's comparing apples to oranges.

**How to apply:** The benchmark.html needs to load BOTH bundles side by side. The browser benchmark at entropyrs/benchmark.html references `../entropy/dist/entropy.min.js` for TS. Make sure both dist/ folders have fresh builds.

**Key architecture:**
- Registry.res: live element index (Map<key, array<{el, directive, param}>>)
- No querySelectorAll in callDirectivesForLeaf — direct Map.get
- No cache/elementCache — registry replaces it
- EnDom.res: typed DOM bindings (@send/@get/@set), no {..}
- Js.res: minimal interop, unknown-based
- Core.res: let rec mutual recursion (no ref indirection), sync functions in pure ReScript

**Known happy-dom quirk:** cloneNode(true) on elements inside DocumentFragment drops child nodes. Fixed via innerHTML-based cloning in initializeArrayElements.

**Known @get bug:** ReScript `@get external x: t => int = "a.b"` compiles to `t["a.b"]` not `t.a.b`. Avoid dotted paths in @get.
