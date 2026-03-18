import { describe, it, expect, vi } from 'vitest';
import { setup, tick, flush } from './helpers';

describe('computed (sync)', () => {
  it('returns computed value from dependencies', () => {
    const { en, data, q, cleanup } = setup(`<span en-mark="full"></span>`);
    data.first = 'Jane';
    data.last = 'Doe';
    data.full = en.computed(() => `${data.first} ${data.last}`);
    expect(q('span').textContent).toBe('Jane Doe');
    cleanup();
  });

  it('re-evaluates when a dependency changes', () => {
    const { en, data, q, cleanup } = setup(`<span en-mark="full"></span>`);
    data.first = 'Jane';
    data.last = 'Doe';
    data.full = en.computed(() => `${data.first} ${data.last}`);
    data.first = 'John';
    expect(q('span').textContent).toBe('John Doe');
    cleanup();
  });

  it('does not re-evaluate when an unrelated key changes', () => {
    const { en, data, cleanup } = setup();
    const fn = vi.fn(() => `${data.a}`);
    data.a = 1;
    data.b = 100;
    data.result = en.computed(fn);
    const callsBefore = fn.mock.calls.length;
    data.b = 200;
    expect(fn.mock.calls.length).toBe(callsBefore);
    cleanup();
  });

  it('supports chained computed values', () => {
    const { en, data, q, cleanup } = setup(`<span en-mark="exclaimed"></span>`);
    data.name = 'World';
    data.greeting = en.computed(() => `Hello, ${data.name}`);
    data.exclaimed = en.computed(() => `${data.greeting}!`);
    expect(q('span').textContent).toBe('Hello, World!');
    data.name = 'entropy';
    expect(q('span').textContent).toBe('Hello, entropy!');
    cleanup();
  });
});

describe('computed (async)', () => {
  it('resolves async computed value into DOM', async () => {
    const { en, data, q, cleanup } = setup(`<span en-mark="label"></span>`);
    data.id = 1;
    data.label = en.computed(async () => {
      await tick();
      return `Item #${data.id}`;
    });
    await flush();
    expect(q('span').textContent).toBe('Item #1');
    cleanup();
  });

  it('discards stale async results on rapid changes', async () => {
    const { en, data, q, cleanup } = setup(`<span en-mark="result"></span>`);
    let resolveFirst!: (v: string) => void;
    let resolveSecond!: (v: string) => void;
    let calls = 0;

    data.input = 'a';
    data.result = en.computed(() => {
      const val = data.input;
      const call = ++calls;
      return call === 1
        ? new Promise<string>(r => { resolveFirst = r; })
        : new Promise<string>(r => { resolveSecond = r; });
    });

    data.input = 'b';
    resolveSecond('resolved: b');
    await flush();
    resolveFirst('resolved: a');
    await flush();
    expect(q('span').textContent).toBe('resolved: b');
    cleanup();
  });
});
