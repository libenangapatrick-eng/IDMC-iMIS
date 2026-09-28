(function () {
    "use strict";

    const state = {
        booted: false,
        busyCount: 0
    };

    function qs(selector, root) {
        return (root || document).querySelector(selector);
    }

    function qsa(selector, root) {
        return Array.from(
            (root || document).querySelectorAll(selector)
        );
    }

    function getPageName() {
        const file =
            String(location.pathname || "")
                .split("/")
                .pop();

        return file || "index";
    }

    function ensureBanner() {
        let banner = qs("#idmcAppRuntimeBanner");

        if (banner) {
            return banner;
        }

        banner = document.createElement("aside");
        banner.id = "idmcAppRuntimeBanner";
        banner.className = "idmc-app-runtime-banner";

        banner.innerHTML = `
            <strong id="idmcAppRuntimeTitle">
                Application notice
            </strong>
            <div id="idmcAppRuntimeMessage"></div>
            <button type="button" id="idmcAppRuntimeClose">
                Close
            </button>
        `;

        document.body.appendChild(banner);

        qs("#idmcAppRuntimeClose", banner)
            .addEventListener(
                "click",
                function () {
                    banner.dataset.visible = "false";
                }
            );

        return banner;
    }

    function notify(title, message, type) {
        const banner = ensureBanner();

        qs("#idmcAppRuntimeTitle", banner)
            .textContent =
            title || "Application notice";

        qs("#idmcAppRuntimeMessage", banner)
            .textContent =
            message || "";

        banner.dataset.type = type || "info";
        banner.dataset.visible = "true";
    }

    function setBusy(value) {
        if (value) {
            state.busyCount += 1;
        }
        else {
            state.busyCount =
                Math.max(
                    0,
                    state.busyCount - 1
                );
        }

        document.documentElement
            .classList.toggle(
                "idmc-app-busy",
                state.busyCount > 0
            );
    }

    function normalizeHref(value) {
        if (!value) {
            return "";
        }

        return String(value)
            .split("#")[0]
            .split("?")[0];
    }

    function markCurrentNavigation() {
        const current = getPageName();

        qsa('a[href]').forEach(function (anchor) {
            const href =
                normalizeHref(
                    anchor.getAttribute("href")
                );

            if (!href) {
                return;
            }

            const target =
                href.split("/").pop();

            if (target === current) {
                anchor.setAttribute(
                    "aria-current",
                    "page"
                );
            }
        });
    }

    function protectFormsFromDoubleSubmit() {
        qsa("form").forEach(function (form) {

            if (form.dataset.idmcSubmitGuard === "true") {
                return;
            }

            form.dataset.idmcSubmitGuard = "true";

            form.addEventListener(
                "submit",
                function () {
                    const submitters =
                        qsa(
                            'button[type="submit"],input[type="submit"]',
                            form
                        );

                    submitters.forEach(function (control) {
                        control.dataset.idmcWasDisabled =
                            control.disabled
                                ? "true"
                                : "false";

                        control.disabled = true;
                    });

                    window.setTimeout(
                        function () {
                            submitters.forEach(
                                function (control) {

                                    if (
                                        control.dataset
                                            .idmcWasDisabled !==
                                        "true"
                                    ) {
                                        control.disabled = false;
                                    }
                                }
                            );
                        },
                        4000
                    );
                }
            );
        });
    }

    function installRuntimeErrorBoundary() {

        window.addEventListener(
            "error",
            function (event) {

                const message =
                    event &&
                    event.error &&
                    event.error.message
                        ? event.error.message
                        : event.message;

                if (!message) {
                    return;
                }

                console.error(
                    "[IDMC Application]",
                    event.error || event.message
                );
            }
        );

        window.addEventListener(
            "unhandledrejection",
            function (event) {

                const reason = event.reason;

                console.error(
                    "[IDMC Application Promise]",
                    reason
                );
            }
        );
    }

    function verifyArchitecture() {
        const page = getPageName();

        const publicPages = [
            "login.html",
            "set-password.html"
        ];

        if (publicPages.includes(page)) {
            return true;
        }

        const missing = [];

        if (!window.IDMCAuth) {
            missing.push("IDMCAuth");
        }

        if (
            !window.IDMCAPI ||
            typeof window.IDMCAPI.request !== "function"
        ) {
            missing.push("IDMCAPI");
        }

        if (missing.length > 0) {

            notify(
                "Application runtime incomplete",
                "Missing: " + missing.join(", "),
                "error"
            );

            console.error(
                "[IDMC Architecture]",
                "Missing runtime:",
                missing
            );

            return false;
        }

        return true;
    }

    function connectGlobalEvents() {

        window.addEventListener(
            "idmc:request-start",
            function () {
                setBusy(true);
            }
        );

        window.addEventListener(
            "idmc:request-end",
            function () {
                setBusy(false);
            }
        );

        window.addEventListener(
            "idmc:auth-expired",
            function () {
                notify(
                    "Session expired",
                    "Please sign in again.",
                    "error"
                );
            }
        );

        window.addEventListener(
            "idmc:crud-armed",
            function () {
                notify(
                    "Live mutation armed",
                    "One mutation is ready for confirmation.",
                    "warning"
                );
            }
        );

        window.addEventListener(
            "idmc:crud-disarmed",
            function () {
                const banner =
                    qs("#idmcAppRuntimeBanner");

                if (banner) {
                    banner.dataset.visible = "false";
                }
            }
        );
    }

    function boot() {
        if (state.booted) {
            return;
        }

        state.booted = true;

        ensureBanner();
        installRuntimeErrorBoundary();
        connectGlobalEvents();
        markCurrentNavigation();
        protectFormsFromDoubleSubmit();
        verifyArchitecture();

        document.documentElement
            .setAttribute(
                "data-idmc-integrated",
                "true"
            );

        window.IDMCApplication =
            Object.freeze({
                notify: notify,
                setBusy: setBusy,
                verifyArchitecture:
                    verifyArchitecture,
                refreshNavigation:
                    markCurrentNavigation,

                get page() {
                    return getPageName();
                },

                get booted() {
                    return state.booted;
                }
            });

        window.dispatchEvent(
            new CustomEvent(
                "idmc:application-ready",
                {
                    detail: {
                        page: getPageName()
                    }
                }
            )
        );
    }

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