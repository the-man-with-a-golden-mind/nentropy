// ─── Directives.res ───────────────────────────────────────────────────────────

open Types

let registerDirective = (ctx: context, name: string, cb: directive, ~isParametric=false): unit =>
  if !(ctx.directives->Map.has(name)) {
    ctx.directives->Map.set(name, {cb, isParametric})->ignore
    // Scan existing DOM for elements that use this new directive
    let attrName = ctx.prefix + name
    EnDom.querySelectorAll(EnDom.document, `[${attrName}]`)->Array.forEach(el =>
      Registry.scanAndRegister(ctx.registry, el, ctx)
    )
  }

// ── mark ────────────────────────────────────────────────────────────────────

let removeElementSmart: EnDom.element => unit = %raw(`
  function(el) {
    if (!(el instanceof HTMLElement)) { el.remove(); return; }
    var parent = el.parentElement;
    if (!parent) { el.remove(); return; }
    var elMark = el.getAttribute('data-en-mark') || el.getAttribute('en-mark');
    var parentMark = parent.getAttribute('data-en-mark') || parent.getAttribute('en-mark');
    if (elMark && elMark === parentMark) { parent.remove(); return; }
    el.remove();
  }
`)

let markDirective = (params: directiveParams): unit => {
  if params.isDelete {
    removeElementSmart(params.el)
  } else if EnDom.isHTMLElement(params.el) {
    if Js.isObject(params.value) {
      if EnDom.hasChildren(params.el) {
        () // children carry their own en-mark — don't clobber
      } else {
        params.el->EnDom.setTextContent(Js.jsonStringify(params.value))
      }
    } else if Js.isFunction(params.value) {
      params.el->EnDom.setTextContent(Js.cast(params.value))
    } else {
      let text: string = Js.cast(params.value)
      params.el->EnDom.setTextContent(text)
    }
  }
}

// ── model — pattern matching on input kind ──────────────────────────────────

type inputKind = Checkbox | Radio | NumberInput | SelectElement | TextLike

let classifyInput = (el: EnDom.element): option<inputKind> =>
  if EnDom.isInput(el) {
    switch el->EnDom.inputType {
    | "checkbox" => Some(Checkbox)
    | "radio" => Some(Radio)
    | "number" => Some(NumberInput)
    | _ => Some(TextLike)
    }
  } else if EnDom.isTextArea(el) {
    Some(TextLike)
  } else if EnDom.isSelect(el) {
    Some(SelectElement)
  } else {
    None
  }

let modelListeners: WeakMap.t<EnDom.element, unit => unit> = WeakMap.make()

let makeModelDirective = (ctx: context): directive =>
  (params: directiveParams) => {
    let el = params.el

    switch classifyInput(el) {
    | None => ()
    | Some(kind) => {
        // data → DOM
        switch kind {
        | Checkbox => el->EnDom.setInputChecked(Js.cast(params.value) === true)
        | Radio => el->EnDom.setInputChecked(el->EnDom.inputValue === Js.cast(params.value))
        | _ =>
          let strVal: string = if Js.isNull(params.value) || Js.isUndefined(params.value) {
            ""
          } else {
            Js.cast(params.value)
          }
          if el->EnDom.inputValue !== strVal {
            el->EnDom.setInputValue(strVal)
          }
        }

        // DOM → data (once per element)
        if !(modelListeners->WeakMap.has(el)) {
          let eventName = switch kind {
          | Checkbox | Radio | SelectElement => "change"
          | _ => "input"
          }
          let handler = _ => {
            let result = DomQuery.getValue(ctx, params.key)
            switch result.parent {
            | None => ()
            | Some(parent) =>
              let incoming: unknown = switch kind {
              | Checkbox => Js.cast(el->EnDom.inputChecked)
              | NumberInput => Js.cast(el->EnDom.valueAsNumber)
              | _ => Js.cast(el->EnDom.inputValue)
              }
              Js.reflectSet(parent, result.prop, incoming)
            }
          }
          el->EnDom.addEventListener(eventName, handler)
          modelListeners->WeakMap.set(el, Js.cast(handler))->ignore
        }
      }
    }
  }

// ── Register builtins ───────────────────────────────────────────────────────

let registerBuiltins = (ctx: context): unit => {
  ctx.directives->Map.set("mark", {cb: markDirective, isParametric: false})->ignore
  ctx.directives->Map.set("model", {cb: makeModelDirective(ctx), isParametric: false})->ignore
}
