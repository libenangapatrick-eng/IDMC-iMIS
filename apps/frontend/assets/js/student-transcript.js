(function(){
  "use strict";
  const $=id=>document.getElementById(id), val=(v,f="—")=>v===null||v===undefined||v===""?f:String(v);
  const esc=v=>val(v,"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const unwrap=r=>r&&Object.prototype.hasOwnProperty.call(r,"data")?r.data:r;
  const badge=s=>`<span class="portal-badge ${s==="ISSUED"||s==="APPROVED"?"success":"warning"}">${esc(val(s))}</span>`;
  const table=(cols,rows)=>`<div class="portal-table-wrap"><table class="portal-table"><thead><tr>${cols.map(x=>`<th>${esc(x[0])}</th>`).join("")}</tr></thead><tbody>${rows.length?rows.map(r=>`<tr>${cols.map(x=>`<td>${x[2]?x[1](r):esc(val(x[1](r)))}</td>`).join("")}</tr>`).join(""):`<tr><td colspan="${cols.length}">No records found.</td></tr>`}</tbody></table></div>`;
  async function load(){
    try{
      if(!await IDMCAuth.requireAuth())return;
      const d=unwrap(await IDMCAPI.get("/students/me/transcript")),s=d.student||{},t=d.transcript;
      const name=[s.first_name,s.middle_name,s.last_name].filter(Boolean).join(" ")||s.full_name||"Student";
      $("currentUser").textContent=name;$("studentName").textContent=name;$("studentNumber").textContent=val(s.registration_number||s.student_number);$("studentProgramme").textContent=val(s.programme_name||s.programme_code||s.programme_id);
      if(!t){$("portalContent").innerHTML=`<div class="portal-empty"><strong>No transcript has been generated.</strong><p>Use Request Transcript to start an official service request.</p></div>`;return;}
      $("portalContent").innerHTML=`<div class="portal-summary"><div class="portal-stat"><div class="portal-stat-label">Transcript Number</div><div class="portal-stat-value">${esc(t.transcript_number)}</div></div><div class="portal-stat"><div class="portal-stat-label">Status</div><div class="portal-stat-value">${badge(t.transcript_status)}</div></div><div class="portal-stat"><div class="portal-stat-label">CGPA</div><div class="portal-stat-value">${esc(val(t.cgpa))}</div></div><div class="portal-stat"><div class="portal-stat-label">Standing</div><div class="portal-stat-value">${esc(val(t.final_academic_standing))}</div></div></div><p><strong>Verification code:</strong> ${esc(val(t.verification_code))} &nbsp; <strong>Issued:</strong> ${esc(val(t.issued_at))}</p><h3>Semester Summary</h3>${table([["Sequence",r=>r.sequence_no],["Academic Year",r=>r.academic_year_id],["Semester",r=>r.semester_id],["GPA",r=>r.gpa],["Earned Credits",r=>r.earned_credits],["Standing",r=>r.academic_standing]],d.semesters||[])}<h3>Course Results</h3>${table([["Code",r=>r.course_code],["Course",r=>r.course_name],["Credits",r=>r.credits],["CW",r=>r.coursework_mark],["Exam",r=>r.examination_mark],["Total",r=>r.total_mark],["Grade",r=>r.grade_code],["Point",r=>r.grade_point],["Result",r=>r.pass_status]],d.courses||[])}`;
    }catch(e){$("portalContent").innerHTML=`<div class="portal-error">${esc(e.message||"Unable to load transcript.")}</div>`;}
  }
  $("printTranscript").addEventListener("click",()=>window.print());
  $("requestTranscript").addEventListener("click",async()=>{try{await IDMCAPI.post("/students/me/requests",{requestType:"TRANSCRIPT",subject:"Official academic transcript",reason:"Student portal transcript request"});alert("Transcript request submitted.");}catch(e){alert(e.message||"Request failed.");}});
  document.addEventListener("DOMContentLoaded",load);
})();
