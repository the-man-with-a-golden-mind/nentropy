// ─── Entropy.res ──────────────────────────────────────────────────────────────
// Entry point — JS-compatible API shape.

let createInstance: unit => {..} = %raw(`
  function() {
    var inst = Instance.make();
    return {
      init: function() { return Instance.init(inst); },
      computed: Instance.computed,
      watch: function(key, fn) { return Instance.watch(inst, key, fn); },
      unwatch: function(key, fn) { return Instance.unwatch(inst, key, fn); },
      directive: function(name, cb, isParametric) {
        return Instance.directive(inst, name, cb, isParametric || false);
      },
      prefix: function(value) { return Instance.prefix(inst, value || 'en'); },
      cache: function(enabled) { return Instance.cache(inst, enabled); },
      batch: function(fn) { return Instance.batch(inst, fn); },
      load: function(files) {
        return Instance.load(inst, Array.isArray(files) ? files : [files]);
      },
      register: function(root) {
        if (typeof root === 'string') {
          var el = document.createElement('div'); el.innerHTML = root;
          return Instance.register(inst, el);
        }
        return Instance.register(inst, root || undefined);
      },
      destroy: function() { return Instance.destroy(inst); }
    };
  }
`)

let default = createInstance()
let computed = Instance.computed
