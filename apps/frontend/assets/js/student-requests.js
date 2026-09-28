(function(){
"use strict";
const state={requests:[],results:[],decision:null,workflow:null};
const el=id=>document.getElementById(id);
const esc=v=>String(v??"-").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll('"',"&quot;").replaceAll("'","&#039;");
const when=v=>v?new Intl.DateTimeFormat("en-GB",{day:"2-digit",month:"short",year:"numeric",hour:"2-digit",minute:"2-digit"}).format(new Date(v)):"-";
const count=(rows,key,value)=>rows.filter(r=>String(r[key]).toUpperCase()===value).length;
const badge=value=>`<span class="status ${String(value||"").toLowerCase()}">${esc(value)}</span>`;

function requestSummary(){
  const open=state.requests.filter(r=>["PENDING","SUBMITTED","UNDER_REVIEW"].includes(String(r.request_status))).length;
  el("summary").innerHTML=[["All Requests",state.requests.length],["Awaiting Decision",open],["Approved",count(state.requests,"request_status","APPROVED")],["Rejected",count(state.requests,"request_status","REJECTED")]].map(x=>`<div class="request-stat"><span>${x[0]}</span><strong>${x[1]}</strong></div>`).join("");
}
function canDecide(row){return ["PENDING","SUBMITTED","UNDER_REVIEW"].includes(String(row.request_status))}
function renderRequests(){
  requestSummary();
  el("requestRows").innerHTML=state.requests.map(r=>`<tr>
    <td><span class="student-name">${esc(r.student_name)}</span><span class="student-number">${esc(r.student_number)}</span><span class="minor">${esc(r.programme_code)} ${r.department_name?"- "+esc(r.department_name):""}</span></td>
    <td><strong>${esc(r.request_type)}</strong><span class="minor">${esc(r.request_category)}</span></td>
    <td><strong>${esc(r.course_code||r.subject)}</strong><span class="minor">${esc(r.course_name)}</span></td>
    <td>${esc(r.academic_year)}<span class="minor">${esc(r.semester_name)}</span></td>
    <td>${esc(r.reason)}</td><td>${esc(when(r.requested_at))}</td><td>${badge(r.request_status)}</td>
    <td>${canDecide(r)?`<div class="row-actions"><button class="approve" data-request-id="${esc(r.id)}" data-decision="APPROVED">Approve</button><button class="reject" data-request-id="${esc(r.id)}" data-decision="REJECTED">Reject</button></div>`:"-"}</td>
  </tr>`).join("")||`<tr><td colspan="8" class="empty">No matching student requests.</td></tr>`;
  document.querySelectorAll("[data-request-id]").forEach(b=>b.onclick=()=>openDecision(b.dataset.requestId,b.dataset.decision));
}
async function loadRequests(){
  el("requestMessage").textContent="Loading requests submitted from the Student Portal...";
  try{
    const q=new URLSearchParams({limit:"100"});
    if(el("searchInput").value.trim())q.set("search",el("searchInput").value.trim());
    if(el("statusFilter").value)q.set("status",el("statusFilter").value);
    const response=await IDMCAPI.get("/student-requests?"+q);
    state.requests=response.data||[];renderRequests();
    el("requestMessage").textContent=`Showing ${state.requests.length} of ${response.meta?.total??state.requests.length} department requests.`;
  }catch(error){el("requestMessage").textContent=error.message||"Unable to load requests.";el("requestRows").innerHTML=""}
}
function openDecision(id,decision){
  const row=state.requests.find(r=>String(r.id)===String(id));state.decision={id,decision};
  el("decisionTitle").textContent=decision==="APPROVED"?"Approve Student Request":"Reject Student Request";
  el("decisionStudent").textContent=`${row.student_name} (${row.student_number}) - ${row.subject||row.course_code||row.request_type}`;
  el("decisionReason").value="";el("decisionDialog").showModal();
}

function filteredResults(){
  const q=el("resultSearch").value.trim().toLowerCase();
  return state.results.filter(r=>!q||[r.student_number,r.student_name,r.course_code,r.course_name,r.offering_code].some(v=>String(v||"").toLowerCase().includes(q)));
}
function groupResults(rows){
  const groups=new Map();
  rows.forEach(r=>{const key=[r.student_id,r.academic_year_id,r.semester_id].join("|");if(!groups.has(key))groups.set(key,[]);groups.get(key).push(r)});
  return groups;
}
function resultSummary(){
  const calculated=state.results.filter(r=>["CALCULATED","SUBMITTED"].includes(r.result_status)).length;
  el("resultSummary").innerHTML=[["Results Loaded",state.results.length],["Awaiting Confirmation",calculated],["Awaiting Approval",count(state.results,"result_status","UNDER_REVIEW")],["Ready to Publish",count(state.results,"result_status","APPROVED")]].map(x=>`<div class="request-stat"><span>${x[0]}</span><strong>${x[1]}</strong></div>`).join("");
  const actions=[
    ["review","Confirm All Calculated",calculated],
    ["approve","Approve All Reviewed",count(state.results,"result_status","UNDER_REVIEW")],
    ["publish","Publish All Approved",count(state.results,"result_status","APPROVED")]
  ];
  el("bulkWorkflow").innerHTML=`<div><strong>Department bulk actions</strong><span>Each action changes only results currently at its correct stage.</span></div><div class="bulk-buttons">${actions.map(x=>`<button type="button" class="workflow-action ${x[0]}" data-bulk-action="${x[0]}" ${x[2]?"":"disabled"}>${x[1]} (${x[2]})</button>`).join("")}</div>`;
  document.querySelectorAll("[data-bulk-action]").forEach(b=>b.onclick=()=>openWorkflow({bulk:true,action:b.dataset.bulkAction,label:"all eligible department results"}));
}
function studentActions(rows){
  const statuses=new Set(rows.map(r=>r.result_status)),actions=[];
  if(statuses.has("CALCULATED")||statuses.has("SUBMITTED"))actions.push(["review","Confirm & Start Review"]);
  if(statuses.has("UNDER_REVIEW"))actions.push(["approve","Approve Results"]);
  if(statuses.has("APPROVED"))actions.push(["publish","Publish to Student"]);
  return actions;
}
function renderResults(){
  resultSummary();
  const groups=groupResults(filteredResults());
  el("resultBatches").innerHTML=[...groups.values()].map(rows=>{
    const first=rows[0],actions=studentActions(rows);
    return `<article class="result-batch"><header><div><span class="batch-code">${esc(first.student_number)}</span><h2>${esc(first.student_name)}</h2><p>${esc(first.academic_year)} - ${esc(first.semester_name)} - ${rows.length} course(s)</p></div><div class="batch-actions">${actions.map(a=>`<button class="workflow-action ${a[0]}" data-student="${esc(first.student_id)}" data-year="${esc(first.academic_year_id)}" data-semester="${esc(first.semester_id)}" data-action="${a[0]}" data-label="${esc(first.student_number+" - "+first.student_name)}">${a[1]}</button>`).join("")}</div></header>
    <div class="request-table-wrap"><table class="result-table"><thead><tr><th>Course</th><th>Coursework</th><th>Exam</th><th>Total</th><th>Grade</th><th>Remark</th><th>Status</th></tr></thead><tbody>${rows.map(r=>`<tr><td><strong>${esc(r.course_code)}</strong><span class="minor">${esc(r.course_name)}</span></td><td>${esc(r.coursework_mark)}</td><td>${esc(r.examination_mark)}</td><td><strong>${esc(r.total_mark)}</strong></td><td>${esc(r.grade_code)}</td><td>${esc(r.pass_status||r.remarks)}</td><td>${badge(r.result_status)}</td></tr>`).join("")}</tbody></table></div></article>`;
  }).join("")||`<div class="empty-card">No results match the selected filters.</div>`;
  document.querySelectorAll("[data-student]").forEach(b=>b.onclick=()=>openWorkflow({bulk:false,studentId:b.dataset.student,academicYearId:b.dataset.year,semesterId:b.dataset.semester,action:b.dataset.action,label:b.dataset.label}));
}
async function loadResults(){
  el("resultMessage").textContent="Loading department results...";
  try{
    const q=new URLSearchParams();if(el("resultStatus").value)q.set("status",el("resultStatus").value);
    const response=await IDMCAPI.get("/student-requests/results"+(q.toString()?"?"+q:""));
    state.results=response.data||[];renderResults();
    el("resultMessage").textContent=`${state.results.length} result(s) loaded and grouped by student. Only PUBLISHED/LOCKED results appear in the Student Portal.`;
  }catch(error){el("resultMessage").textContent=error.message||"Unable to load results.";el("resultBatches").innerHTML="";el("bulkWorkflow").innerHTML=""}
}
function openWorkflow(workflow){
  state.workflow=workflow;
  const labels={review:"Confirm Results and Start HOD Review",approve:"Approve Reviewed Results",publish:"Publish Results to Student Portal"};
  el("workflowTitle").textContent=labels[workflow.action];
  el("workflowText").textContent=`${workflow.label}. Continue with this controlled workflow action?`;
  el("workflowSubmit").className=workflow.action==="publish"?"danger-confirm":"";
  el("workflowDialog").showModal();
}
async function init(){const ok=await IDMCAuth.requireAuth();if(!ok)return;await Promise.all([loadRequests(),loadResults()])}

el("decisionForm").addEventListener("submit",async event=>{
  if(event.submitter?.value==="cancel")return;event.preventDefault();
  const reason=el("decisionReason").value.trim();if(state.decision.decision==="REJECTED"&&!reason){alert("Enter a reason before rejecting.");return}
  el("decisionSubmit").disabled=true;
  try{await IDMCAPI.post(`/student-requests/${encodeURIComponent(state.decision.id)}/decision`,{decision:state.decision.decision,reason});el("decisionDialog").close();await loadRequests()}catch(error){alert(error.message||"Decision failed.")}finally{el("decisionSubmit").disabled=false}
});
el("workflowForm").addEventListener("submit",async event=>{
  if(event.submitter?.value==="cancel")return;event.preventDefault();el("workflowSubmit").disabled=true;
  try{
    const w=state.workflow;
    const path=w.bulk?`/student-requests/results/bulk/${w.action}`:`/student-requests/results/students/${encodeURIComponent(w.studentId)}/${w.action}`;
    const body=w.bulk?{}:{academicYearId:w.academicYearId,semesterId:w.semesterId};
    const response=await IDMCAPI.post(path,body);
    el("workflowDialog").close();await loadResults();
    alert(`${response.meta?.updated??0} result(s) moved to ${response.meta?.status||"the next stage"}.`);
  }catch(error){alert(error.message||"Result workflow action failed.")}finally{el("workflowSubmit").disabled=false}
});
document.querySelectorAll("[data-tab]").forEach(b=>b.onclick=()=>{document.querySelectorAll("[data-tab]").forEach(x=>x.classList.toggle("active",x===b));el("requestsPanel").hidden=b.dataset.tab!=="requests";el("resultsPanel").hidden=b.dataset.tab!=="results"});
el("filterButton").onclick=loadRequests;el("resultFilterButton").onclick=loadResults;el("resultSearch").oninput=renderResults;el("refreshButton").onclick=()=>Promise.all([loadRequests(),loadResults()]);el("searchInput").onkeydown=e=>{if(e.key==="Enter")loadRequests()};document.addEventListener("DOMContentLoaded",init);
}());

