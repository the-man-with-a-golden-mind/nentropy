import { describe, it, expect, vi } from 'vitest';
import { setup } from './helpers';

describe('Custom directives', () => {
  it('fires custom directive when key changes', () => {
    const { en, data, q, cleanup } = setup(`<span en-color="theme"></span>`);
    en.directive('color', ({ el, value }) => {
      (el as HTMLElement).style.color = String(value);
    });
    data.theme = 'red';
    expect(q<HTMLElement>('span').style.color).toBe('red');
    cleanup();
  });

  it('fires directive for multiple matching elements', () => {
    const { en, data, qAll, cleanup } = setup(`
      <span en-txt="msg"></span>
      <span en-txt="msg"></span>
    `);
    en.directive('txt', ({ el, value }) => {
      (el as HTMLElement).textContent = String(value);
    });
    data.msg = 'hello';
    const texts = qAll<HTMLElement>('span').map(el => el.textContent);
    expect(texts).toEqual(['hello', 'hello']);
    cleanup();
  });
});

describe('Parametric directives', () => {
  it('receives param from attribute syntax', () => {
    const { en, data, q, cleanup } = setup(`<div en-style="theme:backgroundColor"></div>`);
    const spy = vi.fn();
    en.directive('style', (params) => {
      spy(params.param, params.value);
      if (params.param) {
        (params.el as HTMLElement).style.setProperty(
          params.param.replace(/[A-Z]/g, m => `-${m.toLowerCase()}`),
          String(params.value)
        );
      }
    }, true);
    data.theme = '#ff0000';
    expect(spy).toHaveBeenCalledWith('backgroundColor', '#ff0000');
    cleanup();
  });
});
