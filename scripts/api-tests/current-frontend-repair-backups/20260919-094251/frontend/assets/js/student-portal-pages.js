(function () {
    "use strict";

    const config = window.IDMC_STUDENT_PAGE || {};
    const view = String(config.view || "").trim();
    const permission = String(config.permission || "").trim();
    const title = String(config.title || "Student Portal");

    let student = null;

    function el(id) {
        return document.getElementById(id);
    }

    function value(v, fallback = "—") {
        if (v === null || v === undefined || v === "") {
            return fallback;
        }
        return String(v);
    }

    function esc(v) {
        return value(v, "")
            .replaceAll("&", "&amp;")
            .replaceAll("<", "&lt;")
            .replaceAll(">", "&gt;")
            .replaceAll('"', "&quot;")
            .replaceAll("'", "&#039;");
    }

    function unwrap(response) {
        if (
            response &&
            typeof response === "object" &&
            Object.prototype.hasOwnProperty.call(response, "data")
        ) {
            return response.data;
        }
        return response;
    }

    function rows(response) {
        const data = unwrap(response);

        if (Array.isArray(data)) return data;
        if (Array.isArray(data?.items)) return data.items;
        if (Array.isArray(data?.rows)) return data.rows;
        if (Array.isArray(data?.data)) return data.data;

        return [];
    }

    function studentId() {
        return (
            student?.id ||
            student?.student_id ||
            student?.studentId ||
            null
        );
    }

    function studentName() {
        const direct =
            student?.full_name ||
            student?.student_name ||
            student?.name;

        if (direct) return direct;

        const composed = [
            student?.first_name,
            student?.middle_name,
            student?.last_name
        ].filter(Boolean).join(" ");

        if (composed) return composed;

        const user = window.IDMCAuth?.getUser?.();

        return (
            user?.user_metadata?.full_name ||
            user?.email ||
            "Student"
        );
    }

    function setContent(html) {
        const root = el("portalContent");
        if (root) root.innerHTML = html;
    }

    function loading(message) {
        setContent(`
            <div class="portal-state">
                <div class="portal-spinner"></div>
                <h3>${esc(message || "Loading")}</h3>
                <p>Please wait while information is loaded.</p>
            </div>
        `);
    }

    function errorState(error) {
        const message =
            error?.message ||
            "The requested information could not be loaded.";

        setContent(`
            <div class="portal-error">
                <strong>Unable to load ${esc(title)}</strong>
                <div style="margin-top:6px">${esc(message)}</div>
            </div>
        `);
    }

    function empty(message) {
        return `
            <div class="portal-empty">
                <i class="fa-regular fa-folder-open"
                   style="font-size:28px;margin-bottom:12px"></i>
                <div><strong>No records found</strong></div>
                <div style="margin-top:5px">
                    ${esc(message || "No information is currently available.")}
                </div>
            </div>
        `;
    }

    async function api(path) {
        if (
            !window.IDMCAPI ||
            typeof window.IDMCAPI.get !== "function"
        ) {
            throw new Error("IDMC API client is unavailable.");
        }

        return window.IDMCAPI.get(path);
    }

    async function requireAuth() {
        if (
            !window.IDMCAuth ||
            typeof window.IDMCAuth.requireAuth !== "function"
        ) {
            throw new Error("Authentication service is unavailable.");
        }

        const ok = await window.IDMCAuth.requireAuth();

        if (!ok) {
            throw new Error("Authentication is required.");
        }
    }

    async function requirePermission() {
        if (!permission) return;

        const rbac = window.IDMC_RBAC_API;

        if (!rbac || typeof rbac.hasPermission !== "function") {
            return;
        }

        const allowed = await rbac.hasPermission(permission);

        if (!allowed) {
            throw new Error(
                "You do not have permission to view this section."
            );
        }
    }

    function statusClass(status) {
        const s = String(status || "").toUpperCase();

        if (
            s.includes("APPROV") ||
            s.includes("PUBLISH") ||
            s.includes("REGISTER") ||
            s === "ACTIVE" ||
            s === "PAID" ||
            s === "PRESENT" ||
            s === "PASS"
        ) {
            return "success";
        }

        if (
            s.includes("PEND") ||
            s.includes("SUBMIT") ||
            s.includes("REVIEW") ||
            s === "LATE"
        ) {
            return "warning";
        }

        if (
            s.includes("REJECT") ||
            s.includes("FAIL") ||
            s.includes("CANCEL") ||
            s === "ABSENT"
        ) {
            return "danger";
        }

        return "";
    }

    function badge(status) {
        return `
            <span class="portal-badge ${statusClass(status)}">
                ${esc(value(status))}
            </span>
        `;
    }

    function table(columns, data) {
        if (!data.length) {
            return empty();
        }

        const head = columns.map(c =>
            `<th>${esc(c.label)}</th>`
        ).join("");

        const body = data.map(row => {
            const cells = columns.map(c => {
                const result =
                    typeof c.value === "function"
                        ? c.value(row)
                        : row[c.value];

                if (c.html) {
                    return `<td>${result || "—"}</td>`;
                }

                return `<td>${esc(value(result))}</td>`;
            }).join("");

            return `<tr>${cells}</tr>`;
        }).join("");

        return `
            <div class="portal-table-wrap">
                <table class="portal-table">
                    <thead><tr>${head}</tr></thead>
                    <tbody>${body}</tbody>
                </table>
            </div>
        `;
    }

    function summary(cards) {
        return `
            <div class="portal-summary">
                ${cards.map(card => `
                    <div class="portal-stat">
                        <div class="portal-stat-label">
                            ${esc(card.label)}
                        </div>
                        <div class="portal-stat-value">
                            ${esc(value(card.value))}
                        </div>
                    </div>
                `).join("")}
            </div>
        `;
    }

    function renderIdentity() {
        const name = studentName();

        const number =
            student?.registration_number ||
            student?.student_number ||
            student?.admission_number ||
            student?.registrationNumber ||
            "—";

        const programme =
            student?.programme_name ||
            student?.program_name ||
            student?.programme_code ||
            student?.programme_id ||
            "—";

        if (el("currentUser")) {
            el("currentUser").textContent = name;
        }

        if (el("studentName")) {
            el("studentName").textContent = name;
        }

        if (el("studentNumber")) {
            el("studentNumber").textContent = number;
        }

        if (el("studentProgramme")) {
            el("studentProgramme").textContent = programme;
        }
    }

    async function loadStudent() {
        const response = await api("/students/me");
        student = unwrap(response);

        if (!student || !studentId()) {
            throw new Error(
                "Authenticated account has no student record."
            );
        }

        renderIdentity();
    }

    async function loadRegistration() {
        const sid = studentId();

        const registrations = rows(
            await api(
                "/registrations?student_id=" +
                encodeURIComponent(sid) +
                "&limit=100"
            )
        );

        let courses = [];

        try {
            courses = rows(
                await api(
                    "/registrations/courses?student_id=" +
                    encodeURIComponent(sid) +
                    "&limit=100"
                )
            );
        } catch (_) {}

        const current = registrations[0] || {};

        setContent(
            summary([
                {
                    label: "Registration status",
                    value:
                        current.registration_status ||
                        "No registration"
                },
                {
                    label: "Registration number",
                    value:
                        current.registration_number ||
                        student?.registration_number
                },
                {
                    label: "Registered credits",
                    value:
                        current.total_registered_credits
                },
                {
                    label: "Registered courses",
                    value: courses.length
                }
            ]) +
            `<h3>Semester Registration</h3>` +
            table([
                {
                    label: "Registration",
                    value: r =>
                        r.registration_number || r.id
                },
                {
                    label: "Academic Year",
                    value: r => r.academic_year_id
                },
                {
                    label: "Semester",
                    value: r => r.semester_id
                },
                {
                    label: "Credits",
                    value: r => r.total_registered_credits
                },
                {
                    label: "Status",
                    html: true,
                    value: r => badge(r.registration_status)
                }
            ], registrations) +
            `<h3 style="margin-top:24px">Registered Courses</h3>` +
            table([
                {
                    label: "Course Offering",
                    value: r => r.course_offering_id
                },
                {
                    label: "Registration",
                    value: r => r.student_registration_id
                },
                {
                    label: "Status",
                    html: true,
                    value: r => badge(r.registration_status)
                }
            ], courses)
        );
    }

    async function loadAttendance() {
        const sid = studentId();

        const records = rows(
            await api(
                "/attendance/records?student_id=" +
                encodeURIComponent(sid) +
                "&limit=100"
            )
        );

        const present = records.filter(r =>
            String(r.attendance_status || "")
                .toUpperCase() === "PRESENT"
        ).length;

        const late = records.filter(r =>
            String(r.attendance_status || "")
                .toUpperCase() === "LATE"
        ).length;

        const absent = records.filter(r =>
            String(r.attendance_status || "")
                .toUpperCase() === "ABSENT"
        ).length;

        const attended = present + late;

        const percentage =
            records.length
                ? ((attended / records.length) * 100).toFixed(1) + "%"
                : "—";

        setContent(
            summary([
                { label: "Attendance records", value: records.length },
                { label: "Present", value: present },
                { label: "Late", value: late },
                { label: "Attendance rate", value: percentage }
            ]) +
            table([
                {
                    label: "Session",
                    value: r => r.attendance_session_id
                },
                {
                    label: "Status",
                    html: true,
                    value: r => badge(r.attendance_status)
                },
                {
                    label: "Check-in",
                    value: r => r.check_in_time
                },
                {
                    label: "Minutes Late",
                    value: r => r.minutes_late
                },
                {
                    label: "Remarks",
                    value: r => r.remarks
                }
            ], records)
        );
    }

    async function loadResults() {
        const sid = studentId();

        const [courseResponse, semesterResponse, cgpaResponse] =
            await Promise.all([
                api(
                    "/results/course-results?student_id=" +
                    encodeURIComponent(sid) +
                    "&limit=100"
                ),
                api(
                    "/results/semester-results?student_id=" +
                    encodeURIComponent(sid) +
                    "&limit=100"
                ),
                api(
                    "/results/cgpa-records?student_id=" +
                    encodeURIComponent(sid) +
                    "&limit=100"
                )
            ]);

        const courseResults = rows(courseResponse);
        const semesterResults = rows(semesterResponse);
        const cgpaRecords = rows(cgpaResponse);

        const latestSemester = semesterResults[0] || {};
        const latestCgpa = cgpaRecords[0] || {};

        setContent(
            summary([
                {
                    label: "Latest GPA",
                    value: latestSemester.gpa
                },
                {
                    label: "CGPA",
                    value: latestCgpa.cgpa
                },
                {
                    label: "Courses",
                    value: courseResults.length
                },
                {
                    label: "Academic standing",
                    value:
                        latestSemester.academic_standing ||
                        "—"
                }
            ]) +
            table([
                {
                    label: "Course Offering",
                    value: r => r.course_offering_id
                },
                {
                    label: "Credits",
                    value: r => r.credits
                },
                {
                    label: "Coursework",
                    value: r => r.coursework_mark
                },
                {
                    label: "Exam",
                    value: r => r.examination_mark
                },
                {
                    label: "Total",
                    value: r => r.total_mark
                },
                {
                    label: "Grade",
                    value: r => r.grade_code
                },
                {
                    label: "Result",
                    html: true,
                    value: r =>
                        badge(
                            r.pass_status ||
                            r.result_status
                        )
                }
            ], courseResults)
        );
    }

    async function loadTimetable() {
        const sid = studentId();

        const courseRegistrations = rows(
            await api(
                "/registrations/courses?student_id=" +
                encodeURIComponent(sid) +
                "&limit=100"
            )
        );

        const offeringIds = [
            ...new Set(
                courseRegistrations
                    .map(r => r.course_offering_id)
                    .filter(Boolean)
            )
        ];

        let entries = [];

        for (const offeringId of offeringIds) {
            try {
                const result = rows(
                    await api(
                        "/timetables/entries?course_offering_id=" +
                        encodeURIComponent(offeringId) +
                        "&limit=100"
                    )
                );

                entries.push(...result);
            } catch (_) {}
        }

        const unique = new Map();

        for (const entry of entries) {
            unique.set(entry.id || JSON.stringify(entry), entry);
        }

        entries = [...unique.values()];

        const slotIds = [
            ...new Set(
                entries
                    .map(r => r.timetable_slot_id)
                    .filter(Boolean)
            )
        ];

        const slots = new Map();

        for (const slotId of slotIds) {
            try {
                const response =
                    await api(
                        "/timetables/slots/" +
                        encodeURIComponent(slotId)
                    );

                const slot = unwrap(response);

                if (slot) {
                    slots.set(slotId, slot);
                }
            } catch (_) {}
        }

        setContent(
            summary([
                {
                    label: "Registered courses",
                    value: offeringIds.length
                },
                {
                    label: "Timetable entries",
                    value: entries.length
                },
                {
                    label: "Classes",
                    value:
                        new Set(
                            entries.map(r => r.class_id).filter(Boolean)
                        ).size
                },
                {
                    label: "Venues",
                    value:
                        new Set(
                            entries.map(r => r.room_id).filter(Boolean)
                        ).size
                }
            ]) +
            table([
                {
                    label: "Day",
                    value: r => {
                        const s = slots.get(r.timetable_slot_id);
                        return (
                            s?.day_of_week ||
                            s?.day_name ||
                            s?.slot_name
                        );
                    }
                },
                {
                    label: "Course Offering",
                    value: r => r.course_offering_id
                },
                {
                    label: "Start",
                    value: r => {
                        const s = slots.get(r.timetable_slot_id);
                        return s?.start_time;
                    }
                },
                {
                    label: "End",
                    value: r => {
                        const s = slots.get(r.timetable_slot_id);
                        return s?.end_time;
                    }
                },
                {
                    label: "Room",
                    value: r => r.room_id
                },
                {
                    label: "Status",
                    html: true,
                    value: r => badge(r.status)
                }
            ], entries)
        );
    }

    async function loadFees() {
        const sid = studentId();
        const base =
            "/finance/students/" +
            encodeURIComponent(sid);

        const accountResponse =
            await api(base + "/account");

        const account = unwrap(accountResponse) || {};

        const [
            transactionsResponse,
            invoicesResponse,
            paymentsResponse
        ] = await Promise.all([
            api(base + "/transactions"),
            api(base + "/invoices")
                .catch(() => ({ data: [] })),
            api(base + "/payments")
                .catch(() => ({ data: [] }))
        ]);

        const transactions = rows(transactionsResponse);
        const invoices = rows(invoicesResponse);
        const payments = rows(paymentsResponse);

        const balance =
            account.balance ??
            account.outstanding_balance ??
            account.current_balance ??
            account.account_balance;

        setContent(
            summary([
                {
                    label: "Outstanding balance",
                    value: balance
                },
                {
                    label: "Transactions",
                    value: transactions.length
                },
                {
                    label: "Invoices",
                    value: invoices.length
                },
                {
                    label: "Payments",
                    value: payments.length
                }
            ]) +
            `<h3>Transactions</h3>` +
            table([
                {
                    label: "Date",
                    value: r =>
                        r.transaction_date ||
                        r.created_at
                },
                {
                    label: "Reference",
                    value: r =>
                        r.reference_number ||
                        r.transaction_number ||
                        r.id
                },
                {
                    label: "Type",
                    value: r => r.transaction_type
                },
                {
                    label: "Description",
                    value: r => r.description
                },
                {
                    label: "Amount",
                    value: r => r.amount
                }
            ], transactions)
        );
    }

    async function loadDocuments() {
        const sid = studentId();

        const candidates = [
            "/documents/documents?entity_type=students&entity_id=" +
                encodeURIComponent(sid) +
                "&limit=100",

            "/documents/documents?entity_type=student&entity_id=" +
                encodeURIComponent(sid) +
                "&limit=100"
        ];

        let documents = [];

        for (const path of candidates) {
            try {
                const found = rows(await api(path));

                for (const item of found) {
                    if (!documents.some(d => d.id === item.id)) {
                        documents.push(item);
                    }
                }
            } catch (_) {}
        }

        setContent(
            summary([
                {
                    label: "Documents",
                    value: documents.length
                },
                {
                    label: "Active",
                    value: documents.filter(r =>
                        String(r.status || "").toUpperCase() === "ACTIVE"
                    ).length
                },
                {
                    label: "With files",
                    value: documents.filter(r => r.file_url).length
                },
                {
                    label: "Student",
                    value:
                        student?.registration_number ||
                        student?.student_number
                }
            ]) +
            table([
                {
                    label: "Document",
                    value: r =>
                        r.title ||
                        r.file_name ||
                        r.document_number
                },
                {
                    label: "Type",
                    value: r => r.document_type
                },
                {
                    label: "Version",
                    value: r => r.current_version
                },
                {
                    label: "Status",
                    html: true,
                    value: r => badge(r.status)
                },
                {
                    label: "File",
                    html: true,
                    value: r => {
                        if (!r.file_url) return "—";

                        const safeUrl = esc(r.file_url);

                        return `
                            <a class="portal-document-link"
                               href="${safeUrl}"
                               target="_blank"
                               rel="noopener noreferrer">
                                Open
                            </a>
                        `;
                    }
                }
            ], documents)
        );
    }

    async function loadNotifications() {
        const announcements = rows(
            await api(
                "/communications/announcements?limit=100"
            )
        );

        const now = new Date();

        const visible = announcements.filter(item => {
            const status =
                String(item.status || "").toUpperCase();

            if (
                status &&
                !["PUBLISHED", "ACTIVE"].includes(status)
            ) {
                return false;
            }

            if (item.publish_at) {
                const publishAt = new Date(item.publish_at);

                if (
                    !Number.isNaN(publishAt.getTime()) &&
                    publishAt > now
                ) {
                    return false;
                }
            }

            if (item.expire_at) {
                const expireAt = new Date(item.expire_at);

                if (
                    !Number.isNaN(expireAt.getTime()) &&
                    expireAt < now
                ) {
                    return false;
                }
            }

            return true;
        });

        setContent(
            summary([
                {
                    label: "Announcements",
                    value: visible.length
                },
                {
                    label: "High priority",
                    value: visible.filter(r =>
                        ["HIGH", "URGENT"].includes(
                            String(r.priority || "").toUpperCase()
                        )
                    ).length
                },
                {
                    label: "General",
                    value: visible.filter(r =>
                        String(r.announcement_type || "")
                            .toUpperCase() === "GENERAL"
                    ).length
                },
                {
                    label: "Student",
                    value:
                        student?.registration_number ||
                        student?.student_number
                }
            ]) +
            table([
                {
                    label: "Published",
                    value: r =>
                        r.published_at ||
                        r.publish_at ||
                        r.created_at
                },
                {
                    label: "Title",
                    value: r => r.title
                },
                {
                    label: "Message",
                    value: r =>
                        r.summary ||
                        r.body
                },
                {
                    label: "Priority",
                    html: true,
                    value: r => badge(r.priority)
                }
            ], visible)
        );
    }

    async function loadView() {
        switch (view) {
            case "registration":
                return loadRegistration();

            case "attendance":
                return loadAttendance();

            case "results":
                return loadResults();

            case "timetable":
                return loadTimetable();

            case "fees":
                return loadFees();

            case "documents":
                return loadDocuments();

            case "notifications":
                return loadNotifications();

            default:
                throw new Error(
                    "Unknown student portal page: " + view
                );
        }
    }

    async function refresh() {
        loading("Loading " + title);

        try {
            await loadView();
        } catch (error) {
            console.error(
                "Student portal load failed:",
                error
            );

            errorState(error);
        }
    }

    async function boot() {
        loading("Preparing student portal");

        try {
            await requireAuth();
            await requirePermission();
            await loadStudent();
            await loadView();
        } catch (error) {
            console.error(
                "Student portal initialization failed:",
                error
            );

            errorState(error);
        }
    }

    document.addEventListener(
        "DOMContentLoaded",
        function () {
            const refreshButton =
                el("portalRefreshButton");

            if (refreshButton) {
                refreshButton.addEventListener(
                    "click",
                    refresh
                );
            }

            document
                .querySelectorAll(".portal-nav a[data-view]")
                .forEach(link => {
                    if (link.dataset.view === view) {
                        link.classList.add("active");
                    }
                });

            boot();
        }
    );

    window.IDMCStudentPortalPage = {
        refresh: refresh
    };
})();