(function () {
    "use strict";

    const state = {
        module: "",
        busy: false,
        lastAction: null,
        lastError: null
    };

    function qs(selector, root) {
        return (root || document).querySelector(selector);
    }

    function qsa(selector, root) {
        return Array.from(
            (root || document).querySelectorAll(selector)
        );
    }

    function detectModule() {
        const bodyModule =
            document.body &&
            document.body.dataset
                ? document.body.dataset.module
                : "";

        if (bodyModule) {
            return bodyModule;
        }

        const file =
            location.pathname
                .split("/")
                .pop()
                .replace(/\.html$/i, "");

        return file || "";
    }

    function getCrud() {
        return (
            window.IDMCModuleCRUD ||
            window.IDMC_MODULE_CRUD ||
            window.ModuleCRUD ||
            null
        );
    }

    function getGuard() {
        return window.IDMCLiveCRUD || null;
    }

    function setStatus(message, type) {
        const el = qs("#idmcE2EStatus");

        if (!el) {
            return;
        }

        el.textContent = message || "";
        el.dataset.type = type || "info";
    }

    function setBusy(value) {
        state.busy = Boolean(value);

        qsa("[data-idmc-e2e-action]")
            .forEach(function (button) {
                button.disabled = state.busy;
            });
    }

    function dispatch(name, detail) {
        window.dispatchEvent(
            new CustomEvent(
                name,
                {
                    detail: detail || {}
                }
            )
        );
    }

    async function refresh() {
        const crud = getCrud();

        setStatus(
            "Refreshing records...",
            "info"
        );

        /*
         * A7.13/A7.14 runtimes may expose different
         * refresh method names. Use only an existing one.
         */
        if (crud) {

            if (typeof crud.refresh === "function") {
                await crud.refresh();
            }
            else if (
                typeof crud.load === "function"
            ) {
                await crud.load();
            }
            else if (
                typeof crud.list === "function"
            ) {
                await crud.list();
            }
            else {
                dispatch(
                    "idmc:module-refresh",
                    {
                        module: state.module
                    }
                );
            }
        }
        else {
            dispatch(
                "idmc:module-refresh",
                {
                    module: state.module
                }
            );
        }

        setStatus(
            "Records refreshed.",
            "success"
        );
    }

    function armMutation() {
        const guard = getGuard();

        if (!guard) {
            throw new Error(
                "A7.18 live CRUD guard is unavailable."
            );
        }

        if (typeof guard.arm !== "function") {
            throw new Error(
                "Live CRUD guard cannot be armed."
            );
        }

        guard.arm();

        setStatus(
            "One live mutation is armed. " +
            "The guard will disarm after execution.",
            "warning"
        );
    }

    function disarmMutation() {
        const guard = getGuard();

        if (
            guard &&
            typeof guard.disarm === "function"
        ) {
            guard.disarm();
        }

        setStatus(
            "Live mutations are disarmed.",
            "success"
        );
    }

    function getVisibleForm() {
        const candidates = [
            "#moduleCrudForm",
            "#crudForm",
            "[data-module-form]",
            ".module-form form",
            ".crud-form form",
            "main form"
        ];

        for (const selector of candidates) {

            const form = qs(selector);

            if (
                form &&
                form.offsetParent !== null
            ) {
                return form;
            }
        }

        return null;
    }

    function validateForm() {
        const form = getVisibleForm();

        if (!form) {
            throw new Error(
                "No visible CRUD form found."
            );
        }

        if (
            typeof form.reportValidity === "function" &&
            !form.reportValidity()
        ) {
            throw new Error(
                "Complete required form fields first."
            );
        }

        setStatus(
            "Form validation passed.",
            "success"
        );

        return true;
    }

    function findCreateButton() {
        return (
            qs('[data-action="create"]') ||
            qs('[data-crud-action="create"]') ||
            qs('[data-module-action="create"]') ||
            qs("#createButton") ||
            qs("#btnCreate")
        );
    }

    function findSaveButton() {
        return (
            qs('[data-action="save"]') ||
            qs('[data-crud-action="save"]') ||
            qs('[data-module-action="save"]') ||
            qs('button[type="submit"]')
        );
    }

    function findSelectedRow() {
        return (
            qs("tr.is-selected") ||
            qs("tr.selected") ||
            qs("[data-record-id].is-selected") ||
            qs("[data-record-id].selected")
        );
    }

    function findEditButton() {
        const selected =
            findSelectedRow();

        if (selected) {
            return (
                qs('[data-action="edit"]', selected) ||
                qs('[data-crud-action="edit"]', selected)
            );
        }

        return (
            qs('[data-action="edit"]') ||
            qs('[data-crud-action="edit"]')
        );
    }

    function findDeleteButton() {
        const selected =
            findSelectedRow();

        if (selected) {
            return (
                qs('[data-action="delete"]', selected) ||
                qs('[data-crud-action="delete"]', selected)
            );
        }

        return (
            qs('[data-action="delete"]') ||
            qs('[data-crud-action="delete"]')
        );
    }

    function clickExisting(button, description) {

        if (!button) {
            throw new Error(
                description +
                " control is not available for this module."
            );
        }

        button.click();
    }

    async function runAction(action) {

        if (state.busy) {
            return;
        }

        setBusy(true);
        state.lastAction = action;
        state.lastError = null;

        try {

            switch (action) {

                case "refresh":
                    await refresh();
                    break;

                case "validate":
                    validateForm();
                    break;

                case "create":
                    validateForm();
                    armMutation();

                    clickExisting(
                        findCreateButton() ||
                        findSaveButton(),
                        "Create"
                    );
                    break;

                case "update":
                    validateForm();
                    armMutation();

                    clickExisting(
                        findEditButton() ||
                        findSaveButton(),
                        "Update"
                    );
                    break;

                case "delete":
                    armMutation();

                    clickExisting(
                        findDeleteButton(),
                        "Delete"
                    );
                    break;

                case "disarm":
                    disarmMutation();
                    break;

                default:
                    throw new Error(
                        "Unknown E2E action: " +
                        action
                    );
            }

            dispatch(
                "idmc:e2e-action",
                {
                    module: state.module,
                    action: action,
                    success: true
                }
            );
        }
        catch (error) {

            state.lastError = error;

            /*
             * Never leave a mutation armed after an
             * orchestration error.
             */
            try {
                const guard = getGuard();

                if (
                    guard &&
                    typeof guard.disarm === "function"
                ) {
                    guard.disarm();
                }
            }
            catch (_) {}

            setStatus(
                error && error.message
                    ? error.message
                    : String(error),
                "error"
            );

            console.error(
                "[IDMC A7.19]",
                error
            );

            dispatch(
                "idmc:e2e-action",
                {
                    module: state.module,
                    action: action,
                    success: false,
                    message:
                        error && error.message
                            ? error.message
                            : String(error)
                }
            );
        }
        finally {
            setBusy(false);
        }
    }

    function buildPanel() {

        if (qs("#idmcE2EPanel")) {
            return;
        }

        const panel =
            document.createElement("section");

        panel.id = "idmcE2EPanel";
        panel.className = "idmc-e2e-panel";

        panel.innerHTML = `
            <div class="idmc-e2e-head">
                <div>
                    <strong>Live CRUD workflow</strong>
                    <small>
                        ${state.module}
                    </small>
                </div>

                <span class="idmc-e2e-live">
                    LIVE
                </span>
            </div>

            <p id="idmcE2EStatus"
               class="idmc-e2e-status">
                Mutations are disarmed.
            </p>

            <div class="idmc-e2e-actions">
                <button type="button"
                        data-idmc-e2e-action="refresh">
                    Refresh
                </button>

                <button type="button"
                        data-idmc-e2e-action="validate">
                    Validate form
                </button>

                <button type="button"
                        data-idmc-e2e-action="create">
                    Create
                </button>

                <button type="button"
                        data-idmc-e2e-action="update">
                    Update
                </button>

                <button type="button"
                        data-idmc-e2e-action="delete">
                    Delete
                </button>

                <button type="button"
                        data-idmc-e2e-action="disarm">
                    Disarm
                </button>
            </div>

            <p class="idmc-e2e-note">
                Create, Update and Delete use the existing
                module controls. Each mutation must pass the
                A7.18 confirmation guard.
            </p>
        `;

        const target =
            qs("main") ||
            qs(".main-content") ||
            qs(".content") ||
            document.body;

        target.insertBefore(
            panel,
            target.firstChild
        );

        qsa(
            "[data-idmc-e2e-action]",
            panel
        ).forEach(function (button) {

            button.addEventListener(
                "click",
                function () {
                    runAction(
                        button.dataset.idmcE2eAction
                    );
                }
            );
        });
    }

    function boot() {
        state.module = detectModule();

        buildPanel();

        /*
         * Start safe every time a page loads.
         */
        try {
            const guard = getGuard();

            if (
                guard &&
                typeof guard.disarm === "function"
            ) {
                guard.disarm();
            }
        }
        catch (_) {}

        window.IDMCE2E = Object.freeze({
            refresh: refresh,
            validate: validateForm,
            arm: armMutation,
            disarm: disarmMutation,
            run: runAction,

            get module() {
                return state.module;
            },

            get busy() {
                return state.busy;
            },

            get lastError() {
                return state.lastError;
            }
        });

        setStatus(
            "Ready. Mutations are disarmed.",
            "success"
        );
    }

    if (
        document.readyState === "loading"
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