import { describe, it, expect } from 'vitest';

// Import utils from compiled ReScript
import { getKey, getParam, isPrefixedObject } from '../src/Utils.res.mjs';

describe('getKey', () => {
  it('returns prop when prefix is empty', () => {
    expect(getKey('name', '')).toBe('name');
  });

  it('joins prefix and prop with dot', () => {
    expect(getKey('name', 'user')).toBe('user.name');
  });

  it('handles multi-level prefix', () => {
    expect(getKey('city', 'user.address')).toBe('user.address.city');
  });
});

describe('getParam', () => {
  it('returns undefined for non-parametric', () => {
    const el = document.createElement('div');
    el.setAttribute('en-mark', 'key:param');
    expect(getParam(el, 'en-mark', false)).toBeUndefined();
  });

  it('extracts param after colon', () => {
    const el = document.createElement('div');
    el.setAttribute('en-sort', 'sortSig:rank');
    expect(getParam(el, 'en-sort', true)).toBe('rank');
  });

  it('returns undefined when attr missing', () => {
    const el = document.createElement('div');
    expect(getParam(el, 'en-missing', true)).toBeUndefined();
  });
});
