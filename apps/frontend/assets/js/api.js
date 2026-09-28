(function () {
    "use strict";

    const CONFIG = window.IDMC_CONFIG || {};

    const API_BASE_URL =
        CONFIG.API_BASE_URL ||
        "/api/v1";

    const DEFAULT_TIMEOUT_MS = 25000;
    const GET_CACHE_MS = 8000;
    const MAX_GET_ATTEMPTS = 3;
    const responseCache = new Map();
    const inFlightGets = new Map();

    function requestId() {
        if (window.crypto?.randomUUID) return window.crypto.randomUUID();
        return `web-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    }

    function normalizePath(path) {
        if (!path) {
            return "";
        }

        return path.startsWith("/")
            ? path
            : `/${path}`;
    }

    function getAccessToken() {
        if (
            window.IDMCAuth &&
            typeof window.IDMCAuth.getAccessToken === "function"
        ) {
            return window.IDMCAuth.getAccessToken();
        }

        return null;
    }

    function buildHeaders(options, token) {
        const headers = new Headers(options.headers || {});

        if (!headers.has("Accept")) {
            headers.set("Accept", "application/json");
        }

        if (
            options.body !== undefined &&
            options.body !== null &&
            !(options.body instanceof FormData) &&
            !headers.has("Content-Type")
        ) {
            headers.set(
                "Content-Type",
                "application/json"
            );
        }

        if (
            token &&
            !headers.has("Authorization")
        ) {
            headers.set(
                "Authorization",
                `Bearer ${token}`
            );
        }

        if (!headers.has("X-Request-Id")) {
            headers.set("X-Request-Id", requestId());
        }

        return headers;
    }

    async function parseResponse(response) {
        if (response.status === 204) {
            return null;
        }

        const contentType =
            response.headers.get("content-type") || "";

        if (contentType.includes("application/json")) {
            return await response.json();
        }

        const text = await response.text();

        return text || null;
    }

    function extractMessage(payload, response) {
        if (
            payload &&
            typeof payload === "object" &&
            payload.message
        ) {
            return payload.message;
        }

        if (typeof payload === "string" && payload) {
            return payload;
        }

        return (
            `Request failed with HTTP ${response.status}`
        );
    }

    function friendlyMessage(message, status, requestId) {
        const raw = String(message || "").trim();
        const generic = /^(internal server error|something went wrong)$/i.test(raw);

        if (status === 401) return "Your session has expired or the login details are incorrect. Please sign in again.";
        if (status === 403) return "Your account is not permitted to open this information.";
        if (status === 404) return raw && !generic ? raw : "The requested information was not found.";
        if (status === 409) return raw && !generic ? raw : "This action conflicts with an existing record.";
        if (status === 429) return "Too many requests were sent. Wait briefly and try again.";
        if (status >= 500 && generic) {
            return `The service could not complete this request. Try again.${requestId ? ` Reference: ${requestId}` : ""}`;
        }
        return raw || `Request failed with HTTP ${status}`;
    }

    function cacheKey(url, token) {
        return `${url}|${token ? token.slice(-18) : "public"}`;
    }

    function wait(ms) {
        return new Promise(resolve => window.setTimeout(resolve, ms));
    }

    function clearGetCache() {
        responseCache.clear();
    }

    async function performRequest(url, requestOptions, callerSignal, timeoutMs, attempt) {
        const controller = new AbortController();
        const timeout = window.setTimeout(() => controller.abort(), timeoutMs);
        if (callerSignal) callerSignal.addEventListener("abort", () => controller.abort(), { once: true });

        let response;
        try {
            response = await fetch(url, { ...requestOptions, signal: controller.signal });
        } catch (networkError) {
            const retryable = !callerSignal?.aborted && requestOptions.method === "GET" && attempt < MAX_GET_ATTEMPTS;
            if (retryable) {
                await wait(350 * attempt);
                return performRequest(url, requestOptions, callerSignal, timeoutMs, attempt + 1);
            }

            const error = new Error(
                networkError?.name === "AbortError"
                    ? "The request took too long. Check the connection and try again."
                    : "Unable to connect to the IDMC backend. Confirm that port 4000 is running."
            );
            error.cause = networkError;
            error.status = 0;
            error.url = url;
            throw error;
        } finally {
            window.clearTimeout(timeout);
        }

        if (requestOptions.method === "GET" && [502, 503, 504].includes(response.status) && attempt < MAX_GET_ATTEMPTS) {
            await wait(350 * attempt);
            return performRequest(url, requestOptions, callerSignal, timeoutMs, attempt + 1);
        }

        let payload = null;
        try {
            payload = await parseResponse(response);
        } catch (parseError) {
            if (response.ok) throw new Error("The server returned an unreadable response.");
        }

        if (!response.ok) {
            const responseRequestId = response.headers.get("x-request-id") || payload?.requestId || null;
            const error = new Error(friendlyMessage(extractMessage(payload, response), response.status, responseRequestId));
            error.status = response.status;
            error.payload = payload;
            error.url = url;
            error.requestId = responseRequestId;
            throw error;
        }

        return payload;
    }

    async function request(path, options = {}) {
        const token = getAccessToken();

        const requestOptions = {
            ...options
        };

        const timeoutMs = Number(requestOptions.timeoutMs || DEFAULT_TIMEOUT_MS);
        const callerSignal = requestOptions.signal;
        delete requestOptions.timeoutMs;
        delete requestOptions.signal;

        requestOptions.method =
            requestOptions.method || "GET";

        requestOptions.headers =
            buildHeaders(requestOptions, token);

        if (
            requestOptions.body !== undefined &&
            requestOptions.body !== null &&
            !(requestOptions.body instanceof FormData) &&
            typeof requestOptions.body !== "string"
        ) {
            requestOptions.body =
                JSON.stringify(requestOptions.body);
        }

        const url =
            `${API_BASE_URL}${normalizePath(path)}`;
        const isGet = requestOptions.method === "GET";
        const key = cacheKey(url, token);

        if (!isGet) clearGetCache();
        if (isGet && requestOptions.cache !== "no-store") {
            const cached = responseCache.get(key);
            if (cached && cached.expiresAt > Date.now()) return cached.payload;
            if (inFlightGets.has(key)) return inFlightGets.get(key);
        }

        delete requestOptions.cache;
        const operation = performRequest(url, requestOptions, callerSignal, timeoutMs, 1)
            .then(payload => {
                if (isGet) responseCache.set(key, { payload, expiresAt: Date.now() + GET_CACHE_MS });
                return payload;
            })
            .finally(() => {
                if (isGet) inFlightGets.delete(key);
            });

        if (isGet) inFlightGets.set(key, operation);
        return operation;
    }

    function get(path, options = {}) {
        return request(path, {
            ...options,
            method: "GET"
        });
    }

    function post(path, body, options = {}) {
        return request(path, {
            ...options,
            method: "POST",
            body
        });
    }

    function patch(path, body, options = {}) {
        return request(path, {
            ...options,
            method: "PATCH",
            body
        });
    }

    function put(path, body, options = {}) {
        return request(path, {
            ...options,
            method: "PUT",
            body
        });
    }

    function remove(path, options = {}) {
        return request(path, {
            ...options,
            method: "DELETE"
        });
    }

    window.IDMCAPI = {
        baseUrl: API_BASE_URL,
        getAccessToken,
        request,
        clearCache: clearGetCache,
        get,
        post,
        patch,
        put,
        delete: remove
    };
})();
