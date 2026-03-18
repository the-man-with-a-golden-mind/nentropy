// ─── EnDom.res ────────────────────────────────────────────────────────────────
// Typed DOM bindings. Zero %raw except defineCustomElement (class extends).
// Every binding compiles to a direct property access or method call.

// ── Abstract types ──────────────────────────────────────────────────────────

type element
type document
type observer
type nodeList

external asElement: 'a => element = "%identity"

// ── Document ────────────────────────────────────────────────────────────────

@val external document: document = "document"
@send external createElement: (document, string) => element = "createElement"
@send @return(nullable)
external querySelector: (document, string) => option<element> = "querySelector"
@get external readyState: document => string = "readyState"
@send external addDocListener: (document, string, unit => unit) => unit = "addEventListener"
@send external removeDocListener: (document, string, unit => unit) => unit = "removeEventListener"

// ── NodeList → Array conversion ─────────────────────────────────────────────

@send external _querySelectorAllRaw: ('a, string) => nodeList = "querySelectorAll"
@val external _arrayFrom: nodeList => array<element> = "Array.from"

let querySelectorAll = (root: 'a, sel: string): array<element> =>
  root->_querySelectorAllRaw(sel)->_arrayFrom

// ── Element — properties via @get/@set ──────────────────────────────────────

@get external parentElement: element => Nullable.t<element> = "parentElement"
@get external parentNode: element => Nullable.t<element> = "parentNode"
@get external nextElementSibling: element => Nullable.t<element> = "nextElementSibling"
@get external previousElementSibling: element => Nullable.t<element> = "previousElementSibling"
@set external setTextContent: (element, string) => unit = "textContent"
@set external setInnerHTML: (element, string) => unit = "innerHTML"
@get external _childrenRaw: element => nodeList = "children"
let getChildren = (el: element): array<element> => el->_childrenRaw->_arrayFrom

// Can't use @get with dotted path "children.length" — ReScript treats it as literal prop name.
// Use the children array length instead.
let hasChildren = (el: element): bool => el->getChildren->Array.length > 0

// ── Element — methods via @send ─────────────────────────────────────────────

@send @return(nullable) external getAttribute: (element, string) => option<string> = "getAttribute"
@send external setAttribute: (element, string, string) => unit = "setAttribute"
@send external remove: element => unit = "remove"
@send external before: (element, element) => unit = "before"
@send external replaceWith: (element, element) => unit = "replaceWith"
@send external cloneNode: (element, bool) => element = "cloneNode"
@send external addEventListener: (element, string, {..} => unit) => unit = "addEventListener"

// ── HTMLTemplateElement ─────────────────────────────────────────────────────

@get external _content: element => element = "content"
@get @return(nullable) external _firstElementChild: element => option<element> = "firstElementChild"
@send external _appendChild: (element, element) => unit = "appendChild"

let isTemplate: element => bool = %raw(`function(el) { return el instanceof HTMLTemplateElement; }`)
let getTemplateFirstChild = (tpl: element): option<element> => tpl->_content->_firstElementChild
let appendToTemplateContent = (tpl: element, node: element): unit =>
  tpl->_content->_appendChild(node)
let getTemplateChildren = (tpl: element): array<element> => tpl->_content->_childrenRaw->_arrayFrom

// ── instanceof checks — need %raw (no ReScript equivalent for instanceof) ──

let isHTMLElement: element => bool = %raw(`function(el) { return el instanceof HTMLElement; }`)
let isInput: element => bool = %raw(`function(el) { return el instanceof HTMLInputElement; }`)
let isTextArea: element => bool = %raw(`function(el) { return el instanceof HTMLTextAreaElement; }`)
let isSelect: element => bool = %raw(`function(el) { return el instanceof HTMLSelectElement; }`)
let isElementInstance: element => bool = %raw(`function(el) { return el instanceof Element; }`)

// ── Input properties via @get/@set ──────────────────────────────────────────

@get external inputType: element => string = "type"
@get external inputValue: element => string = "value"
@set external setInputValue: (element, string) => unit = "value"
@get external inputChecked: element => bool = "checked"
@set external setInputChecked: (element, bool) => unit = "checked"
@get external valueAsNumber: element => float = "valueAsNumber"

// ── MutationObserver ────────────────────────────────────────────────────────

@new external _newObserver: (unit => unit) => observer = "MutationObserver"
@send external _observe: (observer, document, {..}) => unit = "observe"
@send external disconnect: observer => unit = "disconnect"

let makeObserver = (cb: unit => unit): option<observer> =>
  try {Some(_newObserver(cb))} catch {
  | _ => None
  }

let observe = (obs: observer): unit => obs->_observe(document, {"childList": true, "subtree": true})

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
