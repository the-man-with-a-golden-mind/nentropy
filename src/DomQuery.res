// ─── DomQuery.res ─────────────────────────────────────────────────────────────

open Types

let getValue = (ctx: context, key: string): getValueResult => {
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
          if Js.isObject(value) { walk(value, idx + 1) }
          else { {value: Js.cast(undefined), parent: Some(parent), prop} }
        } else {
          {value, parent: Some(parent), prop}
        }
      }

    walk(data, 0)
  }
}

let queryAll = (ctx: context, root: EnDom.element, query: string): array<EnDom.element> => {
  if !ctx.useCache {
    EnDom.querySelectorAll(root, query)
  } else {
    switch ctx.elementCache->Map.get(query) {
    | Some(cached) => cached
    | None =>
      let result = EnDom.querySelectorAll(root, query)
      ctx.elementCache->Map.set(query, result)->ignore
      result
    }
  }
}

// Overload for document root
let queryAllDoc = (ctx: context, query: string): array<EnDom.element> => {
  if !ctx.useCache {
    EnDom.querySelectorAll(EnDom.document, query)
  } else {
    switch ctx.elementCache->Map.get(query) {
    | Some(cached) => cached
    | None =>
      let result = EnDom.querySelectorAll(EnDom.document, query)
      ctx.elementCache->Map.set(query, result)->ignore
      result
    }
  }
}

let setupObserver = (ctx: context): unit =>
  switch ctx.observer {
  | Some(_) => ()
  | None =>
    switch EnDom.makeObserver(() => ctx.elementCache->Map.clear)->Nullable.toOption {
    | Some(obs) =>
      EnDom.observe(obs)
      ctx.observer = Some(obs)
    | None => ()
    }
  }
