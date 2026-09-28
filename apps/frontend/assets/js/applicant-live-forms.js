(function () {
    "use strict";

/* IDMC_CANONICAL_AUTH_BRIDGE */
function idmcCanonicalAccessToken() {
    try {
        if (
            window.IDMCAuth &&
            typeof window.IDMCAuth.getAccessToken === "function"
        ) {
            const token = window.IDMCAuth.getAccessToken();

            if (
                typeof token === "string" &&
                token.trim()
            ) {
                return token.trim();
            }
        }
    } catch (error) {
        console.warn(
            "IDMCAuth.getAccessToken failed:",
            error
        );
    }

    try {
        const raw = sessionStorage.getItem("idmc_session");

        if (raw) {
            const session = JSON.parse(raw);

            if (
                session &&
                typeof session.access_token === "string" &&
                session.access_token.trim()
            ) {
                return session.access_token.trim();
            }
        }
    } catch (error) {
        console.warn(
            "Could not read idmc_session:",
            error
        );
    }

    return null;
}


    const API = window.IDMC_CONFIG?.API_BASE_URL || "/api/v1";

    const endpoints = {
        applicants: "/applications/applicants",
        applications: "/applications/applications",
        choices: "/applications/choices",
        qualifications: "/applications/qualifications",
        documents: "/applications/documents"
    };

    const state = {
        applicants: [],
        applications: [],
        choices: [],
        qualifications: [],
        documents: [],
        currentApplicantId: "",
        currentApplicationId: ""
    };

    function el(id) {
        return document.getElementById(id);
    }

    function value(id) {
        const node = el(id);
        return node ? String(node.value || "").trim() : "";
    }

    function nullable(id) {
        const result = value(id);
        return result === "" ? null : result;
    }

    function status(message, type) {
        const box = el("idmc-live-status");
        if (!box) return;

        box.className = "idmc-status show " + (type || "info");
        box.textContent = message;
    }

    function clearStatus() {
        const box = el("idmc-live-status");
        if (!box) return;
        box.className = "idmc-status";
        box.textContent = "";
    }

    function escapeHtml(value) {
        return String(value == null ? "" : value)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#039;");
    }

    function token() {
        function validJwt(value) {
            return (
                typeof value === "string" &&
                value.trim() !== "" &&
                value.split(".").length === 3
            );
        }

        function inspect(value) {
            if (!value) {
                return "";
            }

            if (validJwt(value)) {
                return value;
            }

            try {
                const parsed = JSON.parse(value);

                const candidates = [
                    parsed && parsed.access_token,
                    parsed && parsed.accessToken,

                    parsed &&
                    parsed.session &&
                    parsed.session.access_token,

                    parsed &&
                    parsed.session &&
                    parsed.session.accessToken,

                    parsed &&
                    parsed.currentSession &&
                    parsed.currentSession.access_token,

                    parsed &&
                    parsed.data &&
                    parsed.data.session &&
                    parsed.data.session.access_token
                ];

                for (const candidate of candidates) {
                    if (validJwt(candidate)) {
                        return candidate;
                    }
                }

                if (Array.isArray(parsed)) {
                    for (const item of parsed) {
                        if (validJwt(item)) {
                            return item;
                        }

                        if (
                            item &&
                            typeof item === "object" &&
                            validJwt(item.access_token)
                        ) {
                            return item.access_token;
                        }
                    }
                }
            }
            catch (_) {
                // Not JSON.
            }

            return "";
        }

        const directKeys = [
            "idmc_access_token",
            "access_token",
            "supabase_access_token",
            "idmc.session",
            "idmc_session",
            "idmc-auth",
            "idmc_auth",
            "supabase.auth.token"
        ];

        for (const key of directKeys) {
            const localResult =
                inspect(localStorage.getItem(key));

            if (localResult) {
                return localResult;
            }

            const sessionResult =
                inspect(sessionStorage.getItem(key));

            if (sessionResult) {
                return sessionResult;
            }
        }

        const stores = [
            localStorage,
            sessionStorage
        ];

        for (const store of stores) {
            for (let i = 0; i < store.length; i++) {
                const key = store.key(i);

                if (!key) {
                    continue;
                }

                const result =
                    inspect(store.getItem(key));

                if (result) {
                    return result;
                }
            }
        }

        return "";
    }

    async function request(path, options) {
        options = options || {};

        const headers = Object.assign(
            { "Accept": "application/json" },
            options.headers || {}
        );

        let accessToken = token();

        if (accessToken) {
            let canonicalToken = idmcCanonicalAccessToken();

        if (canonicalToken) {
            accessToken = canonicalToken;
        }

        if (!accessToken) {
            throw new Error(
                "Authentication session is missing. Please sign in again."
            );
        }

        headers.Authorization = "Bearer " + accessToken;
        }

        if (options.body && !(options.body instanceof FormData)) {
            headers["Content-Type"] = "application/json";
        }

        const response = await fetch(API + path, {
            method: options.method || "GET",
            headers: headers,
            body: options.body
                ? (options.body instanceof FormData
                    ? options.body
                    : JSON.stringify(options.body))
                : undefined,
            credentials: "same-origin"
        });

        const raw = await response.text();

        let data = null;

        if (raw) {
            try {
                data = JSON.parse(raw);
            } catch (_) {
                data = raw;
            }
        }

        if (!response.ok) {
            let message = "HTTP " + response.status;

            if (data && typeof data === "object") {
                message =
                    data.message ||
                    data.error ||
                    data.detail ||
                    message;
            } else if (typeof data === "string" && data.trim()) {
                message = data.trim();
            }

            throw new Error(message);
        }

        return data;
    }

    function unwrap(data) {
        if (Array.isArray(data)) return data;
        if (!data || typeof data !== "object") return [];

        if (Array.isArray(data.data)) return data.data;
        if (Array.isArray(data.items)) return data.items;
        if (Array.isArray(data.records)) return data.records;
        if (Array.isArray(data.results)) return data.results;

        if (data.data && typeof data.data === "object") {
            if (Array.isArray(data.data.items)) return data.data.items;
            if (Array.isArray(data.data.records)) return data.data.records;
        }

        return [];
    }

    function unwrapOne(data) {
        if (!data || typeof data !== "object") return data;
        return data.data && !Array.isArray(data.data)
            ? data.data
            : data;
    }

    function field(record, names) {
        if (!record) return "";

        for (const name of names) {
            if (record[name] !== undefined && record[name] !== null) {
                return record[name];
            }
        }

        return "";
    }

    function currentApplicationId() {
        return (
            state.currentApplicationId ||
            value("application-id") ||
            ""
        );
    }

    function currentApplicantId() {
        return (
            state.currentApplicantId ||
            value("applicant-id") ||
            ""
        );
    }

    function switchTab(name) {
        document.querySelectorAll(".idmc-live-tab").forEach(function (button) {
            button.classList.toggle(
                "active",
                button.getAttribute("data-tab") === name
            );
        });

        document.querySelectorAll(".idmc-panel").forEach(function (panel) {
            panel.classList.toggle(
                "active",
                panel.getAttribute("data-panel") === name
            );
        });
    }

    function populateApplicationSelects() {
        const ids = [
            "choice-application-id",
            "qualification-application-id",
            "document-application-id"
        ];

        ids.forEach(function (id) {
            const select = el(id);
            if (!select) return;

            const oldValue = select.value;

            select.innerHTML =
                '<option value="">Select application</option>';

            state.applications.forEach(function (record) {
                const idValue = field(record, ["id"]);
                const number = field(
                    record,
                    [
                        "application_number",
                        "applicationNumber",
                        "reference_number",
                        "referenceNumber"
                    ]
                );

                const statusValue = field(
                    record,
                    ["status", "application_status", "applicationStatus"]
                );

                const option = document.createElement("option");
                option.value = idValue;
                option.textContent =
                    (number || idValue) +
                    (statusValue ? " - " + statusValue : "");

                select.appendChild(option);
            });

            if (state.currentApplicationId) {
                select.value = state.currentApplicationId;
            } else if (oldValue) {
                select.value = oldValue;
            }
        });
    }

    function renderApplications() {
        const body = el("applications-body");
        if (!body) return;

        if (!state.applications.length) {
            body.innerHTML =
                '<tr><td colspan="6" class="idmc-empty">No applications found.</td></tr>';
            return;
        }

        body.innerHTML = state.applications.map(function (record, index) {
            const idValue = field(record, ["id"]);
            const number = field(
                record,
                [
                    "application_number",
                    "applicationNumber",
                    "reference_number",
                    "referenceNumber"
                ]
            );

            const statusValue = field(
                record,
                ["status", "application_status", "applicationStatus"]
            );

            const intake = field(
                record,
                ["intake", "intake_name", "intakeName"]
            );

            const created = field(
                record,
                ["created_at", "createdAt"]
            );

            return (
                "<tr>" +
                    "<td>" + escapeHtml(number || idValue) + "</td>" +
                    "<td>" + escapeHtml(intake) + "</td>" +
                    "<td>" + escapeHtml(statusValue) + "</td>" +
                    "<td>" + escapeHtml(created) + "</td>" +
                    '<td><button type="button" class="idmc-button" data-application-edit="' +
                        index +
                        '">Edit</button></td>' +
                    '<td><button type="button" class="idmc-button primary" data-application-use="' +
                        index +
                        '">Use</button></td>' +
                "</tr>"
            );
        }).join("");
    }

    function renderSimpleTable(type, records, columns) {
        const body = el(type + "-body");
        if (!body) return;

        if (!records.length) {
            body.innerHTML =
                '<tr><td colspan="' +
                (columns.length + 2) +
                '" class="idmc-empty">No records found.</td></tr>';
            return;
        }

        body.innerHTML = records.map(function (record, index) {
            let html = "<tr>";

            columns.forEach(function (column) {
                html +=
                    "<td>" +
                    escapeHtml(field(record, column.names)) +
                    "</td>";
            });

            html +=
                '<td><button type="button" class="idmc-button" data-' +
                type +
                '-edit="' +
                index +
                '">Edit</button></td>';

            html +=
                '<td><button type="button" class="idmc-button danger" data-' +
                type +
                '-delete="' +
                index +
                '">Delete</button></td>';

            html += "</tr>";

            return html;
        }).join("");
    }

    async function loadApplicants() {
        const result = await request(endpoints.applicants);
        state.applicants = unwrap(result);

        if (state.applicants.length === 1) {
            state.currentApplicantId =
                String(field(state.applicants[0], ["id"]) || "");

            el("applicant-id").value = state.currentApplicantId;
        }

        return state.applicants;
    }

    async function loadApplications() {
        const result = await request(endpoints.applications);
        state.applications = unwrap(result);

        renderApplications();
        populateApplicationSelects();

        return state.applications;
    }

    async function loadChoices() {
        const result = await request(endpoints.choices);
        state.choices = unwrap(result);

        renderSimpleTable(
            "choices",
            state.choices,
            [
                { names: ["programme_id", "programmeId"] },
                { names: ["priority", "choice_order", "choiceOrder"] },
                { names: ["status"] }
            ]
        );
    }

    async function loadQualifications() {
        const result = await request(endpoints.qualifications);
        state.qualifications = unwrap(result);

        renderSimpleTable(
            "qualifications",
            state.qualifications,
            [
                { names: ["qualification_type", "qualificationType", "type"] },
                { names: ["institution_name", "institutionName", "institution"] },
                { names: ["award_year", "awardYear", "year"] }
            ]
        );
    }

    async function loadDocuments() {
        const result = await request(endpoints.documents);
        state.documents = unwrap(result);

        renderSimpleTable(
            "documents",
            state.documents,
            [
                { names: ["document_type", "documentType", "type"] },
                { names: ["file_name", "fileName", "name"] },
                { names: ["status"] }
            ]
        );
    }

    async function refreshAll() {
        clearStatus();
        status("Loading live application data...", "info");

        try {
            await loadApplicants();
            await loadApplications();
            await loadChoices();
            await loadQualifications();
            await loadDocuments();

            status("Live application data loaded.", "success");
        } catch (error) {
            status("Load failed: " + error.message, "error");
        }
    }

    async function saveApplicant(event) {
        event.preventDefault();

        const id = value("applicant-id");

        const payload = {
            firstName: value("applicant-first-name"),
            middleName: nullable("applicant-middle-name"),
            lastName: value("applicant-last-name"),
            email: nullable("applicant-email"),
            phone: nullable("applicant-phone"),
            gender: nullable("applicant-gender"),
            nationality: nullable("applicant-nationality"),
            dateOfBirth: nullable("applicant-dob")
        };

        if (!payload.firstName || !payload.lastName) {
            status("First name and last name are required.", "error");
            return;
        }

        try {
            status(id ? "Updating applicant..." : "Creating applicant...", "info");

            const result = await request(
                id
                    ? endpoints.applicants + "/" + encodeURIComponent(id)
                    : endpoints.applicants,
                {
                    method: id ? "PATCH" : "POST",
                    body: payload
                }
            );

            const record = unwrapOne(result);

            state.currentApplicantId =
                String(field(record, ["id"]) || id || "");

            el("applicant-id").value = state.currentApplicantId;

            status("Applicant profile saved successfully.", "success");

            await loadApplicants();
        } catch (error) {
            status("Applicant save failed: " + error.message, "error");
        }
    }

    async function saveApplication(event) {
        event.preventDefault();

        const id = value("application-id");

        const payload = {
            applicantId:
                value("application-applicant-id") ||
                currentApplicantId(),
            academicYearId: nullable("application-academic-year-id"),
            intakeId: nullable("application-intake-id"),
            applicationType: nullable("application-type"),
            notes: nullable("application-notes")
        };

        if (!payload.applicantId) {
            status(
                "Save Applicant Profile first or provide Applicant ID.",
                "error"
            );
            return;
        }

        try {
            status(id ? "Updating application..." : "Creating application...", "info");

            const result = await request(
                id
                    ? endpoints.applications + "/" + encodeURIComponent(id)
                    : endpoints.applications,
                {
                    method: id ? "PATCH" : "POST",
                    body: payload
                }
            );

            const record = unwrapOne(result);

            state.currentApplicationId =
                String(field(record, ["id"]) || id || "");

            el("application-id").value =
                state.currentApplicationId;

            populateApplicationSelects();

            status("Application saved successfully.", "success");

            await loadApplications();
        } catch (error) {
            status("Application save failed: " + error.message, "error");
        }
    }

    async function saveChoice(event) {
        event.preventDefault();

        const id = value("choice-id");

        const payload = {
            applicationId:
                value("choice-application-id") ||
                currentApplicationId(),
            programmeId: value("choice-programme-id"),
            priority: Number(value("choice-priority") || "1")
        };

        if (!payload.applicationId || !payload.programmeId) {
            status(
                "Application and Programme are required.",
                "error"
            );
            return;
        }

        try {
            const result = await request(
                id
                    ? endpoints.choices + "/" + encodeURIComponent(id)
                    : endpoints.choices,
                {
                    method: id ? "PATCH" : "POST",
                    body: payload
                }
            );

            el("choice-id").value =
                String(field(unwrapOne(result), ["id"]) || id || "");

            status("Programme choice saved.", "success");
            await loadChoices();
        } catch (error) {
            status("Programme choice failed: " + error.message, "error");
        }
    }

    async function saveQualification(event) {
        event.preventDefault();

        const id = value("qualification-id");

        const payload = {
            applicationId:
                value("qualification-application-id") ||
                currentApplicationId(),
            qualificationType:
                value("qualification-type"),
            institutionName:
                value("qualification-institution"),
            awardYear:
                value("qualification-year")
                    ? Number(value("qualification-year"))
                    : null,
            grade:
                nullable("qualification-grade")
        };

        if (
            !payload.applicationId ||
            !payload.qualificationType ||
            !payload.institutionName
        ) {
            status(
                "Application, qualification type and institution are required.",
                "error"
            );
            return;
        }

        try {
            const result = await request(
                id
                    ? endpoints.qualifications + "/" + encodeURIComponent(id)
                    : endpoints.qualifications,
                {
                    method: id ? "PATCH" : "POST",
                    body: payload
                }
            );

            el("qualification-id").value =
                String(field(unwrapOne(result), ["id"]) || id || "");

            status("Qualification saved.", "success");
            await loadQualifications();
        } catch (error) {
            status("Qualification save failed: " + error.message, "error");
        }
    }

    async function saveDocument(event) {
        event.preventDefault();

        const id = value("document-id");

        const payload = {
            applicationId:
                value("document-application-id") ||
                currentApplicationId(),
            documentType:
                value("document-type"),
            fileName:
                value("document-file-name"),
            fileUrl:
                value("document-file-url")
        };

        if (
            !payload.applicationId ||
            !payload.documentType ||
            !payload.fileName ||
            !payload.fileUrl
        ) {
            status(
                "Application, document type, file name and file URL are required.",
                "error"
            );
            return;
        }

        try {
            const result = await request(
                id
                    ? endpoints.documents + "/" + encodeURIComponent(id)
                    : endpoints.documents,
                {
                    method: id ? "PATCH" : "POST",
                    body: payload
                }
            );

            el("document-id").value =
                String(field(unwrapOne(result), ["id"]) || id || "");

            status("Application document saved.", "success");
            await loadDocuments();
        } catch (error) {
            status("Document save failed: " + error.message, "error");
        }
    }

    async function submitApplication() {
        const id = currentApplicationId();

        if (!id) {
            status("Select or save an application first.", "error");
            return;
        }

        if (!window.confirm("Submit this application now?")) {
            return;
        }

        const candidates = [
            endpoints.applications + "/" + encodeURIComponent(id) + "/submit",
            endpoints.applications + "/" + encodeURIComponent(id) + "/submission"
        ];

        let lastError = null;

        for (const path of candidates) {
            try {
                status("Submitting application...", "info");

                await request(path, {
                    method: "POST",
                    body: {}
                });

                status("Application submitted successfully.", "success");
                await loadApplications();
                return;
            } catch (error) {
                lastError = error;

                if (!/404|not found|route/i.test(error.message)) {
                    break;
                }
            }
        }

        status(
            "Application submit failed: " +
            (lastError ? lastError.message : "Unknown error"),
            "error"
        );
    }

    function bindEditButtons() {
        document.addEventListener("click", function (event) {
            const target = event.target;

            if (!(target instanceof HTMLElement)) return;

            const applicationEdit =
                target.getAttribute("data-application-edit");

            const applicationUse =
                target.getAttribute("data-application-use");

            if (applicationEdit !== null) {
                const record =
                    state.applications[Number(applicationEdit)];

                if (!record) return;

                const idValue =
                    String(field(record, ["id"]) || "");

                state.currentApplicationId = idValue;

                el("application-id").value = idValue;

                el("application-applicant-id").value =
                    field(record, ["applicant_id", "applicantId"]);

                el("application-academic-year-id").value =
                    field(record, ["academic_year_id", "academicYearId"]);

                el("application-intake-id").value =
                    field(record, ["intake_id", "intakeId"]);

                el("application-type").value =
                    field(record, ["application_type", "applicationType"]);

                el("application-notes").value =
                    field(record, ["notes"]);

                populateApplicationSelects();
                switchTab("application");

                status("Application loaded for editing.", "info");
            }

            if (applicationUse !== null) {
                const record =
                    state.applications[Number(applicationUse)];

                if (!record) return;

                state.currentApplicationId =
                    String(field(record, ["id"]) || "");

                el("application-id").value =
                    state.currentApplicationId;

                populateApplicationSelects();

                status(
                    "Application selected for choices, qualifications and documents.",
                    "success"
                );
            }

            [
                {
                    type: "choices",
                    records: state.choices,
                    endpoint: endpoints.choices
                },
                {
                    type: "qualifications",
                    records: state.qualifications,
                    endpoint: endpoints.qualifications
                },
                {
                    type: "documents",
                    records: state.documents,
                    endpoint: endpoints.documents
                }
            ].forEach(function (definition) {
                const deleteIndex =
                    target.getAttribute(
                        "data-" + definition.type + "-delete"
                    );

                if (deleteIndex === null) return;

                const record =
                    definition.records[Number(deleteIndex)];

                if (!record) return;

                const idValue = field(record, ["id"]);

                if (!idValue) return;

                if (!window.confirm("Delete this record?")) {
                    return;
                }

                request(
                    definition.endpoint + "/" +
                    encodeURIComponent(idValue),
                    { method: "DELETE" }
                )
                .then(function () {
                    status("Record deleted.", "success");
                    return refreshAll();
                })
                .catch(function (error) {
                    status("Delete failed: " + error.message, "error");
                });
            });
        });
    }

    function buildUi() {
        const host = document.createElement("section");

        host.id = "idmc-applicant-live";

        host.innerHTML = `
            <div class="idmc-live-header">
                <h2>Online Application</h2>
                <p>Complete your applicant profile, application, programme choices, qualifications and documents.</p>
            </div>

            <div class="idmc-live-tabs">
                <button type="button" class="idmc-live-tab active" data-tab="profile">Applicant Profile</button>
                <button type="button" class="idmc-live-tab" data-tab="application">Application</button>
                <button type="button" class="idmc-live-tab" data-tab="choices">Programme Choices</button>
                <button type="button" class="idmc-live-tab" data-tab="qualifications">Qualifications</button>
                <button type="button" class="idmc-live-tab" data-tab="documents">Documents</button>
                <button type="button" class="idmc-live-tab" data-tab="review">Review & Submit</button>
            </div>

            <div class="idmc-live-body">
                <div id="idmc-live-status" class="idmc-status"></div>

                <section class="idmc-panel active" data-panel="profile">
                    <h3 class="idmc-section-title">Applicant Profile</h3>

                    <form id="applicant-form">
                        <input type="hidden" id="applicant-id">

                        <div class="idmc-form-grid">
                            <div class="idmc-field">
                                <label>First Name *</label>
                                <input id="applicant-first-name" name="firstName" required>
                            </div>

                            <div class="idmc-field">
                                <label>Middle Name</label>
                                <input id="applicant-middle-name" name="middleName">
                            </div>

                            <div class="idmc-field">
                                <label>Last Name *</label>
                                <input id="applicant-last-name" name="lastName" required>
                            </div>

                            <div class="idmc-field">
                                <label>Email</label>
                                <input id="applicant-email" name="email" type="email">
                            </div>

                            <div class="idmc-field">
                                <label>Phone</label>
                                <input id="applicant-phone" name="phone">
                            </div>

                            <div class="idmc-field">
                                <label>Gender</label>
                                <select id="applicant-gender" name="gender">
                                    <option value="">Select</option>
                                    <option value="MALE">Male</option>
                                    <option value="FEMALE">Female</option>
                                    <option value="OTHER">Other</option>
                                </select>
                            </div>

                            <div class="idmc-field">
                                <label>Date of Birth</label>
                                <input id="applicant-dob" name="dateOfBirth" type="date">
                            </div>

                            <div class="idmc-field">
                                <label>Nationality</label>
                                <input id="applicant-nationality" name="nationality">
                            </div>
                        </div>

                        <div class="idmc-actions">
                            <button class="idmc-button primary" type="submit">Save Applicant Profile</button>
                        </div>
                    </form>
                </section>

                <section class="idmc-panel" data-panel="application">
                    <h3 class="idmc-section-title">Application</h3>

                    <form id="application-form">
                        <input type="hidden" id="application-id">

                        <div class="idmc-form-grid">
                            <div class="idmc-field">
                                <label>Applicant ID *</label>
                                <input id="application-applicant-id">
                            </div>

                            <div class="idmc-field">
                                <label>Academic Year ID</label>
                                <input id="application-academic-year-id">
                            </div>

                            <div class="idmc-field">
                                <label>Intake ID</label>
                                <input id="application-intake-id">
                            </div>

                            <div class="idmc-field">
                                <label>Application Type</label>
                                <input id="application-type">
                            </div>

                            <div class="idmc-field full">
                                <label>Notes</label>
                                <textarea id="application-notes"></textarea>
                            </div>
                        </div>

                        <div class="idmc-actions">
                            <button class="idmc-button primary" type="submit">Save Application</button>
                            <button class="idmc-button" id="refresh-applications" type="button">Refresh Applications</button>
                        </div>
                    </form>

                    <div class="idmc-table-wrap">
                        <table class="idmc-table">
                            <thead>
                                <tr>
                                    <th>Application</th>
                                    <th>Intake</th>
                                    <th>Status</th>
                                    <th>Created</th>
                                    <th>Edit</th>
                                    <th>Use</th>
                                </tr>
                            </thead>
                            <tbody id="applications-body"></tbody>
                        </table>
                    </div>
                </section>

                <section class="idmc-panel" data-panel="choices">
                    <h3 class="idmc-section-title">Programme Choices</h3>

                    <form id="choice-form">
                        <input type="hidden" id="choice-id">

                        <div class="idmc-form-grid">
                            <div class="idmc-field">
                                <label>Application *</label>
                                <select id="choice-application-id" required></select>
                            </div>

                            <div class="idmc-field">
                                <label>Programme ID *</label>
                                <input id="choice-programme-id" required>
                            </div>

                            <div class="idmc-field">
                                <label>Priority *</label>
                                <input id="choice-priority" type="number" min="1" value="1" required>
                            </div>
                        </div>

                        <div class="idmc-actions">
                            <button class="idmc-button primary" type="submit">Save Programme Choice</button>
                        </div>
                    </form>

                    <div class="idmc-table-wrap">
                        <table class="idmc-table">
                            <thead>
                                <tr>
                                    <th>Programme</th>
                                    <th>Priority</th>
                                    <th>Status</th>
                                    <th>Edit</th>
                                    <th>Delete</th>
                                </tr>
                            </thead>
                            <tbody id="choices-body"></tbody>
                        </table>
                    </div>
                </section>

                <section class="idmc-panel" data-panel="qualifications">
                    <h3 class="idmc-section-title">Academic Qualifications</h3>

                    <form id="qualification-form">
                        <input type="hidden" id="qualification-id">

                        <div class="idmc-form-grid">
                            <div class="idmc-field">
                                <label>Application *</label>
                                <select id="qualification-application-id" required></select>
                            </div>

                            <div class="idmc-field">
                                <label>Qualification Type *</label>
                                <input id="qualification-type" required>
                            </div>

                            <div class="idmc-field">
                                <label>Institution *</label>
                                <input id="qualification-institution" required>
                            </div>

                            <div class="idmc-field">
                                <label>Award Year</label>
                                <input id="qualification-year" type="number">
                            </div>

                            <div class="idmc-field">
                                <label>Grade</label>
                                <input id="qualification-grade">
                            </div>
                        </div>

                        <div class="idmc-actions">
                            <button class="idmc-button primary" type="submit">Save Qualification</button>
                        </div>
                    </form>

                    <div class="idmc-table-wrap">
                        <table class="idmc-table">
                            <thead>
                                <tr>
                                    <th>Qualification</th>
                                    <th>Institution</th>
                                    <th>Year</th>
                                    <th>Edit</th>
                                    <th>Delete</th>
                                </tr>
                            </thead>
                            <tbody id="qualifications-body"></tbody>
                        </table>
                    </div>
                </section>

                <section class="idmc-panel" data-panel="documents">
                    <h3 class="idmc-section-title">Application Documents</h3>

                    <form id="document-form">
                        <input type="hidden" id="document-id">

                        <div class="idmc-form-grid">
                            <div class="idmc-field">
                                <label>Application *</label>
                                <select id="document-application-id" required></select>
                            </div>

                            <div class="idmc-field">
                                <label>Document Type *</label>
                                <input id="document-type" required>
                            </div>

                            <div class="idmc-field">
                                <label>File Name *</label>
                                <input id="document-file-name" required>
                            </div>

                            <div class="idmc-field">
                                <label>File URL *</label>
                                <input id="document-file-url" type="url" required>
                            </div>
                        </div>

                        <div class="idmc-actions">
                            <button class="idmc-button primary" type="submit">Save Document</button>
                        </div>
                    </form>

                    <div class="idmc-table-wrap">
                        <table class="idmc-table">
                            <thead>
                                <tr>
                                    <th>Document Type</th>
                                    <th>File</th>
                                    <th>Status</th>
                                    <th>Edit</th>
                                    <th>Delete</th>
                                </tr>
                            </thead>
                            <tbody id="documents-body"></tbody>
                        </table>
                    </div>
                </section>

                <section class="idmc-panel" data-panel="review">
                    <h3 class="idmc-section-title">Review & Submit</h3>

                    <p>
                        Save the applicant profile, application, programme choices,
                        qualifications and required documents before submitting.
                    </p>

                    <div class="idmc-actions">
                        <button id="refresh-all-application-data" type="button" class="idmc-button">Refresh All</button>
                        <button id="submit-live-application" type="button" class="idmc-button primary">Submit Application</button>
                    </div>
                </section>
            </div>
        `;

        const main =
            document.querySelector("main") ||
            document.querySelector(".main-content") ||
            document.querySelector(".content") ||
            document.body;

        main.insertBefore(host, main.firstChild);
    }

    function bind() {
        document.querySelectorAll(".idmc-live-tab").forEach(function (button) {
            button.addEventListener("click", function () {
                switchTab(button.getAttribute("data-tab"));
            });
        });

        el("applicant-form").addEventListener("submit", saveApplicant);
        el("application-form").addEventListener("submit", saveApplication);
        el("choice-form").addEventListener("submit", saveChoice);
        el("qualification-form").addEventListener("submit", saveQualification);
        el("document-form").addEventListener("submit", saveDocument);

        el("refresh-applications").addEventListener(
            "click",
            loadApplications
        );

        el("refresh-all-application-data").addEventListener(
            "click",
            refreshAll
        );

        el("submit-live-application").addEventListener(
            "click",
            submitApplication
        );

        bindEditButtons();
    }

    function disableLegacyCrudOverlay() {
        const textNeedles = [
            "Live CRUD workflow",
            "No visible CRUD form found",
            "Mutations are disarmed"
        ];

        document.querySelectorAll("body *").forEach(function (node) {
            if (node.children.length !== 0) return;

            const text = String(node.textContent || "").trim();

            if (!text) return;

            if (textNeedles.some(function (needle) {
                return text.indexOf(needle) !== -1;
            })) {
                const parent =
                    node.closest(
                        ".card,.panel,.module-card,.crud-panel,.workspace"
                    );

                if (parent && !parent.closest("#idmc-applicant-live")) {
                    parent.style.display = "none";
                }
            }
        });
    }

    document.addEventListener("DOMContentLoaded", function () {
        buildUi();
        bind();
        disableLegacyCrudOverlay();
        refreshAll();
    });
})();
