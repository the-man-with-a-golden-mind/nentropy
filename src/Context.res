// ─── Context.res ──────────────────────────────────────────────────────────────

open Types

let make = (): context => {
  data: None,
  prefix: "en-",
  watchers: Map.make(),
  directives: Map.make(),
  deps: {
    isEvaluating: false,
    currentSet: Set.make(),
    depMap: Map.make(),
    versions: Map.make(),
  },
  computedResultFns: WeakSet.make(),
  batchQueue: None,
  destroyed: false,
  registry: Registry.make(),
  observer: None,
}
