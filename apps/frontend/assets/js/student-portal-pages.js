(function () {
  "use strict";
  const config = window.IDMC_STUDENT_PAGE || {}, view = String(config.view || "");
  const $ = id => document.getElementById(id);
  const val = (v, fallback = "—") => v === null || v === undefined || v === "" ? fallback : String(v);
  const esc = v => val(v, "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const unwrap = r => r && Object.prototype.hasOwnProperty.call(r, "data") ? r.data : r;
  const badge = s => `<span class="portal-badge ${/(PUBLISH|PASS|PAID|REGISTER|ACTIVE|APPROV)/i.test(s || "") ? "success" : /(FAIL|REJECT|CANCEL|ABSENT)/i.test(s || "") ? "danger" : "warning"}">${esc(val(s))}</span>`;
  const money = n => Number(n || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  function table(columns, records) {
    if (!records.length) return `<div class="portal-empty"><strong>No records found</strong></div>`;
    return `<div class="portal-table-wrap"><table class="portal-table"><thead><tr>${columns.map(c => `<th>${esc(c[0])}</th>`).join("")}</tr></thead><tbody>${records.map(r => `<tr>${columns.map(c => `<td>${c[2] ? c[1](r) : esc(val(c[1](r)))}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`;
  }
  const summary = cards => `<div class="portal-summary">${cards.map(c => `<div class="portal-stat"><div class="portal-stat-label">${esc(c[0])}</div><div class="portal-stat-value">${esc(val(c[1]))}</div></div>`).join("")}</div>`;
  const setContent = html => { $("portalContent").innerHTML = html; };
  async function action(fn, message) { try { await fn(); alert(message); await loadView(); } catch (e) { alert(e.message || "Action failed."); } }

  async function identity() {
    const s = unwrap(await IDMCAPI.get("/students/me")) || {};
    const name = s.full_name || [s.first_name, s.middle_name, s.last_name].filter(Boolean).join(" ") || "Student";
    [["currentUser", name], ["studentName", name], ["studentNumber", s.student_number || s.registration_number], ["studentProgramme", [s.programme_code, s.programme_name].filter(Boolean).join(" — ") || s.programme_id]].forEach(([id, v]) => { if ($(id)) $(id).textContent = val(v); });
  }

  async function registration() {
    const d = unwrap(await IDMCAPI.get("/self-service/student/registration")), current = d.current_registration || {};
    const courses = new Map((d.courses || []).map(x => [x.id, x]));
    const selected = new Set((d.selected_courses || []).filter(x => !["DROPPED", "REJECTED", "CANCELLED"].includes(x.registration_status)).map(x => x.course_offering_id));
    const offerings = d.offerings || [];
    setContent(summary([["Status", current.registration_status || "No registration"], ["Semester registration no.", current.registration_number], ["Credits", current.total_registered_credits], ["Courses", (d.selected_courses || []).length]]) +
      `<div class="portal-actions"><button class="portal-button" id="submitRegistration">Submit Registration</button></div><h3>Available Courses</h3>` +
      table([["Course", r => `${courses.get(r.course_id)?.course_code || r.offering_code} — ${courses.get(r.course_id)?.course_name || ""}`], ["Credits", r => courses.get(r.course_id)?.credit_units], ["Status", r => badge(r.status), true], ["Action", r => selected.has(r.id) ? "Selected" : r.status === "OPEN" ? `<button class="portal-button select-course" data-id="${esc(r.id)}">Select</button>` : "Closed", true]], offerings) +
      `<h3>Add / Drop Request</h3><form id="addDropForm" class="portal-form"><select name="courseOfferingId" required>${offerings.map(o => `<option value="${esc(o.id)}">${esc(courses.get(o.course_id)?.course_code || o.offering_code)}</option>`).join("")}</select><select name="requestType"><option>ADD</option><option>DROP</option></select><textarea name="reason" required placeholder="Reason"></textarea><button class="portal-button" type="submit">Send Request</button></form>` +
      `<h3>Registered Courses</h3>` + table([["Code", r => courses.get(r.course_id)?.course_code], ["Course", r => courses.get(r.course_id)?.course_name], ["Credits", r => r.credits], ["Status", r => badge(r.registration_status), true]], d.selected_courses || []) +
      `<h3>Add / Drop History</h3>` + table([["Type", r => r.request_type], ["Course", r => courses.get(r.course_id)?.course_code], ["Reason", r => r.reason], ["Status", r => badge(r.request_status), true]], d.add_drop_requests || []));
    $("submitRegistration")?.addEventListener("click", () => action(() => IDMCAPI.post("/self-service/student/registration/submit", {}), "Registration submitted."));
    document.querySelectorAll(".select-course").forEach(b => b.addEventListener("click", () => action(() => IDMCAPI.post("/self-service/student/registration/select", { courseOfferingId: b.dataset.id }), "Course selected.")));
    $("addDropForm")?.addEventListener("submit", e => { e.preventDefault(); action(() => IDMCAPI.post("/self-service/student/registration/add-drop", Object.fromEntries(new FormData(e.target))), "Add/drop request submitted."); });
  }

  async function attendance() {
    const rows = unwrap(await IDMCAPI.get("/students/me/attendance")).records || [], attended = rows.filter(x => ["PRESENT", "LATE"].includes(String(x.attendance_status).toUpperCase())).length;
    setContent(summary([["Records", rows.length], ["Present/Late", attended], ["Absent", rows.filter(x => String(x.attendance_status).toUpperCase() === "ABSENT").length], ["Rate", rows.length ? `${((attended / rows.length) * 100).toFixed(1)}%` : "—"]]) + table([["Session", r => r.attendance_session_id], ["Status", r => badge(r.attendance_status), true], ["Check-in", r => r.check_in_time], ["Minutes Late", r => r.minutes_late], ["Remarks", r => r.remarks]], rows));
  }

  async function results() {
    const d = unwrap(await IDMCAPI.get("/students/me/results")), rows = d.course_results || [], sem = d.semester_results?.[0] || {}, cg = d.cgpa_records?.[0] || {};
    setContent(summary([["Latest GPA", sem.gpa], ["CGPA", cg.cgpa || sem.cgpa], ["Published Courses", rows.length], ["Standing", sem.academic_standing || cg.academic_standing]]) + table([["Code", r => r.course_code], ["Module", r => r.course_name], ["CW", r => r.coursework_mark], ["SE", r => r.examination_mark], ["Total", r => r.total_mark], ["Credits", r => r.credits || r.credit_units], ["Grade", r => r.grade_code], ["Points", r => r.quality_points], ["Remarks", r => badge(r.pass_status), true]], rows));
  }

  async function timetable() {
    const d = unwrap(await IDMCAPI.get("/students/me/timetable"));
    setContent(`<h3>Class Timetable</h3>` + table([["Day", r => r.slot?.day_of_week || r.slot?.day_name], ["Course", r => `${val(r.course_code, "")} ${val(r.course_name, "")}`], ["Start", r => r.slot?.start_time], ["End", r => r.slot?.end_time], ["Room", r => r.room?.room_name || r.room?.room_code], ["Lecturer", r => r.lecturer_name]], d.classes || []) + `<h3>Examination Timetable</h3>` + table([["Date", r => r.examination_date], ["Paper", r => r.paper_title || r.course_name], ["Start", r => r.start_time], ["End", r => r.end_time], ["Room", r => r.room?.room_name || r.room?.room_code], ["Eligibility", r => badge(r.eligibility_status), true]], d.examinations || []));
  }

  async function fees() {
    const d = unwrap(await IDMCAPI.get("/finance/workflow/student/dashboard", { timeoutMs: 120000 })), account = d.account || {}, invoices = d.invoices || [], requests = d.payment_requests || [];
    const balance = account.current_balance ?? 0;
    setContent(summary([["Total Charges", `TZS ${money(account.total_charged)}`], ["Total Paid", `TZS ${money(account.total_paid)}`], ["Balance Due", `TZS ${money(balance)}`], ["Account", account.account_status || (Number(balance) > 0 ? "OUTSTANDING" : "CLEARED")]]) + `<div class="portal-actions"><button class="portal-button" onclick="window.print()">Print / Save Statement</button></div><h3>Invoices</h3>` + table([["Invoice", r => r.invoice_number], ["Academic Period", r => `${val(r.academic_year, "")} ${val(r.semester, "")}`], ["Amount", r => `TZS ${money(r.total_amount)}`], ["Paid", r => `TZS ${money(r.amount_paid)}`], ["Balance", r => `TZS ${money(r.balance_amount)}`], ["Status", r => badge(r.status), true], ["Action", r => Number(r.balance_amount || 0) > 0 ? `<button class="portal-button request-payment" data-id="${esc(r.id)}">Request Control Number</button>` : "Cleared", true]], invoices) + `<h3>Control Numbers and Receipt Upload</h3>` + table([["Request", r => r.request_number], ["Control Number", r => r.control_number], ["Amount", r => `TZS ${money(r.amount)}`], ["Status", r => badge(r.request_status), true], ["Finance Message", r => r.provider_message], ["Action", r => ["ISSUED","REJECTED"].includes(r.request_status) ? `<label class="portal-button">Upload Receipt<input class="receipt-upload" data-id="${esc(r.id)}" type="file" accept="application/pdf,image/jpeg,image/png,image/webp" hidden></label>` : r.receipt_file_name || "—", true]], requests) + `<h3>Confirmed Payments</h3>` + table([["Receipt", r => r.receipt_number], ["Date", r => r.payment_date], ["Amount", r => `TZS ${money(r.amount)}`], ["Method", r => r.payment_method], ["Confirmed By", r => r.confirmed_by_name], ["Status", r => badge(r.status), true]], d.payments || []) + `<h3>Published Fee Structures</h3>` + table([["Academic Year", r => r.academic_year], ["Semester", r => r.semester], ["Structure", r => r.fee_structure_name], ["Published", r => r.published_at], ["Status", r => badge(r.status), true]], d.fee_structures || []));
    document.querySelectorAll(".request-payment").forEach(b => b.addEventListener("click", () => { const payerPhone = prompt("Payer phone number (optional):") || ""; action(() => IDMCAPI.post("/self-service/student/payments/control-number", { invoiceId: b.dataset.id, payerPhone }), "Payment request created; awaiting configured provider confirmation."); }));
    document.querySelectorAll(".receipt-upload").forEach(input => input.addEventListener("change", async () => {
      const file = input.files?.[0]; if (!file) return;
      if (file.size > 6 * 1024 * 1024) return alert("Receipt must not exceed 6 MB.");
      try {
        const token = IDMCAuth.getAccessToken();
        const response = await fetch(`${IDMCAPI.baseUrl}/finance/workflow/student/payment-requests/${encodeURIComponent(input.dataset.id)}/receipt`, { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/octet-stream", "X-File-Name": file.name, "X-Mime-Type": file.type }, body: file });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(payload.message || "Receipt upload failed.");
        alert("Receipt uploaded. Finance will review and confirm the payment."); await loadView();
      } catch (error) { alert(error.message || "Receipt upload failed."); }
    }));
  }

  async function documents() {
    const d = unwrap(await IDMCAPI.get("/students/me/documents"));
    setContent(`<h3>My Documents</h3>` + table([["Document", r => r.file_name || r.document_type], ["Type", r => r.document_type], ["Uploaded", r => r.uploaded_at], ["Verification", r => badge(r.verification_status), true], ["Action", r => `<button class="portal-button download-document" data-id="${esc(r.id)}">Download</button>`, true]], d.documents || []) + `<h3>Service Requests</h3>` + table([["Request", r => r.request_number], ["Type", r => r.request_type], ["Subject", r => r.subject], ["Status", r => badge(r.status), true], ["Submitted", r => r.submitted_at]], d.service_requests || []));
    document.querySelectorAll(".download-document").forEach(b => b.addEventListener("click", async () => { try { const x = unwrap(await IDMCAPI.get(`/students/me/documents/${encodeURIComponent(b.dataset.id)}/download`)); window.open(x.url, "_blank", "noopener"); } catch (e) { alert(e.message); } }));
  }

  async function notifications() {
    const d = unwrap(await IDMCAPI.get("/students/me/notifications"));
    setContent(`<div class="portal-actions"><button class="portal-button" id="readAll">Mark All Read</button></div>` + table([["Date", r => r.created_at], ["Title", r => r.title], ["Message", r => r.body || r.message], ["Priority", r => badge(r.priority), true], ["Status", r => badge(r.read_at ? "READ" : r.status || "UNREAD"), true], ["Action", r => r.read_at ? "Read" : `<button class="portal-button read-one" data-id="${esc(r.id)}">Mark Read</button>`, true]], d.notifications || []) + `<h3>Announcements</h3>` + table([["Date", r => r.publish_at || r.created_at], ["Title", r => r.title], ["Message", r => r.summary || r.body || r.message]], d.announcements || []));
    $("readAll")?.addEventListener("click", () => action(() => IDMCAPI.post("/students/me/notifications/read-all", {}), "Notifications marked as read."));
    document.querySelectorAll(".read-one").forEach(b => b.addEventListener("click", () => action(() => IDMCAPI.patch(`/students/me/notifications/${encodeURIComponent(b.dataset.id)}/read`, {}), "Notification marked as read.")));
  }

  const loaders = { registration, attendance, results, timetable, fees, documents, notifications };
  async function loadView() { setContent(`<div class="portal-state"><div class="portal-spinner"></div><h3>Loading ${esc(config.title || "Student Panel")}</h3></div>`); try { await (loaders[view] || registration)(); } catch (e) { setContent(`<div class="portal-error">${esc(e.message || "Unable to load this page.")}</div>`); } }
  async function boot() { try { if (!await IDMCAuth.requireAuth()) return; await identity(); document.querySelector(`[data-view="${CSS.escape(view)}"]`)?.classList.add("active"); await loadView(); } catch (e) { setContent(`<div class="portal-error">${esc(e.message || "Unable to open Student Panel.")}</div>`); } }
  document.addEventListener("DOMContentLoaded", () => { $("portalRefreshButton")?.addEventListener("click", loadView); boot(); });
})();
