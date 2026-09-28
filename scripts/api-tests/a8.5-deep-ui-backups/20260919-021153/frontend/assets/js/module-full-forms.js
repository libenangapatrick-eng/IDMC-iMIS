(function () {
    "use strict";

    const MODULES = ["admissions","registration","attendance","assessment","examinations","results","timetable","finance","communications","library","hostel","hr","research","graduation","alumni","transcripts","operations","reports","system"];

    function qs(selector, root = document) {
        return root.querySelector(selector);
    }

    function qsa(selector, root = document) {
        return Array.from(
            root.querySelectorAll(selector)
        );
    }

    function moduleName() {
        return (
            document.body?.dataset?.idmcModule ||
            ""
        ).trim();
    }

    function getCrudContract(name) {
        const candidates = [
            window.IDMCModuleCRUD,
            window.IDMCModuleCrud,
            window.IDMCModuleCrudRuntime,
            window.IDMCCrud,
            window.IDMCCrudRuntime
        ];

        for (const api of candidates) {
            if (!api) {
                continue;
            }

            if (typeof api.getContract === "function") {
                const contract =
                    api.getContract(name);

                if (contract) {
                    return contract;
                }
            }

            if (
                api.contracts &&
                api.contracts[name]
            ) {
                return api.contracts[name];
            }
        }

        return null;
    }

    function normalizeContract(contract) {
        if (!contract) {
            return {
                canList: false,
                canCreate: false,
                canUpdate: false,
                canDelete: false,
                endpoint: null
            };
        }

        return {
            canList: Boolean(
                contract.canList ??
                contract.CanList
            ),

            canCreate: Boolean(
                contract.canCreate ??
                contract.CanCreate
            ),

            canUpdate: Boolean(
                contract.canUpdate ??
                contract.CanUpdate
            ),

            canDelete: Boolean(
                contract.canDelete ??
                contract.CanDelete
            ),

            endpoint:
                contract.endpoint ??
                contract.Endpoint ??
                null
        };
    }

    function setStatus(state, message) {
        const el =
            qs("[data-idmc-status]");

        if (!el) {
            return;
        }

        if (!message) {
            el.dataset.state = "";
            el.textContent = "";
            return;
        }

        el.dataset.state = state;
        el.textContent = message;
    }

    function setCapability(name, enabled) {
        const el =
            qs(
                `[data-capability="${name}"]`
            );

        if (!el) {
            return;
        }

        el.textContent =
            enabled ? "Available" : "Not exposed";
    }

    function applyCapabilities(contract) {
        setCapability(
            "list",
            contract.canList
        );

        setCapability(
            "create",
            contract.canCreate
        );

        setCapability(
            "update",
            contract.canUpdate
        );

        setCapability(
            "delete",
            contract.canDelete
        );

        qsa("[data-action='create']")
            .forEach(button => {
                button.hidden =
                    !contract.canCreate;
            });

        qsa("[data-action='refresh']")
            .forEach(button => {
                button.disabled =
                    !contract.canList;
            });
    }

    function findExistingCrudHost() {
        const selectors = [
            "[data-module-crud]",
            "[data-crud-root]",
            "#module-crud",
            "#crud-root",
            ".module-crud",
            ".idmc-module-crud"
        ];

        for (const selector of selectors) {
            const element =
                qs(selector);

            if (element) {
                return element;
            }
        }

        return null;
    }

    function moveExistingRuntime() {
        const target =
            qs("[data-idmc-runtime-host]");

        if (!target) {
            return;
        }

        const existing =
            findExistingCrudHost();

        if (
            existing &&
            existing !== target &&
            !target.contains(existing)
        ) {
            target.appendChild(existing);
        }
    }

    function dispatchCrudEvent(name, detail = {}) {
        window.dispatchEvent(
            new CustomEvent(
                name,
                {
                    detail: {
                        module: moduleName(),
                        ...detail
                    }
                }
            )
        );
    }

    function bootKnownCrudRuntime() {
        const candidates = [
            window.IDMCModuleCRUD,
            window.IDMCModuleCrud,
            window.IDMCModuleCrudRuntime,
            window.IDMCCrud,
            window.IDMCCrudRuntime
        ];

        for (const api of candidates) {
            if (!api) {
                continue;
            }

            if (typeof api.boot === "function") {
                try {
                    api.boot();
                    return true;
                }
                catch (error) {
                    console.error(
                        "CRUD runtime boot failed:",
                        error
                    );
                }
            }
        }

        return false;
    }

    function bindActions(contract) {
        const refresh =
            qs("[data-action='refresh']");

        const create =
            qs("[data-action='create']");

        if (refresh) {
            refresh.addEventListener(
                "click",
                () => {
                    if (!contract.canList) {
                        return;
                    }

                    setStatus(
                        "loading",
                        "Refreshing records..."
                    );

                    dispatchCrudEvent(
                        "idmc:crud:refresh"
                    );

                    bootKnownCrudRuntime();

                    window.setTimeout(
                        () => {
                            setStatus("", "");
                        },
                        900
                    );
                }
            );
        }

        if (create) {
            create.addEventListener(
                "click",
                () => {
                    if (!contract.canCreate) {
                        return;
                    }

                    dispatchCrudEvent(
                        "idmc:crud:create"
                    );

                    const form =
                        qs(
                            "[data-idmc-form-host] form"
                        );

                    if (form) {
                        form.scrollIntoView({
                            behavior: "smooth",
                            block: "start"
                        });

                        const first =
                            form.querySelector(
                                "input, select, textarea"
                            );

                        first?.focus();
                    }
                }
            );
        }

        const search =
            qs("[data-idmc-search]");

        if (search) {
            search.addEventListener(
                "input",
                () => {
                    const value =
                        search.value
                            .trim()
                            .toLowerCase();

                    const rows =
                        qsa(
                            "[data-idmc-runtime-host] tbody tr"
                        );

                    for (const row of rows) {
                        row.hidden =
                            value.length > 0 &&
                            !row.textContent
                                .toLowerCase()
                                .includes(value);
                    }
                }
            );
        }
    }

    function protectUnsupportedMutationButtons(
        contract
    ) {
        const mutationRules = [
            [
                "[data-action='create']",
                contract.canCreate
            ],
            [
                "[data-action='edit']",
                contract.canUpdate
            ],
            [
                "[data-action='delete']",
                contract.canDelete
            ]
        ];

        for (
            const [selector, allowed]
            of mutationRules
        ) {
            qsa(selector)
                .forEach(element => {
                    if (!allowed) {
                        element.hidden = true;
                        element.disabled = true;
                    }
                });
        }
    }

    function observeRuntime(contract) {
        const root =
            qs("[data-idmc-runtime-host]");

        if (!root) {
            return;
        }

        const observer =
            new MutationObserver(
                () => {
                    protectUnsupportedMutationButtons(
                        contract
                    );
                }
            );

        observer.observe(
            root,
            {
                childList: true,
                subtree: true
            }
        );
    }

    function boot() {
        const name = moduleName();

        if (
            !name ||
            !MODULES.includes(name)
        ) {
            return;
        }

        const contract =
            normalizeContract(
                getCrudContract(name)
            );

        applyCapabilities(contract);

        moveExistingRuntime();

        bindActions(contract);

        protectUnsupportedMutationButtons(
            contract
        );

        observeRuntime(contract);

        bootKnownCrudRuntime();

        if (
            !contract.canList &&
            !contract.canCreate
        ) {
            setStatus(
                "warning",
                "This module is currently exposed as read-only or has no list/create contract in the verified backend API."
            );
        }
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