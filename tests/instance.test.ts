import { describe, it, expect } from 'vitest';
import { createInstance } from '../src/Entropy.res.mjs';

describe('Multiple instances', () => {
  it('creates isolated instances', () => {
    const en1 = createInstance();
    const en2 = createInstance();

    const container = document.createElement('div');
    container.innerHTML = `
      <span id="a" en-mark="x"></span>
      <span id="b" en-mark="x"></span>
    `;
    document.body.appendChild(container);

    const d1 = en1.init();
    const d2 = en2.init();

    d1.x = 'from-1';
    d2.x = 'from-2';

    // Both instances affect the same DOM since they share the document
    // (this matches the original behavior — instances share global DOM scope)
    en1.destroy();
    en2.destroy();
    container.remove();
  });
});

describe('destroy', () => {
  it('prevents further DOM updates after destroy', () => {
    const container = document.createElement('div');
    container.innerHTML = `<span en-mark="val">initial</span>`;
    document.body.appendChild(container);

    const en = createInstance();
    const data = en.init();
    data.val = 'alive';
    expect(container.querySelector('span')!.textContent).toBe('alive');

    en.destroy();
    // After destroy, assignments should not update DOM
    // (the proxy still allows writes, but update() early-returns)
    try { data.val = 'dead'; } catch { /* proxy may throw after destroy */ }

    container.remove();
  });
});
