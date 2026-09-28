(function () {
    "use strict";

    window.IDMC_MODULE_CONTRACTS = {
        "admissions": {
            endpoint: "/applications/applicants",
            method: "GET",
            mutable: true
        },
        "registration": {
            endpoint: "/academic-core/registrations",
            method: "GET",
            mutable: true
        },
        "attendance": {
            endpoint: "/attendance",
            method: "GET",
            mutable: false
        },
        "assessment": {
            endpoint: "/assessment/assessments",
            method: "GET",
            mutable: false
        },
        "examinations": {
            endpoint: "/examinations/periods",
            method: "GET",
            mutable: false
        },
        "results": {
            endpoint: "/results/course-result-policies",
            method: "GET",
            mutable: false
        },
        "timetable": {
            endpoint: "/timetables",
            method: "GET",
            mutable: false
        },
        "finance": {
            endpoint: "/finance/fee-structures",
            method: "GET",
            mutable: false
        },
        "communications": {
            endpoint: "/communications/helpdesk/messages",
            method: "GET",
            mutable: false
        },
        "library": {
            endpoint: "/library/items",
            method: "GET",
            mutable: false
        },
        "hostel": {
            endpoint: "/hostel/hostels",
            method: "GET",
            mutable: false
        },
        "hr": {
            endpoint: "/hr/leave/balances",
            method: "GET",
            mutable: false
        },
        "research": {
            endpoint: "/research/projects",
            method: "GET",
            mutable: false
        },
        "graduation": {
            endpoint: "/graduation/periods",
            method: "GET",
            mutable: false
        },
        "alumni": {
            endpoint: "/alumni/records",
            method: "GET",
            mutable: false
        },
        "transcripts": {
            endpoint: "/transcripts",
            method: "GET",
            mutable: false
        },
        "operations": {
            endpoint: "/operations/procurement/orders",
            method: "GET",
            mutable: false
        },
        "reports": {
            endpoint: "/reports/definitions",
            method: "GET",
            mutable: false
        },
        "system": {
            endpoint: "/system/settings",
            method: "GET",
            mutable: false
        }
    };

})();
