import { describe, it, expect } from 'vitest';
import { createInstance } from '../src/Entropy.res.mjs';

describe('Custom prefix', () => {
  it('uses custom attribute prefix', () => {
    const container = document.createElement('div');
    container.innerHTML = `<span data-en-mark="msg">—</span>`;
    document.body.appendChild(container);

    const en = createInstance();
    en.prefix('data-en');
    const data = en.init();
    data.msg = 'custom prefix works';

    expect(container.querySelector('span')!.textContent).toBe('custom prefix works');

    en.destroy();
    container.remove();
  });

  it('auto-appends dash if missing', () => {
    const container = document.createElement('div');
    container.innerHTML = `<span x-mark="val">—</span>`;
    document.body.appendChild(container);

    const en = createInstance();
    en.prefix('x');
    const data = en.init();
    data.val = 'hello';

    expect(container.querySelector('span')!.textContent).toBe('hello');

    en.destroy();
    container.remove();
  });
});
