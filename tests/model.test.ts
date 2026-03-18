import { describe, it, expect } from 'vitest';
import { setup } from './helpers';

describe('en-model directive', () => {
  it('syncs data → text input', () => {
    const { data, q, cleanup } = setup(`<input en-model="name" />`);
    data.name = 'Alice';
    expect(q<HTMLInputElement>('input').value).toBe('Alice');
    cleanup();
  });

  it('syncs data → checkbox', () => {
    const { data, q, cleanup } = setup(`<input type="checkbox" en-model="on" />`);
    data.on = true;
    expect(q<HTMLInputElement>('input').checked).toBe(true);
    data.on = false;
    expect(q<HTMLInputElement>('input').checked).toBe(false);
    cleanup();
  });

  it('syncs data → select', () => {
    const { data, q, cleanup } = setup(`
      <select en-model="choice">
        <option value="a">A</option>
        <option value="b">B</option>
      </select>
    `);
    data.choice = 'b';
    expect(q<HTMLSelectElement>('select').value).toBe('b');
    cleanup();
  });

  it('syncs text input → data on input event', () => {
    const { data, q, cleanup } = setup(`<input en-model="name" />`);
    data.name = '';
    const input = q<HTMLInputElement>('input');
    input.value = 'Bob';
    input.dispatchEvent(new Event('input'));
    expect(data.name).toBe('Bob');
    cleanup();
  });

  it('syncs checkbox → data on change event', () => {
    const { data, q, cleanup } = setup(`<input type="checkbox" en-model="on" />`);
    data.on = false;
    const input = q<HTMLInputElement>('input');
    input.checked = true;
    input.dispatchEvent(new Event('change'));
    expect(data.on).toBe(true);
    cleanup();
  });
});
