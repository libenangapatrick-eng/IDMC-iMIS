(function () {
    "use strict";

    const config =
        window.IDMC_STUDENT_PAGE || {};

    const view =
        String(config.view || "").trim();

    const permission =
        String(config.permission || "").trim();

    const title =
        String(config.title || "Student Portal");

    let student = null;

    function byId(id) {
        return document.getElementById(id);
    }

    function text(value, fallback = "—") {
        if (
            value === null ||
            value === undefined ||
            value === ""
        ) {
            return fallback;
        }

        return String(value);
    }

    function escapeHtml(value) {
        return text(value, "")
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
            Object.prototype.hasOwnProperty.call(
                response,
                "data"
            )
        ) {
            return response.data;
        }

        return response;
    }

    function items(response) {
        const data = unwrap(response);

        if (Array.isArray(data)) {
            return data;
        }

        if (Array.isArray(data?.items)) {
            return data.items;
        }

        if (Array.isArray(data?.rows)) {
            return data.rows;
        }

        return [];
    }

    function setState(message, isError = false) {
        const root = byId("page-content");

        if (!root) {
            return;
        }

        root.innerHTML =
            '<div class="idmc-state' +
            (isError ? ' idmc-error' : '') +
            '">' +
            '<div><strong>' +
            (isError ? "Unable to load" : "Loading") +
            '</strong>' +
            escapeHtml(message) +
            "</div></div>";
    }

    async function api(path, options = {}) {
        if (
            !window.IDMCAPI ||
            typeof window.IDMCAPI.request !== "function"
        ) {
            throw new Error(
                "IDMC API client is unavailable."
            );
        }

        return window.IDMCAPI.request(
            path,
            options
        );
    }

    async function requireAuth() {
        if (
            !window.IDMCAuth ||
            typeof window.IDMCAuth.requireAuth !==
                "function"
        ) {
            throw new Error(
                "Authentication service is unavailable."
            );
        }

        const allowed =
            await window.IDMCAuth.requireAuth();

        if (!allowed) {
            throw new Error(
                "Authentication is required."
            );
        }
    }

    async function requirePermission() {
        if (!permission) {
            return true;
        }

        const rbac =
            window.IDMC_RBAC_API;

        if (
            !rbac ||
            typeof rbac.hasPermission !== "function"
        ) {
            return true;
        }

        const allowed =
            await rbac.hasPermission(permission);

        if (!allowed) {
            throw new Error(
                "You do not have permission to view this page."
            );
        }

        return true;
    }

    function getStudentId(record) {
        return (
            record?.id ||
            record?.student_id ||
            record?.studentId ||
            null
        );
    }

    function studentName(record) {
        return (
            record?.full_name ||
            record?.student_name ||
            [
                record?.first_name,
                record?.middle_name,
                record?.last_name
            ]
                .filter(Boolean)
                .join(" ") ||
            "Student"
        );
    }

    function renderIdentity() {
        const user =
            window.IDMCAuth?.getUser?.();

        const userName =
            user?.user_metadata?.full_name ||
            user?.email ||
            "Student";

        const name =
            studentName(student) ||
            userName;

        const registration =
            student?.registration_number ||
            student?.student_number ||
            student?.admission_number ||
            "—";

        const programme =
            student?.programme_name ||
            student?.program_name ||
            student?.programme_code ||
            "—";

        if (byId("current-user")) {
            byId("current-user").textContent =
                name;
        }

        if (byId("student-name")) {
            byId("student-name").textContent =
                name;
        }

        if (byId("student-number")) {
            byId("student-number").textContent =
                registration;
        }

        if (byId("student-programme")) {
            byId("student-programme").textContent =
                programme;
        }
    }

    function table(columns, rows) {
        if (!rows.length) {
            return (
                '<div class="idmc-state">' +
                "<div><strong>No records found</strong>" +
                "There is currently no information " +
                "available for this section.</div></div>"
            );
        }

        const head =
            columns.map((column) =>
                "<th>" +
                escapeHtml(column.label) +
                "</th>"
            ).join("");

        const body =
            rows.map((row) => {
                const cells =
                    columns.map((column) => {
                        let value;

                        if (
                            typeof column.value ===
                            "function"
                        ) {
                            value =
                                column.value(row);
                        } else {
                            value =
                                row[column.value];
                        }

                        return (
                            "<td>" +
                            escapeHtml(
                                text(value)
                            ) +
                            "</td>"
                        );
                    }).join("");

                return "<tr>" + cells + "</tr>";
            }).join("");

        return (
            '<div class="idmc-table-wrap">' +
            '<table class="idmc-table">' +
            "<thead><tr>" +
            head +
            "</tr></thead>" +
            "<tbody>" +
            body +
            "</tbody></table></div>"
        );
    }

    function renderTable(columns, rows) {
        const root = byId("page-content");

        if (root) {
            root.innerHTML =
                table(columns, rows);
        }

        if (byId("record-count")) {
            byId("record-count").textContent =
                String(rows.length);
        }
    }

    async function loadStudent() {
        const response =
            await api("/students/me");

        student =
            unwrap(response);

        if (!student) {
            throw new Error(
                "Student profile could not be resolved."
            );
        }

        renderIdentity();
    }

    async function loadRegistration() {
        const studentId =
            getStudentId(student);

        const response =
            await api(
                "/registrations" +
                (studentId
                    ? "?student_id=" +
                      encodeURIComponent(studentId)
                    : "")
            );

        const rows = items(response);

        renderTable(
            [
                {
                    label: "Registration",
                    value: (r) =>
                        r.registration_number ||
                        r.id
                },
                {
                    label: "Academic Year",
                    value: (r) =>
                        r.academic_year_name ||
                        r.academic_year_id
                },
                {
                    label: "Semester",
                    value: (r) =>
                        r.semester_name ||
                        r.semester_id
                },
                {
                    label: "Status",
                    value: (r) =>
                        r.registration_status ||
                        r.status
                }
            ],
            rows
        );
    }

    async function loadAttendance() {
        const studentId =
            getStudentId(student);

        const response =
            await api(
                "/attendance" +
                (studentId
                    ? "?student_id=" +
                      encodeURIComponent(studentId)
                    : "")
            );

        const rows = items(response);

        renderTable(
            [
                {
                    label: "Date",
                    value: (r) =>
                        r.attendance_date ||
                        r.session_date ||
                        r.created_at
                },
                {
                    label: "Course",
                    value: (r) =>
                        r.course_name ||
                        r.course_code ||
                        r.course_id
                },
                {
                    label: "Status",
                    value: (r) =>
                        r.attendance_status ||
                        r.status
                },
                {
                    label: "Remarks",
                    value: (r) =>
                        r.remarks
                }
            ],
            rows
        );
    }

    async function loadResults() {
        const studentId =
            getStudentId(student);

        const paths = [
            "/results/course-results" +
                (studentId
                    ? "?student_id=" +
                      encodeURIComponent(studentId)
                    : ""),
            "/course-results" +
                (studentId
                    ? "?student_id=" +
                      encodeURIComponent(studentId)
                    : "")
        ];

        let response = null;
        let lastError = null;

        for (const path of paths) {
            try {
                response =
                    await api(path);
                lastError = null;
                break;
            } catch (error) {
                lastError = error;
            }
        }

        if (lastError) {
            throw lastError;
        }

        const rows = items(response);

        renderTable(
            [
                {
                    label: "Course",
                    value: (r) =>
                        r.course_name ||
                        r.course_code ||
                        r.course_id
                },
                {
                    label: "Mark",
                    value: (r) =>
                        r.total_mark ??
                        r.final_mark ??
                        r.mark
                },
                {
                    label: "Grade",
                    value: (r) =>
                        r.grade_code ||
                        r.grade
                },
                {
                    label: "Status",
                    value: (r) =>
                        r.result_status ||
                        r.pass_status ||
                        r.status
                }
            ],
            rows
        );
    }

    async function loadTimetable() {
        const response =
            await api("/timetables");

        const rows = items(response);

        renderTable(
            [
                {
                    label: "Day",
                    value: (r) =>
                        r.day_of_week ||
                        r.day ||
                        r.session_date
                },
                {
                    label: "Course",
                    value: (r) =>
                        r.course_name ||
                        r.course_code ||
                        r.course_id
                },
                {
                    label: "Start",
                    value: (r) =>
                        r.start_time
                },
                {
                    label: "End",
                    value: (r) =>
                        r.end_time
                },
                {
                    label: "Venue",
                    value: (r) =>
                        r.venue_name ||
                        r.room_name ||
                        r.venue_id
                }
            ],
            rows
        );
    }

    async function loadFees() {
        const studentId =
            getStudentId(student);

        if (!studentId) {
            throw new Error(
                "Student ID is unavailable."
            );
        }

        const account =
            unwrap(
                await api(
                    "/finance/students/" +
                    encodeURIComponent(studentId) +
                    "/account"
                )
            );

        const transactions =
            items(
                await api(
                    "/finance/students/" +
                    encodeURIComponent(studentId) +
                    "/transactions"
                )
            );

        if (byId("balance-value")) {
            byId("balance-value").textContent =
                text(
                    account?.balance ??
                    account?.outstanding_balance ??
                    account?.current_balance
                );
        }

        renderTable(
            [
                {
                    label: "Date",
                    value: (r) =>
                        r.transaction_date ||
                        r.created_at
                },
                {
                    label: "Reference",
                    value: (r) =>
                        r.reference_number ||
                        r.transaction_number ||
                        r.id
                },
                {
                    label: "Description",
                    value: (r) =>
                        r.description ||
                        r.transaction_type
                },
                {
                    label: "Amount",
                    value: (r) =>
                        r.amount
                }
            ],
            transactions
        );
    }

    async function loadDocuments() {
        const studentId =
            getStudentId(student);

        const response =
            await api(
                "/documents/documents" +
                (studentId
                    ? "?student_id=" +
                      encodeURIComponent(studentId)
                    : "")
            );

        const rows = items(response);

        renderTable(
            [
                {
                    label: "Document",
                    value: (r) =>
                        r.document_name ||
                        r.title ||
                        r.file_name
                },
                {
                    label: "Type",
                    value: (r) =>
                        r.document_type ||
                        r.category
                },
                {
                    label: "Status",
                    value: (r) =>
                        r.document_status ||
                        r.status
                },
                {
                    label: "Updated",
                    value: (r) =>
                        r.updated_at ||
                        r.created_at
                }
            ],
            rows
        );
    }

    async function loadNotifications() {
        const paths = [
            "/communications/notifications",
            "/communications/announcements"
        ];

        let response = null;
        let lastError = null;

        for (const path of paths) {
            try {
                response =
                    await api(path);
                lastError = null;
                break;
            } catch (error) {
                lastError = error;
            }
        }

        if (lastError) {
            throw lastError;
        }

        const rows = items(response);

        renderTable(
            [
                {
                    label: "Date",
                    value: (r) =>
                        r.published_at ||
                        r.created_at
                },
                {
                    label: "Title",
                    value: (r) =>
                        r.title ||
                        r.subject
                },
                {
                    label: "Message",
                    value: (r) =>
                        r.message ||
                        r.body ||
                        r.content
                },
                {
                    label: "Status",
                    value: (r) =>
                        r.status ||
                        r.notification_status
                }
            ],
            rows
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
                    "Unknown student portal view."
                );
        }
    }

    async function refresh() {
        setState(
            "Retrieving " +
            title.toLowerCase() +
            "..."
        );

        try {
            await loadView();
        } catch (error) {
            console.error(error);

            setState(
                error?.message ||
                "The requested information could not be loaded.",
                true
            );
        }
    }

    async function boot() {
        setState("Preparing student portal...");

        try {
            await requireAuth();
            await requirePermission();
            await loadStudent();
            await refresh();
        } catch (error) {
            console.error(error);

            setState(
                error?.message ||
                "The page could not be initialized.",
                true
            );
        }
    }

    window.IDMCStudentPortalPage = {
        refresh
    };

    document.addEventListener(
        "DOMContentLoaded",
        boot
    );
})();