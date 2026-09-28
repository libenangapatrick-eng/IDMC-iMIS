(function () {
    "use strict";

    let student = null;
    let portalData = null;

    function byId(id) {
        return document.getElementById(id);
    }

    function safe(value, fallback = "—") {
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
        return safe(value, "")
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

    function rows(response) {

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

        if (Array.isArray(data?.data)) {
            return data.data;
        }

        return [];
    }

    async function get(path) {

        if (
            !window.IDMCAPI ||
            typeof window.IDMCAPI.get !== "function"
        ) {
            throw new Error(
                "IDMC API client is not available."
            );
        }

        return window.IDMCAPI.get(path);
    }

    function getStudentId() {

        return (
            student?.id ||
            student?.student_id ||
            student?.studentId ||
            null
        );
    }

    function getStudentName() {

        const direct =
            student?.full_name ||
            student?.student_name ||
            student?.name;

        if (direct) {
            return direct;
        }

        const combined = [
            student?.first_name,
            student?.middle_name,
            student?.last_name
        ]
            .filter(Boolean)
            .join(" ");

        if (combined) {
            return combined;
        }

        const user =
            window.IDMCAuth?.getUser?.();

        return (
            user?.user_metadata?.full_name ||
            user?.email ||
            "Student"
        );
    }

    function setText(id, value) {

        const element = byId(id);

        if (element) {
            element.textContent = safe(value);
        }
    }

    function renderStudent() {

        const name =
            getStudentName();

        const number =
            student?.registration_number ||
            student?.student_number ||
            student?.admission_number;

        const programme =
            student?.programme_name ||
            student?.program_name ||
            student?.programme_code ||
            student?.programme_id;

        setText(
            "currentUserName",
            name
        );

        setText(
            "studentName",
            name
        );

        setText(
            "heroStudentName",
            name
        );

        setText(
            "studentNumber",
            number
        );

        setText(
            "studentProgramme",
            programme
        );

        setText(
            "detailRegistrationNumber",
            number
        );

        setText(
            "detailProgramme",
            programme
        );

        setText(
            "detailStatus",
            student?.student_status || student?.status
        );

        setText(
            "detailEmail",
            student?.email
        );

        for (const id of ["topAvatarPhoto", "sideAvatarPhoto"]) {
            const image = byId(id);
            if (image && student?.profile_photo_url) {
                image.src = student.profile_photo_url;
                image.parentElement?.classList.add("has-photo");
            }
        }
    }

    async function requireAuthentication() {

        if (
            !window.IDMCAuth ||
            typeof window.IDMCAuth.requireAuth !==
                "function"
        ) {
            throw new Error(
                "Authentication service is unavailable."
            );
        }

        const authenticated =
            await window.IDMCAuth.requireAuth();

        if (!authenticated) {
            throw new Error(
                "Authentication is required."
            );
        }
    }

    async function loadStudent() {

        const response = await get("/students/me/portal");
        portalData = unwrap(response) || {};
        student = portalData.student;

        if (
            !student ||
            !getStudentId()
        ) {
            throw new Error(
                "No student profile is linked to this account."
            );
        }

        renderStudent();
    }

    async function optionalGet(path) {

        try {
            return await get(path);
        }
        catch (error) {

            console.warn(
                "Optional portal request failed:",
                path,
                error
            );

            return null;
        }
    }

    async function loadRegistrationSummary() {

        const registrations = portalData?.registrations || [];

        const current =
            registrations[0] || {};

        setText(
            "registrationStatus",
            current.registration_status ||
            (registrations.length
                ? "Available"
                : "No record")
        );
    }

    async function loadAttendanceSummary() {

        const records = portalData?.attendance_records || [];

        let attended = 0;

        for (const record of records) {

            const status =
                String(
                    record.attendance_status ||
                    ""
                ).toUpperCase();

            if (
                status === "PRESENT" ||
                status === "LATE"
            ) {
                attended++;
            }
        }

        const rate =
            records.length
                ? (
                    (attended / records.length) *
                    100
                ).toFixed(1) + "%"
                : "—";

        setText(
            "attendanceRate",
            rate
        );
    }

    async function loadResultSummary() {

        const semesterResults = portalData?.semester_results || [];
        const cgpaRecords = portalData?.cgpa_records || [];

        const latestSemester =
            semesterResults[0] || {};

        const latestCgpa =
            cgpaRecords[0] || {};

        setText(
            "latestGpa",
            latestSemester.gpa
        );

        setText(
            "latestCgpa",
            latestCgpa.cgpa
        );
    }

    async function loadFinanceSummary() {

        const account = portalData?.financial_account || {};

        const balance =
            account.balance ??
            account.outstanding_balance ??
            account.current_balance ??
            account.account_balance;

        setText(
            "financeBalance",
            balance
        );
    }

    async function loadModuleCounts() {

        const registrationCourses = portalData?.course_registrations || [];
        const attendance = portalData?.attendance_records || [];
        const results = portalData?.course_results || [];
        const transactions = portalData?.payments || [];
        const documents = portalData?.documents || [];
        const announcements = portalData?.announcements || [];

        setText(
            "registrationCount",
            registrationCourses.length
        );

        setText(
            "attendanceCount",
            attendance.length
        );

        setText(
            "resultsCount",
            results.length
        );

        setText(
            "financeCount",
            transactions.length
        );

        setText(
            "documentsCount",
            documents.length
        );

        setText(
            "notificationsCount",
            announcements.length
        );
    }

    function formatDate(value) {

        if (!value) {
            return "";
        }

        const date =
            new Date(value);

        if (
            Number.isNaN(
                date.getTime()
            )
        ) {
            return safe(value);
        }

        return date.toLocaleDateString(
            undefined,
            {
                year: "numeric",
                month: "short",
                day: "numeric"
            }
        );
    }

    async function loadAnnouncements() {

        const container =
            byId("announcementList");

        if (!container) {
            return;
        }

        const announcements =
            (portalData?.announcements || [])
                .filter(item => {

                    const status =
                        String(
                            item.status || ""
                        ).toUpperCase();

                    return (
                        !status ||
                        status === "ACTIVE" ||
                        status === "PUBLISHED"
                    );
                })
                .slice(0, 5);

        if (!announcements.length) {

            container.innerHTML =
                '<div class="empty-state">' +
                'No active announcements.' +
                '</div>';

            return;
        }

        container.innerHTML =
            announcements
                .map(item => {

                    const title =
                        escapeHtml(
                            item.title ||
                            "Announcement"
                        );

                    const message =
                        escapeHtml(
                            item.summary ||
                            item.body ||
                            item.message ||
                            ""
                        );

                    const date =
                        escapeHtml(
                            formatDate(
                                item.published_at ||
                                item.publish_at ||
                                item.created_at
                            )
                        );

                    return `
                        <article class="announcement">

                            <div class="announcement-top">

                                <h4>${title}</h4>

                            </div>

                            <p>${message}</p>

                            ${
                                date
                                    ? `<div class="announcement-date">${date}</div>`
                                    : ""
                            }

                        </article>
                    `;
                })
                .join("");
    }

    async function loadDashboardData() {

        await Promise.all([
            loadRegistrationSummary(),
            loadAttendanceSummary(),
            loadResultSummary(),
            loadFinanceSummary(),
            loadModuleCounts(),
            loadAnnouncements()
        ]);
    }

    function showFatal(error) {

        console.error(
            "Student portal failed:",
            error
        );

        const main =
            byId("portalMain");

        if (!main) {
            return;
        }

        main.innerHTML = `
            <div class="panel">
                <div class="panel-body">
                    <div class="error-box">
                        <strong>
                            Student portal could not be loaded.
                        </strong>
                        <div style="margin-top:6px">
                            ${escapeHtml(
                                error?.message ||
                                "Unknown error."
                            )}
                        </div>
                    </div>
                </div>
            </div>
        `;
    }

    async function refreshPortal() {

        const button =
            byId("refreshPortal");

        if (button) {
            button.disabled = true;
        }

        try {

            await loadStudent();
            await loadDashboardData();

        }
        catch (error) {

            showFatal(error);

        }
        finally {

            if (button) {
                button.disabled = false;
            }
        }
    }

    async function boot() {

        try {

            await requireAuthentication();

            await loadStudent();

            await loadDashboardData();

        }
        catch (error) {

            showFatal(error);
        }
    }

    document.addEventListener(
        "DOMContentLoaded",
        function () {

            const refresh =
                byId("refreshPortal");

            if (refresh) {

                refresh.addEventListener(
                    "click",
                    refreshPortal
                );
            }

            boot();
        }
    );

    window.IDMCStudentPortalHome = {
        refresh: refreshPortal
    };

})();
