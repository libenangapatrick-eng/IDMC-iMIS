(function () {
  "use strict";

  const CACHE_KEY = "idmc.student.panel.identity.v1";
  const CACHE_MS = 60000;
  const byId = id => document.getElementById(id);

  function apply(student) {
    if (!student || typeof student !== "object") return;
    const name = student.full_name || [student.first_name, student.middle_name, student.last_name].filter(Boolean).join(" ") || "Student";
    const number = student.student_number || student.registration_number || "—";
    const programme = [student.programme_code, student.programme_name].filter(Boolean).join(" — ") || "Not assigned";
    if (byId("currentUser")) byId("currentUser").textContent = name;
    if (byId("studentName")) byId("studentName").textContent = name;
    if (byId("studentNumber")) byId("studentNumber").textContent = number;
    if (byId("studentProgramme")) byId("studentProgramme").textContent = programme;
  }

  function cached() {
    try {
      const value = JSON.parse(sessionStorage.getItem(CACHE_KEY) || "null");
      return value && Date.now() - value.savedAt < CACHE_MS ? value.student : null;
    } catch { return null; }
  }

  async function loadIdentity() {
    const existing = cached();
    if (existing) apply(existing);
    try {
      if (!window.IDMCAPI || !window.IDMCAuth) return;
      const response = await window.IDMCAPI.get("/students/me/portal");
      const data = response && Object.prototype.hasOwnProperty.call(response, "data") ? response.data : response;
      const student = data?.student || data;
      apply(student);
      sessionStorage.setItem(CACHE_KEY, JSON.stringify({ savedAt: Date.now(), student }));
    } catch (error) {
      console.warn("Student Panel identity could not be refreshed", error?.message || error);
    }
  }

  function activateNavigation() {
    const current = location.pathname.split("/").pop() || "student-portal.html";
    document.querySelectorAll(".portal-nav a").forEach(link => {
      const target = String(link.getAttribute("href") || "").split("#")[0];
      link.classList.toggle("active", target === current);
    });
  }

  function start() {
    activateNavigation();
    loadIdentity();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
  else start();
}());
