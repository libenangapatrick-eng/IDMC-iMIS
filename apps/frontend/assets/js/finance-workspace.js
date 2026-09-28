(function () {
  "use strict";
  const state = { students: [], fees: [], selected: null, showAll: false };
  const $ = (id) => document.getElementById(id),
    esc = (v) =>
      String(v ?? "-").replace(
        /[&<>"']/g,
        (c) =>
          ({
            "&": "&amp;",
            "<": "&lt;",
            ">": "&gt;",
            '"': "&quot;",
            "'": "&#39;",
          })[c],
      ),
    money = (v) =>
      new Intl.NumberFormat("en-TZ", {
        style: "currency",
        currency: "TZS",
        maximumFractionDigits: 0,
      }).format(Number(v || 0)),
    rows = (r) => (Array.isArray(r?.data) ? r.data : Array.isArray(r) ? r : []);
  function name(s) {
    return (
      [s.first_name, s.middle_name, s.last_name].filter(Boolean).join(" ") ||
      "Student"
    );
  }
  function msg(t, e = false) {
    $("message").textContent = t;
    $("message").className = "message" + (e ? " error" : "");
  }
  function badge(v) {
    return `<span class="badge ${String(v || "").toLowerCase()}">${esc(v)}</span>`;
  }
  function renderStudents() {
    const q = $("studentSearch").value.trim().toLowerCase();
    let list = state.students.filter(
      (s) =>
        !q ||
        [s.student_number, name(s), s.email].some((v) =>
          String(v || "")
            .toLowerCase()
            .includes(q),
        ),
    );
    if (!state.showAll && !q) list = list.slice(0, 30);
    $("studentList").innerHTML =
      list
        .map(
          (s) =>
            `<button class="student-card ${state.selected === s.id ? "active" : ""}" data-id="${esc(s.id)}"><strong>${esc(s.student_number)}</strong><span class="minor">${esc(name(s))}</span><span class="minor">${esc(s.student_status)}</span></button>`,
        )
        .join("") || '<div class="empty">No matching students.</div>';
    document
      .querySelectorAll(".student-card")
      .forEach((b) => (b.onclick = () => loadStudent(b.dataset.id)));
  }
  function renderFees() {
    const q = $("feeSearch").value.trim().toLowerCase(),
      list = state.fees.filter(
        (f) => !q || JSON.stringify(f).toLowerCase().includes(q),
      );
    $("feeRows").innerHTML =
      list
        .map(
          (f) =>
            `<tr><td>${esc(f.feeStructureCode || f.fee_structure_code)}</td><td>${esc(f.feeStructureName || f.fee_structure_name)}</td><td>${esc(f.academicYear || f.academic_year)}</td><td>${esc(f.semester)}</td><td>${esc(f.currencyCode || f.currency_code)}</td><td>${badge(f.status)}</td></tr>`,
        )
        .join("") ||
      '<tr><td colspan="6" class="empty">No fee structures found.</td></tr>';
  }
  function table(title, data, columns) {
    return `<h3>${esc(title)}</h3><div class="table-wrap"><table><thead><tr>${columns.map((c) => `<th>${esc(c[0])}</th>`).join("")}</tr></thead><tbody>${data.length ? data.map((r) => `<tr>${columns.map((c) => `<td>${c[2] ? c[1](r) : esc(c[1](r))}</td>`).join("")}</tr>`).join("") : `<tr><td colspan="${columns.length}" class="empty">No records.</td></tr>`}</tbody></table></div>`;
  }
  async function safe(path) {
    try {
      const response = await window.IDMCAPI.get(path);
      return response?.data ?? response ?? [];
    } catch (e) {
      if (e.status === 403 || e.status === 404) return [];
      throw e;
    }
  }
  async function loadStudent(id) {
    state.selected = id;
    renderStudents();
    const s = state.students.find((x) => x.id === id);
    $("studentTitle").textContent = `${s.student_number} - ${name(s)}`;
    $("studentFinance").innerHTML =
      '<div class="empty">Loading financial records...</div>';
    try {
      const base = `/finance/students/${encodeURIComponent(id)}`;
      const [account, charges, invoices, payments, refunds, scholarships] =
        await Promise.all([
          safe(base + "/account"),
          safe(base + "/charges"),
          safe(base + "/invoices"),
          safe(base + "/payments"),
          safe(base + "/refunds"),
          safe(base + "/scholarships"),
        ]);
      const a = Array.isArray(account) ? account[0] || {} : account || {};
      $("studentFinance").innerHTML =
        `<div class="summary"><div class="stat"><span>Charged</span><strong>${money(a.total_charged)}</strong></div><div class="stat"><span>Paid</span><strong>${money(a.total_paid)}</strong></div><div class="stat"><span>Refunded</span><strong>${money(a.total_refunded)}</strong></div><div class="stat"><span>Balance</span><strong>${money(a.current_balance)}</strong></div></div>` +
        table("Invoices", invoices, [
          ["Invoice", (r) => r.invoice_number],
          ["Date", (r) => r.invoice_date],
          ["Total", (r) => money(r.total_amount)],
          ["Balance", (r) => money(r.balance_amount)],
          ["Status", (r) => badge(r.status), true],
        ]) +
        table("Payments", payments, [
          ["Receipt", (r) => r.receipt_number],
          ["Date", (r) => r.payment_date],
          ["Amount", (r) => money(r.amount)],
          ["Method", (r) => r.payment_method],
          ["Status", (r) => badge(r.status), true],
        ]) +
        table(
          "Charges / Scholarships / Refunds",
          [...charges, ...scholarships, ...refunds],
          [
            [
              "Reference",
              (r) => r.charge_number || r.scholarship_number || r.refund_number,
            ],
            [
              "Description",
              (r) => r.description || r.scholarship_name || r.reason,
            ],
            ["Amount", (r) => money(r.amount || r.approved_amount)],
            ["Status", (r) => badge(r.status), true],
          ],
        );
    } catch (e) {
      $("studentFinance").innerHTML =
        `<div class="message error">${esc(e.message)}</div>`;
    }
  }
  async function load() {
    msg("Loading finance workspace...");
    try {
      const [students, fees] = await Promise.all([
        window.IDMCAPI.get("/finance/workspace/students"),
        window.IDMCAPI.get("/finance/fee-structures?limit=100"),
      ]);
      state.students = rows(students);
      state.fees = rows(fees);
      renderStudents();
      renderFees();
      $("summary").innerHTML = [
        ["Students", state.students.length],
        ["Fee Structures", state.fees.length],
        [
          "Active Students",
          state.students.filter((s) => s.student_status === "ACTIVE").length,
        ],
        ["Selected Student", state.selected ? "1" : "0"],
      ]
        .map(
          (x) =>
            `<div class="stat"><span>${x[0]}</span><strong>${x[1]}</strong></div>`,
        )
        .join("");
      msg("Finance data loaded successfully.");
    } catch (e) {
      msg(e.message || "Finance load failed.", true);
    }
  }
  async function init() {
    if (!(await window.IDMCAuth.requireAuth())) return;
    load();
  }
  document.querySelectorAll("[data-view]").forEach(
    (b) =>
      (b.onclick = () => {
        document
          .querySelectorAll("[data-view]")
          .forEach((x) => x.classList.toggle("active", x === b));
        $("studentsView").hidden = b.dataset.view !== "students";
        $("feesView").hidden = b.dataset.view !== "fees";
      }),
  );
  $("studentSearch").oninput = renderStudents;
  $("feeSearch").oninput = renderFees;
  $("loadAll").onclick = () => {
    state.showAll = true;
    renderStudents();
  };
  $("refresh").onclick = load;
  document.addEventListener("DOMContentLoaded", init);
})();
