(function(){
"use strict";
function removeGenericNavigation(){
  document.querySelectorAll("[data-idmc-module-nav-shell]").forEach(function(shell){shell.remove()});
}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",removeGenericNavigation,{once:true});
else removeGenericNavigation();
new MutationObserver(removeGenericNavigation).observe(document.documentElement,{childList:true,subtree:true});
}());
