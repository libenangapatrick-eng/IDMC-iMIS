(function () {
    "use strict";

    const STATE = {
        armed: false,
        executing: false
    };

    function getApi() {
        if (
            !window.IDMCAPI ||
            typeof window.IDMCAPI.request !== "function"
        ) {
            throw new Error(
                "IDMCAPI centralized transport is unavailable."
            );
        }

        return window.IDMCAPI;
    }

    function normalizeMethod(method) {
        return String(method || "GET").toUpperCase();
    }

    function isMutation(method) {
        return [
            "POST",
            "PATCH",
            "PUT",
            "DELETE"
        ].includes(normalizeMethod(method));
    }

    function arm() {
        STATE.armed = true;
        window.dispatchEvent(
            new CustomEvent("idmc:crud-armed")
        );
    }

    function disarm() {
        STATE.armed = false;
        STATE.executing = false;

        window.dispatchEvent(
            new CustomEvent("idmc:crud-disarmed")
        );
    }

    async function request(path, options) {
        const opts = Object.assign({}, options || {});
        const method = normalizeMethod(opts.method);

        if (isMutation(method) && !STATE.armed) {
            throw new Error(
                "Live CRUD mutation blocked: execution guard is not armed."
            );
        }

        if (STATE.executing) {
            throw new Error(
                "Another live CRUD mutation is already executing."
            );
        }

        if (!isMutation(method)) {
            return getApi().request(path, opts);
        }

        const confirmed = window.confirm(
            method +
            " " +
            path +
            "\n\n" +
            "This will modify live IDMC data.\n" +
            "Continue?"
        );

        if (!confirmed) {
            throw new Error(
                "Live CRUD mutation cancelled by user."
            );
        }

        STATE.executing = true;

        try {
            return await getApi().request(
                path,
                opts
            );
        }
        finally {
            STATE.executing = false;

            // Every mutation requires explicit re-arm.
            STATE.armed = false;
        }
    }

    window.IDMCLiveCRUD = Object.freeze({
        arm,
        disarm,
        request,

        get armed() {
            return STATE.armed;
        },

        get executing() {
            return STATE.executing;
        }
    });
})();