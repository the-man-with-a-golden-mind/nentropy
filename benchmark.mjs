#!/usr/bin/env node
/**
 * Headless benchmark — TypeScript vs ReScript entropy
 * Runs in Node.js with happy-dom for DOM simulation.
 * Usage: node benchmark.mjs
 */

import { Window } from 'happy-dom';
import { readFileSync } from 'fs';
import { performance } from 'perf_hooks';

// Set up DOM globals
const win = new Window({ url: 'http://localhost' });
for (const key of ['document', 'HTMLElement', 'HTMLTemplateElement', 'HTMLInputElement',
  'HTMLTextAreaElement', 'HTMLSelectElement', 'Element', 'Document', 'Node',
  'MutationObserver', 'customElements', 'Event', 'DocumentFragment']) {
  globalThis[key] = win[key];
}
globalThis.window = win;
globalThis.document = win.document;

// ── Load both implementations ───────────────────────────────────────────────

function loadIIFE(path) {
  const code = readFileSync(path, 'utf-8');
  const fn = new Function('exports', code + '\nreturn UEntropy;');
  return fn({});
}

const TS = loadIIFE(new URL('../entropy/dist/entropy.min.js', import.meta.url).pathname);
const RS = loadIIFE(new URL('dist/entropy.min.js', import.meta.url).pathname);

// ── Benchmark infrastructure ────────────────────────────────────────────────

const RUNS = 7;
const WARMUP = 2;

function median(arr) {
  const s = [...arr].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

function bench(name, fn) {
  // Warmup
  for (let i = 0; i < WARMUP; i++) fn();
  // Measure
  const times = [];
  for (let i = 0; i < RUNS; i++) {
    // Clean DOM between runs to prevent happy-dom accumulation
    document.body.innerHTML = '';
    const t0 = performance.now();
    fn();
    times.push(performance.now() - t0);
  }
  return median(times);
}

function runBench(name, tsFn, rsFn) {
  // Reset DOM completely between implementations to prevent happy-dom
  // accumulating detached nodes that slow querySelectorAll.
  while (document.body.firstChild) document.body.firstChild.remove();
  const tsMs = bench(name + '-ts', tsFn);
  while (document.body.firstChild) document.body.firstChild.remove();
  const rsMs = bench(name + '-rs', rsFn);
  while (document.body.firstChild) document.body.firstChild.remove();
  return { name, tsMs, rsMs };
}

function makeSandbox() {
  const el = document.createElement('div');
  document.body.appendChild(el);
  return el;
}

// ── Benchmarks ──────────────────────────────────────────────────────────────

const benchmarks = [
  {
    name: '1. Instance create+init (1000×)',
    run(lib) {
      for (let i = 0; i < 1000; i++) {
        const en = lib.createInstance();
        en.init();
        en.destroy();
      }
    }
  },
  {
    name: '2. Primitive set/get (50k)',
    run(lib) {
      const en = lib.createInstance();
      const data = en.init();
      for (let i = 0; i < 50000; i++) data['k' + (i % 100)] = i;
      let s = 0;
      for (let i = 0; i < 50000; i++) s += data['k' + (i % 100)];
      en.destroy();
    }
  },
  {
    name: '3. Nested objects (10k)',
    run(lib) {
      const en = lib.createInstance();
      const data = en.init();
      for (let i = 0; i < 10000; i++) data['o' + (i % 50)] = { a: { b: { c: i } } };
      en.destroy();
    }
  },
  {
    name: '4. Array mutations (push+splice+assign)',
    run(lib) {
      const en = lib.createInstance();
      const data = en.init();
      data.list = [];
      for (let i = 0; i < 1000; i++) data.list.push(i);
      for (let i = 0; i < 500; i++) data.list.splice(0, 1);
      for (let i = 0; i < 100; i++) data.list = Array.from({ length: 50 }, (_, j) => i * 50 + j);
      en.destroy();
    }
  },
  {
    name: '5. Computed re-eval (20k)',
    run(lib) {
      const en = lib.createInstance();
      const data = en.init();
      data.a = 0; data.b = 0;
      data.sum = en.computed(() => data.a + data.b);
      for (let i = 0; i < 10000; i++) { data.a = i; data.b = i * 2; }
      en.destroy();
    }
  },
  {
    name: '6. Watcher dispatch (20k fires)',
    run(lib) {
      const en = lib.createInstance();
      const data = en.init();
      data.val = 0;
      let acc = 0;
      for (let w = 0; w < 10; w++) en.watch('val', v => { acc += v; });
      for (let i = 0; i < 2000; i++) data.val = i;
      en.destroy();
    }
  },
  {
    name: '7. Directive fire (5k)',
    run(lib) {
      const sandbox = makeSandbox();
      sandbox.innerHTML = Array.from({ length: 50 }, () => '<span en-mark="val"></span>').join('');
      const en = lib.createInstance();
      const data = en.init();
      for (let i = 0; i < 100; i++) data.val = 'u-' + i;
      en.destroy();
      sandbox.remove();
    }
  },
  {
    name: '8. Batch (50 × 20 props)',
    run(lib) {
      const sandbox = makeSandbox();
      sandbox.innerHTML = Array.from({ length: 20 }, (_, i) => `<span en-mark="p${i}"></span>`).join('');
      const en = lib.createInstance();
      const data = en.init();
      for (let i = 0; i < 20; i++) data['p' + i] = 0;
      for (let r = 0; r < 50; r++) {
        en.batch(() => { for (let i = 0; i < 20; i++) data['p' + i] = r * 20 + i; });
      }
      en.destroy();
      sandbox.remove();
    }
  },
  {
    name: '9. DOM array render (500 × 10)',
    run(lib) {
      const sandbox = makeSandbox();
      sandbox.innerHTML = '<ul><li en-mark="items.#"></li></ul>';
      const en = lib.createInstance();
      const data = en.init();
      for (let r = 0; r < 10; r++) {
        data.items = Array.from({ length: 500 }, (_, i) => `item-${r}-${i}`);
      }
      en.destroy();
      sandbox.remove();
    }
  },
  {
    name: '10. Mixed realistic workload',
    run(lib) {
      const sandbox = makeSandbox();
      sandbox.innerHTML = `
        <div en-mark="title"></div><span en-mark="count"></span>
        <template en-if="show"><p en-mark="msg"></p></template>
        <ul><li en-mark="todos.#"></li></ul>`;
      const en = lib.createInstance();
      const data = en.init();
      data.title = 'App'; data.show = false; data.msg = ''; data.todos = [];
      data.count = en.computed(() => data.todos ? data.todos.length : 0);
      let wc = 0;
      en.watch('todos', () => { wc++; });
      for (let i = 0; i < 200; i++) {
        en.batch(() => {
          data.todos = [...(data.todos || []), `Todo ${i}`];
          data.title = `App (${i + 1})`;
          data.show = i % 3 === 0;
          data.msg = data.show ? `Show ${i}` : '';
        });
      }
      for (let i = 0; i < 50; i++) data.todos = data.todos.slice(1);
      en.destroy();
      sandbox.remove();
    }
  },
];

// ── Run ─────────────────────────────────────────────────────────────────────

console.log('');
console.log('⚡ uentropy Benchmark — TypeScript vs ReScript');
console.log('─'.repeat(72));
console.log(`  ${RUNS} runs per benchmark (median), ${WARMUP} warmup rounds`);
console.log('');

const PAD_NAME = 38;
const PAD_NUM = 10;

console.log(
  'Benchmark'.padEnd(PAD_NAME) +
  'TS (ms)'.padStart(PAD_NUM) +
  'RS (ms)'.padStart(PAD_NUM) +
  '  Result'
);
console.log('─'.repeat(72));

let totalTs = 0, totalRs = 0, rsWins = 0, tsWins = 0, ties = 0;
const allResults = [];

for (const b of benchmarks) {
  const result = runBench(b.name, () => b.run(TS), () => b.run(RS));
  allResults.push(result);
  totalTs += result.tsMs;
  totalRs += result.rsMs;

  const ratio = result.tsMs / result.rsMs;
  let tag;
  if (Math.abs(ratio - 1) < 0.05) {
    tag = '  ~tie'; ties++;
  } else if (result.rsMs < result.tsMs) {
    const pct = ((1 - result.rsMs / result.tsMs) * 100).toFixed(1);
    tag = `  ✓ RS ${pct}% faster`; rsWins++;
  } else {
    const pct = ((1 - result.tsMs / result.rsMs) * 100).toFixed(1);
    tag = `  ✗ TS ${pct}% faster`; tsWins++;
  }

  console.log(
    result.name.padEnd(PAD_NAME) +
    result.tsMs.toFixed(2).padStart(PAD_NUM) +
    result.rsMs.toFixed(2).padStart(PAD_NUM) +
    tag
  );
}

console.log('─'.repeat(72));
console.log(
  'TOTAL'.padEnd(PAD_NAME) +
  totalTs.toFixed(2).padStart(PAD_NUM) +
  totalRs.toFixed(2).padStart(PAD_NUM)
);
console.log('');
const overall = totalRs < totalTs ? 'ReScript' : 'TypeScript';
const overallPct = ((1 - Math.min(totalTs, totalRs) / Math.max(totalTs, totalRs)) * 100).toFixed(1);
console.log(`  RS wins: ${rsWins}  |  TS wins: ${tsWins}  |  Ties: ${ties}`);
console.log(`  Overall: ${overall} ~${overallPct}% faster`);
console.log(`  Bundle: TS 14K  |  RS 18K (minified)`);
console.log('');

win.close();
