(function () {
    "use strict";

    const state = {
        module: "",
        contract: null,
        mode: "create",
        record: null,
        form: null
    };

    const SYSTEM_FIELDS = new Set([
        "id",
        "created_at",
        "updated_at",
        "created_by",
        "updated_by",
        "deleted_at"
    ]);

    function qs(selector, root = document) {
        return root.querySelector(selector);
    }

    function qsa(selector, root = document) {
        return Array.from(
            root.querySelectorAll(selector)
        );
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

    function relationshipApis() {
        return [
            window.IDMCModuleRelationships,
            window.IDMCModuleRelationship,
            window.IDMCRelationships
        ].filter(Boolean);
    }

    function getContract(module) {
        for (const api of crudApis()) {

            if (
                typeof api.getContract ===
                "function"
            ) {
                try {
                    const result =
                        api.getContract(module);

                    if (result) {
                        return result;
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

    function firstDefined(object, keys) {
        if (!object) {
            return undefined;
        }

        for (const key of keys) {
            if (
                Object.prototype.hasOwnProperty.call(
                    object,
                    key
                )
            ) {
                return object[key];
            }
        }

        return undefined;
    }

    function boolValue(object, keys) {
        return Boolean(
            firstDefined(object, keys)
        );
    }

    function normalizeContract(raw) {

        if (!raw) {
            return {
                raw: null,
                canList: false,
                canCreate: false,
                canUpdate: false,
                canDelete: false,
                updateMethod: null,
                fields: []
            };
        }

        const fields =
            firstDefined(
                raw,
                [
                    "fields",
                    "Fields",
                    "formFields",
                    "FormFields"
                ]
            );

        return {
            raw,

            canList:
                boolValue(
                    raw,
                    ["canList", "CanList"]
                ),

            canCreate:
                boolValue(
                    raw,
                    ["canCreate", "CanCreate"]
                ),

            canUpdate:
                boolValue(
                    raw,
                    ["canUpdate", "CanUpdate"]
                ),

            canDelete:
                boolValue(
                    raw,
                    ["canDelete", "CanDelete"]
                ),

            updateMethod:
                firstDefined(
                    raw,
                    [
                        "updateMethod",
                        "UpdateMethod"
                    ]
                ) || null,

            fields:
                Array.isArray(fields)
                    ? fields
                    : []
        };
    }

    function humanize(value) {
        return String(value || "")
            .replace(/_/g, " ")
            .replace(/([a-z])([A-Z])/g, "$1 $2")
            .replace(/\b\w/g, char =>
                char.toUpperCase()
            );
    }

    function fieldName(field) {

        if (typeof field === "string") {
            return field;
        }

        return (
            firstDefined(
                field,
                [
                    "name",
                    "Name",
                    "field",
                    "Field",
                    "key",
                    "Key",
                    "column",
                    "Column"
                ]
            ) || ""
        );
    }

    function fieldRequired(field) {

        if (
            !field ||
            typeof field === "string"
        ) {
            return false;
        }

        const direct =
            firstDefined(
                field,
                [
                    "required",
                    "Required",
                    "isRequired",
                    "IsRequired"
                ]
            );

        if (direct !== undefined) {
            return Boolean(direct);
        }

        const nullable =
            firstDefined(
                field,
                [
                    "nullable",
                    "Nullable",
                    "isNullable",
                    "IsNullable"
                ]
            );

        if (nullable !== undefined) {
            return !Boolean(nullable);
        }

        return false;
    }

    function explicitType(field) {

        if (
            !field ||
            typeof field === "string"
        ) {
            return "";
        }

        return String(
            firstDefined(
                field,
                [
                    "inputType",
                    "InputType",
                    "type",
                    "Type",
                    "dataType",
                    "DataType"
                ]
            ) || ""
        ).toLowerCase();
    }

    function inferType(name, field) {

        const explicit =
            explicitType(field);

        if (
            [
                "textarea",
                "select",
                "email",
                "tel",
                "date",
                "datetime-local",
                "number",
                "checkbox",
                "url",
                "password",
                "text"
            ].includes(explicit)
        ) {
            return explicit;
        }

        if (
            explicit.includes("bool")
        ) {
            return "checkbox";
        }

        if (
            explicit.includes("int") ||
            explicit.includes("numeric") ||
            explicit.includes("decimal") ||
            explicit.includes("float") ||
            explicit.includes("double")
        ) {
            return "number";
        }

        const lower =
            name.toLowerCase();

        if (
            lower === "email" ||
            lower.endsWith("_email")
        ) {
            return "email";
        }

        if (
            lower === "phone" ||
            lower.endsWith("_phone") ||
            lower.includes("telephone")
        ) {
            return "tel";
        }

        if (
            lower === "website" ||
            lower.endsWith("_url")
        ) {
            return "url";
        }

        if (
            lower.includes("description") ||
            lower.includes("remarks") ||
            lower.includes("comment") ||
            lower.includes("notes") ||
            lower.includes("address") ||
            lower.includes("message") ||
            lower.includes("content")
        ) {
            return "textarea";
        }

        if (
            lower.endsWith("_date") ||
            lower === "date" ||
            lower === "dob" ||
            lower.includes("birth_date")
        ) {
            return "date";
        }

        if (
            lower.endsWith("_at") &&
            !SYSTEM_FIELDS.has(lower)
        ) {
            return "datetime-local";
        }

        if (
            lower.startsWith("is_") ||
            lower.startsWith("has_") ||
            lower === "active" ||
            lower === "enabled"
        ) {
            return "checkbox";
        }

        if (
            lower.includes("amount") ||
            lower.includes("score") ||
            lower.includes("marks") ||
            lower.includes("quantity") ||
            lower.includes("credits") ||
            lower.includes("percentage") ||
            lower.includes("year")
        ) {
            return "number";
        }

        return "text";
    }

    function getOptions(field) {

        if (
            !field ||
            typeof field === "string"
        ) {
            return [];
        }

        const options =
            firstDefined(
                field,
                [
                    "options",
                    "Options",
                    "values",
                    "Values",
                    "enum",
                    "Enum"
                ]
            );

        return Array.isArray(options)
            ? options
            : [];
    }

    function getRelationship(name) {

        for (
            const api
            of relationshipApis()
        ) {

            const methods = [
                "getRelationship",
                "getFieldRelationship",
                "resolve"
            ];

            for (const method of methods) {

                if (
                    typeof api[method] !==
                    "function"
                ) {
                    continue;
                }

                try {
                    const result =
                        api[method](
                            state.module,
                            name
                        );

                    if (result) {
                        return result;
                    }
                }
                catch (error) {
                    console.error(error);
                }
            }

            const contracts =
                api.relationships ||
                api.contracts;

            if (
                contracts &&
                contracts[state.module] &&
                contracts[state.module][name]
            ) {
                return (
                    contracts[state.module][name]
                );
            }
        }

        return null;
    }

    function escapeHtml(value) {
        const div =
            document.createElement("div");

        div.textContent =
            value == null
                ? ""
                : String(value);

        return div.innerHTML;
    }

    function createControl(field) {

        const name =
            fieldName(field);

        if (
            !name ||
            SYSTEM_FIELDS.has(
                name.toLowerCase()
            )
        ) {
            return null;
        }

        const required =
            fieldRequired(field);

        const type =
            inferType(name, field);

        const options =
            getOptions(field);

        const relationship =
            getRelationship(name);

        const wrapper =
            document.createElement("div");

        wrapper.className =
            "idmc-field";

        wrapper.dataset.field =
            name;

        const label =
            document.createElement("label");

        label.htmlFor =
            `idmc-field-${name}`;

        label.textContent =
            humanize(name);

        if (required) {
            const marker =
                document.createElement("span");

            marker.className =
                "idmc-required";

            marker.textContent = " *";

            label.appendChild(marker);
        }

        wrapper.appendChild(label);

        let control;

        if (
            options.length > 0
        ) {
            control =
                document.createElement(
                    "select"
                );

            const blank =
                document.createElement(
                    "option"
                );

            blank.value = "";
            blank.textContent =
                `Select ${humanize(name)}`;

            control.appendChild(blank);

            for (const option of options) {

                const element =
                    document.createElement(
                        "option"
                    );

                if (
                    option &&
                    typeof option === "object"
                ) {
                    element.value =
                        option.value ??
                        option.id ??
                        "";

                    element.textContent =
                        option.label ??
                        option.name ??
                        option.value ??
                        option.id ??
                        "";
                }
                else {
                    element.value =
                        option;

                    element.textContent =
                        String(option);
                }

                control.appendChild(element);
            }
        }
        else if (type === "textarea") {

            control =
                document.createElement(
                    "textarea"
                );

            control.rows = 4;
        }
        else if (type === "checkbox") {

            const checkboxWrap =
                document.createElement(
                    "div"
                );

            checkboxWrap.className =
                "idmc-checkbox-wrap";

            control =
                document.createElement(
                    "input"
                );

            control.type = "checkbox";

            checkboxWrap.appendChild(
                control
            );

            const text =
                document.createElement(
                    "span"
                );

            text.textContent =
                `Enable ${humanize(name)}`;

            checkboxWrap.appendChild(text);

            wrapper.appendChild(
                checkboxWrap
            );
        }
        else {

            control =
                document.createElement(
                    "input"
                );

            control.type = type;
        }

        control.id =
            `idmc-field-${name}`;

        control.name = name;

        control.dataset.idmcField =
            name;

        if (required) {
            control.required = true;
        }

        if (
            type === "number" &&
            control.tagName === "INPUT"
        ) {
            control.step = "any";
        }

        if (
            relationship &&
            control.tagName !== "SELECT"
        ) {
            control.dataset.relationshipField =
                "true";
        }

        if (
            !control.parentElement
        ) {
            wrapper.appendChild(control);
        }

        const error =
            document.createElement("div");

        error.className =
            "idmc-field-error";

        error.dataset.errorFor =
            name;

        wrapper.appendChild(error);

        return wrapper;
    }

    function buildFields() {

        const host =
            qs("[data-idmc-form-host]");

        if (!host) {
            return;
        }

        host.innerHTML = "";

        if (
            state.contract.fields.length === 0
        ) {
            const message =
                document.createElement("p");

            message.className =
                "idmc-module-note";

            message.textContent =
                "No backend-derived writable fields are available for this module.";

            host.appendChild(message);

            return;
        }

        const form =
            document.createElement("form");

        form.id =
            "idmc-module-record-form";

        form.noValidate = true;

        for (
            const field
            of state.contract.fields
        ) {
            const control =
                createControl(field);

            if (control) {
                form.appendChild(control);
            }
        }

        const actions =
            document.createElement("div");

        actions.className =
            "idmc-form-actions";

        const save =
            document.createElement(
                "button"
            );

        save.type = "submit";
        save.className =
            "idmc-btn idmc-btn-primary";

        save.dataset.formSave = "true";

        save.textContent =
            state.mode === "edit"
                ? "Save Changes"
                : "Create Record";

        const cancel =
            document.createElement(
                "button"
            );

        cancel.type = "button";
        cancel.className =
            "idmc-btn";

        cancel.dataset.formCancel =
            "true";

        cancel.textContent = "Cancel";

        actions.appendChild(save);
        actions.appendChild(cancel);

        form.appendChild(actions);

        form.addEventListener(
            "submit",
            handleSubmit
        );

        cancel.addEventListener(
            "click",
            resetForm
        );

        host.appendChild(form);

        state.form = form;

        applyMode();
    }

    function applyMode() {

        if (!state.form) {
            return;
        }

        const save =
            qs(
                "[data-form-save]",
                state.form
            );

        if (!save) {
            return;
        }

        const allowed =
            state.mode === "edit"
                ? state.contract.canUpdate
                : state.contract.canCreate;

        save.hidden = !allowed;
        save.disabled = !allowed;

        save.textContent =
            state.mode === "edit"
                ? "Save Changes"
                : "Create Record";
    }

    function clearErrors() {
        qsa(".idmc-field-error")
            .forEach(element => {
                element.textContent = "";
            });

        qsa("[data-idmc-field]")
            .forEach(element => {
                element.removeAttribute(
                    "aria-invalid"
                );
            });
    }

    function showFieldError(
        name,
        message
    ) {
        const error =
            qs(
                `[data-error-for="${CSS.escape(name)}"]`
            );

        const field =
            qs(
                `[data-idmc-field="${CSS.escape(name)}"]`
            );

        if (error) {
            error.textContent = message;
        }

        if (field) {
            field.setAttribute(
                "aria-invalid",
                "true"
            );
        }
    }

    function collectPayload() {

        clearErrors();

        if (!state.form) {
            return {
                valid: false,
                payload: {}
            };
        }

        const payload = {};
        let valid = true;

        const controls =
            qsa(
                "[data-idmc-field]",
                state.form
            );

        for (const control of controls) {

            const name =
                control.dataset.idmcField;

            let value;

            if (
                control.type ===
                "checkbox"
            ) {
                value = control.checked;
            }
            else {
                value =
                    control.value.trim();
            }

            if (
                control.required &&
                (
                    value === "" ||
                    value === null ||
                    value === undefined
                )
            ) {
                valid = false;

                showFieldError(
                    name,
                    `${humanize(name)} is required.`
                );

                continue;
            }

            if (
                value === "" &&
                !control.required
            ) {
                payload[name] = null;
                continue;
            }

            if (
                control.type ===
                "number" &&
                value !== ""
            ) {
                const numeric =
                    Number(value);

                if (
                    Number.isNaN(numeric)
                ) {
                    valid = false;

                    showFieldError(
                        name,
                        `${humanize(name)} must be a valid number.`
                    );

                    continue;
                }

                value = numeric;
            }

            payload[name] = value;
        }

        return {
            valid,
            payload
        };
    }

    function dispatchMutation(
        operation,
        payload
    ) {
        const detail = {
            module: state.module,
            operation,
            payload,
            record: state.record
        };

        window.dispatchEvent(
            new CustomEvent(
                "idmc:form:submit",
                { detail }
            )
        );

        window.dispatchEvent(
            new CustomEvent(
                `idmc:crud:${operation}`,
                { detail }
            )
        );
    }

    function handleSubmit(event) {

        event.preventDefault();

        const operation =
            state.mode === "edit"
                ? "update"
                : "create";

        const allowed =
            operation === "update"
                ? state.contract.canUpdate
                : state.contract.canCreate;

        if (!allowed) {
            return;
        }

        const result =
            collectPayload();

        if (!result.valid) {
            return;
        }

        /*
         * A7.13 deliberately does NOT call an
         * endpoint directly.
         *
         * Existing module-crud.js owns the
         * verified CRUD route/method contract.
         */

        dispatchMutation(
            operation,
            result.payload
        );
    }

    function setControlValue(
        control,
        value
    ) {
        if (
            control.type ===
            "checkbox"
        ) {
            control.checked =
                Boolean(value);

            return;
        }

        if (
            value === null ||
            value === undefined
        ) {
            control.value = "";
            return;
        }

        if (
            control.type ===
            "datetime-local"
        ) {
            const text =
                String(value);

            control.value =
                text.length >= 16
                    ? text.substring(0, 16)
                    : text;

            return;
        }

        control.value =
            String(value);
    }

    function editRecord(record) {

        if (
            !record ||
            !state.contract.canUpdate
        ) {
            return;
        }

        state.mode = "edit";
        state.record = record;

        if (!state.form) {
            buildFields();
        }

        const controls =
            qsa(
                "[data-idmc-field]",
                state.form
            );

        for (const control of controls) {

            const name =
                control.dataset.idmcField;

            setControlValue(
                control,
                record[name]
            );
        }

        applyMode();

        state.form?.scrollIntoView({
            behavior: "smooth",
            block: "start"
        });
    }

    function resetForm() {

        state.mode = "create";
        state.record = null;

        if (state.form) {
            state.form.reset();
        }

        clearErrors();
        applyMode();
    }

    function bindExternalEvents() {

        window.addEventListener(
            "idmc:crud:create",
            () => {
                if (
                    !state.contract.canCreate
                ) {
                    return;
                }

                resetForm();

                state.form?.scrollIntoView({
                    behavior: "smooth",
                    block: "start"
                });
            }
        );

        window.addEventListener(
            "idmc:crud:edit",
            event => {
                editRecord(
                    event.detail?.record
                );
            }
        );

        window.addEventListener(
            "idmc:record:edit",
            event => {
                editRecord(
                    event.detail?.record
                );
            }
        );

        window.addEventListener(
            "idmc:crud:success",
            () => {
                resetForm();
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
                getContract(
                    state.module
                )
            );

        buildFields();
        bindExternalEvents();
    }

    window.IDMCModuleFormBinding = {
        boot,
        reset: resetForm,
        editRecord,
        collectPayload,
        getState: () => ({
            module: state.module,
            mode: state.mode,
            record: state.record,
            contract: state.contract
        })
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