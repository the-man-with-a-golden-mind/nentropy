import { Window } from 'happy-dom';
import { readFileSync } from 'fs';
import { performance } from 'perf_hooks';

const win = new Window({ url: 'http://localhost' });
for (const key of ['document','HTMLElement','HTMLTemplateElement','HTMLInputElement',
  'HTMLTextAreaElement','HTMLSelectElement','Element','Document','Node',
  'MutationObserver','customElements','Event','DocumentFragment']) {
  globalThis[key] = win[key];
}
globalThis.window = win;
globalThis.document = win.document;

function loadIIFE(p) {
  const fn = new Function('exports', readFileSync(p, 'utf8') + '\nreturn UEntropy;');
  return fn({});
}

function profile(label, lib) {
  const sandbox = document.createElement('div');
  sandbox.innerHTML = `
    <div en-mark="title"></div><span en-mark="count"></span>
    <template en-if="show"><p en-mark="msg"></p></template>
    <ul><li en-mark="todos.#"></li></ul>`;
  document.body.appendChild(sandbox);

  const en = lib.createInstance();
  const data = en.init();
  data.title = 'App'; data.show = false; data.msg = ''; data.todos = [];
  data.count = en.computed(() => data.todos ? data.todos.length : 0);
  en.watch('todos', () => {});

  // Phase 1: Growing
  let t0 = performance.now();
  for (let i = 0; i < 200; i++) {
    en.batch(() => {
      data.todos = [...(data.todos || []), `Todo ${i}`];
      data.title = `App (${i + 1})`;
      data.show = i % 3 === 0;
      data.msg = data.show ? `Show ${i}` : '';
    });
  }
  const growMs = performance.now() - t0;

  // Phase 2: Shrinking
  t0 = performance.now();
  for (let i = 0; i < 50; i++) {
    data.todos = data.todos.slice(1);
  }
  const shrinkMs = performance.now() - t0;

  en.destroy();
  sandbox.remove();

  console.log(`${label}: grow=${growMs.toFixed(1)}ms  shrink=${shrinkMs.toFixed(1)}ms  total=${(growMs+shrinkMs).toFixed(1)}ms`);
}

const TS = loadIIFE(new URL('../entropy/dist/entropy.min.js', import.meta.url).pathname);
const RS = loadIIFE(new URL('dist/entropy.min.js', import.meta.url).pathname);

// Warmup
profile('TS warmup', TS);
profile('RS warmup', RS);

// Measured
profile('TS', TS);
profile('RS', RS);
profile('TS', TS);
profile('RS', RS);

win.close();
