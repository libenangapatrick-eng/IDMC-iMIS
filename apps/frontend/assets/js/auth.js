(function () {
    "use strict";

    const CONFIG = window.IDMC_CONFIG;

    if (!CONFIG) {
        console.error("IDMC_CONFIG is missing.");
        return;
    }

    const STORAGE_KEY = "idmc_session";
    const USER_KEY = "idmc_user";
    const REDIRECT_KEY = "idmc_redirect";
    const REQUEST_TIMEOUT_MS = 12000;

    async function fetchWithTimeout(url, options) {
        const controller = new AbortController();
        const timeoutId = window.setTimeout(function () {
            controller.abort();
        }, REQUEST_TIMEOUT_MS);

        try {
            return await fetch(url, {
                ...(options || {}),
                signal: controller.signal
            });
        } catch (error) {
            if (error && error.name === "AbortError") {
                throw new Error(
                    "The backend did not respond within 12 seconds. Confirm that it is running on port 4000."
                );
            }

            throw error;
        } finally {
            window.clearTimeout(timeoutId);
        }
    }

    function saveSession(session) {
        if (!session || !session.access_token) {
            throw new Error("Invalid authentication session received.");
        }

        sessionStorage.setItem(
            STORAGE_KEY,
            JSON.stringify({
                access_token: session.access_token,
                refresh_token: session.refresh_token || null,
                expires_at: session.expires_at || null,
                expires_in: session.expires_in || null,
                token_type: session.token_type || "bearer"
            })
        );
    }

    function getSession() {
        try {
            const raw = sessionStorage.getItem(STORAGE_KEY);
            return raw ? JSON.parse(raw) : null;
        } catch (error) {
            console.error("Could not read session:", error);
            return null;
        }
    }

    function clearSession() {
        sessionStorage.removeItem(STORAGE_KEY);
        sessionStorage.removeItem(USER_KEY);
        sessionStorage.removeItem(REDIRECT_KEY);
    }

    function getAccessToken() {
        return getSession()?.access_token || null;
    }

    function saveUser(data) {
        sessionStorage.setItem(USER_KEY, JSON.stringify(data));
    }

    function getUser() {
        try {
            const raw = sessionStorage.getItem(USER_KEY);
            return raw ? JSON.parse(raw) : null;
        } catch {
            return null;
        }
    }

    function redirectToLogin() {
        const currentPage = window.location.pathname.split("/").pop();

        if (
            currentPage &&
            currentPage !== "login.html" &&
            currentPage !== ""
        ) {
            sessionStorage.setItem(REDIRECT_KEY, currentPage);
        }

        window.location.replace("login.html");
    }

    function landingPage() {
        // Student-only accounts open the Student Portal; everyone else the dashboard.
        const codes = ((getUser() && getUser().roles) || []).map(function (role) {
            return role.roleCode || role.role_code;
        });

        const studentOnly =
            codes.length > 0 &&
            codes.every(function (code) {
                return code === "STUDENT";
            });

        return studentOnly ? "student-portal.html" : "dashboard.html";
    }

    function redirectAfterLogin() {
        const redirect = sessionStorage.getItem(REDIRECT_KEY);

        sessionStorage.removeItem(REDIRECT_KEY);

        if (
            redirect &&
            redirect !== "login.html" &&
            redirect !== "undefined"
        ) {
            window.location.replace(redirect);
            return;
        }

        window.location.replace(landingPage());
    }

    async function parseResponse(response) {
        const text = await response.text();

        if (!text) {
            return {};
        }

        try {
            return JSON.parse(text);
        } catch {
            return {
                message: text
            };
        }
    }

    async function login(identifier, password) {
        identifier = String(identifier || "").trim();
        password = String(password || "");

        if (!identifier) {
            throw new Error("Please enter your Registration Number, Application Number or email.");
        }

        if (!password) {
            throw new Error("Please enter your password.");
        }

        if (!CONFIG.API_BASE_URL) {
            throw new Error("Backend API URL is not configured.");
        }

        let response;

        try {
            response = await fetchWithTimeout(
                `${CONFIG.API_BASE_URL}/auth/login`,
                {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json"
                    },
                    body: JSON.stringify({
                        identifier,
                        password
                    })
                }
            );
        } catch (error) {
            console.error("Backend connection error:", error);

            throw new Error(
                "Unable to connect to the configured IDMC backend."
            );
        }

        const data = await parseResponse(response);

        if (!response.ok || !data?.success) {
            throw new Error(
                data?.message ||
                data?.error ||
                "Login failed."
            );
        }

        saveSession(data.data);

        return data.data;
    }

    async function studentLogin(studentNumber, password) {
        studentNumber = String(studentNumber || "").trim().toUpperCase();
        password = String(password || "");

        if (!/^(?:IDMC\/\d{4}\/\d{5}|N[A-Z]\d{4}\/\d{4}\/\d{4})$/.test(studentNumber)) {
            throw new Error("Enter a valid Student Number or Registration Number.");
        }
        if (!password) {
            throw new Error("Please enter your password.");
        }

        let response;
        try {
            response = await fetchWithTimeout(`${CONFIG.API_BASE_URL}/auth/student-login`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ studentNumber, password })
            });
        } catch (error) {
            console.error("Student login connection error:", error);
            throw new Error("Unable to connect to the configured IDMC backend.");
        }

        const data = await parseResponse(response);
        if (!response.ok || !data?.success || !data?.data?.access_token) {
            throw new Error(data?.message || "Student login failed.");
        }

        saveSession(data.data);
        return data.data;
    }

    async function supabaseLogin(identifier, password) {
        identifier = String(identifier || "").trim();
        password = String(password || "");

        if (!identifier) {
            throw new Error("Please enter your email, username or student number.");
        }

        if (!password) {
            throw new Error("Please enter your password.");
        }

        if (!CONFIG.API_BASE_URL) {
            throw new Error("Backend API URL is not configured.");
        }

        let response;
        try {
            response = await fetchWithTimeout(`${CONFIG.API_BASE_URL}/auth/login`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ identifier, password })
            });
        } catch (error) {
            console.error("Backend login connection error:", error);
            throw new Error("Unable to connect to IDMC backend.");
        }

        const payload = await parseResponse(response);
        if (!response.ok || !payload?.success || !payload?.data?.access_token) {
            throw new Error(payload?.message || "Login failed.");
        }

        saveSession(payload.data);
        return payload.data;
    }
    async function getCurrentUser() {
        const token = getAccessToken();

        if (!token) {
            throw new Error("No authentication session.");
        }

        if (!CONFIG.API_BASE_URL) {
            throw new Error("Backend API URL is not configured.");
        }

        let response;

        try {
            response = await fetchWithTimeout(
                `${CONFIG.API_BASE_URL}/auth/me`,
                {
                    method: "GET",
                    headers: {
                        "Authorization": `Bearer ${token}`,
                        "Content-Type": "application/json"
                    }
                }
            );
        } catch (error) {
            console.error("Backend connection error:", error);

            throw new Error(
                "Unable to connect to the configured IDMC backend."
            );
        }

        const data = await parseResponse(response);

        if (!response.ok) {
            throw new Error(
                data?.message ||
                data?.error ||
                "Unable to load user profile."
            );
        }

        if (!data.success || !data.data) {
            throw new Error("Invalid authentication response.");
        }

        saveUser(data.data);

        return data.data;
    }

    async function refreshSession() {
        const session = getSession();

        if (!session?.refresh_token) {
            return null;
        }

        let response;

        try {
            response = await fetch(
                `${CONFIG.SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`,
                {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                        "apikey": CONFIG.SUPABASE_ANON_KEY,
                        "Authorization": `Bearer ${CONFIG.SUPABASE_ANON_KEY}`
                    },
                    body: JSON.stringify({
                        refresh_token: session.refresh_token
                    })
                }
            );
        } catch (error) {
            console.error("Session refresh failed:", error);
            clearSession();
            return null;
        }

        if (!response.ok) {
            clearSession();
            return null;
        }

        const newSession = await parseResponse(response);

        if (!newSession?.access_token) {
            clearSession();
            return null;
        }

        saveSession(newSession);

        return newSession;
    }

    async function logout() {
        const token = getAccessToken();

        try {
            if (token) {
                await fetch(
                    `${CONFIG.SUPABASE_URL}/auth/v1/logout`,
                    {
                        method: "POST",
                        headers: {
                            "Authorization": `Bearer ${token}`,
                            "apikey": CONFIG.SUPABASE_ANON_KEY
                        }
                    }
                );
            }
        } catch (error) {
            console.warn("Logout request failed:", error);
        } finally {
            clearSession();
            window.location.replace("login.html");
        }
    }

    function hasPermission(permission) {
        const user = getUser();

        if (!user) return false;

        return (
            Array.isArray(user.permissions) &&
            user.permissions.includes(permission)
        );
    }

    function hasAnyPermission(permissions) {
        if (!Array.isArray(permissions)) return false;

        return permissions.some(permission =>
            hasPermission(permission)
        );
    }

    function hasAllPermissions(permissions) {
        if (!Array.isArray(permissions)) return false;

        return permissions.every(permission =>
            hasPermission(permission)
        );
    }

    function hasRole(roleCode) {
        const user = getUser();

        if (!user) return false;

        return (
            Array.isArray(user.roles) &&
            user.roles.some(role =>
                role.roleCode === roleCode ||
                role.role_code === roleCode
            )
        );
    }

    async function requireAuth() {
        let session = getSession();

        if (!session) {
            redirectToLogin();
            return null;
        }

        try {
            return await getCurrentUser();
        } catch (error) {
            console.warn("Session validation failed:", error);

            const refreshed = await refreshSession();

            if (!refreshed) {
                clearSession();
                redirectToLogin();
                return null;
            }

            try {
                return await getCurrentUser();
            } catch (secondError) {
                console.error(
                    "Authentication failed after refresh:",
                    secondError
                );

                clearSession();
                redirectToLogin();
                return null;
            }
        }
    }

    function requirePermission(permission) {
        if (!hasPermission(permission)) {
            alert(
                `Access denied.\nRequired permission: ${permission}`
            );

            window.location.replace("dashboard.html");
            return false;
        }

        return true;
    }

    function getPrimaryRole() {
        const user = getUser();

        if (!user?.roles?.length) {
            return null;
        }

        return user.roles[0];
    }

    function getDisplayName() {
        const user = getUser();

        return (
            user?.user?.displayName ||
            user?.user?.display_name ||
            user?.user?.email ||
            "IDMC User"
        );
    }

    window.IDMCAuth = {
        saveSession,
        getSession,
        clearSession,
        getAccessToken,
        saveUser,
        getUser,
        login,
        studentLogin,
        supabaseLogin,
        getCurrentUser,
        refreshSession,
        logout,
        requireAuth,
        requirePermission,
        hasPermission,
        hasAnyPermission,
        hasAllPermissions,
        hasRole,
        getPrimaryRole,
        getDisplayName,
        redirectToLogin,
        redirectAfterLogin
    };

})();
