// ─── Computed.res ─────────────────────────────────────────────────────────────

open Types

let markComputed: 'a => 'a = %raw(`
  function(fn) {
    Object.defineProperty(fn, Symbol.for("@en/computed"), {
      value: true, enumerable: false, configurable: true, writable: false
    });
    return fn;
  }
`)

let clearDepsForKey = (ctx: context, key: string): unit => {
  let toDelete = []
  ctx.deps.depMap->Js.mapForEach((list, depKey) => {
    let filtered = list->Array.filter(d => d.key !== key)
    if filtered->Array.length === 0 {
      toDelete->Array.push(depKey)
    } else {
      ctx.deps.depMap->Map.set(depKey, filtered)->ignore
    }
  })
  toDelete->Array.forEach(k => ctx.deps.depMap->Map.delete(k)->ignore)
}

let registerTrackedDeps = (
  ctx: context,
  key: string,
  computedFn: unknown,
  parent: unknown,
  prop: string,
): unit => {
  let dep: computedDep = {key, computed: computedFn, parent, prop}
  ctx.deps.currentSet->Set.forEach(depKey => {
    let list = ctx.deps.depMap->Map.get(depKey)->Option.getOr([])
    list->Array.push(dep)
    ctx.deps.depMap->Map.set(depKey, list)->ignore
  })
}

let setDependents = (
  ctx: context,
  value: unknown,
  key: string,
  parent: unknown,
  prop: string,
): unit => {
  clearDepsForKey(ctx, key)
  ctx.deps.isEvaluating = true
  ctx.deps.currentSet->Set.clear
  try {Js.callFn(value)->ignore} catch {
  | _ => ()
  }
  ctx.deps.isEvaluating = false
  registerTrackedDeps(ctx, key, value, parent, prop)
  ctx.deps.currentSet->Set.clear
}

let getDependentsOf = (ctx: context, changedKey: string): array<computedDep> => {
  let result = []
  let seen = Set.make()
  let changedDot = changedKey + "."
  ctx.deps.depMap->Js.mapForEach((list, k) => {
    if (
      k === changedKey || k->String.startsWith(changedDot) || changedKey->String.startsWith(k + ".")
    ) {
      list->Array.forEach(dep => {
        if !(seen->Set.has(dep.computed)) {
          seen->Set.add(dep.computed)->ignore
          result->Array.push(dep)
        }
      })
    }
  })
  result
}

let removeDependentsFor = (ctx: context, deletedKey: string): unit => {
  ctx.deps.depMap->Map.delete(deletedKey)->ignore
  let toDelete = []
  ctx.deps.depMap->Js.mapForEach((list, k) => {
    let filtered = list->Array.filter(d => d.key !== deletedKey)
    if filtered->Array.length === 0 {
      toDelete->Array.push(k)
    } else {
      ctx.deps.depMap->Map.set(k, filtered)->ignore
    }
  })
  toDelete->Array.forEach(k => ctx.deps.depMap->Map.delete(k)->ignore)
}

let bumpVersion = (ctx: context, key: string): int => {
  let v = ctx.deps.versions->Map.get(key)->Option.getOr(0) + 1
  ctx.deps.versions->Map.set(key, v)->ignore
  v
}

let isCurrentVersion = (ctx: context, key: string, version: int): bool =>
  ctx.deps.versions->Map.get(key) === Some(version)
