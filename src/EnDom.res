// ─── Dom.res ──────────────────────────────────────────────────────────────────
// Typed DOM bindings using @send/@get/@set — no %raw wrappers.
// Each binding compiles to a DIRECT property access or method call.

// ── Abstract types ──────────────────────────────────────────────────────────

type element
type document
type observer

// Cast between element subtypes (template, input, etc.) — zero cost
external asElement: 'a => element = "%identity"

// ── Document ────────────────────────────────────────────────────────────────

@val external document: document = "document"
@send external createElement: (document, string) => element = "createElement"
@send @return(nullable) external querySelector: (document, string) => option<element> = "querySelector"
@send external querySelectorAllDoc: (document, string) => array<element> = "querySelectorAll"
@get external readyState: document => string = "readyState"
@send external addDocListener: (document, string, unit => unit) => unit = "addEventListener"
@send external removeDocListener: (document, string, unit => unit) => unit = "removeEventListener"

// querySelectorAll returns NodeList, we need Array — keep one %raw for this
let querySelectorAll: ('a, string) => array<element> = %raw(`
  function(root, sel) { return Array.from(root.querySelectorAll(sel)); }
`)

// ── Element — property access via @get/@set ─────────────────────────────────

@get external parentElement: element => Nullable.t<element> = "parentElement"
@get external parentNode: element => Nullable.t<element> = "parentNode"
@get external nextElementSibling: element => Nullable.t<element> = "nextElementSibling"
@get external previousElementSibling: element => Nullable.t<element> = "previousElementSibling"
@set external setTextContent: (element, string) => unit = "textContent"
@set external setInnerHTML: (element, string) => unit = "innerHTML"

// ── Element — methods via @send ─────────────────────────────────────────────

@send @return(nullable) external getAttribute: (element, string) => option<string> = "getAttribute"
@send external setAttribute: (element, string, string) => unit = "setAttribute"
@send external remove: element => unit = "remove"
@send external before: (element, element) => unit = "before"
@send external replaceWith: (element, element) => unit = "replaceWith"
@send external cloneNode: (element, bool) => element = "cloneNode"
@send external addEventListener: (element, string, {..} => unit) => unit = "addEventListener"
@send @return(nullable) external elQuerySelector: (element, string) => option<element> = "querySelector"
@send external elQuerySelectorAll: (element, string) => array<element> = "querySelectorAll"

// ── Element — children ──────────────────────────────────────────────────────

let getChildren: element => array<element> = %raw(`
  function(el) { return Array.from(el.children); }
`)
let hasChildren: element => bool = %raw(`
  function(el) { return el.children && el.children.length > 0; }
`)

// ── HTMLTemplateElement ─────────────────────────────────────────────────────

let isTemplate: element => bool = %raw(`
  function(el) { return el instanceof HTMLTemplateElement; }
`)
let getTemplateFirstChild: element => Nullable.t<element> = %raw(`
  function(tpl) { return tpl.content.firstElementChild; }
`)
let appendToTemplateContent: (element, element) => unit = %raw(`
  function(tpl, node) { tpl.content.appendChild(node); }
`)
let getTemplateChildren: element => array<element> = %raw(`
  function(tpl) { return Array.from(tpl.content.children); }
`)

// ── HTMLInputElement ────────────────────────────────────────────────────────

let isHTMLElement: element => bool = %raw(`function(el) { return el instanceof HTMLElement; }`)
let isInput: element => bool = %raw(`function(el) { return el instanceof HTMLInputElement; }`)
let isTextArea: element => bool = %raw(`function(el) { return el instanceof HTMLTextAreaElement; }`)
let isSelect: element => bool = %raw(`function(el) { return el instanceof HTMLSelectElement; }`)
let isElementInstance: element => bool = %raw(`function(el) { return el instanceof Element; }`)

@get external inputType: element => string = "type"
@get external inputValue: element => string = "value"
@set external setInputValue: (element, string) => unit = "value"
@get external inputChecked: element => bool = "checked"
@set external setInputChecked: (element, bool) => unit = "checked"
@get external valueAsNumber: element => float = "valueAsNumber"

// ── MutationObserver ────────────────────────────────────────────────────────

let makeObserver: (unit => unit) => Nullable.t<observer> = %raw(`
  function(cb) {
    if (typeof MutationObserver === 'undefined') return null;
    return new MutationObserver(cb);
  }
`)
let observe: observer => unit = %raw(`
  function(obs) { obs.observe(document, { childList: true, subtree: true }); }
`)
@send external disconnect: observer => unit = "disconnect"

// ── Custom Elements (genuinely needs %raw — class extends) ──────────────────

let defineCustomElement: (string, element) => unit = %raw(`
  function(name, tpl) {
    if (customElements.get(name)) return;
    customElements.define(name, class extends HTMLElement {
      constructor() {
        super();
        var shadow = this.attachShadow({ mode: 'open' });
        document.getElementsByTagName('style').forEach(s => shadow.appendChild(s.cloneNode(true)));
        document.querySelectorAll('link[rel="stylesheet"]').forEach(l => shadow.appendChild(l.cloneNode(true)));
        tpl.content.childNodes.forEach(c => shadow.appendChild(c.cloneNode(true)));
      }
    });
  }
`)
