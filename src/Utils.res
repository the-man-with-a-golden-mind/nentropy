// ─── Utils.res ────────────────────────────────────────────────────────────────

let getKey = (prop: string, prefix: string): string =>
  if prefix === "" {
    prop
  } else {
    prefix + "." + prop
  }

let getParam = (el: EnDom.element, attrName: string, isParametric: bool): option<string> =>
  if !isParametric {
    None
  } else {
    switch el->EnDom.getAttribute(attrName) {
    | None => None
    | Some(value) =>
      let idx = value->String.indexOf(":")
      if idx === -1 {
        None
      } else {
        Some(value->String.slice(~start=idx + 1))
      }
    }
  }
