(function () {
    "use strict";

    const contracts = {"admissions":{"endpoint":"/admission-offers","canList":false,"canCreate":true,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":["academic_completion_status","actionCode","actorUserId","admission_letter_url","approval_level","approval_role","approval_stage","comments","decision","entityType","ipAddress","joining_instructions_url","moduleCode","next","offer_number","patch","permission","reason","remarks","req","requestId","res","status","table"]},"registration":{"endpoint":"/registrations","canList":false,"canCreate":true,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":["academic_completion_status","actionCode","actorUserId","admission_letter_url","approval_level","approval_role","approval_stage","comments","decision","entityType","ipAddress","joining_instructions_url","moduleCode","next","offer_number","patch","permission","reason","remarks","req","requestId","res","status","table"]},"attendance":{"endpoint":"/attendance","canList":false,"canCreate":false,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":[]},"assessment":{"endpoint":"/assessments","canList":false,"canCreate":true,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":["academic_completion_status","actionCode","actorUserId","admission_letter_url","approval_level","approval_role","approval_stage","comments","decision","entityType","ipAddress","joining_instructions_url","moduleCode","next","offer_number","patch","permission","reason","remarks","req","requestId","res","status","table"]},"examinations":{"endpoint":"/examinations","canList":false,"canCreate":true,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":["academic_completion_status","actionCode","actorUserId","admission_letter_url","approval_level","approval_role","approval_stage","comments","decision","entityType","ipAddress","joining_instructions_url","moduleCode","next","offer_number","patch","permission","reason","remarks","req","requestId","res","status","table"]},"results":{"endpoint":"/course-result-policies","canList":false,"canCreate":true,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":["academic_completion_status","actionCode","actorUserId","admission_letter_url","approval_level","approval_role","approval_stage","comments","decision","entityType","ipAddress","joining_instructions_url","moduleCode","next","offer_number","patch","permission","reason","remarks","req","requestId","res","status","table"]},"timetable":{"endpoint":"/timetables","canList":false,"canCreate":true,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":["academic_completion_status","actionCode","actorUserId","admission_letter_url","approval_level","approval_role","approval_stage","comments","decision","entityType","ipAddress","joining_instructions_url","moduleCode","next","offer_number","patch","permission","reason","remarks","req","requestId","res","status","table"]},"finance":{"endpoint":"/fee-structures","canList":true,"canCreate":false,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":[]},"communications":{"endpoint":"/helpdesk/messages","canList":false,"canCreate":false,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":[]},"library":{"endpoint":"/library","canList":false,"canCreate":false,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":[]},"hostel":{"endpoint":"/hostels","canList":false,"canCreate":false,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":[]},"hr":{"endpoint":"/hr/leave/balances","canList":false,"canCreate":false,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":[]},"research":{"endpoint":"/research/projects","canList":false,"canCreate":false,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":[]},"graduation":{"endpoint":"/graduation","canList":false,"canCreate":true,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":["academic_completion_status","actionCode","actorUserId","admission_letter_url","approval_level","approval_role","approval_stage","comments","decision","entityType","ipAddress","joining_instructions_url","moduleCode","next","offer_number","patch","permission","reason","remarks","req","requestId","res","status","table"]},"alumni":{"endpoint":"/alumni","canList":false,"canCreate":true,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":["academic_completion_status","actionCode","actorUserId","admission_letter_url","approval_level","approval_role","approval_stage","comments","decision","entityType","ipAddress","joining_instructions_url","moduleCode","next","offer_number","patch","permission","reason","remarks","req","requestId","res","status","table"]},"transcripts":{"endpoint":"/transcripts","canList":false,"canCreate":true,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":["academic_completion_status","actionCode","actorUserId","admission_letter_url","approval_level","approval_role","approval_stage","comments","decision","entityType","ipAddress","joining_instructions_url","moduleCode","next","offer_number","patch","permission","reason","remarks","req","requestId","res","status","table"]},"operations":{"endpoint":"/procurement/orders","canList":false,"canCreate":false,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":[]},"reports":{"endpoint":"/reports","canList":false,"canCreate":false,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":[]},"system":{"endpoint":"/settings","canList":false,"canCreate":false,"canUpdate":false,"updateMethod":null,"canDelete":false,"fields":[]}};

    // Correct the legacy generated finance contract. The canonical API is
    // mounted below /finance; leaving the old root path creates a false 404.
    if (contracts.finance) {
        contracts.finance.endpoint = "/finance/fee-structures";
    }

    function moduleName() {
        return (
            document.body?.dataset?.module ||
            location.pathname
                .split("/")
                .pop()
                ?.replace(/\.html$/i, "") ||
            ""
        );
    }

    function contract() {
        return contracts[moduleName()] || null;
    }

    function apiRequest(path, options = {}) {
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

    function escapeHtml(value) {
        return String(value ?? "")
            .replaceAll("&", "&amp;")
            .replaceAll("<", "&lt;")
            .replaceAll(">", "&gt;")
            .replaceAll('"', "&quot;")
            .replaceAll("'", "&#039;");
    }

    function label(value) {
        return String(value || "")
            .replaceAll("_", " ")
            .replace(/\b\w/g, x => x.toUpperCase());
    }

    function rowsOf(response) {
        const value = response?.data ?? response;

        if (Array.isArray(value)) {
            return value;
        }

        for (
            const key of [
                "items",
                "rows",
                "records",
                "results",
                "data"
            ]
        ) {
            if (Array.isArray(value?.[key])) {
                return value[key];
            }
        }

        return [];
    }

    function recordId(row) {
        return (
            row?.id ??
            row?.uuid ??
            row?.record_id ??
            null
        );
    }

    function mount() {
        return (
            document.querySelector(
                "[data-idmc-module-workspace]"
            ) ||
            document.querySelector("main") ||
            document.body
        );
    }

    async function boot() {
        const c = contract();

        if (!c || !c.canList) {
            return;
        }

        const root =
            document.createElement("section");

        root.className = "idmc-real-crud";

        root.innerHTML = `
            <div class="idmc-real-crud-head">
                <div>
                    <h2>${escapeHtml(label(moduleName()))}</h2>
                    <span data-crud-status>Loading...</span>
                </div>

                <div>
                    <button type="button" data-refresh>
                        Refresh
                    </button>

                    ${
                        c.canCreate
                            ? `<button type="button" data-create>Add New</button>`
                            : ""
                    }
                </div>
            </div>

            <div data-crud-content>
                Loading...
            </div>

            <dialog data-crud-dialog>
                <form method="dialog" data-crud-form>
                    <h3 data-form-title>Record</h3>

                    <div data-fields></div>

                    <div>
                        <button
                            type="button"
                            data-cancel
                        >
                            Cancel
                        </button>

                        <button type="submit">
                            Save
                        </button>
                    </div>
                </form>
            </dialog>
        `;

        mount().appendChild(root);

        const status =
            root.querySelector("[data-crud-status]");

        const content =
            root.querySelector("[data-crud-content]");

        const dialog =
            root.querySelector("[data-crud-dialog]");

        const form =
            root.querySelector("[data-crud-form]");

        const fields =
            root.querySelector("[data-fields]");

        const title =
            root.querySelector("[data-form-title]");

        let records = [];
        let editing = null;

        function openForm(row = null) {
            editing = row;

            title.textContent =
                row ? "Edit Record" : "Add Record";

            fields.innerHTML = "";

            for (const field of c.fields) {
                const wrapper =
                    document.createElement("label");

                wrapper.innerHTML =
                    `<span>${escapeHtml(label(field))}</span>`;

                const relationship =
                    window.IDMCRelationships?.get(
                        c.endpoint,
                        field
                    );

                let input;

                if (relationship) {
                    input =
                        document.createElement("select");

                    input.name = field;

                    const placeholder =
                        document.createElement("option");

                    placeholder.value = "";
                    placeholder.textContent =
                        `Select ${label(field)}`;

                    input.appendChild(placeholder);

                    input.disabled = true;

                    window.IDMCRelationships
                        .optionsFor(relationship.endpoint)
                        .then(rows => {
                            for (const item of rows) {
                                const value =
                                    item?.[
                                        relationship.valueKey ||
                                        "id"
                                    ] ??
                                    item?.uuid;

                                if (
                                    value === null ||
                                    value === undefined
                                ) {
                                    continue;
                                }

                                const option =
                                    document.createElement(
                                        "option"
                                    );

                                option.value =
                                    String(value);

                                option.textContent =
                                    window.IDMCRelationships
                                        .displayValue(item);

                                input.appendChild(option);
                            }

                            if (
                                row &&
                                row[field] !== null &&
                                row[field] !== undefined
                            ) {
                                input.value =
                                    String(row[field]);
                            }

                            input.disabled = false;
                        })
                        .catch(error => {
                            console.error(
                                "Relationship selector failed:",
                                field,
                                relationship.endpoint,
                                error
                            );

                            input.disabled = false;
                        });
                }
                else {
                    input =
                        document.createElement("input");

                    input.name = field;

                    input.type =
                        /email/i.test(field)
                            ? "email"
                            : "text";

                    if (
                        row &&
                        row[field] !== null &&
                        row[field] !== undefined
                    ) {
                        input.value =
                            String(row[field]);
                    }
                }

                wrapper.appendChild(input);
                fields.appendChild(wrapper);
            }

            dialog.showModal();
        }

        function render() {
            if (!records.length) {
                content.innerHTML =
                    `<p>No records found.</p>`;
                return;
            }

            const columnSet = new Set();

            for (const row of records.slice(0, 10)) {
                for (const key of Object.keys(row || {})) {
                    if (
                        row[key] === null ||
                        typeof row[key] !== "object"
                    ) {
                        columnSet.add(key);
                    }
                }
            }

            const columns =
                [...columnSet].slice(0, 8);

            const actions =
                c.canUpdate || c.canDelete;

            content.innerHTML = `
                <div style="overflow:auto">
                    <table>
                        <thead>
                            <tr>
                                ${columns.map(
                                    x =>
                                        `<th>${escapeHtml(label(x))}</th>`
                                ).join("")}

                                ${actions ? "<th>Actions</th>" : ""}
                            </tr>
                        </thead>

                        <tbody>
                            ${records.map(
                                (row, index) => `
                                    <tr>
                                        ${columns.map(
                                            x =>
                                                `<td>${escapeHtml(
                                                    row?.[x] ?? ""
                                                )}</td>`
                                        ).join("")}

                                        ${
                                            actions
                                                ? `
                                                    <td>
                                                        ${
                                                            c.canUpdate
                                                                ? `<button type="button" data-edit="${index}">Edit</button>`
                                                                : ""
                                                        }

                                                        ${
                                                            c.canDelete
                                                                ? `<button type="button" data-delete="${index}">Delete</button>`
                                                                : ""
                                                        }
                                                    </td>
                                                `
                                                : ""
                                        }
                                    </tr>
                                `
                            ).join("")}
                        </tbody>
                    </table>
                </div>
            `;

            content
                .querySelectorAll("[data-edit]")
                .forEach(button => {
                    button.onclick = () =>
                        openForm(
                            records[
                                Number(button.dataset.edit)
                            ]
                        );
                });

            content
                .querySelectorAll("[data-delete]")
                .forEach(button => {
                    button.onclick = async () => {
                        const row =
                            records[
                                Number(button.dataset.delete)
                            ];

                        const id = recordId(row);

                        if (!id) {
                            alert("Record ID unavailable.");
                            return;
                        }

                        if (!confirm("Delete this record?")) {
                            return;
                        }

                        try {
                            await apiRequest(
                                `${c.endpoint}/${encodeURIComponent(id)}`,
                                {
                                    method: "DELETE"
                                }
                            );

                            await load();
                        }
                        catch (error) {
                            alert(
                                error?.message ||
                                "Delete failed."
                            );
                        }
                    };
                });
        }

        async function load() {
            status.textContent = "Loading...";

            try {
                const response =
                    await apiRequest(c.endpoint);

                records = rowsOf(response);

                status.textContent =
                    `${records.length} record(s)`;

                render();
            }
            catch (error) {
                status.textContent = "Load failed";

                content.innerHTML =
                    `<p>${escapeHtml(
                        error?.message ||
                        "Unable to load data."
                    )}</p>`;
            }
        }

        root
            .querySelector("[data-refresh]")
            .onclick = load;

        root
            .querySelector("[data-create]")
            ?.addEventListener(
                "click",
                () => openForm()
            );

        root
            .querySelector("[data-cancel]")
            .onclick = () => dialog.close();

        form.addEventListener(
            "submit",
            async event => {
                event.preventDefault();

                const payload =
                    Object.fromEntries(
                        new FormData(form).entries()
                    );

                try {
                    if (editing) {
                        const id = recordId(editing);

                        if (!id) {
                            throw new Error(
                                "Record ID unavailable."
                            );
                        }

                        await apiRequest(
                            `${c.endpoint}/${encodeURIComponent(id)}`,
                            {
                                method:
                                    c.updateMethod ||
                                    "PATCH",

                                headers: {
                                    "Content-Type":
                                        "application/json"
                                },

                                body:
                                    JSON.stringify(payload)
                            }
                        );
                    }
                    else {
                        await apiRequest(
                            c.endpoint,
                            {
                                method: "POST",

                                headers: {
                                    "Content-Type":
                                        "application/json"
                                },

                                body:
                                    JSON.stringify(payload)
                            }
                        );
                    }

                    dialog.close();
                    editing = null;
                    await load();
                }
                catch (error) {
                    alert(
                        error?.message ||
                        "Save failed."
                    );
                }
            }
        );

        await load();
    }

    window.IDMCRealCRUD = {
        contracts,
        boot
    };

    if (document.readyState === "loading") {
        document.addEventListener(
            "DOMContentLoaded",
            boot
        );
    }
    else {
        boot();
    }
})();
