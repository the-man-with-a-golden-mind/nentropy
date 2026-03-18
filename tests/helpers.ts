/**
 * Test helpers – shared across all test files.
 * Creates a fresh entropy instance + minimal DOM fixture.
 */

import { createInstance } from '../src/Entropy.res.mjs';

export function setup(html = '') {
  const container = document.createElement('div');
  container.innerHTML = html;
  document.body.appendChild(container);

  const en = createInstance();
  const data = en.init();

  function q<T extends Element = Element>(selector: string): T {
    return container.querySelector<T>(selector)!;
  }

  function qAll<T extends Element = Element>(selector: string): T[] {
    return Array.from(container.querySelectorAll<T>(selector));
  }

  function cleanup() {
    en.destroy();
    container.remove();
  }

  return { en, data, container, q, qAll, cleanup };
}

/** Waits one microtask tick (resolves pending Promises). */
export const tick = () => new Promise<void>(r => queueMicrotask(r));

/** Waits multiple microtask ticks for async computed chains to settle. */
export const flush = async (n = 5) => {
  for (let i = 0; i < n; i++) await tick();
};
