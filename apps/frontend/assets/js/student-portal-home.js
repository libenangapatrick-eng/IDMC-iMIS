(function(){
"use strict";
const $=id=>document.getElementById(id);
const text=(id,value,fallback="—")=>{if($(id))$(id).textContent=value===null||value===undefined||value===""?fallback:String(value);};
const esc=value=>String(value??"").replace(/[&<>"']/g,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[ch]));
const title=value=>String(value??"").toLowerCase().replace(/(^|[_\s-])\w/g,part=>part.toUpperCase()).replaceAll("_"," ");
const dateTime=value=>value?new Intl.DateTimeFormat("en-GB",{day:"2-digit",month:"short",year:"numeric",hour:"2-digit",minute:"2-digit",second:"2-digit"}).format(new Date(value)):"—";
const longDate=value=>new Intl.DateTimeFormat("en-GB",{weekday:"long",day:"2-digit",month:"short",year:"numeric"}).format(value);
const money=(amount,currency="TZS")=>`${currency} ${Number(amount||0).toLocaleString("en-GB")}`;
let panelData=null;
let selectedDay="today";

function showMessage(value,type=""){
 const box=$("panelMessage");if(!box)return;box.hidden=!value;box.textContent=value||"";box.className=`panel-message ${type}`;
}
function initials(student){
 const names=[student.first_name,student.middle_name,student.last_name].filter(Boolean);return names.slice(0,2).map(x=>String(x)[0]).join("").toUpperCase()||"ST";
}
function statusLabel(value){
 const status=String(value||"").toUpperCase();
 return ({ACTIVE:"Continuing",REGISTERED:"Registered",COMPLETED:"Completed",GRADUATED:"Graduated",DEFERRED:"Deferred",SUSPENDED:"Suspended",WITHDRAWN:"Withdrawn"})[status]||title(value)||"—";
}
function modeLabel(value){return ({FULL_TIME:"Full Time",PART_TIME:"Part Time",EVENING:"Evening",WEEKEND:"Weekend",DISTANCE:"Distance Learning",ONLINE:"Online"})[String(value||"").toUpperCase()]||title(value)||"—";}
function courseDateMatches(entry,target){
 const date=new Date();date.setDate(date.getDate()+(target==="tomorrow"?1:0));
 if(entry.entry_date){const actual=new Date(`${String(entry.entry_date).slice(0,10)}T00:00:00`);return actual.toDateString()===date.toDateString();}
 const expected=new Intl.DateTimeFormat("en-GB",{weekday:"long"}).format(date).toUpperCase();
 return String(entry.slot?.day_of_week||entry.day_of_week||"").toUpperCase()===expected;
}
function renderTimetable(){
 const rows=(panelData?.upcoming_classes||[]).filter(x=>courseDateMatches(x,selectedDay));
 $("timetableRows").innerHTML=rows.length?rows.map((item,index)=>{
  const start=item.slot?.start_time||item.start_time||"";const end=item.slot?.end_time||item.end_time||"";
  const room=item.room?.room_name||item.room?.room_code||item.room_name||"—";
  return `<tr><td>${index+1}</td><td><strong>${esc(item.course_code||item.offering_code||"—")}</strong></td><td>${esc(item.course_name||item.class_record?.class_name||"Scheduled class")}</td><td>${esc([start,end].filter(Boolean).join(" – ")||"—")}</td><td>${esc(room)}</td></tr>`;
 }).join(""):`<tr><td colspan="5" class="empty-cell">No ${selectedDay} classes have been published.</td></tr>`;
}
function renderNotices(data){
 const notices=[...(data.alerts||[]).map(x=>({title:x.title,body:x.message})),...(data.announcements||[]).map(x=>({title:x.title||"Announcement",body:x.summary||x.body||""}))].slice(0,5);
 $("noticeList").innerHTML=notices.length?notices.map(x=>`<article class="notice"><strong>${esc(x.title)}</strong><span>${esc(x.body)}</span></article>`).join(""):'<p class="empty-notice">No active notices.</p>';
}
function render(data){
 panelData=data;const student=data.student||{},panel=data.panel||{},registration=data.current_registration||{},counts=data.counts||{};
 const fullName=student.full_name||[student.first_name,student.middle_name,student.last_name].filter(Boolean).join(" ")||"Student";
 const programme=panel.programme||student.programme_name||"Not assigned";
 text("sidebarName",fullName);text("welcomeName",fullName);text("sidebarNumber",student.registration_number||student.student_number);text("profileStudentNumber",student.registration_number||student.student_number);
 text("currentYear",panel.current_year||registration.academic_year_name);text("lastLogin",dateTime(panel.last_login_at));text("todayDate",longDate(new Date()));
 text("yearOfStudy",panel.year_of_study,"Not determined");text("studentStream",panel.stream,"Not assigned");text("studentStatus",statusLabel(panel.student_status));
 text("registrationStatus",registration.registration_status||"No registration");text("registrationNumber",registration.registration_number||"—");
 text("entryYear",panel.entry_year,"Not recorded");text("intake",panel.intake,"Not recorded");text("session",modeLabel(panel.session));text("programme",programme);
 text("department",panel.department,"Not assigned");text("school",panel.school,"Not assigned");text("campus",panel.campus,"Not assigned");
 text("registeredCourses",counts.registered_courses||0);text("attendanceRate",data.attendance?.percentage===null||data.attendance?.percentage===undefined?"—":`${data.attendance.percentage}%`);text("publishedResults",counts.published_results||0);text("accountBalance",money(data.finance?.balance,data.finance?.currency));
 text("photoFallback",initials(student));
 if(student.profile_photo_url){$("studentPhoto").src=student.profile_photo_url;$("studentPhoto").hidden=false;$("photoFallback").hidden=true;}
 else{$("studentPhoto").hidden=true;$("photoFallback").hidden=false;}
 renderTimetable();renderNotices(data);
}
function fatal(error){showMessage(error?.message||"Student Panel could not be loaded.","error");$("timetableRows").innerHTML='<tr><td colspan="5" class="empty-cell">Unable to load timetable.</td></tr>';}
async function load(){
 const button=$("refreshPanel");if(button)button.disabled=true;showMessage("Loading your Student Panel...");
 try{if(!await IDMCAuth.requireAuth())return;const response=await IDMCAPI.get("/students/me/summary");render(response.data||response);showMessage("");}
 catch(error){fatal(error);}finally{if(button)button.disabled=false;}
}
document.addEventListener("DOMContentLoaded",()=>{
 text("copyrightYear",new Date().getFullYear());
 $("refreshPanel")?.addEventListener("click",load);$("menuButton")?.addEventListener("click",()=>$("studentSidebar")?.classList.toggle("open"));
 ["logoutTop","logoutSide"].forEach(id=>$(id)?.addEventListener("click",()=>IDMCAuth.logout()));
 document.querySelectorAll("[data-day]").forEach(button=>button.addEventListener("click",()=>{selectedDay=button.dataset.day;document.querySelectorAll("[data-day]").forEach(x=>x.classList.toggle("active",x===button));renderTimetable();}));
 load();
});
})();
