(function () {
    "use strict";

    const config =
        window.IDMC_MODULE_PAGE || {};

    const contracts =
        window.IDMC_MODULE_CONTRACTS || {};

    const contract =
        contracts[config.key] || {};

    const $ =
        (selector) =>
            document.querySelector(selector);

    function escapeHtml(value) {
        return String(value ?? "")
            .replaceAll("&", "&amp;")
            .replaceAll("<", "&lt;")
            .replaceAll(">", "&gt;")
            .replaceAll('"', "&quot;")
            .replaceAll("'", "&#039;");
    }

    function setState(type, title, message) {

        const body =
            $("#moduleTableBody");

        if (!body) return;

        body.innerHTML =
            '<tr>' +
                '<td colspan="5">' +
                    '<div class="state ' +
                        (type === "error" ? "error" : "") +
                    '">' +
                        '<strong>' +
                            escapeHtml(title) +
                        '</strong>' +
                        '<span>' +
                            escapeHtml(message || "") +
                        '</span>' +
                    '</div>' +
                '</td>' +
            '</tr>';
    }

    function normalizeCollection(payload) {

        if (Array.isArray(payload)) {
            return payload;
        }

        if (!payload) {
            return [];
        }

        if (Array.isArray(payload.items)) {
            return payload.items;
        }

        if (Array.isArray(payload.rows)) {
            return payload.rows;
        }

        if (Array.isArray(payload.data)) {
            return payload.data;
        }

        if (
            payload.data &&
            Array.isArray(payload.data.items)
        ) {
            return payload.data.items;
        }

        if (
            payload.data &&
            Array.isArray(payload.data.rows)
        ) {
            return payload.data.rows;
        }

        if (
            payload.success === true &&
            payload.data &&
            typeof payload.data === "object"
        ) {
            const arrays =
                Object.values(payload.data)
                    .filter(Array.isArray);

            if (arrays.length === 1) {
                return arrays[0];
            }
        }

        return [];
    }

    function chooseValue(record, fields) {

        for (const field of fields) {

            const value =
                record?.[field];

            if (
                value !== undefined &&
                value !== null &&
                String(value).trim() !== ""
            ) {
                return value;
            }
        }

        return "—";
    }

    function renderRows(rows) {

        const body =
            $("#moduleTableBody");

        if (!body) return;

        if (!rows.length) {

            setState(
                "empty",
                "No records found",
                "The backend returned no records for this module."
            );

            return;
        }

        body.innerHTML =
            rows.map((row, index) => {

                const reference =
                    chooseValue(
                        row,
                        [
                            "code",
                            "reference",
                            "reference_number",
                            "registration_number",
                            "student_number",
                            "employee_number",
                            "id"
                        ]
                    );

                const name =
                    chooseValue(
                        row,
                        [
                            "name",
                            "title",
                            "description",
                            "student_name",
                            "full_name",
                            "subject",
                            "type"
                        ]
                    );

                const status =
                    chooseValue(
                        row,
                        [
                            "status",
                            "state",
                            "approval_status"
                        ]
                    );

                const updated =
                    chooseValue(
                        row,
                        [
                            "updated_at",
                            "created_at",
                            "date",
                            "effective_date"
                        ]
                    );

                return (
                    '<tr data-row>' +
                        '<td>' +
                            escapeHtml(reference) +
                        '</td>' +

                        '<td>' +
                            escapeHtml(name) +
                        '</td>' +

                        '<td>' +
                            '<span class="badge">' +
                                escapeHtml(status) +
                            '</span>' +
                        '</td>' +

                        '<td>' +
                            escapeHtml(updated) +
                        '</td>' +

                        '<td>' +
                            '<button ' +
                                'type="button" ' +
                                'class="btn btn-secondary" ' +
                                'data-record-index="' +
                                index +
                                '">' +
                                'View' +
                            '</button>' +
                        '</td>' +
                    '</tr>'
                );
            }).join("");
    }

    function updateStats(rows) {

        const total =
            $("#statTotal");

        const active =
            $("#statActive");

        const pending =
            $("#statPending");

        const updated =
            $("#statUpdated");

        if (total) {
            total.textContent =
                String(rows.length);
        }

        const activeCount =
            rows.filter((row) => {
                return String(
                    row.status ??
                    row.state ??
                    ""
                ).toUpperCase() === "ACTIVE";
            }).length;

        const pendingCount =
            rows.filter((row) => {
                const status =
                    String(
                        row.status ??
                        row.state ??
                        row.approval_status ??
                        ""
                    ).toUpperCase();

                return (
                    status === "PENDING" ||
                    status === "SUBMITTED" ||
                    status === "DRAFT"
                );
            }).length;

        if (active) {
            active.textContent =
                String(activeCount);
        }

        if (pending) {
            pending.textContent =
                String(pendingCount);
        }

        if (updated) {
            updated.textContent =
                "Live";
        }
    }

    async function requireAuthentication() {

        if (!window.IDMCAuth) {
            throw new Error(
                "IDMCAuth is not available."
            );
        }

        if (
            typeof window.IDMCAuth.requireAuth ===
            "function"
        ) {
            return window.IDMCAuth.requireAuth();
        }

        if (
            typeof window.IDMCAuth.getAccessToken ===
                "function" &&
            window.IDMCAuth.getAccessToken()
        ) {
            return true;
        }

        window.location.href =
            "login.html";

        return false;
    }

    async function checkPermission() {

        if (!config.permission) {
            return true;
        }

        if (
            !window.IDMC_RBAC_API ||
            typeof window.IDMC_RBAC_API.hasPermission !==
                "function"
        ) {
            return true;
        }

        try {

            const allowed =
                await window.IDMC_RBAC_API.hasPermission(
                    config.permission
                );

            if (!allowed) {

                setState(
                    "error",
                    "Access denied",
                    "You do not have permission to view this module."
                );

                return false;
            }

            return true;

        } catch (error) {

            console.warn(
                "RBAC permission check failed.",
                error
            );

            return true;
        }
    }

    function activateNavigation() {

        document
            .querySelectorAll(
                "[data-module-link]"
            )
            .forEach((link) => {

                if (
                    link.dataset.moduleLink ===
                    config.key
                ) {
                    link.classList.add(
                        "active"
                    );
                }
            });
    }

    function setIdentity() {

        const title =
            $("#moduleTitle");

        const subtitle =
            $("#moduleSubtitle");

        const badge =
            $("#moduleBadge");

        if (title) {
            title.textContent =
                config.title || "Module";
        }

        if (subtitle) {
            subtitle.textContent =
                config.description ||
                "IDMC iMIS workspace";
        }

        if (badge) {
            badge.textContent =
                config.permission ||
                "Authenticated";
        }

        document.title =
            (config.title || "Module") +
            " | IDMC iMIS";
    }

    function wireSearch() {

        const input =
            $("#moduleSearch");

        if (!input) return;

        input.addEventListener(
            "input",
            () => {

                const query =
                    input.value
                        .trim()
                        .toLowerCase();

                document
                    .querySelectorAll(
                        "#moduleTableBody tr[data-row]"
                    )
                    .forEach((row) => {

                        row.hidden =
                            query.length > 0 &&
                            !row.textContent
                                .toLowerCase()
                                .includes(query);
                    });
            }
        );
    }

    function wireStatusFilter() {

        const filter =
            $("#statusFilter");

        if (!filter) return;

        filter.addEventListener(
            "change",
            () => {

                const selected =
                    filter.value
                        .trim()
                        .toUpperCase();

                document
                    .querySelectorAll(
                        "#moduleTableBody tr[data-row]"
                    )
                    .forEach((row) => {

                        if (!selected) {
                            row.hidden = false;
                            return;
                        }

                        row.hidden =
                            !row.textContent
                                .toUpperCase()
                                .includes(selected);
                    });
            }
        );
    }

    async function initializeWorkspace() {

        if (
            !contract.endpoint
        ) {

            setState(
                "empty",
                config.title + " ready",
                "No safe collection GET endpoint was discovered automatically. No backend contract has been invented."
            );

            const total =
                $("#statTotal");

            const active =
                $("#statActive");

            const pending =
                $("#statPending");

            const updated =
                $("#statUpdated");

            if (total) total.textContent = "—";
            if (active) active.textContent = "—";
            if (pending) pending.textContent = "—";
            if (updated) updated.textContent = "Unbound";

            return;
        }

        if (
            !window.IDMCAPI ||
            typeof window.IDMCAPI.request !==
                "function"
        ) {
            throw new Error(
                "IDMCAPI is not available."
            );
        }

        setState(
            "loading",
            "Loading...",
            "Reading live data from " +
                contract.endpoint
        );

        try {

            const response =
                await window.IDMCAPI.request(
                    contract.endpoint,
                    {
                        method: "GET"
                    }
                );

            const rows =
                normalizeCollection(response);

            renderRows(rows);
            updateStats(rows);

        } catch (error) {

            console.error(
                "Module load failed:",
                error
            );

            setState(
                "error",
                "Unable to load data",
                error?.message ||
                "The backend request failed."
            );

            const updated =
                $("#statUpdated");

            if (updated) {
                updated.textContent =
                    "Error";
            }
        }
    }

    function wireRefresh() {

        const button =
            $("#refreshButton");

        if (!button) return;

        button.addEventListener(
            "click",
            initializeWorkspace
        );
    }

    async function boot() {

        try {

            setIdentity();
            activateNavigation();

            await requireAuthentication();

            const allowed =
                await checkPermission();

            if (!allowed) {
                return;
            }

            wireSearch();
            wireStatusFilter();
            wireRefresh();

            await initializeWorkspace();

        } catch (error) {

            console.error(error);

            setState(
                "error",
                "Unable to open module",
                error?.message ||
                "An unexpected application error occurred."
            );
        }
    }

    window.IDMCModulePages = {
        initializeWorkspace
    };

    if (
        document.readyState ===
        "loading"
    ) {
        document.addEventListener(
            "DOMContentLoaded",
            boot
        );
    }
    else {
        boot();
    }

})();