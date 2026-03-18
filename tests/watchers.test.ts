import { describe, it, expect, vi } from 'vitest';
import { setup } from './helpers';

describe('watch', () => {
  it('fires watcher on key change', () => {
    const { en, data, cleanup } = setup();
    const spy = vi.fn();
    data.count = 0;
    en.watch('count', spy);
    data.count = 1;
    expect(spy).toHaveBeenCalledWith(1);
    cleanup();
  });

  it('fires watcher on nested key change', () => {
    const { en, data, cleanup } = setup();
    const spy = vi.fn();
    data.user = { name: 'Alice' };
    en.watch('user.name', spy);
    data.user.name = 'Bob';
    expect(spy).toHaveBeenCalledWith('Bob');
    cleanup();
  });

  it('fires ancestor watcher when child changes', () => {
    const { en, data, cleanup } = setup();
    const spy = vi.fn();
    data.user = { name: 'Alice', age: 30 };
    en.watch('user', spy);
    data.user.name = 'Bob';
    expect(spy).toHaveBeenCalled();
    // Should receive the whole user object
    const arg = spy.mock.calls[0][0];
    expect(arg.name).toBe('Bob');
    cleanup();
  });

  it('does not fire watcher for unrelated key', () => {
    const { en, data, cleanup } = setup();
    const spy = vi.fn();
    data.a = 1;
    data.b = 2;
    en.watch('a', spy);
    data.b = 3;
    expect(spy).not.toHaveBeenCalled();
    cleanup();
  });
});

describe('unwatch', () => {
  it('removes a specific watcher', () => {
    const { en, data, cleanup } = setup();
    const spy = vi.fn();
    data.x = 0;
    en.watch('x', spy);
    en.unwatch('x', spy);
    data.x = 1;
    expect(spy).not.toHaveBeenCalled();
    cleanup();
  });

  it('removes all watchers for a key', () => {
    const { en, data, cleanup } = setup();
    const spy1 = vi.fn();
    const spy2 = vi.fn();
    data.x = 0;
    en.watch('x', spy1);
    en.watch('x', spy2);
    en.unwatch('x');
    data.x = 1;
    expect(spy1).not.toHaveBeenCalled();
    expect(spy2).not.toHaveBeenCalled();
    cleanup();
  });

  it('removes all watchers when called with no args', () => {
    const { en, data, cleanup } = setup();
    const spy1 = vi.fn();
    const spy2 = vi.fn();
    data.a = 0;
    data.b = 0;
    en.watch('a', spy1);
    en.watch('b', spy2);
    en.unwatch();
    data.a = 1;
    data.b = 1;
    expect(spy1).not.toHaveBeenCalled();
    expect(spy2).not.toHaveBeenCalled();
    cleanup();
  });
});
