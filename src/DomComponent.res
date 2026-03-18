// ─── DomComponent.res ─────────────────────────────────────────────────────────

let registerTemplates = (rootElement: option<EnDom.element>): unit => {
  let templates = switch rootElement {
  | Some(el) => EnDom.querySelectorAll(el, "template[name]")
  | None => EnDom.querySelectorAll(EnDom.document, "template[name]")
  }
  templates->Array.forEach(tpl =>
    switch tpl->EnDom.getAttribute("name") {
    | None => ()
    | Some(name) => EnDom.defineCustomElement(name->String.toLowerCase, tpl)
    }
  )
}

let fetchText: string => promise<string> = %raw(`
  async function(url) {
    var r = await fetch(url);
    if (!r.ok) throw new Error("HTTP " + r.status);
    return r.text();
  }
`)

let loadTemplateFile = async (file: string): unit => {
  try {
    let html = await fetchText(file)
    let wrapper = EnDom.document->EnDom.createElement("div")
    wrapper->EnDom.setInnerHTML(html)
    registerTemplates(Some(wrapper))
  } catch {
  | exn => Console.error2("[entropy] Failed to load template:", exn)
  }
}
