(function(){
"use strict";
const state={institution:null,campuses:[],schools:[],departments:[]};
const $=(selector,root=document)=>root.querySelector(selector);
const $$=(selector,root=document)=>Array.from(root.querySelectorAll(selector));
const esc=value=>String(value??"").replace(/[&<>"']/g,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[ch]));
const dataOf=response=>response&&Object.prototype.hasOwnProperty.call(response,"data")?response.data:response;
const plural=kind=>kind==="campus"?"campuses":`${kind}s`;
function message(text,type="ok"){const box=$("#message");box.hidden=!text;box.textContent=text||"";box.className=`message ${type}`;if(text&&type!=="error")window.setTimeout(()=>{box.hidden=true;},3500);}
function openTab(name){$$(".tab").forEach(x=>x.classList.toggle("active",x.dataset.tab===name));$$(".panel").forEach(x=>x.classList.toggle("active",x.dataset.panel===name));const url=new URL(location.href);url.searchParams.set("tab",name);history.replaceState(null,"",url);}
function nameBy(list,id,key){return list.find(x=>x.id===id)?.[key]||"—";}
function empty(colspan,label){return `<tr><td class="empty" colspan="${colspan}">${esc(label)}</td></tr>`;}
function render(){
 const i=state.institution||{},form=$("#institutionForm");
 ["registration_number","accreditation_number","institution_type","ownership_type","email","phone","website","physical_address","postal_address","city","region","country"].forEach(k=>{if(form.elements[k])form.elements[k].value=i[k]||(k==="country"?"Tanzania":"");});
 $("#campusCount").textContent=state.campuses.length;$("#schoolCount").textContent=state.schools.length;$("#departmentCount").textContent=state.departments.length;
 $("#campusRows").innerHTML=state.campuses.length?state.campuses.map(x=>`<tr><td><strong>${esc(x.campus_code)}</strong></td><td>${esc(x.campus_name)}</td><td>${esc(x.campus_type||"—")}</td><td>${esc([x.city,x.region].filter(Boolean).join(", ")||"—")}</td><td><span class="status">${esc(x.status)}</span></td><td><button class="edit" data-edit="campus" data-id="${x.id}">Edit</button></td></tr>`).join(""):empty(6,"No campuses have been registered.");
 $("#schoolRows").innerHTML=state.schools.length?state.schools.map(x=>`<tr><td><strong>${esc(x.school_code)}</strong></td><td>${esc(x.school_name)}</td><td>${esc(nameBy(state.campuses,x.campus_id,"campus_name"))}</td><td>${esc(x.dean_title||"Dean")}</td><td><span class="status">${esc(x.status)}</span></td><td><button class="edit" data-edit="school" data-id="${x.id}">Edit</button></td></tr>`).join(""):empty(6,"No schools or faculties have been registered.");
 $("#departmentRows").innerHTML=state.departments.length?state.departments.map(x=>`<tr><td><strong>${esc(x.department_code)}</strong></td><td>${esc(x.department_name)}</td><td>${esc(nameBy(state.schools,x.school_id,"school_name"))}</td><td>${esc(x.head_title||"Head of Department")}</td><td><span class="status">${esc(x.status)}</span></td><td><button class="edit" data-edit="department" data-id="${x.id}">Edit</button></td></tr>`).join(""):empty(6,"No departments have been registered.");
}
async function load(){try{message("Loading institution structure...");const payload=dataOf(await IDMCAPI.get("/institutions/primary/structure"));Object.assign(state,payload);render();message("Institution structure loaded.");}catch(error){message(error.message||"Unable to load institution structure.","error");}}
const input=(label,name,value="",type="text")=>`<label>${label}<input name="${name}" type="${type}" value="${esc(value)}"></label>`;
const select=(label,name,items,value,key,text,allowEmpty=false)=>`<label>${label}<select name="${name}">${allowEmpty?'<option value="">Not assigned</option>':""}${items.map(x=>`<option value="${x[key]}" ${x[key]===value?"selected":""}>${esc(x[text])}</option>`).join("")}</select></label>`;
function openDialog(kind,id){
 const record=id?state[plural(kind)].find(x=>x.id===id):{},editing=Boolean(id);let fields="";
 if(kind==="campus")fields=input("Campus Code *","campus_code",record.campus_code)+input("Campus Name *","campus_name",record.campus_name)+input("Campus Type","campus_type",record.campus_type)+input("City","city",record.city)+input("Region","region",record.region)+input("Phone","phone",record.phone)+input("Email","email",record.email,"email")+select("Status","status",[{v:"ACTIVE",t:"Active"},{v:"INACTIVE",t:"Inactive"}],record.status||"ACTIVE","v","t");
 if(kind==="school")fields=input("School Code *","school_code",record.school_code)+input("School / Faculty Name *","school_name",record.school_name)+select("Campus","campus_id",state.campuses,record.campus_id,"id","campus_name",true)+input("Dean Title","dean_title",record.dean_title||"Dean")+input("Email","email",record.email,"email")+input("Phone","phone",record.phone)+select("Status","status",[{v:"ACTIVE",t:"Active"},{v:"INACTIVE",t:"Inactive"}],record.status||"ACTIVE","v","t");
 if(kind==="department")fields=input("Department Code *","department_code",record.department_code)+input("Department Name *","department_name",record.department_name)+select("School / Faculty *","school_id",state.schools,record.school_id,"id","school_name")+input("Head Title","head_title",record.head_title||"Head of Department")+input("Email","email",record.email,"email")+input("Phone","phone",record.phone)+select("Status","status",[{v:"ACTIVE",t:"Active"},{v:"INACTIVE",t:"Inactive"}],record.status||"ACTIVE","v","t");
 if((kind==="department"&&!state.schools.length)||(kind==="school"&&!state.campuses.length)){message(`Create ${kind==="department"?"a school":"a campus"} first.`,"error");return;}
 const form=$("#recordForm");form.elements.id.value=id||"";form.elements.kind.value=kind;$("#dialogTitle").textContent=`${editing?"Edit":"Add"} ${kind[0].toUpperCase()+kind.slice(1)}`;$("#recordFields").innerHTML=fields;$("#recordDialog").showModal();
}
function payload(form){return Object.fromEntries(Array.from(new FormData(form).entries()).filter(([key])=>!["id","kind"].includes(key)));}
async function saveInstitution(event){event.preventDefault();try{await IDMCAPI.patch(`/institutions/${state.institution.id}`,payload(event.currentTarget));message("Institution profile saved.");await load();}catch(error){message(error.message,"error");}}
async function saveRecord(event){event.preventDefault();const form=event.currentTarget,kind=form.elements.kind.value,id=form.elements.id.value,collection=plural(kind);try{const body=payload(form);if(id)await IDMCAPI.patch(`/${collection}/${id}`,body);else await IDMCAPI.post(`/${collection}`,body);$("#recordDialog").close();message(`${kind[0].toUpperCase()+kind.slice(1)} saved.`);await load();openTab(collection);}catch(error){message(error.message,"error");}}
async function init(){
 const user=await IDMCAuth.requireAuth();if(!user)return;
 $$(".tab").forEach(x=>x.addEventListener("click",()=>openTab(x.dataset.tab)));$$("[data-open]").forEach(x=>x.addEventListener("click",()=>openDialog(x.dataset.open)));
 document.addEventListener("click",e=>{const b=e.target.closest("[data-edit]");if(b)openDialog(b.dataset.edit,b.dataset.id);});
 $("#institutionForm").addEventListener("submit",saveInstitution);$("#recordForm").addEventListener("submit",saveRecord);$("#refreshButton").addEventListener("click",load);$("#logoutButton").addEventListener("click",()=>IDMCAuth.logout());
 ["#closeDialog","#cancelDialog"].forEach(id=>$(id).addEventListener("click",()=>$("#recordDialog").close()));openTab(new URLSearchParams(location.search).get("tab")||"profile");await load();
}
document.addEventListener("DOMContentLoaded",init);
})();
