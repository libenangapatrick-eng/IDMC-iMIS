(() => {

    "use strict";

    const REQUIRED_PERMISSION =
        "students.view";

    let students = [];

    const $ =
        (selector) =>
            document.querySelector(
                selector
            );

    function escapeHtml(
        value
    ) {

        return String(
            value ?? ""
        )
            .replace(
                /&/g,
                "&amp;"
            )
            .replace(
                /</g,
                "&lt;"
            )
            .replace(
                />/g,
                "&gt;"
            )
            .replace(
                /"/g,
                "&quot;"
            )
            .replace(
                /'/g,
                "&#039;"
            );

    }

    function setStatus(
        text
    ) {

        const element =
            $("#studentsStatus");

        if (element) {
            element.textContent =
                text;
        }

    }

    function getStudentName(
        student
    ) {

        return [
            student.first_name,
            student.middle_name,
            student.last_name
        ]
            .filter(Boolean)
            .join(" ");

    }

    function render(
        records
    ) {

        const body =
            $("#studentsBody");

        if (!body) {
            return;
        }

        if (!records.length) {

            body.innerHTML = `
                <tr>
                    <td
                        colspan="7"
                        class="empty-state"
                    >
                        No student records found.
                    </td>
                </tr>
            `;

            return;
        }

        body.innerHTML =
            records
                .map(
                    student => `
                        <tr>

                            <td>
                                ${escapeHtml(
                                    student.student_number
                                )}
                            </td>

                            <td>
                                ${escapeHtml(
                                    getStudentName(
                                        student
                                    )
                                )}
                            </td>

                            <td>
                                ${escapeHtml(
                                    student.gender ||
                                    "—"
                                )}
                            </td>

                            <td>
                                ${escapeHtml(
                                    student.email ||
                                    "—"
                                )}
                            </td>

                            <td>
                                ${escapeHtml(
                                    student.phone ||
                                    "—"
                                )}
                            </td>

                            <td>
                                ${escapeHtml(
                                    student.student_status ||
                                    "—"
                                )}
                            </td>

                            <td>

                                <a
                                    class="view-link"
                                    href="#"
                                    data-student-id="${
                                        escapeHtml(
                                            student.id
                                        )
                                    }"
                                >
                                    View
                                </a>

                            </td>

                        </tr>
                    `
                )
                .join("");

    }

    async function loadStudents() {

        setStatus(
            "Loading students..."
        );

        const body =
            $("#studentsBody");

        if (body) {

            body.innerHTML = `
                <tr>
                    <td
                        colspan="7"
                        class="loading-state"
                    >
                        Loading student records...
                    </td>
                </tr>
            `;

        }

        try {

            if (
                !window.IDMC_RBAC_API ||
                typeof
                    window.IDMC_RBAC_API.request !==
                    "function"
            ) {

                throw new Error(
                    "IDMC frontend RBAC API is not available."
                );

            }

            if (
                typeof
                    window.IDMC_RBAC_API.hasPermission ===
                    "function"
            ) {

                if (
                    !window.IDMC_RBAC_API.hasPermission(
                        REQUIRED_PERMISSION
                    )
                ) {

                    throw new Error(
                        "You do not have permission to view students."
                    );

                }

            }

            const search =
                $("#studentSearch")
                    ?.value
                    ?.trim() || "";

            const status =
                $("#studentStatus")
                    ?.value
                    ?.trim() || "";

            const params =
                new URLSearchParams();

            params.set(
                "page",
                "1"
            );

            params.set(
                "limit",
                "50"
            );

            if (search) {
                params.set(
                    "search",
                    search
                );
            }

            if (status) {
                params.set(
                    "status",
                    status
                );
            }

            const result =
                await window.IDMC_RBAC_API.request(
                    `/students?${params.toString()}`
                );

            students =
                Array.isArray(
                    result?.data?.items
                )
                    ? result.data.items
                    : [];

            render(
                students
            );

            setStatus(
                `${students.length} student(s)`
            );

        } catch (error) {

            console.error(
                "Students load failed:",
                error
            );

            students = [];

            if (body) {

                body.innerHTML = `
                    <tr>
                        <td
                            colspan="7"
                            class="error-state"
                        >
                            ${escapeHtml(
                                error?.message ||
                                "Unable to load students."
                            )}
                        </td>
                    </tr>
                `;

            }

            setStatus(
                "Unable to load"
            );

        }

    }

    async function viewStudent(
        id
    ) {

        if (!id) {
            return;
        }

        try {

            const result =
                await window.IDMC_RBAC_API.request(
                    `/students/${encodeURIComponent(id)}`
                );

            const student =
                result?.data;

            if (!student) {
                throw new Error(
                    "Student record not found."
                );
            }

            const name =
                getStudentName(
                    student
                );

            alert(
                [
                    `Student Number: ${
                        student.student_number ||
                        "—"
                    }`,
                    `Name: ${name || "—"}`,
                    `Status: ${
                        student.student_status ||
                        "—"
                    }`,
                    `Email: ${
                        student.email ||
                        "—"
                    }`,
                    `Phone: ${
                        student.phone ||
                        "—"
                    }`
                ].join("\n")
            );

        } catch (error) {

            console.error(
                "Student details failed:",
                error
            );

            alert(
                error?.message ||
                "Unable to load student details."
            );

        }

    }

    document.addEventListener(
        "click",
        event => {

            const link =
                event.target.closest(
                    "[data-student-id]"
                );

            if (!link) {
                return;
            }

            event.preventDefault();

            viewStudent(
                link.dataset.studentId
            );

        }
    );

    $("#studentSearch")
        ?.addEventListener(
            "input",
            () => {

                clearTimeout(
                    window.__idmcStudentSearchTimer
                );

                window.__idmcStudentSearchTimer =
                    setTimeout(
                        loadStudents,
                        300
                    );

            }
        );

    $("#studentStatus")
        ?.addEventListener(
            "change",
            loadStudents
        );

    $("#refreshStudents")
        ?.addEventListener(
            "click",
            loadStudents
        );

    async function initialize() {

        try {

            if (
                window.IDMCAuth &&
                typeof
                    window.IDMCAuth.requireAuth ===
                    "function"
            ) {

                await window.IDMCAuth.requireAuth();

            }

            await loadStudents();

        } catch (error) {

            console.error(
                "Student page initialization failed:",
                error
            );

        }

    }

    if (
        document.readyState ===
        "loading"
    ) {

        document.addEventListener(
            "DOMContentLoaded",
            initialize,
            {
                once: true
            }
        );

    } else {

        initialize();

    }

    window.IDMC_STUDENTS = {
        reload:
            loadStudents
    };

})();
