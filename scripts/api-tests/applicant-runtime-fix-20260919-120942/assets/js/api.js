(function () {
    "use strict";

    const CONFIG = window.IDMC_CONFIG || {};

    const API_BASE_URL =
        CONFIG.API_BASE_URL ||
        "/api/v1";

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

    async function request(path, options = {}) {
        const token = getAccessToken();

        const requestOptions = {
            ...options
        };

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

        let response;

        try {
            response = await fetch(
                url,
                requestOptions
            );
        } catch (networkError) {
            const error =
                new Error(
                    "Unable to connect to IDMC backend."
                );

            error.cause = networkError;
            error.status = 0;
            error.url = url;

            throw error;
        }

        let payload = null;

        try {
            payload =
                await parseResponse(response);
        } catch (parseError) {
            if (response.ok) {
                throw parseError;
            }
        }

        if (!response.ok) {
            const error =
                new Error(
                    extractMessage(
                        payload,
                        response
                    )
                );

            error.status = response.status;
            error.payload = payload;
            error.url = url;

            throw error;
        }

        return payload;
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
        get,
        post,
        patch,
        put,
        delete: remove
    };
})();
