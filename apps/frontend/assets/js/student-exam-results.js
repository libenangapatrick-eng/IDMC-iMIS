(function () {
    "use strict";

    const state = { data: null, selectedYear: "all" };
    const byId = id => document.getElementById(id);
    const esc = value => String(value ?? "—")
        .replaceAll("&", "&amp;").replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#039;");
    const number = (value, digits = 1) => value === null || value === undefined || value === ""
        ? "—" : Number(value).toFixed(digits).replace(/\.0$/, "");
    const dateTime = value => value ? new Intl.DateTimeFormat("en-GB", {
        day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit"
    }).format(new Date(value)) : "—";
    const today = () => new Intl.DateTimeFormat("en-GB", {
        day: "2-digit", month: "short", year: "numeric"
    }).format(new Date());

    function setIdentity(student) {
        byId("currentUser").textContent = student.fullName || "Student";
        byId("studentName").textContent = student.fullName || "Student";
        byId("studentNumber").textContent = student.studentNumber || "—";
        byId("studentProgramme").textContent = student.programmeName || student.programmeCode || "—";
    }

    function yearButtons(years) {
        const items = years.map(year => `
            <button class="result-year-button ${state.selectedYear === year.id ? "active" : ""}"
                    type="button" data-year-id="${esc(year.id)}">
                <span>${esc(year.studyYearLabel)}</span>
                <small>${year.semesters.reduce((sum, semester) => sum + semester.results.length, 0)} modules</small>
            </button>`).join("");
        return `<div class="result-year-picker">
            <div class="result-section-label">Year of Study</div>
            <div class="result-year-list">${items}
                <button class="result-year-button ${state.selectedYear === "all" ? "active" : ""}" type="button" data-year-id="all">
                    <span>View All Results</span><small>Every published year</small>
                </button>
            </div>
        </div>`;
    }

    function semesterTable(semester) {
        const rows = semester.results.map(row => `
            <tr>
                <td class="result-code">${esc(row.code)}</td>
                <td>${esc(row.moduleName)}</td>
                <td>${esc(row.type)}</td>
                <td>${number(row.coursework, 2)}</td>
                <td>${number(row.semesterExam, 2)}</td>
                <td>${number(row.supplementary, 2)}</td>
                <td class="result-strong">${number(row.total, 2)}</td>
                <td>${number(row.credits, 1)}</td>
                <td><span class="result-grade">${esc(row.grade)}</span></td>
                <td>${number(row.points, 2)}</td>
                <td><span class="result-remark ${String(row.remarks).toUpperCase() === "PASS" ? "pass" : ""}">${esc(row.remarks)}</span></td>
                <td></td>
            </tr>`).join("");
        return `<section class="result-semester">
            <h3>${esc(semester.name || `Semester ${semester.number}`)}</h3>
            <div class="portal-table-wrap">
                <table class="portal-table result-table">
                    <thead><tr><th>Code</th><th>Module Name</th><th>Type</th><th>CW</th><th>SE</th><th>SUP</th><th>Total</th><th>Credits</th><th>Grade</th><th>Points</th><th>Remarks</th><th>GPA</th></tr></thead>
                    <tbody>${rows || `<tr><td colspan="12" class="result-empty">No published results.</td></tr>`}</tbody>
                    <tfoot><tr><td colspan="7" class="result-summary-label">Semester Summary</td><td>${number(semester.credits, 1)}</td><td></td><td>${number(semester.qualityPoints, 2)}</td><td></td><td class="result-gpa">${number(semester.gpa, 2)}</td></tr></tfoot>
                </table>
            </div>
        </section>`;
    }

    function render() {
        const data = state.data;
        const chosen = state.selectedYear === "all" ? data.years : data.years.filter(year => year.id === state.selectedYear);
        const resultBlocks = chosen.map(year => `
            <div class="result-year-block">
                <div class="result-year-heading"><div><small>Examination Results</small><h2>${esc(year.name || year.code)}</h2></div><span>${esc(year.studyYearLabel.split(" - ")[0])}</span></div>
                ${year.semesters.map(semesterTable).join("")}
            </div>`).join("");

        byId("portalContent").innerHTML = `
            <div class="result-meta">
                <div><span>Current Academic Year</span><strong>${esc(data.currentAcademicYear)}</strong></div>
                <div><span>Last Login</span><strong>${esc(dateTime(data.lastLoginAt))}</strong></div>
                <div><span>Today</span><strong>${esc(today())}</strong></div>
            </div>
            ${yearButtons(data.years)}
            ${resultBlocks || `<div class="portal-empty"><strong>No published examination results yet.</strong><p>Results appear here only after official publication.</p></div>`}
            <div class="result-note"><strong>Result codes:</strong> TF = Technical Failure, ABS = Absent. A blank SUP column means no supplementary examination mark was recorded.</div>`;

        document.querySelectorAll("[data-year-id]").forEach(button => button.addEventListener("click", () => {
            state.selectedYear = button.dataset.yearId;
            render();
        }));
    }

    async function load() {
        byId("portalContent").innerHTML = `<div class="portal-state"><div class="portal-spinner"></div><h3>Loading Examination Results</h3><p>Please wait while published results are prepared.</p></div>`;
        try {
            const authenticated = await window.IDMCAuth.requireAuth();
            if (!authenticated) return;
            const response = await window.IDMCAPI.get("/student-results/me");
            state.data = response.data;
            state.selectedYear = state.data.years.at(-1)?.id || "all";
            setIdentity(state.data.student);
            render();
        } catch (error) {
            byId("portalContent").innerHTML = `<div class="portal-error"><strong>Examination results are temporarily unavailable.</strong><div>${esc(error.message || "Please try again.")}</div><button class="portal-button" id="retryResults" type="button">Try Again</button></div>`;
            byId("retryResults")?.addEventListener("click", () => {
                window.IDMCAPI.clearCache?.();
                load();
            }, { once: true });
        }
    }

    byId("portalRefreshButton")?.addEventListener("click", load);
    document.addEventListener("DOMContentLoaded", load);
}());
