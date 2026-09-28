(function () {
  "use strict";

  if (document.body.dataset.workspace !== "academics") return;

  var api = window.IDMCAPI;
  var auth = window.IDMCAuth;
  var state = { lookups: {}, active: "versions", ready: false, importRows: [], importValid: false };

  function esc(value) {
    return String(value == null || value === "" ? "—" : value).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function unwrap(response) {
    var payload = response && Object.prototype.hasOwnProperty.call(response, "data") ? response.data : response;
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.items)) return payload.items;
    return payload || {};
  }
  function human(value) {
    return String(value || "").replace(/_/g, " ").replace(/\b\w/g, function (x) { return x.toUpperCase(); });
  }
  function byId(key, id) {
    return (state.lookups[key] || []).find(function (row) { return row.id === id; }) || {};
  }
  function courseLabel(row) { return [row.course_code, row.course_name].filter(Boolean).join(" - ") || row.id; }
  function programmeLabel(row) { return [row.programme_code, row.programme_name].filter(Boolean).join(" - ") || row.id; }
  function versionLabel(row) {
    var programme = byId("programmes", row.programme_id);
    return [programme.programme_code, row.version_code, row.version_name].filter(Boolean).join(" · ") || row.id;
  }
  function curriculumLabel(row) { return [row.curriculum_code, row.curriculum_name].filter(Boolean).join(" - ") || row.id; }
  function yearLabel(row) { return row.year_name || row.year_code || row.id; }
  function semesterLabel(row) { return row.semester_name || row.semester_code || row.id; }
  function labelFor(key, row) {
    var labels = { years: yearLabel, semesters: semesterLabel, programmes: programmeLabel, versions: versionLabel, courses: courseLabel, curricula: curriculumLabel };
    return labels[key] ? labels[key](row) : (row.name || row.id);
  }

  var forms = {
    year: { title: "Add Academic Year", endpoint: "/academic-core/years", fields: [
      ["yearCode", "Year Code", "text", null, true, "Example: 2027/2028"],
      ["yearName", "Year Name", "text", null, true, "Example: Academic Year 2027/2028"],
      ["startDate", "Start Date", "date", null, true], ["endDate", "End Date", "date", null, true],
      ["status", "Status", "choices", ["PLANNED", "ACTIVE", "CLOSED", "ARCHIVED"], true]
    ]},
    semester: { title: "Add Semester", endpoint: "/academic-core/semesters", fields: [
      ["academicYearId", "Academic Year", "select", "years", true], ["semesterNumber", "Semester Number", "number", null, true],
      ["semesterCode", "Semester Code", "text", null, true, "Example: SEM1"], ["semesterName", "Semester Name", "text", null, true],
      ["startDate", "Start Date", "date", null, true], ["endDate", "End Date", "date", null, true],
      ["status", "Status", "choices", ["PLANNED", "ACTIVE", "CLOSED", "ARCHIVED"], true]
    ]},
    programme: { title: "Add Programme", endpoint: "/academic-core/programmes", fields: [
      ["institutionId", "Institution", "institution", null, true], ["schoolId", "School", "selectOptional", "schools", false],
      ["departmentId", "Department", "selectOptional", "departments", false], ["programmeCode", "Programme Code", "text", null, true],
      ["programmeName", "Programme Name", "text", null, true], ["programmeType", "Programme Type", "choices", ["ACADEMIC", "PROFESSIONAL", "SHORT_COURSE", "CERTIFICATE", "OTHER"], true],
      ["awardLevel", "Award Level", "text", null, true], ["durationYears", "Duration (years)", "number", null, true],
      ["modeOfStudy", "Mode of Study", "choices", ["FULL_TIME", "PART_TIME", "EVENING", "WEEKEND", "DISTANCE", "ONLINE", "BLENDED"], true],
      ["status", "Status", "choices", ["ACTIVE", "INACTIVE", "SUSPENDED", "ARCHIVED"], true], ["description", "Description", "textarea", null, false]
    ]},
    version: { title: "Add Programme Version", endpoint: "/academic-core/programme-versions", fields: [
      ["programmeId", "Programme", "select", "programmes", true], ["versionCode", "Version Code", "text", null, true, "Example: 2026"],
      ["versionName", "Version Name", "text", null, false], ["effectiveFrom", "Effective From", "date", null, true],
      ["effectiveTo", "Effective To", "date", null, false], ["totalCredits", "Total Credits", "number", null, false],
      ["status", "Status", "choices", ["DRAFT", "ACTIVE", "RETIRED", "ARCHIVED"], true]
    ]},
    course: { title: "Add Course", endpoint: "/academic-core/courses", fields: [
      ["institutionId", "Institution", "institution", null, true], ["departmentId", "Department", "selectOptional", "departments", false],
      ["courseCode", "Course Code", "text", null, true], ["courseName", "Course Name", "text", null, true],
      ["courseShortName", "Short Name", "text", null, false], ["creditUnits", "Credit Units", "number", null, true],
      ["contactHours", "Contact Hours", "number", null, false], ["courseType", "Course Type", "choices", ["CORE", "ELECTIVE", "OPTIONAL", "GENERAL", "PRACTICAL", "FIELD", "CLINICAL", "PROJECT", "OTHER"], true],
      ["level", "Level", "text", null, false], ["status", "Status", "choices", ["ACTIVE", "INACTIVE", "RETIRED", "ARCHIVED"], true],
      ["description", "Description", "textarea", null, false]
    ]},
    curriculum: { title: "Add Curriculum", endpoint: "/academic-core/curricula", fields: [
      ["programmeVersionId", "Programme Version", "select", "versions", true], ["curriculumCode", "Curriculum Code", "text", null, true],
      ["curriculumName", "Curriculum Name", "text", null, true], ["effectiveFrom", "Effective From", "date", null, true],
      ["effectiveTo", "Effective To", "date", null, false], ["totalCredits", "Total Credits", "number", null, false],
      ["status", "Status", "choices", ["DRAFT", "ACTIVE", "RETIRED", "ARCHIVED"], true]
    ]},
    curriculumCourse: { title: "Add Course to Curriculum", endpoint: "/academic-core/curriculum-courses", fields: [
      ["curriculumId", "Curriculum", "select", "curricula", true], ["courseId", "Course", "select", "courses", true],
      ["yearNumber", "Year of Study", "number", null, true], ["semesterNumber", "Semester Number", "number", null, true],
      ["courseCategory", "Course Category", "choices", ["CORE", "ELECTIVE", "OPTIONAL", "GENERAL", "PRACTICAL", "FIELD", "CLINICAL", "PROJECT", "OTHER"], true],
      ["isCompulsory", "Compulsory", "choices", ["true", "false"], true], ["creditUnits", "Curriculum Credits", "number", null, false]
    ]},
    prerequisite: { title: "Add Course Prerequisite", endpoint: "/academic-core/course-prerequisites", fields: [
      ["courseId", "Course", "select", "courses", true], ["prerequisiteCourseId", "Required Previous Course", "select", "courses", true],
      ["minimumGrade", "Minimum Grade", "text", null, false, "Example: C"]
    ]},
    offering: { title: "Add Course Offering", endpoint: "/academic-core/course-offerings", fields: [
      ["academicYearId", "Academic Year", "select", "years", true], ["semesterId", "Semester", "select", "semesters", true],
      ["programmeId", "Programme", "select", "programmes", true], ["programmeVersionId", "Programme Version", "selectOptional", "versions", false],
      ["courseId", "Course", "select", "courses", true], ["offeringCode", "Offering Code", "text", null, true],
      ["sectionName", "Section / Stream", "text", null, false], ["capacity", "Capacity", "number", null, true],
      ["minimumStudents", "Minimum Students", "number", null, true], ["deliveryMode", "Delivery Mode", "choices", ["ON_CAMPUS", "ONLINE", "HYBRID", "DISTANCE", "FIELD", "CLINICAL"], true],
      ["registrationOpenAt", "Registration Opens", "datetime-local", null, false], ["registrationCloseAt", "Registration Closes", "datetime-local", null, false],
      ["status", "Status", "choices", ["DRAFT", "OPEN", "CLOSED", "SUSPENDED", "COMPLETED", "CANCELLED"], true]
    ]}
  };

  var registry = {
    years: { label: "Academic Years", endpoint: "/academic-core/years", form: "year", columns: [["Year", "year_name"], ["Code", "year_code"], ["Start", "start_date"], ["End", "end_date"], ["Status", "status", "badge"]] },
    semesters: { label: "Semesters", endpoint: "/academic-core/semesters", form: "semester", columns: [["Semester", "semester_name"], ["Code", "semester_code"], ["Number", "semester_number"], ["Start", "start_date"], ["End", "end_date"], ["Status", "status", "badge"]] },
    programmes: { label: "Programmes", endpoint: "/academic-core/programmes", form: "programme", columns: [["Code", "programme_code"], ["Programme", "programme_name"], ["Award", "award_level"], ["Duration", "duration_years"], ["Status", "status", "badge"]] },
    versions: { label: "Programme Versions", endpoint: "/academic-core/programme-versions", form: "version", columns: [["Programme", "programme_id", "programme"], ["Version", "version_code"], ["Name", "version_name"], ["Effective", "effective_from"], ["Credits", "total_credits"], ["Status", "status", "badge"]] },
    courses: { label: "Courses", endpoint: "/academic-core/courses", form: "course", columns: [["Code", "course_code"], ["Course", "course_name"], ["Credits", "credit_units"], ["Level", "level"], ["Type", "course_type"], ["Status", "status", "badge"]] },
    curricula: { label: "Curricula", endpoint: "/academic-core/curricula", form: "curriculum", columns: [["Programme Version", "programme_version_id", "version"], ["Code", "curriculum_code"], ["Curriculum", "curriculum_name"], ["Effective", "effective_from"], ["Credits", "total_credits"], ["Status", "status", "badge"]] },
    curriculumCourses: { label: "Curriculum Courses", endpoint: "/academic-core/curriculum-courses", form: "curriculumCourse", columns: [["Curriculum", "curriculum_id", "curriculum"], ["Course", "course_id", "course"], ["Year", "year_number"], ["Semester", "semester_number"], ["Category", "course_category"], ["Compulsory", "is_compulsory", "yesno"], ["Credits", "credit_units"]] },
    prerequisites: { label: "Prerequisites", endpoint: "/academic-core/course-prerequisites", form: "prerequisite", columns: [["Course", "course_id", "course"], ["Required Previous Course", "prerequisite_course_id", "course"], ["Minimum Grade", "minimum_grade"]] },
    offerings: { label: "Course Offerings", endpoint: "/academic-core/course-offerings", form: "offering", columns: [["Offering", "offering_code"], ["Course", "course_id", "course"], ["Programme", "programme_id", "programme"], ["Section", "section_name"], ["Capacity", "capacity"], ["Status", "status", "badge"]] }
  };

  function installUi() {
    var guidance = document.querySelector(".iw-guidance");
    if (!guidance || document.getElementById("amxPanel")) return;
    var panel = document.createElement("section");
    panel.id = "amxPanel";
    panel.className = "amx-panel";
    panel.innerHTML = '<header class="amx-head"><div><h3>Academic Structure Setup</h3><p>Create and connect the academic structure without entering database IDs.</p></div><button class="amx-btn primary" id="amxReload" type="button">Refresh setup</button></header>' +
      '<div class="amx-workflow"><strong>Recommended order: Year & Semester → Programme → Version → Courses → Curriculum → Curriculum Courses → Prerequisites → Course Offering</strong><div class="amx-buttons" id="amxButtons"></div></div>' +
      '<div class="amx-import"><label><span>Import Section</span><select id="amxImportType"></select></label><label><span>Excel-compatible CSV file</span><input id="amxImportFile" type="file" accept=".csv,text/csv"></label><button class="amx-btn" id="amxTemplate" type="button">Download Template</button><button class="amx-btn" id="amxValidate" type="button">Validate & Preview</button><button class="amx-btn primary" id="amxConfirmImport" type="button" disabled>Confirm Import</button><p class="amx-import-status" id="amxImportStatus">Complete the template in Excel and save it as CSV UTF-8 before upload.</p><div class="amx-preview" id="amxPreview" hidden></div></div>' +
      '<nav class="amx-tabs" id="amxTabs"></nav><p class="amx-note" id="amxNote">Loading academic structure…</p><div class="amx-table-wrap"><table class="amx-table" id="amxTable"></table></div>';
    guidance.parentNode.insertBefore(panel, guidance);
    document.body.insertAdjacentHTML("beforeend", '<div class="amx-modal" id="amxModal" role="dialog" aria-modal="true"><section class="amx-dialog"><header class="amx-dialog-head"><h3 id="amxTitle">New Academic Record</h3><button class="amx-btn" id="amxClose" type="button">Close</button></header><form class="amx-form" id="amxForm"><div class="amx-form-message wide" id="amxFormMessage" role="alert"></div></form></section></div>');
    var buttonOrder = [["year", "Add Academic Year"], ["semester", "Add Semester"], ["programme", "Add Programme"], ["version", "Add Programme Version"], ["course", "Add Course"], ["curriculum", "Add Curriculum"], ["curriculumCourse", "Add Curriculum Course"], ["prerequisite", "Add Prerequisite"], ["offering", "Add Course Offering"]];
    document.getElementById("amxButtons").innerHTML = buttonOrder.map(function (item) { return '<button class="amx-btn" type="button" data-amx-form="' + item[0] + '">' + item[1] + '</button>'; }).join("");
    document.querySelectorAll("[data-amx-form]").forEach(function (button) { button.onclick = function () { openForm(button.dataset.amxForm); }; });
    document.getElementById("amxReload").onclick = load;
    document.getElementById("amxImportType").innerHTML = Object.keys(registry).map(function (key) { return '<option value="' + key + '">' + registry[key].label + '</option>'; }).join("");
    document.getElementById("amxTemplate").onclick = downloadTemplate;
    document.getElementById("amxValidate").onclick = validateImport;
    document.getElementById("amxConfirmImport").onclick = confirmImport;
    document.getElementById("amxClose").onclick = closeForm;
    document.getElementById("amxModal").onclick = function (event) { if (event.target === this) closeForm(); };
    document.getElementById("amxForm").onsubmit = submitForm;
  }

  async function load() {
    var note = document.getElementById("amxNote");
    if (note) note.textContent = "Loading authoritative academic structure…";
    try {
      var responses = await Promise.all([
        api.get("/academic-core/reference-data?resource=years", { cache: "no-store" }),
        api.get("/academic-core/reference-data?resource=semesters", { cache: "no-store" }),
        api.get("/academic-core/programmes?limit=100", { cache: "no-store" }),
        api.get("/academic-core/programme-versions?limit=100", { cache: "no-store" }),
        api.get("/academic-core/courses?limit=100", { cache: "no-store" }),
        api.get("/academic-core/curricula?limit=100", { cache: "no-store" }),
        api.get("/academic-core/curriculum-courses?limit=100", { cache: "no-store" }),
        api.get("/academic-core/course-prerequisites?limit=100", { cache: "no-store" }),
        api.get("/academic-core/course-offerings?limit=100", { cache: "no-store" }),
        api.get("/institutions/primary/structure", { cache: "no-store" })
      ]);
      ["years", "semesters", "programmes", "versions", "courses", "curricula", "curriculumCourses", "prerequisites", "offerings"].forEach(function (key, index) { state.lookups[key] = unwrap(responses[index]); });
      var structure = unwrap(responses[9]);
      state.lookups.institution = structure.institution || null;
      state.lookups.schools = structure.schools || [];
      state.lookups.departments = structure.departments || [];
      state.ready = true;
      renderRegistry();
      if (note) note.textContent = "These records are stored in the authoritative database and reused by registration, timetable, attendance, examinations and results.";
    } catch (error) {
      if (note) note.textContent = error.message || "Unable to load academic setup data.";
    }
  }

  function renderRegistry() {
    var tabs = document.getElementById("amxTabs");
    var table = document.getElementById("amxTable");
    if (!tabs || !table) return;
    tabs.innerHTML = Object.keys(registry).map(function (key) { return '<button class="amx-tab ' + (key === state.active ? "active" : "") + '" type="button" data-amx-tab="' + key + '">' + registry[key].label + ' (' + (state.lookups[key] || []).length + ')</button>'; }).join("");
    document.querySelectorAll("[data-amx-tab]").forEach(function (button) { button.onclick = function () { state.active = button.dataset.amxTab; renderRegistry(); }; });
    var def = registry[state.active];
    var rows = state.lookups[state.active] || [];
    var head = def.columns.map(function (col) { return "<th>" + esc(col[0]) + "</th>"; }).join("") + "<th>Action</th>";
    var body = rows.length ? rows.map(function (row) { return "<tr>" + def.columns.map(function (col) { return "<td>" + display(row[col[1]], col[2]) + "</td>"; }).join("") + '<td><button class="amx-btn amx-danger" type="button" data-amx-delete="' + esc(row.id) + '">Delete</button></td></tr>'; }).join("") : '<tr><td class="amx-empty" colspan="' + (def.columns.length + 1) + '">No records yet. Use the relevant Add button above.</td></tr>';
    table.innerHTML = "<thead><tr>" + head + "</tr></thead><tbody>" + body + "</tbody>";
    table.querySelectorAll("[data-amx-delete]").forEach(function (button) { button.onclick = function () { deleteRecord(state.active, button.dataset.amxDelete); }; });
  }

  async function deleteRecord(key, id) {
    var def = registry[key], row = byId(key, id), label = labelFor(key, row), note = document.getElementById("amxNote");
    if (!window.confirm('Delete test record "' + label + '"? Linked official records are protected by database constraints.')) return;
    if (!window.confirm("Final confirmation: permanently delete this test record?")) return;
    try { await api.delete(def.endpoint + "/" + encodeURIComponent(id)); api.clearCache(); if (note) note.textContent = "Test record deleted; the action was audit logged."; await load(); }
    catch (error) { if (note) note.textContent = error.message || "Delete failed because this record is already in use."; }
  }

  function display(value, mode) {
    if (mode === "badge") return '<span class="amx-badge">' + esc(human(value)) + "</span>";
    if (mode === "yesno") return value ? "Yes" : "No";
    if (mode === "course") return esc(courseLabel(byId("courses", value)) || value);
    if (mode === "programme") return esc(programmeLabel(byId("programmes", value)) || value);
    if (mode === "version") return esc(versionLabel(byId("versions", value)) || value);
    if (mode === "curriculum") return esc(curriculumLabel(byId("curricula", value)) || value);
    return esc(value);
  }

  function importFields(key) { return forms[registry[key].form].fields.filter(function (field) { return field[2] !== "institution"; }); }
  function csvEscape(value) { var text=String(value==null?"":value); return /[",\n]/.test(text)?'"'+text.replace(/"/g,'""')+'"':text; }
  function downloadTemplate() {
    var key=document.getElementById("amxImportType").value, fields=importFields(key);
    var csv=fields.map(function(f){return csvEscape(f[0]);}).join(",")+"\r\n";
    var blob=new Blob(["\ufeff"+csv],{type:"text/csv;charset=utf-8"}), link=document.createElement("a"); link.href=URL.createObjectURL(blob); link.download="IDMC-"+key+"-template.csv"; link.click(); URL.revokeObjectURL(link.href);
  }
  function parseCsv(text) {
    var rows=[],row=[],cell="",quoted=false;
    for(var i=0;i<text.length;i+=1){var ch=text[i],next=text[i+1];if(quoted&&ch==='"'&&next==='"'){cell+='"';i+=1;}else if(ch==='"')quoted=!quoted;else if(ch===","&&!quoted){row.push(cell.trim());cell="";}else if((ch==="\n"||ch==="\r")&&!quoted){if(ch==="\r"&&next==="\n")i+=1;row.push(cell.trim());if(row.some(Boolean))rows.push(row);row=[];cell="";}else cell+=ch;}row.push(cell.trim());if(row.some(Boolean))rows.push(row);return rows;
  }
  function referenceId(source,value,payload) {
    if(!value)return "";var normalized=String(value).trim().toLowerCase(),fields={years:["id","year_code","year_name"],semesters:["id","semester_code","semester_name"],programmes:["id","programme_code","programme_name"],versions:["id","version_code","version_name"],courses:["id","course_code","course_name"],curricula:["id","curriculum_code","curriculum_name"],schools:["id","school_code","school_name"],departments:["id","department_code","department_name"]}[source]||["id"];
    var matches=(state.lookups[source]||[]).filter(function(item){return fields.some(function(field){return String(item[field]||"").trim().toLowerCase()===normalized;});});
    if(source==="semesters"&&payload.academicYearId)matches=matches.filter(function(item){return item.academic_year_id===payload.academicYearId;});
    if(source==="versions"&&payload.programmeId)matches=matches.filter(function(item){return item.programme_id===payload.programmeId;});
    return matches.length===1?matches[0].id:null;
  }
  async function validateImport() {
    var key=document.getElementById("amxImportType").value,file=document.getElementById("amxImportFile").files[0],status=document.getElementById("amxImportStatus"),preview=document.getElementById("amxPreview"),confirmButton=document.getElementById("amxConfirmImport");state.importRows=[];state.importValid=false;confirmButton.disabled=true;
    if(!file){status.textContent="Select a CSV file first.";return;}if(!/\.csv$/i.test(file.name)){status.textContent="Open the Excel file and Save As CSV UTF-8, then upload it.";return;}
    var matrix=parseCsv((await file.text()).replace(/^\ufeff/,"")),fields=importFields(key);if(matrix.length<2){status.textContent="The file has no data rows.";return;}var headers=matrix[0],allowed=fields.map(function(f){return f[0];}),unknown=headers.filter(function(h){return !allowed.includes(h);});if(unknown.length){status.textContent="Unknown columns: "+unknown.join(", ");return;}
    state.importRows=matrix.slice(1).map(function(cells,index){var raw={},payload={},errors=[];headers.forEach(function(h,i){raw[h]=cells[i]||"";});fields.forEach(function(field){var name=field[0],type=field[2],source=field[3],required=field[4],value=raw[name];if(!value&&required)errors.push(name+" is required");if(!value)return;if(type==="select"||type==="selectOptional"){var id=referenceId(source,value,payload);if(!id)errors.push(name+" reference not found or ambiguous");else payload[name]=id;}else if(type==="number"){var number=Number(value);if(!Number.isFinite(number))errors.push(name+" must be numeric");else payload[name]=number;}else if(name==="isCompulsory")payload[name]=String(value).toLowerCase()==="true";else payload[name]=value;});if(["programme","course"].includes(registry[key].form))payload.institutionId=(state.lookups.institution||{}).id;return{line:index+2,payload:payload,errors:errors};});
    var invalid=state.importRows.filter(function(row){return row.errors.length;});state.importValid=invalid.length===0&&state.importRows.length>0;confirmButton.disabled=!state.importValid;status.textContent=state.importRows.length+" row(s): "+(state.importRows.length-invalid.length)+" valid, "+invalid.length+" invalid.";preview.hidden=false;preview.innerHTML='<table><thead><tr><th>Row</th><th>Status</th><th>Details</th></tr></thead><tbody>'+state.importRows.slice(0,100).map(function(row){return'<tr><td>'+row.line+'</td><td class="'+(row.errors.length?'amx-invalid':'')+'">'+(row.errors.length?'INVALID':'VALID')+'</td><td>'+esc(row.errors.join("; ")||JSON.stringify(row.payload))+'</td></tr>';}).join("")+'</tbody></table>';
  }
  async function confirmImport() {
    if(!state.importValid||!state.importRows.length)return;var key=document.getElementById("amxImportType").value,status=document.getElementById("amxImportStatus"),button=document.getElementById("amxConfirmImport");if(!window.confirm("Import "+state.importRows.length+" validated "+registry[key].label+" record(s)?"))return;button.disabled=true;var completed=0,failures=[];
    for(var i=0;i<state.importRows.length;i+=1){try{await api.post(registry[key].endpoint,state.importRows[i].payload);completed+=1;}catch(error){failures.push("Row "+state.importRows[i].line+": "+(error.message||"failed"));}status.textContent="Importing "+(i+1)+"/"+state.importRows.length+"…";}api.clearCache();await load();state.importValid=false;state.importRows=[];status.textContent=completed+" imported; "+failures.length+" failed."+(failures.length?" "+failures.slice(0,3).join(" | "):"");
  }

  function fieldHtml(field) {
    var name = field[0], label = field[1], type = field[2], source = field[3], required = field[4], placeholder = field[5] || "";
    var requiredText = required ? " required" : "";
    var labelClass = required ? "amx-required" : "";
    var control;
    if (type === "institution") {
      var institution = state.lookups.institution || {};
      control = '<input class="amx-locked" name="' + name + '" type="hidden" value="' + esc(institution.id || "") + '"><input class="amx-locked" value="' + esc(institution.institution_name || "Institute of Development and Medical Sciences") + '" readonly>';
    } else if (type === "select" || type === "selectOptional") {
      var options = (state.lookups[source] || []).map(function (row) { return '<option value="' + esc(row.id) + '">' + esc(labelFor(source, row)) + "</option>"; }).join("");
      control = '<select name="' + name + '"' + (type === "select" ? requiredText : "") + '><option value="">' + (type === "select" ? "Select " : "Optional: ") + esc(label) + "</option>" + options + "</select>";
    } else if (type === "choices") {
      control = '<select name="' + name + '"' + requiredText + '><option value="">Select ' + esc(label) + "</option>" + source.map(function (value) { return '<option value="' + esc(value) + '">' + esc(human(value)) + "</option>"; }).join("") + "</select>";
    } else if (type === "textarea") {
      control = '<textarea name="' + name + '" placeholder="' + esc(placeholder) + '"' + requiredText + "></textarea>";
    } else {
      var step = type === "number" ? ' step="any" min="0"' : "";
      control = '<input name="' + name + '" type="' + type + '" placeholder="' + esc(placeholder) + '"' + step + requiredText + ">";
    }
    return '<label class="' + labelClass + (type === "textarea" ? " wide" : "") + '"><span>' + esc(label) + "</span>" + control + "</label>";
  }

  function openForm(code) {
    var def = forms[code];
    if (!def) return;
    if (!state.ready) { window.alert("Academic reference data is still loading. Try again in a moment."); return; }
    var form = document.getElementById("amxForm");
    form.dataset.code = code;
    form.dataset.endpoint = def.endpoint;
    document.getElementById("amxTitle").textContent = def.title;
    form.innerHTML = '<div class="amx-form-message wide" id="amxFormMessage" role="alert"></div>' + def.fields.map(fieldHtml).join("") + '<div class="amx-form-actions"><button class="amx-btn" type="button" id="amxCancel">Cancel</button><button class="amx-btn primary" type="submit">Save Record</button></div>';
    document.getElementById("amxCancel").onclick = closeForm;
    bindDependencies(code, form);
    document.getElementById("amxModal").classList.add("open");
  }

  function bindDependencies(code, form) {
    function filterSelect(name, rows, labelKey) {
      var select = form.elements[name];
      if (!select) return;
      var current = select.value;
      select.innerHTML = '<option value="">Select ' + esc(select.closest("label").querySelector("span").textContent.replace(" *", "")) + "</option>" + rows.map(function (row) { return '<option value="' + esc(row.id) + '">' + esc(labelFor(labelKey, row)) + "</option>"; }).join("");
      if (rows.some(function (row) { return row.id === current; })) select.value = current;
    }
    if (code === "offering") {
      form.elements.academicYearId.onchange = function () { filterSelect("semesterId", (state.lookups.semesters || []).filter(function (row) { return row.academic_year_id === form.elements.academicYearId.value; }), "semesters"); };
      form.elements.programmeId.onchange = function () { filterSelect("programmeVersionId", (state.lookups.versions || []).filter(function (row) { return row.programme_id === form.elements.programmeId.value; }), "versions"); };
    }
  }

  function closeForm() { document.getElementById("amxModal").classList.remove("open"); }
  function formMessage(text, type) {
    var box = document.getElementById("amxFormMessage");
    if (!box) return;
    box.className = "amx-form-message wide show " + (type || "error");
    box.textContent = text;
  }

  async function submitForm(event) {
    event.preventDefault();
    var form = event.currentTarget;
    var code = form.dataset.code;
    var payload = {};
    new FormData(form).forEach(function (value, key) { if (String(value).trim() !== "") payload[key] = value; });
    ["semesterNumber", "durationYears", "creditUnits", "contactHours", "totalCredits", "yearNumber", "capacity", "minimumStudents"].forEach(function (key) { if (Object.prototype.hasOwnProperty.call(payload, key)) payload[key] = Number(payload[key]); });
    if (Object.prototype.hasOwnProperty.call(payload, "isCompulsory")) payload.isCompulsory = payload.isCompulsory === "true";
    if (payload.registrationOpenAt) payload.registrationOpenAt = new Date(payload.registrationOpenAt).toISOString();
    if (payload.registrationCloseAt) payload.registrationCloseAt = new Date(payload.registrationCloseAt).toISOString();
    if (code === "prerequisite" && payload.courseId === payload.prerequisiteCourseId) { formMessage("A course cannot be its own prerequisite.", "error"); return; }
    var submit = form.querySelector('[type="submit"]');
    submit.disabled = true;
    submit.textContent = "Saving…";
    try {
      await api.post(form.dataset.endpoint, payload);
      formMessage("Record saved successfully.", "success");
      api.clearCache();
      await load();
      window.setTimeout(closeForm, 550);
    } catch (error) {
      formMessage(error.message || "The record could not be saved.", "error");
    } finally {
      submit.disabled = false;
      submit.textContent = "Save Record";
    }
  }

  installUi();
  (async function () {
    var user = await auth.requireAuth();
    if (user) await load();
  })().catch(function (error) {
    var note = document.getElementById("amxNote");
    if (note) note.textContent = error.message || "Unable to initialise Academic Structure Setup.";
  });
})();
