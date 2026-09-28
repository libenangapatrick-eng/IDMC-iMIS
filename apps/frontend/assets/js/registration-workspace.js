(function () {
"use strict";

const API = window.IDMCAPI;

if (!API || typeof API.request !== "function") {
    console.error("IDMCAPI transport is unavailable.");
    return;
}

const RESOURCES = [
    {
        key: "registrations",
        title: "Student Registrations",
        endpoint: "/academic-core/registrations",
        fields: [
            "studentId",
            "academicYearId",
            "semesterId",
            "programmeId",
            "programmeVersionId",
            "registrationNumber",
            "registrationStatus",
            "academicEligibilityStatus",
            "financeEligibilityStatus",
            "documentEligibilityStatus",
            "totalRegisteredCredits",
            "minimumCredits",
            "maximumCredits",
            "notes"
        ]
    },
    {
        key: "courses",
        title: "Course Registrations",
        endpoint: "/academic-core/course-registrations",
        fields: [
            "studentRegistrationId",
            "studentId",
            "courseId",
            "courseOfferingId",
            "registrationType",
            "registrationStatus",
            "credits",
            "attemptNumber",
            "isCore",
            "isElective",
            "prerequisiteStatus",
            "eligibilityStatus",
            "notes"
        ]
    },
    {
        key: "approvals",
        title: "Registration Approvals",
        endpoint: "/academic-core/registration-approvals",
        fields: [
            "studentRegistrationId",
            "approvalLevel",
            "approvalRole",
            "approvalStatus",
            "comments"
        ]
    },
    {
        key: "adddrop",
        title: "Add / Drop Requests",
        endpoint: "/academic-core/add-drop-requests",
        fields: [
            "studentRegistrationId",
            "studentId",
            "courseId",
            "courseOfferingId",
            "requestType",
            "requestStatus",
            "reason",
            "decisionReason"
        ]
    }
];

const RELATIONSHIPS = {
    studentId:              { endpoint: "/students",                       label: ["studentNumber","firstName","lastName"] },
    academicYearId:         { endpoint: "/academic-core/years",            label: ["yearCode","yearName"] },
    semesterId:             { endpoint: "/academic-core/semesters",        label: ["semesterCode","semesterName"] },
    programmeId:            { endpoint: "/academic-core/programmes",       label: ["programmeCode","programmeName"] },
    programmeVersionId:     { endpoint: "/academic-core/programme-versions",label:["versionCode","versionName"] },
    courseId:               { endpoint: "/academic-core/courses",          label: ["courseCode","courseName"] },
    courseOfferingId:       { endpoint: "/academic-core/course-offerings", label: ["offeringCode","sectionName"] },
    studentRegistrationId:  { endpoint: "/academic-core/registrations",    label: ["registrationNumber","registrationStatus"] }
};

const ENUMS = {
    registrationStatus: ["DRAFT","SUBMITTED","PENDING_APPROVAL","APPROVED","REGISTERED","LOCKED","REJECTED","CANCELLED"],
    academicEligibilityStatus: ["PENDING","ELIGIBLE","NOT_ELIGIBLE","CLEARED"],
    financeEligibilityStatus: ["PENDING","ELIGIBLE","NOT_ELIGIBLE","CLEARED"],
    documentEligibilityStatus: ["PENDING","ELIGIBLE","NOT_ELIGIBLE","CLEARED"],
    registrationType: ["NORMAL","REPEAT","RETAKE","CARRY_OVER","SPECIAL"],
    prerequisiteStatus: ["PENDING","MET","NOT_MET","WAIVED"],
    eligibilityStatus: ["PENDING","ELIGIBLE","NOT_ELIGIBLE","WAIVED"],
    approvalStatus: ["PENDING","APPROVED","REJECTED"],
    requestType: ["ADD","DROP"],
    requestStatus: ["PENDING","APPROVED","REJECTED","CANCELLED"]
};

const REQUIRED = {
    registrations: ["studentId","academicYearId","semesterId","programmeId","registrationNumber"],
    courses: ["studentRegistrationId","studentId","courseId","courseOfferingId"],
    approvals: ["studentRegistrationId","approvalLevel","approvalRole","approvalStatus"],
    adddrop: ["studentRegistrationId","studentId","courseId","courseOfferingId","requestType"]
};

const CACHE = Object.create(null);

function rows(value) {
    value = value && value.data !== undefined ? value.data : value;
    if (Array.isArray(value)) return value;
    for (const key of ["items","rows","records","results","data"]) {
        if (value && Array.isArray(value[key])) return value[key];
    }
    return [];
}

function esc(value) {
    return String(value == null ? "" : value).replace(/[&<>"']/g, function (c) {
        return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c];
    });
}

function label(value) {
    return String(value || "")
        .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
        .replace(/_/g, " ")
        .replace(/\b\w/g, function (c) { return c.toUpperCase(); });
}

function display(item, config) {
    if (!item) return "";
    const values = [];
    for (const key of config.label) {
        if (item[key] !== undefined && item[key] !== null && String(item[key]).trim()) {
            values.push(String(item[key]).trim());
        }
    }
    return values.join(" - ") || String(item.id || "");
}

async function relationData(config) {
    if (!CACHE[config.endpoint]) {
        CACHE[config.endpoint] = rows(await API.request(config.endpoint));
    }
    return CACHE[config.endpoint];
}

async function makeField(field, current) {
    const wrap = document.createElement("label");
    wrap.className = "idmc-reg-field";

    const title = document.createElement("span");
    title.textContent = label(field) + ((REQUIRED[active.key] || []).includes(field) ? " *" : "");
    wrap.appendChild(title);

    let input;

    if (RELATIONSHIPS[field]) {
        input = document.createElement("select");
        input.innerHTML = '<option value="">Select ' + esc(label(field)) + '</option>';

        try {
            const options = await relationData(RELATIONSHIPS[field]);
            for (const item of options) {
                const option = document.createElement("option");
                option.value = item.id || item.uuid || "";
                option.textContent = display(item, RELATIONSHIPS[field]);
                input.appendChild(option);
            }
        } catch (error) {
            input.innerHTML = '<option value="">Dependency unavailable</option>';
            input.title = error.message || "Unable to load dependency";
        }
    } else if (ENUMS[field]) {
        input = document.createElement("select");
        input.innerHTML = '<option value="">Select ' + esc(label(field)) + '</option>';
        for (const value of ENUMS[field]) {
            const option = document.createElement("option");
            option.value = value;
            option.textContent = value.replace(/_/g, " ");
            input.appendChild(option);
        }
    } else if (/^(isCore|isElective)$/.test(field)) {
        input = document.createElement("select");
        input.innerHTML = '<option value="">Select</option><option value="true">Yes</option><option value="false">No</option>';
    } else if (/credits|attemptNumber|approvalLevel/i.test(field)) {
        input = document.createElement("input");
        input.type = "number";
        input.step = "any";
        input.min = "0";
    } else if (/notes|comments|reason/i.test(field)) {
        input = document.createElement("textarea");
        input.rows = 3;
    } else {
        input = document.createElement("input");
        input.type = "text";
    }

    input.name = field;
    if ((REQUIRED[active.key] || []).includes(field)) input.required = true;

    if (current !== undefined && current !== null) {
        input.value = String(current);
    }

    wrap.appendChild(input);
    return wrap;
}

function serialize(form) {
    const result = {};
    for (const element of form.elements) {
        if (!element.name) continue;
        let value = element.value;
        if (value === "") continue;

        if (element.type === "number") value = Number(value);
        if (value === "true") value = true;
        if (value === "false") value = false;

        result[element.name] = value;
    }
    return result;
}

function getId(record) {
    return record && (record.id || record.uuid);
}

let active = RESOURCES[0];
let records = [];
let editing = null;

function build() {
    const oldDeep = document.querySelector(".idmc-deep-shell");
    if (oldDeep) oldDeep.remove();

    const legacyGrid = document.querySelector(".idmc-module-grid");
    if (legacyGrid) legacyGrid.hidden = true;

    const shell = document.createElement("section");
    shell.className = "idmc-reg-workspace";
    shell.innerHTML =
        '<div class="idmc-reg-head">' +
          '<div><h2>Live Registration Workspace</h2><p data-status>Ready</p></div>' +
          '<button type="button" data-refresh>Refresh</button>' +
        '</div>' +
        '<div class="idmc-reg-tabs" data-tabs></div>' +
        '<div class="idmc-reg-toolbar">' +
          '<input type="search" data-search placeholder="Search current records">' +
          '<button type="button" data-create>+ Create</button>' +
        '</div>' +
        '<div class="idmc-reg-table" data-table></div>' +
        '<dialog class="idmc-reg-dialog" data-dialog>' +
          '<form data-form>' +
            '<h3 data-form-title>Registration Record</h3>' +
            '<div class="idmc-reg-fields" data-fields></div>' +
            '<div class="idmc-reg-actions">' +
              '<button type="button" data-cancel>Cancel</button>' +
              '<button type="submit" class="idmc-primary">Save</button>' +
            '</div>' +
          '</form>' +
        '</dialog>';

    const main = document.querySelector("main") || document.body;
    const nav = main.querySelector("[data-idmc-module-nav-shell]");
    if (nav) main.insertBefore(shell, nav);
    else main.appendChild(shell);

    const tabs = shell.querySelector("[data-tabs]");
    const table = shell.querySelector("[data-table]");
    const status = shell.querySelector("[data-status]");
    const search = shell.querySelector("[data-search]");
    const dialog = shell.querySelector("[data-dialog]");
    const form = shell.querySelector("[data-form]");
    const fields = shell.querySelector("[data-fields]");
    const formTitle = shell.querySelector("[data-form-title]");

    function stat(text, state) {
        status.textContent = text;
        status.dataset.state = state || "";
    }

    function render() {
        const q = search.value.trim().toLowerCase();
        const shown = records.filter(function (record) {
            return !q || JSON.stringify(record).toLowerCase().indexOf(q) >= 0;
        });

        if (!shown.length) {
            table.innerHTML = '<div class="idmc-reg-empty">No records found for ' + esc(active.title) + '.</div>';
            return;
        }

        const keys = Array.from(new Set(shown.flatMap(function (x) { return Object.keys(x); }))).slice(0, 9);

        table.innerHTML =
            '<table><thead><tr>' +
            keys.map(function (k) { return '<th>' + esc(label(k)) + '</th>'; }).join("") +
            '<th>Actions</th></tr></thead><tbody>' +
            shown.map(function (record, index) {
                return '<tr>' +
                    keys.map(function (k) { return '<td>' + esc(record[k]) + '</td>'; }).join("") +
                    '<td>' +
                      '<button type="button" data-edit="' + index + '">Edit</button> ' +
                      '<button type="button" data-delete="' + index + '">Delete</button>' +
                    '</td></tr>';
            }).join("") +
            '</tbody></table>';

        table.querySelectorAll("[data-edit]").forEach(function (button) {
            button.onclick = function () { openForm(shown[Number(button.dataset.edit)]); };
        });

        table.querySelectorAll("[data-delete]").forEach(function (button) {
            button.onclick = async function () {
                const record = shown[Number(button.dataset.delete)];
                const id = getId(record);
                if (!id) return;

                if (!window.confirm("Delete this " + active.title + " record?")) return;

                stat("Deleting...");
                try {
                    await API.request(active.endpoint + "/" + encodeURIComponent(id), { method: "DELETE" });
                    await load();
                    stat("Deleted successfully.", "ok");
                } catch (error) {
                    stat(error.message || "Delete failed.", "error");
                }
            };
        });
    }

    async function load() {
        stat("Loading " + active.title + "...");
        try {
            records = rows(await API.request(active.endpoint));
            render();
            stat(records.length + " record(s) loaded.", "ok");
        } catch (error) {
            records = [];
            render();
            stat(error.message || "Load failed.", "error");
        }
    }

    async function openForm(row) {
        editing = row || null;
        form.reset();
        fields.innerHTML = "";
        formTitle.textContent = (editing ? "Edit " : "Create ") + active.title;

        stat("Loading form dependencies...");

        for (const field of active.fields) {
            const control = await makeField(field, editing ? editing[field] : null);
            fields.appendChild(control);
        }

        stat("Form ready.", "ok");
        dialog.showModal();
    }

    form.onsubmit = async function (event) {
        event.preventDefault();

        if (!form.reportValidity()) return;

        const body = serialize(form);
        const id = getId(editing);
        const method = editing ? "PATCH" : "POST";
        const path = editing ? active.endpoint + "/" + encodeURIComponent(id) : active.endpoint;

        stat((editing ? "Updating" : "Creating") + " record...");

        try {
            await API.request(path, { method: method, body: body });
            dialog.close();
            CACHE["/academic-core/registrations"] = null;
            await load();
            stat(editing ? "Record updated successfully." : "Record created successfully.", "ok");
        } catch (error) {
            stat(error.message || "Save failed.", "error");
        }
    };

    shell.querySelector("[data-cancel]").onclick = function () { dialog.close(); };
    shell.querySelector("[data-refresh]").onclick = load;
    shell.querySelector("[data-create]").onclick = function () { openForm(null); };
    search.oninput = render;

    RESOURCES.forEach(function (resource, index) {
        const button = document.createElement("button");
        button.type = "button";
        button.textContent = resource.title;
        button.setAttribute("aria-selected", index === 0 ? "true" : "false");
        button.onclick = function () {
            active = resource;
            editing = null;
            tabs.querySelectorAll("button").forEach(function (x) {
                x.setAttribute("aria-selected", "false");
            });
            button.setAttribute("aria-selected", "true");
            load();
        };
        tabs.appendChild(button);
    });

    load();
}

if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", build, { once: true });
} else {
    build();
}
})();