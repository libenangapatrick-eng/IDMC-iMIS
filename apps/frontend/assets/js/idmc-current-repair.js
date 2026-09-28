(function () {
  "use strict";

  function textCleanup() {
    document.querySelectorAll("title,h1,h2,h3,h4,h5,p,span,small,strong,label,div").forEach(function(el){
      if (el.children.length) return;
      var t=(el.textContent||"").trim();
      if (!t) return;
      if (/blue[\s-]*print/i.test(t)) {
        el.textContent=t.replace(/blue[\s-]*print/ig,"").replace(/\s{2,}/g," ").trim();
      }
      if (/IDMC LOGO PLACEHOLDER/i.test(t)) {
        el.textContent=t.replace(/IDMC LOGO PLACEHOLDER/ig,"IDMC");
      }
    });
  }

  function formUx() {
    document.querySelectorAll("form").forEach(function(form){
      form.querySelectorAll("input,select,textarea").forEach(function(field){
        if (!field.id && field.name) {
          field.id="idmc-"+field.name.replace(/[^a-zA-Z0-9_-]/g,"-");
        }
        if (field.required) field.setAttribute("aria-required","true");
        var type=(field.getAttribute("type")||"").toLowerCase();
        if (type==="email") field.setAttribute("autocomplete","email");
        if (type==="tel") field.setAttribute("autocomplete","tel");
      });
    });
  }

  function safeLinks() {
    document.querySelectorAll('a[target="_blank"]').forEach(function(a){
      var rel=(a.getAttribute("rel")||"").split(/\s+/).filter(Boolean);
      if (rel.indexOf("noopener")<0) rel.push("noopener");
      if (rel.indexOf("noreferrer")<0) rel.push("noreferrer");
      a.setAttribute("rel",rel.join(" "));
    });
  }

  function exposeRuntimeFailure() {
    window.addEventListener("error",function(e){
      var msg=(e && e.message) ? String(e.message) : "";
      if (!msg) return;
      if (!/module|form|crud|relationship|IDMC/i.test(msg)) return;
      if (document.querySelector(".idmc-runtime-error")) return;
      var host=document.querySelector(".idmc-form-host") || document.querySelector("#module-crud");
      if (!host) return;
      var box=document.createElement("div");
      box.className="idmc-runtime-error";
      box.textContent="Module UI error: "+msg;
      host.prepend(box);
    });
  }

  function removeGenericClutter() {
    document.querySelectorAll("[data-idmc-module-nav-shell]").forEach(function (node) {
      node.remove();
    });

    if (!/\/(dashboard|dashboard\.html)\/?$/i.test(window.location.pathname)) return;

    [
      ".page-heading",
      ".welcome-panel",
      ".modules-heading",
      ".module-information",
      ".operations-grid",
      ".system-status-grid"
    ].forEach(function (selector) {
      document.querySelectorAll(selector).forEach(function (node) { node.remove(); });
    });

    document.querySelectorAll("h1,h2,h3,p,span,strong").forEach(function (node) {
      if (node.children.length) return;
      var label = (node.textContent || "").trim();
      if (/^(WELCOME TO IDMC iMIS|Available Modules|Permission Based|Today's Operations|System Status)$/i.test(label)) {
        var section = node.closest("section,article,.card,.dashboard-section");
        if (section) section.remove();
      }
    });
  }

  function boot(){
    textCleanup();
    formUx();
    safeLinks();
    exposeRuntimeFailure();
    removeGenericClutter();
  }

  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded",boot,{once:true});
  }else{
    boot();
  }
})();
