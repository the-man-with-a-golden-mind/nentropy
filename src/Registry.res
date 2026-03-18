// ─── Registry.res ─────────────────────────────────────────────────────────────
// Live element index — replaces querySelectorAll for directive dispatch.
// Types (registryEntry, registry) live in Types.res to avoid circular deps.

open Types

let make = (): registry => Map.make()

let register = (reg: registry, key: string, entry: registryEntry): unit => {
  let entries = switch reg->Map.get(key) {
  | Some(existing) => existing
  | None =>
    let arr = []
    reg->Map.set(key, arr)->ignore
    arr
  }
  entries->Array.push(entry)
}

let unregisterElement = (reg: registry, el: EnDom.element): unit => {
  let toDelete = []
  reg->Js.mapForEach((entries, key) => {
    let filtered = entries->Array.filter(e => Js.cast(e.el) !== Js.cast(el))
    if filtered->Array.length === 0 {
      toDelete->Array.push(key)
    } else if filtered->Array.length !== entries->Array.length {
      reg->Map.set(key, filtered)->ignore
    }
  })
  toDelete->Array.forEach(k => reg->Map.delete(k)->ignore)
}

let unregisterByPrefix = (reg: registry, prefix: string): unit => {
  let toDelete = []
  reg->Js.mapForEach((_, key) => {
    if key->String.startsWith(prefix) {
      toDelete->Array.push(key)
    }
  })
  toDelete->Array.forEach(k => reg->Map.delete(k)->ignore)
}

let lookup = (reg: registry, key: string): array<registryEntry> =>
  reg->Map.get(key)->Option.getOr([])

let scanAndRegister = (reg: registry, el: EnDom.element, ctx: context): unit =>
  ctx.directives->Js.mapForEach((dirEntry, name) => {
    let attrName = ctx.prefix + name
    switch el->EnDom.getAttribute(attrName) {
    | None => ()
    | Some(attrValue) =>
      let (key, param) = if dirEntry.isParametric {
        let i = attrValue->String.indexOf(":")
        if i === -1 {
          (attrValue, None)
        } else {
          (attrValue->String.slice(~start=0, ~end=i), Some(attrValue->String.slice(~start=i + 1)))
        }
      } else {
        (attrValue, None)
      }
      if !(key->String.endsWith(".#")) {
        register(reg, key, {el, directive: name, param})
      }
    }
  })

let rec scanTree = (reg: registry, el: EnDom.element, ctx: context): unit => {
  scanAndRegister(reg, el, ctx)
  EnDom.getChildren(el)->Array.forEach(child => scanTree(reg, child, ctx))
}
