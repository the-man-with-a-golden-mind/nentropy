// ─── Core.res ─────────────────────────────────────────────────────────────────
// Reactive engine with Element Registry.
//
// callDirectivesForLeaf uses Registry.lookup — O(1) Map hit, no querySelectorAll.
// syncNode/syncClone rewritten in pure ReScript.
// Array DOM ops still %raw (template content access) but register on clone.

open Types

// ═══════════════════════════════════════════════════════════════════════════════
// Batch scheduling
// ═══════════════════════════════════════════════════════════════════════════════

let scheduleUpdate = (ctx: context, fn: unit => unit): unit =>
  switch ctx.batchQueue {
  | Some(queue) => queue->Array.push(fn)
  | None => fn()
  }

// ═══════════════════════════════════════════════════════════════════════════════
// Forward ref for reactive (only used by proxyComputed)
// ═══════════════════════════════════════════════════════════════════════════════

let reactiveRef: ref<(context, unknown, string, option<unknown>, option<string>) => unknown> =
  ref((_, v, _, _, _) => v)

let proxyComputed = (
  ctx: context,
  value: unknown,
  key: option<string>,
  parent: option<unknown>,
  prop: option<string>,
): unknown =>
  if Js.isFunction(value) {
    ctx.computedResultFns->WeakSet.add(value)->ignore
    value
  } else {
    let cloned: unknown = Js.clone(value)
    switch (key, parent, prop) {
    | (Some(k), Some(p), Some(pr)) => reactiveRef.contents(ctx, cloned, k, Some(p), Some(pr))
    | _ => cloned
    }
  }

// ═══════════════════════════════════════════════════════════════════════════════
// P2: Sync functions — pure ReScript
// ═══════════════════════════════════════════════════════════════════════════════

// Forward ref needed because syncDirectives calls update which isn't defined yet
let updateFnRef: ref<(context, unknown, string, bool, unknown, string, option<syncConfig>) => unit> =
  ref((_, _, _, _, _, _, _) => ())

let syncDirectives = (ctx: context, el: EnDom.element, skipConditionals: bool, skipMark: bool): unit =>
  ctx.directives->Js.mapForEach((dirEntry, name) => {
    if skipMark && name === "mark" {
      ()
    } else if skipConditionals && (name === "if" || name === "ifnot") {
      ()
    } else {
      let attrFull = ctx.prefix + name
      switch el->EnDom.getAttribute(attrFull) {
      | None => ()
      | Some(rawKey) => {
          let key = if dirEntry.isParametric {
            let i = rawKey->String.indexOf(":")
            if i >= 0 { rawKey->String.slice(~start=0, ~end=i) } else { rawKey }
          } else {
            rawKey
          }
          let key = if key->String.endsWith(".#") {
            key->String.slice(~start=0, ~end=key->String.length - 2)
          } else {
            key
          }
          let result = DomQuery.getValue(ctx, key)
          switch result.parent {
          | None => ()
          | Some(_) =>
            updateFnRef.contents(
              ctx,
              result.value,
              key,
              false,
              result.parent->Option.getUnsafe,
              result.prop,
              Some({directive: name, el, skipConditionals, skipMark}),
            )
          }
        }
      }
    }
  })

let rec syncNode = (ctx: context, el: EnDom.element, isSyncRoot: bool): unit => {
  EnDom.getChildren(el)->Array.forEach(child => syncNode(ctx, child, false))
  syncDirectives(ctx, el, isSyncRoot, false)
}

let rec syncClone = (ctx: context, el: EnDom.element): unit => {
  EnDom.getChildren(el)->Array.forEach(child => syncClone(ctx, child))
  // Register this element in the registry BEFORE syncing directives
  Registry.scanAndRegister(ctx.registry, el, ctx)
  syncDirectives(ctx, el, false, true)
}

// ═══════════════════════════════════════════════════════════════════════════════
// ifOrIfNot — rewritten in ReScript (P2)
// ═══════════════════════════════════════════════════════════════════════════════

let ifOrIfNot = (
  ctx: context,
  el: EnDom.element,
  value: unknown,
  key: string,
  condType: conditionalType,
): unit => {
  let isShow = switch condType {
  | If => Js.cast(value) === true || (Js.isObject(value) && !Js.isNull(value))
  | IfNot => Js.cast(value) === false || Js.isNull(value) || Js.isUndefined(value)
  }
  // Truthiness: for If, any truthy value. For IfNot, any falsy value.
  let isShow = switch condType {
  | If => !Js.isNull(value) && !Js.isUndefined(value) && Js.cast(value) !== false && Js.cast(value) !== 0
  | IfNot => Js.isNull(value) || Js.isUndefined(value) || Js.cast(value) === false || Js.cast(value) === 0
  }
  let isTemplate = EnDom.isTemplate(el)
  let attrType = ctx.prefix + (switch condType { | If => "if" | IfNot => "ifnot" })
  let attrMark = ctx.prefix + "mark"

  // Show: template → clone children, register, sync, insert
  if isShow && isTemplate {
    let children = EnDom.getTemplateChildren(el)
    if children->Array.length > 0 {
      children->Array.forEach(child => {
        let clone = child->EnDom.cloneNode(true)
        clone->EnDom.setAttribute(attrType, key)
        // Register BEFORE sync — sync triggers update which needs registry lookup
        Registry.scanTree(ctx.registry, clone, ctx)
        syncNode(ctx, clone, true)
        el->EnDom.before(clone)
      })
      Registry.unregisterElement(ctx.registry, el)
      el->EnDom.remove
    }
  }

  // Hide: collect siblings, wrap in template
  if !isShow && !isTemplate {
    switch el->EnDom.parentNode->Nullable.toOption {
    | None => ()
    | Some(_) => {
        let siblings = [el]
        let rec collectSiblings = (current: EnDom.element) =>
          switch current->EnDom.nextElementSibling->Nullable.toOption {
          | Some(next) =>
            switch next->EnDom.getAttribute(attrType) {
            | Some(attr) if attr === key =>
              siblings->Array.push(next)
              collectSiblings(next)
            | _ => ()
            }
          | None => ()
          }
        collectSiblings(el)

        let temp = EnDom.document->EnDom.createElement("template")
        siblings->Array.forEach(s => {
          let clone = s->EnDom.cloneNode(true)
          temp->EnDom.appendToTemplateContent(clone)
        })
        temp->EnDom.setAttribute(attrType, key)
        switch el->EnDom.getAttribute(attrMark) {
        | Some(mark) => temp->EnDom.setAttribute(attrMark, mark)
        | None => ()
        }

        // Unregister all siblings from registry
        siblings->Array.forEach(s => Registry.unregisterElement(ctx.registry, s))

        el->EnDom.replaceWith(temp)
        // Register the new template in the registry so it can be found on re-show
        Registry.scanAndRegister(ctx.registry, temp, ctx)
        // Remove remaining siblings
        siblings
        ->Array.sliceToEnd(~start=1)
        ->Array.forEach(s => s->EnDom.remove)
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Array DOM management — still %raw for template content, but registers clones
// ═══════════════════════════════════════════════════════════════════════════════

let rewriteCloneKeys = (ctx: context, clone: EnDom.element, key: string, placeholderKey: string): unit => {
  // Collect attr names once
  let attrNames = []
  ctx.directives->Js.mapForEach((_, name) => attrNames->Array.push(ctx.prefix + name))

  // Rewrite on clone itself
  attrNames->Array.forEach(attrName =>
    switch clone->EnDom.getAttribute(attrName) {
    | Some(cur) if cur->String.startsWith(placeholderKey) =>
      clone->EnDom.setAttribute(attrName, key + cur->String.sliceToEnd(~start=placeholderKey->String.length))
    | _ => ()
    }
  )
  // Rewrite on all descendants
  EnDom.querySelectorAll(clone, "*")->Array.forEach(child =>
    attrNames->Array.forEach(attrName =>
      switch child->EnDom.getAttribute(attrName) {
      | Some(cur) if cur->String.startsWith(placeholderKey) =>
        child->EnDom.setAttribute(attrName, key + cur->String.sliceToEnd(~start=placeholderKey->String.length))
      | _ => ()
      }
    )
  )
}

// ── Remove old array item elements (walk backward from placeholder) ─────────

let removeOldItems = (ctx: context, plc: EnDom.element, placeholderKey: string, attrMark: string): unit => {
  let prev = ref(plc->EnDom.previousElementSibling->Nullable.toOption)
  let continue_ = ref(true)
  while prev.contents !== None && continue_.contents {
    let curr = prev.contents->Option.getUnsafe
    prev := curr->EnDom.previousElementSibling->Nullable.toOption
    switch curr->EnDom.getAttribute(attrMark) {
    | None => () // skip, keep going
    | Some(k) =>
      if k !== placeholderKey && Js.replaceTrailingDigits(k, "#") === placeholderKey {
        Registry.unregisterElement(ctx.registry, curr)
        curr->EnDom.remove
      } else {
        continue_ := false
      }
    }
  }
}

// ── Resolve template placeholder ────────────────────────────────────────────

type templateResolution = {template: EnDom.element, placeholder: option<EnDom.element>}

let resolveTemplate: (EnDom.element, string, string) => templateResolution = %raw(`
  function(plc, placeholderKey, attrMark) {
    if (plc instanceof HTMLTemplateElement) {
      var ph = plc.content.firstElementChild;
      if (ph) ph.setAttribute(attrMark, placeholderKey);
      return { template: plc, placeholder: ph || undefined };
    } else {
      var template = document.createElement('template');
      template.content.appendChild(plc.cloneNode(true));
      template.setAttribute(attrMark, placeholderKey);
      plc.replaceWith(template);
      return { template: template, placeholder: plc };
    }
  }
`)

// ── Initialize array elements ────────────────────────────────────────────────
// Uses %raw for template content access (happy-dom cloneNode quirk with
// DocumentFragment requires the clone to happen in the same JS scope as
// the template resolution).

let initializeArrayElements: (context, EnDom.element, string, unknown) => array<EnDom.element> = %raw(`
  function(ctx, plc, placeholderKey, array) {
    var attrMark = ctx.prefix + 'mark';
    var prev = plc.previousElementSibling;
    while (prev) {
      var curr = prev; prev = curr.previousElementSibling;
      var k = curr.getAttribute(attrMark);
      if (!k) continue;
      if (k !== placeholderKey && k.replace(/\d+$/, '#') === placeholderKey) {
        Registry.unregisterElement(ctx.registry, curr);
        curr.remove();
      } else break;
    }
    var template, placeholder;
    if (plc instanceof HTMLTemplateElement) {
      template = plc; placeholder = plc.content.firstElementChild;
      if (placeholder) placeholder.setAttribute(attrMark, placeholderKey);
    } else {
      template = document.createElement('template');
      // Use innerHTML to preserve children in happy-dom (cloneNode(true) on
      // DocumentFragment firstElementChild drops child nodes in happy-dom)
      template.innerHTML = plc.outerHTML;
      template.setAttribute(attrMark, placeholderKey);
      plc.replaceWith(template);
      placeholder = template.content.firstElementChild;
    }
    if (!placeholder) return [];
    // Cache outerHTML for cloning — happy-dom's cloneNode(true) on elements
    // inside DocumentFragment drops child nodes. innerHTML parse preserves them.
    var phHTML = placeholder.outerHTML;
    var prefix = placeholderKey.slice(0, -2), elements = [], len = array.length;
    var cloneContainer = document.createElement('div');
    for (var i = 0; i < len; i++) {
      cloneContainer.innerHTML = phHTML;
      var clone = cloneContainer.firstElementChild;
      if (!clone) continue;
      var key = prefix === '' ? String(i) : prefix + '.' + i;
      rewriteCloneKeys(ctx, clone, key, placeholderKey);
      template.before(clone);
      syncClone(ctx, clone);
      elements.push(clone);
    }
    return elements;
  }
`)

// ── Find placeholder template after an element ──────────────────────────────

let findPlaceholderAfter = (el: EnDom.element, placeholderKey: string, attrMark: string): option<EnDom.element> => {
  let ph = ref(el->EnDom.nextElementSibling->Nullable.toOption)
  let result = ref(None)
  while ph.contents !== None && result.contents === None {
    let current = ph.contents->Option.getUnsafe
    switch current->EnDom.getAttribute(attrMark) {
    | Some(attr) if attr === placeholderKey => result := Some(current)
    | _ => ph := current->EnDom.nextElementSibling->Nullable.toOption
    }
  }
  result.contents
}

// ── Clone from template/placeholder ─────────────────────────────────────────

let cloneFromPlaceholder = (ph: EnDom.element): option<EnDom.element> =>
  if EnDom.isTemplate(ph) {
    switch ph->EnDom.getTemplateFirstChild {
    | Some(c) => Some(c->EnDom.cloneNode(true))
    | None => None
    }
  } else {
    Some(ph->EnDom.cloneNode(true))
  }

// ── Update array item element — pure ReScript ───────────────────────────────

let updateArrayItemElement = (
  ctx: context,
  key: string,
  idx: string,
  item: unknown,
  array: unknown,
): unit => {
  let attrMark = ctx.prefix + "mark"

  // Find existing items via registry
  let entries = Registry.lookup(ctx.registry, key)
  let markEntries = entries->Array.filter(e => e.directive === "mark")

  // Primitive items: text update only (no DOM replacement needed)
  if markEntries->Array.length > 0 && !Js.hasPrefix(item) {
    () // callDirectivesForLeaf will update textContent via mark directive
  } else {
    let prefix = Js.getPrefix(array)
    let placeholderKey = Js.replaceTrailingDigits(key, "#")
    let itemReplaced = ref(false)

    markEntries->Array.forEach(entry => {
      let el = entry.el
      switch findPlaceholderAfter(el, placeholderKey, attrMark) {
      | None => ()
      | Some(ph) =>
        switch cloneFromPlaceholder(ph) {
        | None => ()
        | Some(cl) => {
            let k = if prefix === "" { idx } else { prefix + "." + idx }
            rewriteCloneKeys(ctx, cl, k, placeholderKey)
            Registry.unregisterElement(ctx.registry, el)
            el->EnDom.replaceWith(cl)
            syncClone(ctx, cl)
            itemReplaced := true
          }
        }
      }
    })

    if !itemReplaced.contents {
      // No existing item — find templates and insert before them
      let query = `[${attrMark}="${placeholderKey}"]`
      EnDom.querySelectorAll(EnDom.document, query)->Array.forEach(tpl => {
        if EnDom.isTemplate(tpl) {
          switch tpl->EnDom.getTemplateFirstChild {
          | None => ()
          | Some(firstChild) => {
              let clone = firstChild->EnDom.cloneNode(true)
              let k = if prefix === "" { idx } else { prefix + "." + idx }
              rewriteCloneKeys(ctx, clone, k, placeholderKey)
              tpl->EnDom.before(clone)
              syncClone(ctx, clone)
            }
          }
        }
      })
    }
  }
}

// ── Sort array item elements — pure ReScript ────────────────────────────────

type sortEntry = {el: EnDom.element, idx: int}

let sortArrayItemElements = (ctx: context, array: unknown): unit => {
  let attrMark = ctx.prefix + "mark"
  let prefix = Js.getPrefix(array)
  let templateKey = if prefix === "" { "#" } else { prefix + ".#" }
  let templatePrefix = templateKey->String.slice(~start=0, ~end=templateKey->String.length - 1)

  EnDom.querySelectorAll(EnDom.document, `[${attrMark}="${templateKey}"]`)->Array.forEach(tpl => {
    let items: array<sortEntry> = []
    let prev = ref(tpl->EnDom.previousElementSibling->Nullable.toOption)
    let isSorted = ref(true)
    let lastIdx = ref(-1)

    let continue_ = ref(true)
    while prev.contents !== None && continue_.contents {
      let curr = prev.contents->Option.getUnsafe
      prev := curr->EnDom.previousElementSibling->Nullable.toOption
      switch curr->EnDom.getAttribute(attrMark) {
      | None => () // skip
      | Some(k) if k === templateKey => continue_ := false
      | Some(k) if k->String.startsWith(templatePrefix) =>
        let idxStr = k->String.sliceToEnd(~start=templatePrefix->String.length)
        let idx = Js.parseInt(idxStr)
        if !Float.isNaN(idx) {
          let idxInt = Float.toInt(idx)
          items->Array.push({el: curr, idx: idxInt})
          if isSorted.contents && lastIdx.contents !== -1 && lastIdx.contents !== idxInt + 1 {
            isSorted := false
          }
          lastIdx := idxInt
        }
      | _ => ()
      }
    }

    if !isSorted.contents {
      items
      ->Array.toSorted((a, b) => Float.fromInt(a.idx - b.idx))
      ->Array.forEach(item => tpl->EnDom.before(item.el))
    }
  })
}

// ═══════════════════════════════════════════════════════════════════════════════
// P1: callDirectivesForLeaf uses Registry — O(1) lookup, no DOM query
// ═══════════════════════════════════════════════════════════════════════════════

let rec callDirectivesForLeaf = (
  ctx: context,
  value: unknown,
  key: string,
  isDelete: bool,
  parent: unknown,
  prop: string,
  syncCfg: option<syncConfig>,
): unit =>
  switch syncCfg {
  | Some(cfg) =>
    if cfg.skipMark && cfg.directive === "mark" {
      ()
    } else if cfg.skipConditionals && (cfg.directive === "if" || cfg.directive === "ifnot") {
      ()
    } else {
      switch ctx.directives->Map.get(cfg.directive) {
      | None => ()
      | Some(entry) =>
        entry.cb({
          el: cfg.el,
          value,
          key,
          isDelete,
          parent,
          prop,
          param: Utils.getParam(cfg.el, ctx.prefix + cfg.directive, entry.isParametric),
        })
      }
    }
  | None =>
    // P1: Registry lookup — no querySelectorAll, no query building
    Registry.lookup(ctx.registry, key)->Array.forEach(entry => {
      switch ctx.directives->Map.get(entry.directive) {
      | None => ()
      | Some(dirEntry) =>
        dirEntry.cb({el: entry.el, value, key, isDelete, parent, prop, param: entry.param})
      }
    })
  }

and callDirectivesForObject = (
  ctx: context,
  value: unknown,
  key: string,
  isDelete: bool,
): unit =>
  Js.objectKeys(value)->Array.forEach(k =>
    callDirectives(ctx, Js.getProp(value, k), Utils.getKey(k, key), isDelete, value, k, false, None)
  )

and callDirectivesForArray = (
  ctx: context,
  value: unknown,
  key: string,
  isDelete: bool,
  parent: unknown,
  prop: string,
  syncCfg: option<syncConfig>,
): unit => {
  let placeholderKey = key + ".#"
  let attrMark = ctx.prefix + "mark"

  // Find placeholder templates — still need querySelectorAll for templates
  // (templates aren't registered since they're placeholders, not bound elements)
  let query = `[${attrMark}="${placeholderKey}"]`
  let targets = switch syncCfg {
  | Some(cfg) =>
    switch cfg.el->EnDom.parentElement->Nullable.toOption {
    | Some(p) => EnDom.querySelectorAll(p, query)
    | None => EnDom.querySelectorAll(EnDom.document, query)
    }
  | None => EnDom.querySelectorAll(EnDom.document, query)
  }

  // Clear old registry entries for array item indices (items.0, items.1, etc.)
  // but NOT items.length or items.# — those are structural, not per-item
  let itemPrefix = key + "."
  let lengthKey = key + ".length"
  let toDelete = []
  ctx.registry->Js.mapForEach((_, regKey) => {
    if regKey->String.startsWith(itemPrefix) && regKey !== lengthKey {
      toDelete->Array.push(regKey)
    }
  })
  toDelete->Array.forEach(k => ctx.registry->Map.delete(k)->ignore)

  let elsArrays: array<array<EnDom.element>> = []
  targets->Array.forEach(plc => {
    let els = initializeArrayElements(ctx, plc, placeholderKey, value)
    elsArrays->Array.push(els)
  })

  let len: int = Js.cast(Js.getProp(value, "length"))
  elsArrays->Array.forEach(els => {
    for i in 0 to len - 1 {
      let idx = Int.toString(i)
      callDirectives(ctx, Js.getProp(value, idx), Utils.getKey(idx, key), isDelete, value, idx, true, None)
    }
  })

  callDirectivesForLeaf(ctx, Js.cast(len), Utils.getKey("length", key), isDelete, value, "length", None)
}

and callDirectives = (
  ctx: context,
  value: unknown,
  key: string,
  isDelete: bool,
  parent: unknown,
  prop: string,
  skipUpdateArrayElements: bool,
  syncCfg: option<syncConfig>,
): unit => {
  let isParentArr = Js.isArray(parent)

  if isParentArr && Js.isDigitString(prop) && !skipUpdateArrayElements {
    let skip = switch syncCfg { | Some(cfg) => cfg.skipMark | None => false }
    if !skip {
      updateArrayItemElement(ctx, key, prop, value, parent)
    }
  } else if isParentArr && prop === "length" {
    sortArrayItemElements(ctx, parent)
  }

  if Js.hasPrefix(value) {
    if Js.isArray(value) {
      let skip = switch syncCfg { | Some(cfg) => cfg.skipMark | None => false }
      if !skip {
        callDirectivesForArray(ctx, value, key, isDelete, parent, prop, syncCfg)
      }
    } else {
      callDirectivesForObject(ctx, value, key, isDelete)
      callDirectivesForLeaf(ctx, value, key, isDelete, parent, prop, syncCfg)
    }
  } else {
    callDirectivesForLeaf(ctx, value, key, isDelete, parent, prop, syncCfg)
  }
}

and update = (
  ctx: context,
  value: unknown,
  key: string,
  isDelete: bool,
  parent: unknown,
  prop: string,
  syncCfg: option<syncConfig>,
): unit => {
  if !ctx.destroyed {
    let isCompFn = Js.isFunction(value) && !(ctx.computedResultFns->WeakSet.has(value))
    let finalValue = if isCompFn { runComputed(ctx, value, key, parent, prop) } else { value }

    if isCompFn && Js.isUndefined(finalValue) {
      ()
    } else if Js.isPromise(finalValue) {
      let version = Computed.bumpVersion(ctx, key)
      Js.promiseThen(finalValue, resolved =>
        if Computed.isCurrentVersion(ctx, key, version) {
          update(ctx, resolved, key, false, parent, prop, syncCfg)
        }
      )
    } else {
      if syncCfg === None {
        Watchers.callWatchers(ctx, key, finalValue, k => DomQuery.getValue(ctx, k).value)
      }
      callDirectives(ctx, finalValue, key, isDelete, parent, prop, false, syncCfg)
    }
  }
}

and runComputed = (
  ctx: context,
  computedFn: unknown,
  key: string,
  parent: unknown,
  prop: string,
): unknown => {
  let version = Computed.bumpVersion(ctx, key)
  let result = Js.callFn(computedFn)
  if Js.isPromise(result) {
    Js.promiseThenCatch(
      result,
      v =>
        if Computed.isCurrentVersion(ctx, key, version) {
          update(ctx, proxyComputed(ctx, v, Some(key), Some(parent), Some(prop)), key, false, parent, prop, None)
        },
      err => Console.error3("[entropy] Async computed error at", key, err),
    )
    Js.cast(undefined)
  } else {
    proxyComputed(ctx, result, Some(key), Some(parent), Some(prop))
  }
}

and updateComputed = (ctx: context, changedKey: string): unit =>
  Computed.getDependentsOf(ctx, changedKey)->Array.forEach(dep =>
    update(ctx, dep.computed, dep.key, false, dep.parent, dep.prop, None)
  )

// Wire up update forward ref
let () = updateFnRef := update

// ═══════════════════════════════════════════════════════════════════════════════
// reactive — Proxy handler
// ═══════════════════════════════════════════════════════════════════════════════

let reactive: (context, 'a, string, option<unknown>, option<string>) => 'a = %raw(`
  function reactive(ctx, obj, prefix, parentOpt, propOpt) {
    if (obj === null) return obj;
    var isObj = typeof obj === 'object', isFn = typeof obj === 'function';
    var SYM = Symbol.for("@en/prefix");
    var parent = parentOpt !== undefined ? parentOpt : null;
    var prop = propOpt !== undefined ? propOpt : null;
    if (isFn && parent) obj = obj.bind(parent);
    if (isObj || isFn) Object.defineProperty(obj, SYM, {value:prefix, enumerable:false, writable:true, configurable:true});
    if (isFn && prop && parent) { Computed.setDependents(ctx, obj, prefix, parent, prop); return obj; }
    if (!isObj) return obj;
    var proxied = new Proxy(obj, {
      get: function(t, p, r) {
        if (typeof p === 'symbol') return Reflect.get(t, p, r);
        if (ctx.deps.isEvaluating) { var d = Object.getOwnPropertyDescriptor(t, p); if (d && d.enumerable) ctx.deps.currentSet.add(prefix===''?p:prefix+'.'+p); }
        var v = Reflect.get(t, p, r);
        if (typeof v === 'function' && SYM in v && !ctx.computedResultFns.has(v)) {
          var res = v();
          if (res instanceof Promise) return res.then(function(x) { if (typeof x==='function'){ctx.computedResultFns.add(x);return x;} return Js.clone(x); });
          if (typeof res === 'function') { ctx.computedResultFns.add(res); return res; }
          return Js.clone(res);
        }
        return v;
      },
      set: function(t, p, v, r) {
        if (typeof p === 'symbol') return Reflect.set(t, p, v, r);
        var key = prefix===''?p:prefix+'.'+p;
        var rv = reactive(ctx, v, key, r, p);
        var ok = Reflect.set(t, p, rv, r);
        scheduleUpdate(ctx, function(){update(ctx, rv, key, false, r, p, undefined);});
        scheduleUpdate(ctx, function(){updateComputed(ctx, key);});
        return ok;
      },
      deleteProperty: function(t, p) {
        if (typeof p === 'symbol') return Reflect.deleteProperty(t, p);
        var key = prefix===''?p:prefix+'.'+p;
        var ok = Reflect.deleteProperty(t, p);
        update(ctx, undefined, key, true, t, p, undefined);
        Computed.removeDependentsFor(ctx, key);
        return ok;
      },
      defineProperty: function(t, p, d) {
        if (p===SYM && SYM in t && typeof d.value==='string' && /\.\d+$/.test(d.value)) return Reflect.set(t,p,d.value);
        return Reflect.defineProperty(t, p, d);
      }
    });
    for (var k of Object.keys(obj)) obj[k] = reactive(ctx, obj[k], prefix===''?k:prefix+'.'+k, proxied, k);
    return proxied;
  }
`)

let () = reactiveRef := Js.cast(reactive)

// ═══════════════════════════════════════════════════════════════════════════════
// Bootstrap
// ═══════════════════════════════════════════════════════════════════════════════

let bootstrapDirectives = (ctx: context): unit => {
  Directives.registerBuiltins(ctx)
  ctx.directives
  ->Map.set("if", {cb: (p: directiveParams) => ifOrIfNot(ctx, p.el, p.value, p.key, If), isParametric: false})
  ->ignore
  ctx.directives
  ->Map.set("ifnot", {cb: (p: directiveParams) => ifOrIfNot(ctx, p.el, p.value, p.key, IfNot), isParametric: false})
  ->ignore
}

// ═══════════════════════════════════════════════════════════════════════════════
// batch
// ═══════════════════════════════════════════════════════════════════════════════

let batch = (ctx: context, fn: unit => unit): unit => {
  ctx.batchQueue = Some([])
  try { fn() } catch { | _ => () }
  let queue = switch ctx.batchQueue { | Some(q) => q | None => [] }
  ctx.batchQueue = None
  queue->Array.forEach(task => task())
}
