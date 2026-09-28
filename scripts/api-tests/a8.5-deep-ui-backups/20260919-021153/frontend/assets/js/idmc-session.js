(function () {
    "use strict";

    const STORAGE_KEY = "idmc_session";

    function readSession() {
        try {
            const raw = sessionStorage.getItem(STORAGE_KEY);

            if (!raw) {
                return null;
            }

            const session = JSON.parse(raw);

            if (
                !session ||
                typeof session !== "object"
            ) {
                return null;
            }

            return session;

        } catch (error) {
            console.error(
                "IDMC session read failed:",
                error
            );

            return null;
        }
    }

    function writeSession(session) {
        if (
            !session ||
            typeof session !== "object"
        ) {
            return false;
        }

        try {
            sessionStorage.setItem(
                STORAGE_KEY,
                JSON.stringify(session)
            );

            return true;

        } catch (error) {
            console.error(
                "IDMC session write failed:",
                error
            );

            return false;
        }
    }

    function getAccessToken() {
        const session = readSession();

        if (
            session &&
            typeof session.access_token === "string" &&
            session.access_token.trim()
        ) {
            return session.access_token;
        }

        return (
            sessionStorage.getItem(
                "idmc_access_token"
            ) ||
            sessionStorage.getItem(
                "access_token"
            ) ||
            sessionStorage.getItem(
                "supabase_access_token"
            ) ||
            null
        );
    }

    function getRefreshToken() {
        const session = readSession();

        if (
            session &&
            typeof session.refresh_token === "string" &&
            session.refresh_token.trim()
        ) {
            return session.refresh_token;
        }

        return null;
    }

    function getSession() {
        return readSession();
    }

    function setSession(session) {
        const saved =
            writeSession(session);

        if (!saved) {
            return false;
        }

        if (
            session.access_token
        ) {
            sessionStorage.setItem(
                "idmc_access_token",
                session.access_token
            );

            sessionStorage.setItem(
                "access_token",
                session.access_token
            );

            sessionStorage.setItem(
                "supabase_access_token",
                session.access_token
            );
        }

        return true;
    }

    function sync() {
        const session = readSession();

        if (!session) {
            return false;
        }

        if (
            typeof session.access_token === "string" &&
            session.access_token.trim()
        ) {
            sessionStorage.setItem(
                "idmc_access_token",
                session.access_token
            );

            sessionStorage.setItem(
                "access_token",
                session.access_token
            );

            sessionStorage.setItem(
                "supabase_access_token",
                session.access_token
            );

            return true;
        }

        return false;
    }

    function clear() {
        [
            "idmc_session",
            "idmc_access_token",
            "access_token",
            "supabase_access_token"
        ].forEach(key => {
            try {
                sessionStorage.removeItem(key);
            } catch (error) {
                console.error(
                    `Unable to remove session key ${key}:`,
                    error
                );
            }
        });

        return true;
    }

    window.IDMCSession = {
        getSession,
        getAccessToken,
        getRefreshToken,
        setSession,
        sync,
        clear
    };

    sync();

    console.log(
        "IDMC session manager loaded:",
        Boolean(getAccessToken())
    );
})();
