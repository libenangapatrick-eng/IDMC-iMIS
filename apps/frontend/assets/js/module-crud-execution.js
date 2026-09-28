(function () {
    "use strict";

    const state = {
        module: "",
        contract: null,
        busy: false
    };

    function qs(selector, root = document) {
        return root.querySelector(selector);
    }

    function qsa(selector, root = document) {
        return Array.from(
            root.querySelectorAll(selector)
        );
    }

    function firstDefined(object, keys) {

        if (!object) {
            return undefined;
        }

        for (const key of keys) {

            if (
                Object.prototype
                    .hasOwnProperty
                    .call(object, key)
            ) {
                return object[key];
            }
        }

        return undefined;
    }

    function getModule() {

        return (
            document.body?.dataset?.idmcModule ||
            ""
        ).trim();
    }

    function crudApis() {

        return [
            window.IDMCModuleCRUD,
            window.IDMCModuleCrud,
            window.IDMCModuleCrudRuntime,
            window.IDMCCrud,
            window.IDMCCrudRuntime
        ].filter(Boolean);
    }

    function getRawContract(module) {

        for (const api of crudApis()) {

            if (
                typeof api.getContract ===
                "function"
            ) {
                try {

                    const contract =
                        api.getContract(module);

                    if (contract) {
                        return contract;
                    }
                }
                catch (error) {
                    console.error(error);
                }
            }

            if (
                api.contracts &&
                api.contracts[module]
            ) {
                return api.contracts[module];
            }
        }

        return null;
    }

    function normalizeMethod(value) {

        if (!value) {
            return null;
        }

        const method =
            String(value)
                .trim()
                .toUpperCase();

        if (
            ![
                "GET",
                "POST",
                "PATCH",
                "PUT",
                "DELETE"
            ].includes(method)
        ) {
            return null;
        }

        return method;
    }

    function normalizeContract(raw) {

        if (!raw) {
            return null;
        }

        const canCreate =
            Boolean(
                firstDefined(
                    raw,
                    [
                        "canCreate",
                        "CanCreate"
                    ]
                )
            );

        const canUpdate =
            Boolean(
                firstDefined(
                    raw,
                    [
                        "canUpdate",
                        "CanUpdate"
                    ]
                )
            );

        const canDelete =
            Boolean(
                firstDefined(
                    raw,
                    [
                        "canDelete",
                        "CanDelete"
                    ]
                )
            );

        const endpoint =
            firstDefined(
                raw,
                [
                    "endpoint",
                    "Endpoint",
                    "path",
                    "Path",
                    "route",
                    "Route",
                    "listEndpoint",
                    "ListEndpoint"
                ]
            ) || null;

        const createEndpoint =
            firstDefined(
                raw,
                [
                    "createEndpoint",
                    "CreateEndpoint",
                    "postEndpoint",
                    "PostEndpoint"
                ]
            ) || endpoint;

        const updateEndpoint =
            firstDefined(
                raw,
                [
                    "updateEndpoint",
                    "UpdateEndpoint",
                    "patchEndpoint",
                    "PatchEndpoint",
                    "putEndpoint",
                    "PutEndpoint"
                ]
            ) || endpoint;

        const deleteEndpoint =
            firstDefined(
                raw,
                [
                    "deleteEndpoint",
                    "DeleteEndpoint"
                ]
            ) || endpoint;

        const updateMethod =
            normalizeMethod(
                firstDefined(
                    raw,
                    [
                        "updateMethod",
                        "UpdateMethod"
                    ]
                )
            );

        const idField =
            firstDefined(
                raw,
                [
                    "idField",
                    "IdField",
                    "primaryKey",
                    "PrimaryKey"
                ]
            ) || "id";

        return {
            raw,
            canCreate,
            canUpdate,
            canDelete,
            endpoint,
            createEndpoint,
            updateEndpoint,
            deleteEndpoint,
            createMethod:
                canCreate
                    ? "POST"
                    : null,
            updateMethod:
                canUpdate
                    ? updateMethod
                    : null,
            deleteMethod:
                canDelete
                    ? "DELETE"
                    : null,
            idField
        };
    }

    function setStatus(stateName, message) {

        const element =
            qs("[data-idmc-status]");

        if (!element) {
            return;
        }

        element.dataset.state =
            message
                ? stateName
                : "";

        element.textContent =
            message || "";
    }

    function setBusy(value) {

        state.busy =
            Boolean(value);

        qsa(
            [
                "[data-form-save]",
                "[data-action='create']",
                "[data-action='edit']",
                "[data-action='delete']"
            ].join(",")
        ).forEach(element => {

            if (state.busy) {

                element.dataset
                    .idmcWasDisabled =
                    element.disabled
                        ? "true"
                        : "false";

                element.disabled = true;
            }
            else if (
                element.dataset
                    .idmcWasDisabled !==
                "true"
            ) {
                element.disabled = false;
            }
        });
    }

    function requireApi() {

        if (
            !window.IDMCAPI ||
            typeof window.IDMCAPI.request !==
                "function"
        ) {
            throw new Error(
                "IDMC API client is not available."
            );
        }

        return window.IDMCAPI;
    }

    function unwrap(response) {

        if (
            response &&
            typeof response === "object" &&
            Object.prototype
                .hasOwnProperty
                .call(response, "data")
        ) {
            return response.data;
        }

        return response;
    }

    function extractRecordId(record) {

        if (
            !record ||
            typeof record !== "object"
        ) {
            return null;
        }

        const preferred =
            state.contract?.idField ||
            "id";

        return (
            record[preferred] ??
            record.id ??
            record.uuid ??
            null
        );
    }

    function replaceIdToken(
        template,
        id
    ) {

        if (!template) {
            return null;
        }

        const encoded =
            encodeURIComponent(
                String(id)
            );

        return String(template)
            .replace(
                /:id\b/g,
                encoded
            )
            .replace(
                /\{id\}/g,
                encoded
            );
    }

    function buildItemPath(
        endpoint,
        id
    ) {

        if (
            !endpoint ||
            id === null ||
            id === undefined ||
            id === ""
        ) {
            return null;
        }

        const path =
            String(endpoint)
                .trim();

        if (
            /:id\b/.test(path) ||
            /\{id\}/.test(path)
        ) {
            return replaceIdToken(
                path,
                id
            );
        }

        return (
            path.replace(/\/+$/, "") +
            "/" +
            encodeURIComponent(
                String(id)
            )
        );
    }

    function resolveCreatePath() {

        if (
            !state.contract?.canCreate
        ) {
            return null;
        }

        return (
            state.contract
                .createEndpoint ||
            state.contract
                .endpoint ||
            null
        );
    }

    function resolveUpdatePath(record) {

        if (
            !state.contract?.canUpdate
        ) {
            return null;
        }

        const id =
            extractRecordId(record);

        if (
            id === null ||
            id === undefined ||
            id === ""
        ) {
            return null;
        }

        return buildItemPath(
            state.contract.updateEndpoint,
            id
        );
    }

    function resolveDeletePath(record) {

        if (
            !state.contract?.canDelete
        ) {
            return null;
        }

        const id =
            extractRecordId(record);

        if (
            id === null ||
            id === undefined ||
            id === ""
        ) {
            return null;
        }

        return buildItemPath(
            state.contract.deleteEndpoint,
            id
        );
    }

    function dispatch(name, detail = {}) {

        window.dispatchEvent(
            new CustomEvent(
                name,
                {
                    detail: {
                        module:
                            state.module,
                        ...detail
                    }
                }
            )
        );
    }

    function errorMessage(error) {

        if (!error) {
            return "Request failed.";
        }

        if (
            typeof error === "string"
        ) {
            return error;
        }

        return (
            error.message ||
            error.error ||
            "Request failed."
        );
    }

    async function executeCreate(
        payload
    ) {

        if (
            !state.contract?.canCreate
        ) {
            throw new Error(
                "Create is not supported by this module."
            );
        }

        const path =
            resolveCreatePath();

        if (!path) {
            throw new Error(
                "Verified create endpoint is unavailable."
            );
        }

        const api =
            requireApi();

        return unwrap(
            await api.request(
                path,
                {
                    method: "POST",
                    body: payload
                }
            )
        );
    }

    async function executeUpdate(
        payload,
        record
    ) {

        if (
            !state.contract?.canUpdate
        ) {
            throw new Error(
                "Update is not supported by this module."
            );
        }

        const method =
            state.contract
                .updateMethod;

        if (
            method !== "PATCH" &&
            method !== "PUT"
        ) {
            throw new Error(
                "Verified PATCH/PUT method is unavailable."
            );
        }

        const path =
            resolveUpdatePath(record);

        if (!path) {
            throw new Error(
                "Verified update endpoint or record ID is unavailable."
            );
        }

        const api =
            requireApi();

        return unwrap(
            await api.request(
                path,
                {
                    method,
                    body: payload
                }
            )
        );
    }

    async function executeDelete(
        record
    ) {

        if (
            !state.contract?.canDelete
        ) {
            throw new Error(
                "Delete is not supported by this module."
            );
        }

        const path =
            resolveDeletePath(record);

        if (!path) {
            throw new Error(
                "Verified delete endpoint or record ID is unavailable."
            );
        }

        const api =
            requireApi();

        return unwrap(
            await api.request(
                path,
                {
                    method: "DELETE"
                }
            )
        );
    }

    async function refreshRecords() {

        dispatch(
            "idmc:crud:refresh-requested"
        );

        for (const api of crudApis()) {

            const methods = [
                "refresh",
                "reload",
                "load",
                "loadRecords"
            ];

            for (const method of methods) {

                if (
                    typeof api[method] !==
                    "function"
                ) {
                    continue;
                }

                try {

                    await api[method](
                        state.module
                    );

                    return;
                }
                catch (error) {

                    console.error(
                        `CRUD ${method} failed:`,
                        error
                    );
                }
            }
        }

        dispatch(
            "idmc:crud:refresh"
        );
    }

    async function handleFormSubmit(
        event
    ) {

        const detail =
            event.detail || {};

        if (
            detail.module &&
            detail.module !==
                state.module
        ) {
            return;
        }

        if (state.busy) {
            return;
        }

        const operation =
            detail.operation;

        const payload =
            detail.payload || {};

        const record =
            detail.record || null;

        if (
            operation !== "create" &&
            operation !== "update"
        ) {
            return;
        }

        setBusy(true);

        setStatus(
            "loading",
            operation === "create"
                ? "Creating record..."
                : "Saving changes..."
        );

        try {

            let result;

            if (
                operation === "create"
            ) {
                result =
                    await executeCreate(
                        payload
                    );
            }
            else {
                result =
                    await executeUpdate(
                        payload,
                        record
                    );
            }

            setStatus(
                "success",
                operation === "create"
                    ? "Record created successfully."
                    : "Record updated successfully."
            );

            dispatch(
                "idmc:crud:success",
                {
                    operation,
                    record: result
                }
            );

            await refreshRecords();
        }
        catch (error) {

            console.error(error);

            setStatus(
                "error",
                errorMessage(error)
            );

            dispatch(
                "idmc:crud:error",
                {
                    operation,
                    error
                }
            );
        }
        finally {
            setBusy(false);
        }
    }

    function getRowRecord(element) {

        const row =
            element.closest(
                "tr, [data-record-row], [data-record]"
            );

        if (!row) {
            return null;
        }

        if (row.__idmcRecord) {
            return row.__idmcRecord;
        }

        if (row.dataset.record) {
            try {
                return JSON.parse(
                    row.dataset.record
                );
            }
            catch (error) {
                console.error(error);
            }
        }

        return null;
    }

    function requestEdit(record) {

        if (
            !state.contract?.canUpdate ||
            !record
        ) {
            return;
        }

        dispatch(
            "idmc:record:edit",
            { record }
        );
    }

    async function requestDelete(record) {

        if (
            !state.contract?.canDelete ||
            !record ||
            state.busy
        ) {
            return;
        }

        const id =
            extractRecordId(record);

        if (
            id === null ||
            id === undefined
        ) {
            setStatus(
                "error",
                "Cannot delete record because its identifier is unavailable."
            );

            return;
        }

        const accepted =
            window.confirm(
                "Delete this record? This action cannot be undone."
            );

        if (!accepted) {
            return;
        }

        setBusy(true);

        setStatus(
            "loading",
            "Deleting record..."
        );

        try {

            const result =
                await executeDelete(
                    record
                );

            setStatus(
                "success",
                "Record deleted successfully."
            );

            dispatch(
                "idmc:crud:success",
                {
                    operation:
                        "delete",
                    record,
                    result
                }
            );

            await refreshRecords();
        }
        catch (error) {

            console.error(error);

            setStatus(
                "error",
                errorMessage(error)
            );

            dispatch(
                "idmc:crud:error",
                {
                    operation:
                        "delete",
                    record,
                    error
                }
            );
        }
        finally {
            setBusy(false);
        }
    }

    function bindRecordActions() {

        document.addEventListener(
            "click",
            event => {

                const target =
                    event.target.closest(
                        [
                            "[data-action='edit']",
                            "[data-action='delete']"
                        ].join(",")
                    );

                if (!target) {
                    return;
                }

                const record =
                    target.__idmcRecord ||
                    getRowRecord(target);

                if (!record) {
                    return;
                }

                if (
                    target.matches(
                        "[data-action='edit']"
                    )
                ) {
                    event.preventDefault();
                    requestEdit(record);
                    return;
                }

                if (
                    target.matches(
                        "[data-action='delete']"
                    )
                ) {
                    event.preventDefault();

                    requestDelete(
                        record
                    );
                }
            }
        );

        window.addEventListener(
            "idmc:record:delete",
            event => {

                const record =
                    event.detail?.record;

                if (record) {
                    requestDelete(record);
                }
            }
        );
    }

    function addActionsToTable() {

        const host =
            qs(
                "[data-idmc-runtime-host]"
            );

        if (!host) {
            return;
        }

        const tables =
            qsa("table", host);

        for (const table of tables) {

            const headerRow =
                qs("thead tr", table);

            if (
                headerRow &&
                !qs(
                    "[data-idmc-actions-header]",
                    headerRow
                )
            ) {
                const th =
                    document.createElement(
                        "th"
                    );

                th.textContent =
                    "Actions";

                th.dataset
                    .idmcActionsHeader =
                    "true";

                headerRow.appendChild(th);
            }

            const rows =
                qsa("tbody tr", table);

            for (const row of rows) {

                if (
                    qs(
                        "[data-idmc-actions]",
                        row
                    )
                ) {
                    continue;
                }

                const record =
                    row.__idmcRecord ||
                    (
                        row.dataset.record
                            ? safeParse(
                                row.dataset.record
                            )
                            : null
                    );

                const td =
                    document.createElement(
                        "td"
                    );

                td.dataset.idmcActions =
                    "true";

                td.className =
                    "idmc-record-actions";

                if (
                    state.contract?.canUpdate
                ) {
                    const edit =
                        document.createElement(
                            "button"
                        );

                    edit.type = "button";
                    edit.className =
                        "idmc-btn";

                    edit.dataset.action =
                        "edit";

                    edit.textContent =
                        "Edit";

                    if (record) {
                        edit.__idmcRecord =
                            record;
                    }

                    td.appendChild(edit);
                }

                if (
                    state.contract?.canDelete
                ) {
                    const remove =
                        document.createElement(
                            "button"
                        );

                    remove.type =
                        "button";

                    remove.className =
                        "idmc-btn idmc-btn-danger";

                    remove.dataset.action =
                        "delete";

                    remove.textContent =
                        "Delete";

                    if (record) {
                        remove.__idmcRecord =
                            record;
                    }

                    td.appendChild(remove);
                }

                if (
                    td.childElementCount > 0
                ) {
                    row.appendChild(td);
                }
            }
        }
    }

    function safeParse(value) {

        try {
            return JSON.parse(value);
        }
        catch {
            return null;
        }
    }

    function observeRecordTables() {

        const host =
            qs(
                "[data-idmc-runtime-host]"
            );

        if (!host) {
            return;
        }

        addActionsToTable();

        const observer =
            new MutationObserver(
                () => {
                    addActionsToTable();
                }
            );

        observer.observe(
            host,
            {
                childList: true,
                subtree: true
            }
        );
    }

    function boot() {

        state.module =
            getModule();

        if (!state.module) {
            return;
        }

        state.contract =
            normalizeContract(
                getRawContract(
                    state.module
                )
            );

        if (!state.contract) {

            console.warn(
                "No verified CRUD contract for:",
                state.module
            );

            return;
        }

        window.addEventListener(
            "idmc:form:submit",
            handleFormSubmit
        );

        bindRecordActions();
        observeRecordTables();

        dispatch(
            "idmc:crud:execution-ready",
            {
                contract:
                    state.contract.raw
            }
        );
    }

    window.IDMCModuleCRUDExecution = {
        boot,

        create(payload) {
            return executeCreate(payload);
        },

        update(payload, record) {
            return executeUpdate(
                payload,
                record
            );
        },

        delete(record) {
            return requestDelete(record);
        },

        refresh() {
            return refreshRecords();
        },

        getContract() {
            return state.contract;
        }
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