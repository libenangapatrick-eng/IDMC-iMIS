(function () {
    "use strict";

    const relationships = {};

    function rowsOf(response) {
        const value = response?.data ?? response;

        if (Array.isArray(value)) {
            return value;
        }

        const keys = [
            "items",
            "rows",
            "records",
            "results",
            "data"
        ];

        for (const key of keys) {
            if (Array.isArray(value?.[key])) {
                return value[key];
            }
        }

        return [];
    }

    function displayValue(row) {
        if (!row || typeof row !== "object") {
            return "";
        }

        const keys = [
            "name",
            "title",
            "code",
            "label",
            "full_name",
            "display_name",
            "registration_number",
            "student_number",
            "email"
        ];

        for (const key of keys) {
            const value = row[key];

            if (
                value !== null &&
                value !== undefined &&
                String(value).trim()
            ) {
                return String(value);
            }
        }

        return String(
            row.id ??
            row.uuid ??
            ""
        );
    }

    async function optionsFor(endpoint) {
        if (
            !window.IDMCAPI ||
            typeof window.IDMCAPI.request !== "function"
        ) {
            throw new Error(
                "IDMCAPI is unavailable."
            );
        }

        const response =
            await window.IDMCAPI.request(endpoint);

        return rowsOf(response);
    }

    function get(endpoint, field) {
        return relationships?.[endpoint]?.[field] || null;
    }

    window.IDMCRelationships = {
        manifest: relationships,
        get,
        optionsFor,
        displayValue
    };
})();