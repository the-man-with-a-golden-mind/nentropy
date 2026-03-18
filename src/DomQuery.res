// ─── DomQuery.res ─────────────────────────────────────────────────────────────
// Key-to-value resolver. No more querySelectorAll caching — the Registry
// handles element lookup. This module only resolves reactive key paths.

open Types

let getValue = (ctx: context, key: string): getValueResult =>
  switch ctx.data {
  | None => {value: Js.cast(undefined), parent: None, prop: ""}
  | Some(data) =>
    let parts = key->String.split(".")
    let len = parts->Array.length

    let rec walk = (parent: unknown, idx: int): getValueResult =>
      if idx >= len {
        {value: Js.cast(undefined), parent: None, prop: ""}
      } else {
        let prop = parts->Array.getUnsafe(idx)
        let value = Js.reflectGet(parent, prop)
        if idx < len - 1 {
          if Js.isObject(value) {
            walk(value, idx + 1)
          } else {
            {value: Js.cast(undefined), parent: Some(parent), prop}
          }
        } else {
          {value, parent: Some(parent), prop}
        }
      }

    walk(data, 0)
  }

let setupObserver = (ctx: context): unit =>
  switch ctx.observer {
  | Some(_) => ()
  | None =>
    switch EnDom.makeObserver(() => ()) {
    | Some(obs) =>
      EnDom.observe(obs)
      ctx.observer = Some(obs)
    | None => ()
    }
  }
