// ─── Instance.res ─────────────────────────────────────────────────────────────

open Types

type t = {
  ctx: context,
  mutable readyStateHandler: option<unit => unit>,
}

let make = (): t => {
  let ctx = Context.make()
  Core.bootstrapDirectives(ctx)
  {ctx, readyStateHandler: None}
}

let init = (inst: t): unknown => {
  switch inst.ctx.data {
  | None =>
    let obj: unknown = Js.cast(%raw(`{}`))
    inst.ctx.data = Some(Core.reactive(inst.ctx, obj, "", None, None))
  | Some(_) => ()
  }

  DomComponent.registerTemplates(None)
  DomQuery.setupObserver(inst.ctx)

  // Scan existing DOM elements into the registry.
  // Build a selector that matches ANY registered directive attribute.
  let selectors = []
  inst.ctx.directives->Js.mapForEach((_, name) => {
    selectors->Array.push(`[${inst.ctx.prefix}${name}]`)
  })
  if selectors->Array.length > 0 {
    let query = selectors->Array.join(",")
    EnDom.querySelectorAll(EnDom.document, query)
    ->Array.forEach(el => Registry.scanAndRegister(inst.ctx.registry, el, inst.ctx))
  }

  switch inst.readyStateHandler {
  | None =>
    let handler = () =>
      if EnDom.document->EnDom.readyState === "interactive" {
        DomComponent.registerTemplates(None)
      }
    inst.readyStateHandler = Some(handler)
    EnDom.document->EnDom.addDocListener("readystatechange", handler)
  | Some(_) => ()
  }

  switch inst.ctx.data {
  | Some(data) => data
  | None => Js.cast(%raw(`{}`))
  }
}

let computed = Computed.markComputed

let watch = (inst: t, key: string, watcher: watcher): unit =>
  Watchers.watch(inst.ctx, key, watcher)

let unwatch = (inst: t, ~key: option<string>=?, ~watcher: option<watcher>=?): unit =>
  Watchers.unwatch(inst.ctx, key, watcher)

let directive = (inst: t, name: string, cb: directive, ~isParametric=false): unit =>
  Directives.registerDirective(inst.ctx, name, cb, ~isParametric)

let prefix = (inst: t, ~value: string="en"): unit =>
  inst.ctx.prefix = if value->String.endsWith("-") { value } else { value + "-" }

let batch = (inst: t, fn: unit => unit): unit => Core.batch(inst.ctx, fn)

let load = async (_inst: t, files: array<string>): unit => {
  let _ = await Promise.all(files->Array.map(DomComponent.loadTemplateFile))
}

let register = (_inst: t, root: option<EnDom.element>): unit =>
  DomComponent.registerTemplates(root)

let destroy = (inst: t): unit => {
  inst.ctx.destroyed = true
  switch inst.readyStateHandler {
  | Some(handler) =>
    EnDom.document->EnDom.removeDocListener("readystatechange", handler)
    inst.readyStateHandler = None
  | None => ()
  }
  inst.ctx.watchers->Map.clear
  inst.ctx.deps.depMap->Map.clear
  inst.ctx.deps.versions->Map.clear
  inst.ctx.registry->Map.clear
  switch inst.ctx.observer {
  | Some(obs) =>
    obs->EnDom.disconnect
    inst.ctx.observer = None
  | None => ()
  }
  inst.ctx.data = None
}
