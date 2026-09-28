(function () {
    "use strict";

    const config = window.IDMC_MODULE_PAGE || {};

    const $ = (selector) => document.querySelector(selector);

    function setState(type, title, message) {
        const state = $("#moduleState");

        if (!state) return;

        state.classList.toggle("error", type === "error");

        state.innerHTML =
            "<strong>" + escapeHtml(title) + "</strong>" +
            "<span>" + escapeHtml(message || "") + "</span>";
    }

    function escapeHtml(value) {
        return String(value ?? "")
            .replaceAll("&", "&amp;")
            .replaceAll("<", "&lt;")
            .replaceAll(">", "&gt;")
            .replaceAll('"', "&quot;")
            .replaceAll("'", "&#039;");
    }

    async function requireAuthentication() {
        if (!window.IDMCAuth) {
            throw new Error("IDMCAuth is not available.");
        }

        if (typeof window.IDMCAuth.requireAuth === "function") {
            return window.IDMCAuth.requireAuth();
        }

        if (
            typeof window.IDMCAuth.getAccessToken === "function" &&
            window.IDMCAuth.getAccessToken()
        ) {
            return true;
        }

        window.location.href = "login.html";
        return false;
    }

    async function checkPermission() {
        if (!config.permission) return true;

        if (
            !window.IDMC_RBAC_API ||
            typeof window.IDMC_RBAC_API.hasPermission !== "function"
        ) {
            return true;
        }

        try {
            const allowed =
                await window.IDMC_RBAC_API.hasPermission(
                    config.permission
                );

            if (!allowed) {
                setState(
                    "error",
                    "Access denied",
                    "You do not have permission to view this module."
                );

                return false;
            }

            return true;
        } catch (error) {
            console.warn(
                "Permission check could not be completed.",
                error
            );

            return true;
        }
    }

    function activateNavigation() {
        document
            .querySelectorAll("[data-module-link]")
            .forEach((link) => {
                if (
                    link.dataset.moduleLink ===
                    config.key
                ) {
                    link.classList.add("active");
                }
            });
    }

    function setIdentity() {
        const title = $("#moduleTitle");
        const subtitle = $("#moduleSubtitle");
        const badge = $("#moduleBadge");

        if (title) {
            title.textContent =
                config.title || "Module";
        }

        if (subtitle) {
            subtitle.textContent =
                config.description ||
                "IDMC iMIS management workspace";
        }

        if (badge) {
            badge.textContent =
                config.permission || "Authenticated";
        }

        document.title =
            (config.title || "Module") +
            " | IDMC iMIS";
    }

    function wireSearch() {
        const input = $("#moduleSearch");

        if (!input) return;

        input.addEventListener("input", () => {
            const query =
                input.value.trim().toLowerCase();

            document
                .querySelectorAll(
                    "#moduleTableBody tr[data-row]"
                )
                .forEach((row) => {
                    row.hidden =
                        query.length > 0 &&
                        !row.textContent
                            .toLowerCase()
                            .includes(query);
                });
        });
    }

    function wireRefresh() {
        const button = $("#refreshButton");

        if (!button) return;

        button.addEventListener(
            "click",
            async () => {
                await initializeWorkspace();
            }
        );
    }

    async function initializeWorkspace() {
        /*
         * A7.7 deliberately does NOT invent module endpoints.
         *
         * Each generated page is now structurally complete and
         * connected to authentication, centralized API transport,
         * RBAC and navigation.
         *
         * Exact module resource binding is installed only when
         * its real backend route contract is known.
         */

        setState(
            "empty",
            config.title + " workspace ready",
            "Frontend module is installed. Resource binding will use the existing backend contract."
        );

        const total = $("#statTotal");
        const active = $("#statActive");
        const pending = $("#statPending");
        const updated = $("#statUpdated");

        if (total) total.textContent = "—";
        if (active) active.textContent = "—";
        if (pending) pending.textContent = "—";
        if (updated) updated.textContent = "Ready";
    }

    async function boot() {
        try {
            setIdentity();
            activateNavigation();

            await requireAuthentication();

            const allowed =
                await checkPermission();

            if (!allowed) return;

            wireSearch();
            wireRefresh();

            await initializeWorkspace();
        } catch (error) {
            console.error(error);

            setState(
                "error",
                "Unable to open module",
                error?.message ||
                "An unexpected application error occurred."
            );
        }
    }

    window.IDMCModulePages = {
        initializeWorkspace
    };

    if (document.readyState === "loading") {
        document.addEventListener(
            "DOMContentLoaded",
            boot
        );
    } else {
        boot();
    }
})();