// ─── Core.res ─────────────────────────────────────────────────────────────────
// Reactive engine. Proper types — no {..}, no jsObj.
// `unknown` for dynamic reactive values, `EnDom.element` for DOM.
// `let rec ... and ...` for mutual recursion — no ref indirection.

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
// Forward ref for reactive (only used by proxyComputed — not hot loop)
// ═══════════════════════════════════════════════════════════════════════════════

let reactiveRef: ref<(context, unknown, string, option<unknown>, option<string>) => unknown> =
  ref((_, v, _, _, _) => v)

let proxyComputed = (
  ctx: context,
  value: unknown,
  key: option<string>,
  parent: option<unknown>,
  prop: option<string>,
): unknown => {
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
}

// ═══════════════════════════════════════════════════════════════════════════════
// DOM helpers — %raw only where genuinely unavoidable
// ═══════════════════════════════════════════════════════════════════════════════

let ifOrIfNot: (
  context,
  EnDom.element,
  unknown,
  string,
  conditionalType,
  (context, EnDom.element, bool) => unit,
) => unit = %raw(`
  function(ctx, el, value, key, type, syncNodeFn) {
    var isShow = type === "If" ? !!value : !value;
    var isTemplate = el instanceof HTMLTemplateElement;
    var attrType = ctx.prefix + (type === "If" ? "if" : "ifnot");
    var attrMark = ctx.prefix + "mark";
    if (isShow && isTemplate) {
      var children = Array.from(el.content.children);
      if (!children.length) return;
      children.forEach(function(child) {
        var clone = child.cloneNode(true);
        clone.setAttribute(attrType, key);
        syncNodeFn(ctx, clone, true);
        el.before(clone);
      });
      el.remove();
    }
    if (!isShow && !isTemplate) {
      if (!el.parentNode) return;
      var siblings = [el];
      var next = el.nextElementSibling;
      while (next && next.getAttribute(attrType) === key) { siblings.push(next); next = next.nextElementSibling; }
      var temp = document.createElement('template');
      siblings.forEach(function(s) { temp.content.appendChild(s.cloneNode(true)); });
      temp.setAttribute(attrType, key);
      var mark = el.getAttribute(attrMark);
      if (mark) temp.setAttribute(attrMark, mark);
      el.replaceWith(temp);
      siblings.slice(1).forEach(function(s) { s.remove(); });
    }
  }
`)

let syncDirectivesImpl: (
  context,
  EnDom.element,
  bool,
  bool,
  (context, unknown, string, bool, unknown, string, option<syncConfig>) => unit,
) => unit = %raw(`
  function(ctx, el, skipConditionals, skipMark, updateFn) {
    ctx.directives.forEach(function(dirEntry, name) {
      if (skipMark && name === 'mark') return;
      if (skipConditionals && (name === 'if' || name === 'ifnot')) return;
      var attrFull = ctx.prefix + name;
      var key = el.getAttribute(attrFull);
      if (dirEntry.isParametric && key) key = key.split(':')[0];
      if (key && key.endsWith('.#')) key = key.slice(0, -2);
      if (key === null) return;
      var result = DomQuery.getValue(ctx, key);
      if (!result.parent) return;
      updateFn(ctx, result.value, key, false, result.parent, result.prop, {
        directive: name, el: el, skipConditionals: skipConditionals, skipMark: skipMark
      });
    });
  }
`)

let syncNodeImpl: (
  context, EnDom.element, bool,
  (context, unknown, string, bool, unknown, string, option<syncConfig>) => unit,
) => unit = %raw(`
  function syncNodeImpl(ctx, el, isSyncRoot, updateFn) {
    Array.from(el.children).forEach(function(c) { syncNodeImpl(ctx, c, false, updateFn); });
    syncDirectivesImpl(ctx, el, isSyncRoot, false, updateFn);
  }
`)

let syncCloneImpl: (
  context, EnDom.element,
  (context, unknown, string, bool, unknown, string, option<syncConfig>) => unit,
) => unit = %raw(`
  function syncCloneImpl(ctx, clone, updateFn) {
    Array.from(clone.children).forEach(function(c) { syncCloneImpl(ctx, c, updateFn); });
    syncDirectivesImpl(ctx, clone, false, true, updateFn);
  }
`)

// ═══════════════════════════════════════════════════════════════════════════════
// Array DOM management
// ═══════════════════════════════════════════════════════════════════════════════

let initializeArrayElements: (
  context, EnDom.element, string, unknown,
  (context, unknown, string, bool, unknown, string, option<syncConfig>) => unit,
) => array<EnDom.element> = %raw(`
  function(ctx, plc, placeholderKey, array, updateFn) {
    var attrMark = ctx.prefix + 'mark';
    var prev = plc.previousElementSibling;
    while (prev) {
      var curr = prev; prev = curr.previousElementSibling;
      var k = curr.getAttribute(attrMark);
      if (!k) continue;
      if (k !== placeholderKey && k.replace(/\d+$/, '#') === placeholderKey) curr.remove();
      else break;
    }
    var template, placeholder;
    if (plc instanceof HTMLTemplateElement) {
      template = plc; placeholder = plc.content.firstElementChild;
      if (placeholder) placeholder.setAttribute(attrMark, placeholderKey);
    } else {
      placeholder = plc; template = document.createElement('template');
      template.content.appendChild(plc.cloneNode(true));
      template.setAttribute(attrMark, placeholderKey); plc.replaceWith(template);
    }
    if (!placeholder) return [];
    var prefix = placeholderKey.slice(0, -2), elements = [], len = array.length;
    var attrNames = []; ctx.directives.forEach(function(_, n) { attrNames.push(ctx.prefix + n); });
    for (var i = 0; i < len; i++) {
      var clone = placeholder.cloneNode(true);
      if (!(clone instanceof Element)) continue;
      var key = prefix === '' ? String(i) : prefix + '.' + i;
      for (var j = 0; j < attrNames.length; j++) {
        var cur = clone.getAttribute(attrNames[j]);
        if (cur && cur.startsWith(placeholderKey)) clone.setAttribute(attrNames[j], key + cur.slice(placeholderKey.length));
      }
      clone.querySelectorAll('*').forEach(function(child) {
        for (var j = 0; j < attrNames.length; j++) {
          var cur = child.getAttribute(attrNames[j]);
          if (cur && cur.startsWith(placeholderKey)) child.setAttribute(attrNames[j], key + cur.slice(placeholderKey.length));
        }
      });
      template.before(clone); syncCloneImpl(ctx, clone, updateFn); elements.push(clone);
    }
    return elements;
  }
`)

let updateArrayItemElement: (
  context, string, string, unknown, unknown,
  (context, unknown, string, bool, unknown, string, option<syncConfig>) => unit,
) => unit = %raw(`
  function(ctx, key, idx, item, array, updateFn) {
    var attrMark = ctx.prefix + 'mark', SYM = Symbol.for("@en/prefix");
    var arrayItems = document.querySelectorAll('[' + attrMark + '="' + key + '"]');
    if (arrayItems.length && (typeof item !== 'object' || item === null || !(SYM in item))) return;
    var prefix = array[SYM] || '', placeholderKey = key.replace(/\d+$/, '#'), itemReplaced = false;
    Array.from(arrayItems).forEach(function(el) {
      var ph = el.nextElementSibling;
      while (ph) { if (ph.getAttribute(attrMark) === placeholderKey) break; ph = ph.nextElementSibling; }
      var cl = null;
      if (ph instanceof HTMLTemplateElement) { var c = ph.content.firstElementChild; cl = c ? c.cloneNode(true) : null; }
      else if (ph && ph.getAttribute(attrMark) === placeholderKey) cl = ph.cloneNode(true);
      if (!cl) return;
      var attrNames = []; ctx.directives.forEach(function(_, n) { attrNames.push(ctx.prefix + n); });
      var k = prefix === '' ? idx : prefix + '.' + idx;
      for (var j = 0; j < attrNames.length; j++) {
        var cur = cl.getAttribute(attrNames[j]);
        if (cur && cur.startsWith(placeholderKey)) cl.setAttribute(attrNames[j], k + cur.slice(placeholderKey.length));
      }
      cl.querySelectorAll('*').forEach(function(child) {
        for (var j = 0; j < attrNames.length; j++) {
          var cur = child.getAttribute(attrNames[j]);
          if (cur && cur.startsWith(placeholderKey)) child.setAttribute(attrNames[j], k + cur.slice(placeholderKey.length));
        }
      });
      el.replaceWith(cl); syncCloneImpl(ctx, cl, updateFn); itemReplaced = true;
    });
    if (itemReplaced) return;
    Array.from(document.querySelectorAll('[' + attrMark + '="' + placeholderKey + '"]')).forEach(function(tpl) {
      if (!(tpl instanceof HTMLTemplateElement)) return;
      var clone = tpl.content.firstElementChild; if (!clone) return; clone = clone.cloneNode(true);
      var attrNames = []; ctx.directives.forEach(function(_, n) { attrNames.push(ctx.prefix + n); });
      var k = prefix === '' ? idx : prefix + '.' + idx;
      for (var j = 0; j < attrNames.length; j++) {
        var cur = clone.getAttribute(attrNames[j]);
        if (cur && cur.startsWith(placeholderKey)) clone.setAttribute(attrNames[j], k + cur.slice(placeholderKey.length));
      }
      clone.querySelectorAll('*').forEach(function(child) {
        for (var j = 0; j < attrNames.length; j++) {
          var cur = child.getAttribute(attrNames[j]);
          if (cur && cur.startsWith(placeholderKey)) child.setAttribute(attrNames[j], k + cur.slice(placeholderKey.length));
        }
      });
      tpl.before(clone); syncCloneImpl(ctx, clone, updateFn);
    });
  }
`)

let sortArrayItemElements: (context, unknown) => unit = %raw(`
  function(ctx, array) {
    var attrMark = ctx.prefix + 'mark', SYM = Symbol.for("@en/prefix");
    var prefix = array[SYM] || '';
    var templateKey = prefix === '' ? '#' : prefix + '.#', templatePrefix = templateKey.slice(0, -1);
    Array.from(document.querySelectorAll('[' + attrMark + '="' + templateKey + '"]')).forEach(function(tpl) {
      var items = [], prev = tpl.previousElementSibling, isSorted = true, lastIdx = -1;
      while (prev) {
        var curr = prev; prev = curr.previousElementSibling;
        var k = curr.getAttribute(attrMark); if (!k) continue; if (k === templateKey) break;
        if (k.startsWith(templatePrefix)) {
          var idx = +(k.slice(templatePrefix.length));
          if (!isNaN(idx)) { items.push({el:curr,idx:idx}); if (isSorted && lastIdx!==-1 && lastIdx!==idx+1) isSorted=false; lastIdx=idx; }
        }
      }
      if (isSorted) return;
      items.sort(function(a,b){return a.idx-b.idx;}).forEach(function(it){tpl.before(it.el);});
    });
  }
`)

// ═══════════════════════════════════════════════════════════════════════════════
// Mutual recursion: callDirectives ↔ update (no ref indirection)
// ═══════════════════════════════════════════════════════════════════════════════

let rec callDirectivesForLeaf = (
  ctx: context,
  value: unknown,
  key: string,
  isDelete: bool,
  parent: unknown,
  prop: string,
  searchRoot: option<EnDom.element>,
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
    let prefix = ctx.prefix
    ctx.directives->Js.mapForEach((entry, attrSuffix) => {
      let attrName = prefix + attrSuffix
      let query = if entry.isParametric {
        `[${attrName}^='${key}:']`
      } else {
        `[${attrName}='${key}']`
      }

      let elements = switch searchRoot {
      | Some(root) => DomQuery.queryAll(ctx, root, query)
      | None => DomQuery.queryAllDoc(ctx, query)
      }

      elements->Array.forEach(el =>
        entry.cb({
          el,
          value,
          key,
          isDelete,
          parent,
          prop,
          param: Utils.getParam(el, attrName, entry.isParametric),
        })
      )

      // Check root element itself for scoped searches
      switch searchRoot {
      | Some(root) =>
        switch root->EnDom.getAttribute(attrName) {
        | Some(attr) if attr === key =>
          entry.cb({
            el: root,
            value,
            key,
            isDelete,
            parent,
            prop,
            param: Utils.getParam(root, attrName, entry.isParametric),
          })
        | _ => ()
        }
      | None => ()
      }
    })
  }

and callDirectivesForObject = (
  ctx: context,
  value: unknown,
  key: string,
  isDelete: bool,
  searchRoot: option<EnDom.element>,
): unit =>
  Js.objectKeys(value)->Array.forEach(k =>
    callDirectives(
      ctx,
      Js.getProp(value, k),
      Utils.getKey(k, key),
      isDelete,
      value,
      k,
      searchRoot,
      false,
      None,
    )
  )

and callDirectivesForArray = (
  ctx: context,
  value: unknown,
  key: string,
  isDelete: bool,
  parent: unknown,
  prop: string,
  searchRoot: option<EnDom.element>,
  syncCfg: option<syncConfig>,
): unit => {
  let placeholderKey = key + ".#"
  let attrMark = ctx.prefix + "mark"
  let query = `[${attrMark}="${placeholderKey}"]`

  let targets = switch syncCfg {
  | Some(cfg) =>
    switch cfg.el->EnDom.parentElement->Nullable.toOption {
    | Some(p) => DomQuery.queryAll(ctx, p, query)
    | None => DomQuery.queryAllDoc(ctx, query)
    }
  | None => DomQuery.queryAllDoc(ctx, query)
  }

  let elsArrays: array<array<EnDom.element>> = []
  targets->Array.forEach(plc => {
    let els = initializeArrayElements(ctx, plc, placeholderKey, value, update)
    elsArrays->Array.push(els)
  })

  let len: int = Js.cast(Js.getProp(value, "length"))
  elsArrays->Array.forEach(els => {
    for i in 0 to len - 1 {
      let idx = Int.toString(i)
      let childEl = els->Array.get(i)
      callDirectives(
        ctx,
        Js.getProp(value, idx),
        Utils.getKey(idx, key),
        isDelete,
        value,
        idx,
        childEl,
        true,
        None,
      )
    }
  })

  callDirectivesForLeaf(
    ctx,
    Js.cast(len),
    Utils.getKey("length", key),
    isDelete,
    value,
    "length",
    searchRoot,
    None,
  )
}

and callDirectives = (
  ctx: context,
  value: unknown,
  key: string,
  isDelete: bool,
  parent: unknown,
  prop: string,
  searchRoot: option<EnDom.element>,
  skipUpdateArrayElements: bool,
  syncCfg: option<syncConfig>,
): unit => {
  let isParentArr = Js.isArray(parent)

  if isParentArr && Js.isDigitString(prop) && !skipUpdateArrayElements {
    let skip = switch syncCfg {
    | Some(cfg) => cfg.skipMark
    | None => false
    }
    if !skip {
      updateArrayItemElement(ctx, key, prop, value, parent, update)
    }
  } else if isParentArr && prop === "length" {
    sortArrayItemElements(ctx, parent)
  }

  if Js.hasPrefix(value) {
    if Js.isArray(value) {
      let skip = switch syncCfg {
      | Some(cfg) => cfg.skipMark
      | None => false
      }
      if !skip {
        callDirectivesForArray(ctx, value, key, isDelete, parent, prop, searchRoot, syncCfg)
      }
    } else {
      callDirectivesForObject(ctx, value, key, isDelete, searchRoot)
      callDirectivesForLeaf(ctx, value, key, isDelete, parent, prop, searchRoot, syncCfg)
    }
  } else {
    callDirectivesForLeaf(ctx, value, key, isDelete, parent, prop, searchRoot, syncCfg)
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
  if ctx.destroyed {
    ()
  } else {
    let isCompFn =
      Js.isFunction(value) && !(ctx.computedResultFns->WeakSet.has(value))

    let finalValue = if isCompFn {
      runComputed(ctx, value, key, parent, prop)
    } else {
      value
    }

    if isCompFn && Js.isUndefined(finalValue) {
      () // async — will re-enter when resolved
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
      callDirectives(ctx, finalValue, key, isDelete, parent, prop, None, false, syncCfg)
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
          let proxied = proxyComputed(ctx, v, Some(key), Some(parent), Some(prop))
          update(ctx, proxied, key, false, parent, prop, None)
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

// ═══════════════════════════════════════════════════════════════════════════════
// reactive — Proxy handler (genuinely needs %raw — Proxy is a JS concept)
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
  ->Map.set(
    "if",
    {
      cb: (params: directiveParams) =>
        ifOrIfNot(ctx, params.el, params.value, params.key, If, (ctx, el, isSyncRoot) =>
          syncNodeImpl(ctx, el, isSyncRoot, update)
        ),
      isParametric: false,
    },
  )
  ->ignore
  ctx.directives
  ->Map.set(
    "ifnot",
    {
      cb: (params: directiveParams) =>
        ifOrIfNot(ctx, params.el, params.value, params.key, IfNot, (ctx, el, isSyncRoot) =>
          syncNodeImpl(ctx, el, isSyncRoot, update)
        ),
      isParametric: false,
    },
  )
  ->ignore
}

// ═══════════════════════════════════════════════════════════════════════════════
// batch
// ═══════════════════════════════════════════════════════════════════════════════

let batch = (ctx: context, fn: unit => unit): unit => {
  ctx.batchQueue = Some([])
  try { fn() } catch { | _ => () }
  let queue = switch ctx.batchQueue {
  | Some(q) => q
  | None => []
  }
  ctx.batchQueue = None
  queue->Array.forEach(task => task())
}
