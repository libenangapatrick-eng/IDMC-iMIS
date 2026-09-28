(function () {
    "use strict";

    const injected = window.__IDMC_RUNTIME_CONFIG__ || {};
    const metaApi = document.querySelector('meta[name="idmc-api-base-url"]')?.content;
    const localFrontendPorts = new Set(["5500", "5501", "5502"]);

    function trimSlash(value) {
        return String(value || "").trim().replace(/\/+$/, "");
    }

    function defaultApiBase() {
        if (localFrontendPorts.has(window.location.port)) {
            return `${window.location.protocol}//${window.location.hostname}:4000/api/v1`;
        }
        return `${window.location.origin}/api/v1`;
    }

    const existing = window.IDMC_CONFIG || {};
    const apiBase = trimSlash(
        injected.API_BASE_URL ||
        metaApi ||
        existing.API_BASE_URL ||
        defaultApiBase()
    );

    if (!/^https?:\/\//i.test(apiBase) && !apiBase.startsWith("/")) {
        throw new Error("IDMC API_BASE_URL must be an absolute HTTP(S) URL or a same-origin path.");
    }

    window.IDMC_CONFIG = Object.freeze({
        ...existing,
        ...injected,
        SUPABASE_URL:
            injected.SUPABASE_URL ||
            existing.SUPABASE_URL ||
            "https://ocvfpoxukbquzmapfqjx.supabase.co",
        // Publishable/anon key only. Never place a service-role key in frontend files.
        SUPABASE_ANON_KEY:
            injected.SUPABASE_ANON_KEY ||
            existing.SUPABASE_ANON_KEY ||
            "sb_publishable_62rJTajRkmlGIe3BikTq_g_P0L6KzPI",
        API_BASE_URL: apiBase
    });
})();
