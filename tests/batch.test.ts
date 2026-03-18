import { describe, it, expect, vi } from 'vitest';
import { setup } from './helpers';

describe('batch', () => {
  it('batches multiple changes into a single update pass', () => {
    const { en, data, q, cleanup } = setup(`
      <span en-mark="firstName"></span>
      <span en-mark="lastName"></span>
    `);
    const spy = vi.fn();
    en.watch('firstName', spy);

    data.firstName = 'initial';
    spy.mockClear();

    en.batch(() => {
      data.firstName = 'Jane';
      data.lastName = 'Doe';
    });

    // Watcher should have been called (after batch flush)
    expect(spy).toHaveBeenCalledWith('Jane');
    expect(q('[en-mark="firstName"]').textContent).toBe('Jane');
    expect(q('[en-mark="lastName"]').textContent).toBe('Doe');
    cleanup();
  });

  it('flushes even if fn throws', () => {
    const { en, data, q, cleanup } = setup(`<span en-mark="val"></span>`);
    data.val = 'before';

    try {
      en.batch(() => {
        data.val = 'after';
        throw new Error('boom');
      });
    } catch { /* expected */ }

    expect(q('span').textContent).toBe('after');
    cleanup();
  });
});
