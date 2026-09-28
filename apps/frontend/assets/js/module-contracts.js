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
            endpoint: "/assessments",
            method: "GET",
            mutable: false
        },
        "examinations": {
            endpoint: "/examinations",
            method: "GET",
            mutable: false
        },
        "results": {
            endpoint: "/course-result-policies",
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
            endpoint: "/helpdesk/messages",
            method: "GET",
            mutable: false
        },
        "library": {
            endpoint: "/library",
            method: "GET",
            mutable: false
        },
        "hostel": {
            endpoint: "/hostels",
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
            endpoint: "/graduation",
            method: "GET",
            mutable: false
        },
        "alumni": {
            endpoint: "/alumni",
            method: "GET",
            mutable: false
        },
        "transcripts": {
            endpoint: "/transcripts",
            method: "GET",
            mutable: false
        },
        "operations": {
            endpoint: "/procurement/orders",
            method: "GET",
            mutable: false
        },
        "reports": {
            endpoint: "/reports",
            method: "GET",
            mutable: false
        },
        "system": {
            endpoint: "/settings",
            method: "GET",
            mutable: false
        }
    };

})();