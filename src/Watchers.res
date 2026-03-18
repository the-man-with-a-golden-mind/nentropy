// ─── Watchers.res ─────────────────────────────────────────────────────────────

open Types

let watch = (ctx: context, key: string, watcher: watcher): unit => {
  let list = ctx.watchers->Map.get(key)->Option.getOr([])
  list->Array.push(watcher)
  ctx.watchers->Map.set(key, list)->ignore
}

let unwatch = (ctx: context, key: option<string>, watcher: option<watcher>): unit =>
  switch (key, watcher) {
  | (None, None) => ctx.watchers->Map.clear
  | (Some(k), None) => ctx.watchers->Map.delete(k)->ignore
  | (_, Some(w)) =>
    let targets = switch key {
    | Some(k) => ctx.watchers->Map.get(k)->Option.mapOr([], list => [(k, list)])
    | None =>
      let result = []
      ctx.watchers->Js.mapForEach((list, k) => result->Array.push((k, list)))
      result
    }
    targets->Array.forEach(((k, list)) => {
      let filtered = list->Array.filter(fn => Js.cast(fn) !== Js.cast(w))
      if filtered->Array.length === 0 {
        ctx.watchers->Map.delete(k)->ignore
      } else {
        ctx.watchers->Map.set(k, filtered)->ignore
      }
    })
  }

let callWatchers = (
  ctx: context,
  changedKey: string,
  changedValue: unknown,
  getValue: string => unknown,
): unit => {
  // Fast path: exact match
  switch ctx.watchers->Map.get(changedKey) {
  | Some(exact) => exact->Array.forEach(cb => cb(changedValue))
  | None => ()
  }
  // Ancestor watchers
  ctx.watchers->Js.mapForEach((watchers, watchedKey) => {
    if watchedKey !== changedKey && changedKey->String.startsWith(watchedKey + ".") {
      watchers->Array.forEach(cb => cb(getValue(watchedKey)))
    }
  })
}
