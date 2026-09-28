(function(){
"use strict";
let state={accounts:[],allowed_roles:[],institutions:[],departments:[]};
const $=id=>document.getElementById(id),esc=value=>String(value??"").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll('"',"&quot;").replaceAll("'","&#39;"),unwrap=value=>value&&typeof value==="object"&&"data" in value?value.data:value;
function message(text,error=false){const box=$("message");box.hidden=!text;box.textContent=text||"";box.className=`message${error?" error":""}`;if(text)scrollTo({top:0,behavior:"smooth"})}
function option(value,label){return `<option value="${esc(value)}">${esc(label)}</option>`}
function renderSelects(){
  $("roleCode").innerHTML='<option value="">Select role</option>'+state.allowed_roles.map(x=>option(x.role_code,x.role_name)).join("");
  $("institutionId").innerHTML=state.institutions.map(x=>option(x.id,`${x.institution_code} — ${x.institution_name}`)).join("");
  if(state.institutions.length===1){$("institutionId").value=state.institutions[0].id;$("institutionId").disabled=true;}
  renderDepartments();
}
function renderDepartments(){const institutionId=$("institutionId").value;$("departmentId").innerHTML='<option value="">No department selected</option>'+state.departments.filter(x=>!institutionId||x.institution_id===institutionId).map(x=>option(x.id,`${x.department_code} — ${x.department_name}`)).join("")}
function renderAccounts(){
  const rows=state.accounts||[];
  $("accounts").innerHTML=`<div class="table-wrap"><table><thead><tr><th>Employee</th><th>Staff Member</th><th>Login</th><th>Job Title</th><th>Role</th><th>Status</th><th>Portal</th></tr></thead><tbody>${rows.length?rows.map(item=>{const s=item.staff||{},u=item.user||{},roles=item.roles||[];return `<tr><td>${esc(s.employee_number||"—")}</td><td><strong>${esc(u.display_name||[s.first_name,s.middle_name,s.last_name].filter(Boolean).join(" "))}</strong><br>${esc(u.user_number||"")}</td><td>${esc(u.email||s.email||"—")}<br>${esc(u.username||"")}</td><td>${esc(s.job_title||"—")}</td><td>${roles.length?roles.map(r=>esc(r.role_name)).join("<br>"):"—"}</td><td><span class="status">${esc(s.employment_status||u.status||"—")}</span></td><td>${roles.map(r=>{const found=state.allowed_roles.find(x=>x.role_code===r.role_code);return found?`<a href="${esc(found.portal)}">Open</a>`:""}).filter(Boolean).join("<br>")||"—"}</td></tr>`}).join(""):'<tr><td colspan="7" class="empty">No connected staff accounts.</td></tr>'}</tbody></table></div>`;
}
function setMode(){const link=$("mode").value==="LINK";document.querySelectorAll(".link-field").forEach(x=>x.hidden=!link);document.querySelectorAll(".create-field").forEach(x=>x.hidden=link);$("identifier").required=link;for(const id of ["firstName","lastName","email","password"])$(id).required=!link}
async function load(){state=unwrap(await IDMCAPI.get("/staff-workspace/admin/accounts"))||state;renderSelects();renderAccounts()}
async function submit(event){event.preventDefault();message("");const form=event.currentTarget,body=Object.fromEntries(new FormData(form).entries()),button=form.querySelector("button[type=submit]");button.disabled=true;try{const result=unwrap(await IDMCAPI.post("/staff-workspace/admin/accounts",body));form.reset();setMode();await load();message(`Staff account saved. Assigned role: ${result.role.role_name}. Portal: ${result.portal}`)}catch(error){message(error.message||"Unable to save staff account.",true)}finally{button.disabled=false}}
async function init(){try{if(!await IDMCAuth.requireAuth())return;await load()}catch(error){message(error.message||"Unable to load staff account administration.",true)}}
$("today").textContent=new Date().toLocaleDateString("en-GB",{weekday:"long",day:"numeric",month:"long",year:"numeric"});$("mode").onchange=setMode;$("institutionId").onchange=renderDepartments;$("accountForm").onsubmit=submit;$("menuButton").onclick=()=>$("sidebar").classList.toggle("open");$("logoutButton").onclick=()=>IDMCAuth.logout();setMode();init();
})();
