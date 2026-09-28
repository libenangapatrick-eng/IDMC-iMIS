(function () {
  "use strict";

  const CONFIG = window.IDMC_CONFIG;

  if (!CONFIG) {
    console.error("IDMC_CONFIG is missing.");
    return;
  }

  /*
   * ============================================================
   * IDMC iMIS FRONTEND RBAC
   * ============================================================
   *
   * Backend RBAC remains the REAL security layer.
   *
   * Frontend RBAC:
   * 1. Reads authenticated session
   * 2. Loads current user's roles/permissions
   * 3. Checks permissions
   * 4. Controls UI visibility
   * 5. Protects frontend page actions
   *
   * IMPORTANT:
   * This file does NOT replace backend authorization.
   * ============================================================
   */

  let currentUser = null;
  let currentRoles = [];
  let currentPermissions = new Set();
  let rbacLoaded = false;

  let rbacLoadPromise = null;

  /* ============================================================
     SESSION TOKEN
  ============================================================ */

  function getSessionToken() {
    try {
      if (
        window.IDMCSession &&
        typeof window.IDMCSession.getAccessToken === "function"
      ) {
        const token =
          window.IDMCSession.getAccessToken();

        if (token) {
          return token;
        }
      }
    } catch (error) {
      console.warn(
        "IDMCSession token read failed:",
        error
      );
    }

    try {
      if (
        window.IDMCAuth &&
        typeof window.IDMCAuth.getAccessToken === "function"
      ) {
        const token =
          window.IDMCAuth.getAccessToken();

        if (token) {
          return token;
        }
      }
    } catch (error) {
      console.warn(
        "IDMCAuth token read failed:",
        error
      );
    }

    try {
      const raw =
        sessionStorage.getItem(
          "idmc_session"
        );

      if (raw) {
        const session =
          JSON.parse(raw);

        if (
          session &&
          session.access_token
        ) {
          return session.access_token;
        }
      }
    } catch (error) {
      console.warn(
        "idmc_session read failed:",
        error
      );
    }

    return null;
  }

  /* ============================================================
     STORED USER
  ============================================================ */

  function getStoredUser() {
    try {
      const raw =
        sessionStorage.getItem(
          "idmc_user"
        );

      if (!raw) {
        return null;
      }

      const parsed =
        JSON.parse(raw);

      return parsed || null;

    } catch (error) {
      console.warn(
        "Stored user read failed:",
        error
      );

      return null;
    }
  }

  /* ============================================================
     OPTIONAL AUTH USER READER
     ------------------------------------------------------------
     We do not change auth.js.
     We only read commonly available data if it exists.
  ============================================================ */

  function getAuthUserData() {
    try {

      if (
        window.IDMCAuth &&
        typeof window.IDMCAuth.getCurrentUser ===
          "function"
      ) {
        const value =
          window.IDMCAuth.getCurrentUser();

        if (value) {
          return value;
        }
      }

    } catch (error) {
      console.warn(
        "IDMCAuth current user read failed:",
        error
      );
    }

    return null;
  }

  /* ============================================================
     SESSION CLEAR
  ============================================================ */

  function clearLocalSessionOnly() {
    try {
      if (
        window.IDMCSession &&
        typeof window.IDMCSession.clear ===
          "function"
      ) {
        window.IDMCSession.clear();
      }
    } catch (error) {
      console.warn(
        "IDMCSession clear failed:",
        error
      );
    }

    try {
      if (
        window.IDMCAuth &&
        typeof window.IDMCAuth.clearSession ===
          "function"
      ) {
        window.IDMCAuth.clearSession();
      }
    } catch (error) {
      console.warn(
        "IDMCAuth clearSession failed:",
        error
      );
    }

    try {
      sessionStorage.removeItem(
        "idmc_session"
      );

      sessionStorage.removeItem(
        "idmc_user"
      );

      sessionStorage.removeItem(
        "idmc_redirect"
      );

    } catch (error) {
      console.warn(
        "Session storage cleanup failed:",
        error
      );
    }
  }

  /* ============================================================
     GO LOGIN
  ============================================================ */

  function goToLogin() {
    clearLocalSessionOnly();

    window.location.replace(
      "login.html"
    );
  }

  /* ============================================================
     AUTH REFRESH
  ============================================================ */

  async function refreshAuthentication() {
    try {

      if (
        window.IDMCAuth &&
        typeof window.IDMCAuth.refreshSession ===
          "function"
      ) {

        const refreshed =
          await window.IDMCAuth.refreshSession();

        if (
          refreshed &&
          refreshed.access_token
        ) {
          return refreshed;
        }

        /*
         * Some auth implementations return:
         * { data: { session: {...} } }
         */

        const nested =
          refreshed?.data?.session ||
          refreshed?.session ||
          null;

        if (
          nested &&
          nested.access_token
        ) {
          return nested;
        }
      }

    } catch (error) {

      console.warn(
        "Authentication refresh failed:",
        error
      );

    }

    return null;
  }

  /* ============================================================
     RESPONSE PARSER
  ============================================================ */

  async function parseResponse(response) {
    try {

      const text =
        await response.text();

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

    } catch {

      return {};

    }
  }

  /* ============================================================
     FETCH WITH TOKEN
  ============================================================ */

  async function fetchWithToken(
    path,
    options = {},
    accessToken
  ) {

    const headers = {
      "Content-Type":
        "application/json",

      ...(options.headers || {}),

      Authorization:
        `Bearer ${accessToken}`
    };

    return fetch(
      `${CONFIG.API_BASE_URL}${path}`,
      {
        ...options,
        headers
      }
    );
  }

  /* ============================================================
     ERROR MESSAGE NORMALIZER
  ============================================================ */

  function getErrorMessage(value) {

    if (
      typeof value ===
      "string"
    ) {

      const text =
        value.trim();

      return text ||
        null;
    }

    if (
      !value ||
      typeof value !==
        "object"
    ) {
      return null;
    }

    if (
      typeof value.message ===
      "string"
    ) {

      return (
        value.message.trim() ||
        null
      );
    }

    if (
      typeof value.error ===
      "string"
    ) {

      return (
        value.error.trim() ||
        null
      );
    }

    if (
      typeof value.details ===
      "string"
    ) {

      return (
        value.details.trim() ||
        null
      );
    }

    if (
      typeof value.detail ===
      "string"
    ) {

      return (
        value.detail.trim() ||
        null
      );
    }

    if (
      typeof value.msg ===
      "string"
    ) {

      return (
        value.msg.trim() ||
        null
      );
    }

    if (
      Array.isArray(
        value.errors
      )
    ) {

      const messages =
        value.errors
          .map(
            item =>
              getErrorMessage(
                item
              )
          )
          .filter(Boolean);

      if (
        messages.length
      ) {
        return messages.join(
          "\n"
        );
      }
    }

    try {

      return JSON.stringify(
        value,
        null,
        2
      );

    } catch {

      return null;

    }
  }

  /* ============================================================
     GENERAL API REQUEST
  ============================================================ */


  /*
   * A6.10 TRANSPORT COMPATIBILITY NOTE
   *
   * RBAC retains its existing request/fetchWithToken transport because
   * request() owns the RBAC 401 refresh/retry and Response parsing
   * lifecycle.
   *
   * New page/application API traffic uses window.IDMCAPI.
   * IDMC_RBAC_API remains the authorization/RBAC compatibility layer.
   *
   * Do not delegate fetchWithToken() directly to IDMCAPI.request():
   * IDMCAPI.request() returns parsed application data while this RBAC
   * pipeline requires the native Response object.
   */
  async function request(
    path,
    options = {}
  ) {

    if (
      !CONFIG.API_BASE_URL
    ) {

      throw new Error(
        "Backend API URL is not configured."
      );

    }

    let accessToken =
      getSessionToken();

    if (!accessToken) {

      throw new Error(
        "No authentication session."
      );

    }

    let response;

    try {

      response =
        await fetchWithToken(
          path,
          options,
          accessToken
        );

    } catch (error) {

      console.error(
        "RBAC backend connection error:",
        error
      );

      throw new Error(
        "Unable to connect to IDMC backend. Make sure the backend server is running on port 4000."
      );

    }

    let result =
      await parseResponse(
        response
      );

    /* ==========================================================
       401 - TOKEN EXPIRED
    ========================================================== */

    if (
      response.status ===
      401
    ) {

      const refreshed =
        await refreshAuthentication();

      if (
        refreshed &&
        refreshed.access_token
      ) {

        accessToken =
          refreshed.access_token;

        try {

          response =
            await fetchWithToken(
              path,
              options,
              accessToken
            );

        } catch (error) {

          console.error(
            "RBAC retry connection error:",
            error
          );

          throw new Error(
            "Unable to connect to IDMC backend. Make sure the backend server is running on port 4000."
          );

        }

        result =
          await parseResponse(
            response
          );
      }

      if (
        response.status ===
        401
      ) {

        goToLogin();

        throw new Error(
          "Your session has expired. Please log in again."
        );

      }
    }

    /* ==========================================================
       403 - ACCESS DENIED
    ========================================================== */

    if (
      response.status ===
      403
    ) {

      const message =
        getErrorMessage(
          result?.message
        ) ||

        getErrorMessage(
          result?.error
        ) ||

        getErrorMessage(
          result?.details
        ) ||

        getErrorMessage(
          result
        ) ||

        "Access denied. You do not have permission to access this resource.";

      throw new Error(
        message
      );
    }

    /* ==========================================================
       OTHER ERRORS
    ========================================================== */

    if (!response.ok) {

      const message =
        getErrorMessage(
          result?.message
        ) ||

        getErrorMessage(
          result?.error
        ) ||

        getErrorMessage(
          result?.details
        ) ||

        getErrorMessage(
          result
        ) ||

        `Request failed with status ${response.status}`;

      throw new Error(
        message
      );
    }

    return result;
  }

  /* ============================================================
     NORMALIZATION
  ============================================================ */

  function normalizePermissionCode(
    value
  ) {

    if (
      typeof value !==
      "string"
    ) {
      return null;
    }

    const code =
      value.trim();

    return code ||
      null;
  }

  function normalizeRoleCode(
    value
  ) {

    if (
      typeof value !==
      "string"
    ) {
      return null;
    }

    const code =
      value.trim();

    return code
      ? code.toUpperCase()
      : null;
  }

  /* ============================================================
     EXTRACT PERMISSION FROM OBJECT
     ------------------------------------------------------------
     Supports:
       "students.view"

     {
       permission_code: "students.view"
     }

     {
       permissionCode: "students.view"
     }

     {
       permissions: {
         permission_code: "students.view"
       }
     }
  ============================================================ */

  function extractPermissionCode(
    value
  ) {

    if (
      typeof value ===
      "string"
    ) {

      return normalizePermissionCode(
        value
      );

    }

    if (
      !value ||
      typeof value !==
        "object"
    ) {

      return null;

    }

    return (
      normalizePermissionCode(
        value.permission_code
      ) ||

      normalizePermissionCode(
        value.permissionCode
      ) ||

      normalizePermissionCode(
        value.code
      ) ||

      normalizePermissionCode(
        value.name
      ) ||

      extractPermissionCode(
        value.permission
      ) ||

      extractPermissionCode(
        value.permissions
      )
    );
  }

  /* ============================================================
     EXTRACT ROLE FROM OBJECT
  ============================================================ */

  function extractRoleCode(
    value
  ) {

    if (
      typeof value ===
      "string"
    ) {

      return normalizeRoleCode(
        value
      );

    }

    if (
      !value ||
      typeof value !==
        "object"
    ) {

      return null;

    }

    return (
      normalizeRoleCode(
        value.role_code
      ) ||

      normalizeRoleCode(
        value.roleCode
      ) ||

      normalizeRoleCode(
        value.code
      ) ||

      normalizeRoleCode(
        value.name
      ) ||

      extractRoleCode(
        value.role
      ) ||

      extractRoleCode(
        value.roles
      )
    );
  }

  /* ============================================================
     EXTRACT PERMISSIONS
  ============================================================ */

  function extractPermissionCodes(
    data
  ) {

    const permissions =
      new Set();

    if (
      !Array.isArray(data)
    ) {

      return permissions;

    }

    function scan(value) {

      if (!value) {
        return;
      }

      if (
        typeof value ===
        "string"
      ) {

        const code =
          extractPermissionCode(
            value
          );

        if (code) {
          permissions.add(
            code
          );
        }

        return;
      }

      if (
        Array.isArray(value)
      ) {

        value.forEach(
          item =>
            scan(item)
        );

        return;
      }

      if (
        typeof value ===
        "object"
      ) {

        const direct =
          extractPermissionCode(
            value
          );

        if (direct) {

          permissions.add(
            direct
          );

        }

        /*
         * role_permissions
         */

        if (
          Array.isArray(
            value.role_permissions
          )
        ) {

          value.role_permissions
            .forEach(
              item =>
                scan(item)
            );

        }

        /*
         * permissions
         */

        if (
          Array.isArray(
            value.permissions
          )
        ) {

          value.permissions
            .forEach(
              item =>
                scan(item)
            );

        }

        /*
         * permission
         */

        if (
          value.permission
        ) {

          scan(
            value.permission
          );

        }

        /*
         * roles
         */

        if (
          value.roles
        ) {

          scan(
            value.roles
          );

        }

      }
    }

    data.forEach(
      item =>
        scan(item)
    );

    return permissions;
  }

  /* ============================================================
     EXTRACT ROLES
  ============================================================ */

  function extractRoleCodes(
    data
  ) {

    const roles =
      new Set();

    if (
      !Array.isArray(data)
    ) {

      return roles;

    }

    function scan(value) {

      if (!value) {
        return;
      }

      if (
        typeof value ===
        "string"
      ) {

        const code =
          normalizeRoleCode(
            value
          );

        if (code) {
          roles.add(code);
        }

        return;
      }

      if (
        Array.isArray(value)
      ) {

        value.forEach(
          item =>
            scan(item)
        );

        return;
      }

      if (
        typeof value ===
        "object"
      ) {

        const direct =
          extractRoleCode(
            value
          );

        if (direct) {

          roles.add(
            direct
          );

        }

        if (
          value.roles
        ) {

          scan(
            value.roles
          );

        }

        if (
          value.role
        ) {

          scan(
            value.role
          );

        }

      }
    }

    data.forEach(
      item =>
        scan(item)
    );

    return roles;
  }

  /* ============================================================
     COLLECT ALL POSSIBLE RBAC SOURCES
     ------------------------------------------------------------
     This is the important improvement.
     ============================================================ */

  function collectRBACSources(
    storedUser
  ) {

    const sources =
      [];

    if (
      storedUser
    ) {

      sources.push(
        storedUser
      );

      if (
        storedUser.user
      ) {

        sources.push(
          storedUser.user
        );

      }

      if (
        storedUser.profile
      ) {

        sources.push(
          storedUser.profile
        );

      }

      if (
        storedUser.rbac
      ) {

        sources.push(
          storedUser.rbac
        );

      }

      if (
        Array.isArray(
          storedUser.user_roles
        )
      ) {

        sources.push(
          storedUser.user_roles
        );

      }

      if (
        Array.isArray(
          storedUser.roles
        )
      ) {

        sources.push(
          storedUser.roles
        );

      }

      if (
        Array.isArray(
          storedUser.permissions
        )
      ) {

        sources.push(
          storedUser.permissions
        );

      }
    }

    const authUser =
      getAuthUserData();

    if (authUser) {

      sources.push(
        authUser
      );

      if (
        authUser.user
      ) {

        sources.push(
          authUser.user
        );

      }

      if (
        Array.isArray(
          authUser.roles
        )
      ) {

        sources.push(
          authUser.roles
        );

      }

      if (
        Array.isArray(
          authUser.permissions
        )
      ) {

        sources.push(
          authUser.permissions
        );

      }

      if (
        Array.isArray(
          authUser.user_roles
        )
      ) {

        sources.push(
          authUser.user_roles
        );

      }
    }

    return sources;
  }

  /* ============================================================
     LOAD CURRENT USER RBAC
  ============================================================ */

  async function loadCurrentUserRBAC() {

    /*
     * Prevent multiple simultaneous RBAC loads.
     */

    if (
      rbacLoadPromise
    ) {

      return rbacLoadPromise;

    }

    rbacLoadPromise =
      (async function () {

        try {

          const storedUser =
            getStoredUser();

          const authUser =
            getAuthUserData();

          /*
           * ------------------------------------------------------
           * USER
           * ------------------------------------------------------
           */

          currentUser =
            storedUser?.user ||
            storedUser?.profile ||
            storedUser ||
            authUser?.user ||
            authUser ||
            null;

          /*
           * ------------------------------------------------------
           * SOURCES
           * ------------------------------------------------------
           */

          const sources =
            collectRBACSources(
              storedUser
            );

          /*
           * Add direct auth user
           * explicitly.
           */

          if (
            authUser
          ) {

            sources.push(
              authUser
            );

          }

          /*
           * ------------------------------------------------------
           * ROLES
           * ------------------------------------------------------
           */

          const roles =
            new Set();

          sources.forEach(
            source => {

              if (
                Array.isArray(
                  source
                )
              ) {

                extractRoleCodes(
                  source
                ).forEach(
                  role =>
                    roles.add(
                      role
                    )
                );

                return;

              }

              if (
                source &&
                Array.isArray(
                  source.roles
                )
              ) {

                extractRoleCodes(
                  source.roles
                ).forEach(
                  role =>
                    roles.add(
                      role
                    )
                );

              }

              if (
                source &&
                Array.isArray(
                  source.user_roles
                )
              ) {

                extractRoleCodes(
                  source.user_roles
                ).forEach(
                  role =>
                    roles.add(
                      role
                    )
                );

              }
            }
          );

          currentRoles =
            Array.from(
              roles
            );

          /*
           * ------------------------------------------------------
           * PERMISSIONS
           * ------------------------------------------------------
           */

          const permissions =
            new Set();

          sources.forEach(
            source => {

              if (
                Array.isArray(
                  source
                )
              ) {

                extractPermissionCodes(
                  source
                ).forEach(
                  permission =>
                    permissions.add(
                      permission
                    )
                );

                return;

              }

              if (
                source &&
                Array.isArray(
                  source.permissions
                )
              ) {

                extractPermissionCodes(
                  source.permissions
                ).forEach(
                  permission =>
                    permissions.add(
                      permission
                    )
                );

              }

              if (
                source &&
                Array.isArray(
                  source.user_roles
                )
              ) {

                extractPermissionCodes(
                  source.user_roles
                ).forEach(
                  permission =>
                    permissions.add(
                      permission
                    )
                );

              }

              if (
                source &&
                Array.isArray(
                  source.roles
                )
              ) {

                extractPermissionCodes(
                  source.roles
                ).forEach(
                  permission =>
                    permissions.add(
                      permission
                    )
                );

              }
            }
          );

          currentPermissions =
            permissions;

          /*
           * ------------------------------------------------------
           * IMPORTANT
           * ------------------------------------------------------
           *
           * A valid authenticated user may have zero frontend
           * permissions. That is not the same as a broken session.
           *
           * Therefore we DO NOT logout here.
           * ------------------------------------------------------
           */

          rbacLoaded =
            true;

          console.log(
            "IDMC frontend RBAC loaded:",
            {
              user:
                currentUser,

              roles:
                currentRoles,

              permissions:
                Array.from(
                  currentPermissions
                ),

              permissionCount:
                currentPermissions.size,

              roleCount:
                currentRoles.length,

              loaded:
                rbacLoaded
            }
          );

          return {
            user:
              currentUser,

            roles:
              currentRoles,

            permissions:
              Array.from(
                currentPermissions
              )
          };

        } catch (error) {

          console.error(
            "Frontend RBAC loading failed:",
            error
          );

          /*
           * Do not destroy authenticated session.
           */

          currentUser =
            null;

          currentRoles =
            [];

          currentPermissions =
            new Set();

          rbacLoaded =
            false;

          return {
            user:
              null,

            roles:
              [],

            permissions:
              []
          };

        } finally {

          rbacLoadPromise =
            null;

        }

      })();

    return rbacLoadPromise;
  }

  /* ============================================================
     ENSURE RBAC READY
  ============================================================ */

  async function ensureRBACLoaded() {

    if (
      rbacLoaded
    ) {

      return {
        user:
          currentUser,

        roles:
          currentRoles,

        permissions:
          Array.from(
            currentPermissions
          )
      };

    }

    return loadCurrentUserRBAC();
  }

  /* ============================================================
     PERMISSION CHECK
  ============================================================ */

  function hasPermission(
    permissionCode
  ) {

    const code =
      normalizePermissionCode(
        permissionCode
      );

    if (!code) {
      return false;
    }

    return currentPermissions.has(
      code
    );
  }

  /* ============================================================
     ANY PERMISSION
  ============================================================ */

  function hasAnyPermission(
    permissionCodes
  ) {

    if (
      !Array.isArray(
        permissionCodes
      )
    ) {

      return false;

    }

    return permissionCodes.some(
      permissionCode =>
        hasPermission(
          permissionCode
        )
    );
  }

  /* ============================================================
     ALL PERMISSIONS
  ============================================================ */

  function hasAllPermissions(
    permissionCodes
  ) {

    if (
      !Array.isArray(
        permissionCodes
      )
    ) {

      return false;

    }

    return permissionCodes.every(
      permissionCode =>
        hasPermission(
          permissionCode
        )
    );
  }

  /* ============================================================
     ROLE CHECK
  ============================================================ */

  function hasRole(
    roleCode
  ) {

    const normalized =
      normalizeRoleCode(
        roleCode
      );

    if (!normalized) {
      return false;
    }

    return currentRoles.some(
      role =>
        normalizeRoleCode(
          role
        ) === normalized
    );
  }

  /* ============================================================
     ANY ROLE
  ============================================================ */

  function hasAnyRole(
    roleCodes
  ) {

    if (
      !Array.isArray(
        roleCodes
      )
    ) {

      return false;

    }

    return roleCodes.some(
      roleCode =>
        hasRole(
          roleCode
        )
    );
  }

  /* ============================================================
     UI VISIBILITY
  ============================================================ */

  function setElementPermissionState(
    element,
    allowed
  ) {

    if (!element) {
      return;
    }

    element.hidden =
      !allowed;

    element.setAttribute(
      "aria-hidden",
      allowed
        ? "false"
        : "true"
    );
  }

  function applyPermissionVisibility(
    root = document
  ) {

    if (!root) {
      return;
    }

    /*
     * data-permission
     */

    root
      .querySelectorAll(
        "[data-permission]"
      )
      .forEach(
        element => {

          const required =
            element.getAttribute(
              "data-permission"
            );

          setElementPermissionState(
            element,
            hasPermission(
              required
            )
          );

        }
      );

    /*
     * data-permissions-any
     */

    root
      .querySelectorAll(
        "[data-permissions-any]"
      )
      .forEach(
        element => {

          const value =
            element.getAttribute(
              "data-permissions-any"
            ) || "";

          const permissions =
            value
              .split(",")
              .map(
                item =>
                  item.trim()
              )
              .filter(Boolean);

          setElementPermissionState(
            element,
            hasAnyPermission(
              permissions
            )
          );

        }
      );

    /*
     * data-permissions-all
     */

    root
      .querySelectorAll(
        "[data-permissions-all]"
      )
      .forEach(
        element => {

          const value =
            element.getAttribute(
              "data-permissions-all"
            ) || "";

          const permissions =
            value
              .split(",")
              .map(
                item =>
                  item.trim()
              )
              .filter(Boolean);

          setElementPermissionState(
            element,
            hasAllPermissions(
              permissions
            )
          );

        }
      );

    /*
     * data-role
     */

    root
      .querySelectorAll(
        "[data-role]"
      )
      .forEach(
        element => {

          const required =
            element.getAttribute(
              "data-role"
            );

          setElementPermissionState(
            element,
            hasRole(
              required
            )
          );

        }
      );

    /*
     * data-roles-any
     */

    root
      .querySelectorAll(
        "[data-roles-any]"
      )
      .forEach(
        element => {

          const value =
            element.getAttribute(
              "data-roles-any"
            ) || "";

          const roles =
            value
              .split(",")
              .map(
                item =>
                  item.trim()
              )
              .filter(Boolean);

          setElementPermissionState(
            element,
            hasAnyRole(
              roles
            )
          );

        }
      );
  }

  /* ============================================================
     PAGE PERMISSION
  ============================================================ */

  async function requireRBACPage(
    permissionCode
  ) {

    try {

      /*
       * ---------------------------------------------------------
       * 1. AUTH SESSION
       * ---------------------------------------------------------
       */

      if (
        !getSessionToken()
      ) {

        goToLogin();

        return false;

      }

      /*
       * ---------------------------------------------------------
       * 2. LOAD RBAC
       * ---------------------------------------------------------
       */

      await ensureRBACLoaded();

      /*
       * ---------------------------------------------------------
       * 3. CHECK
       * ---------------------------------------------------------
       */

      const allowed =
        hasPermission(
          permissionCode
        );

      if (allowed) {

        return true;

      }

      /*
       * ---------------------------------------------------------
       * 4. ACCESS RESTRICTED
       * ---------------------------------------------------------
       */

      document.documentElement.style.visibility =
        "visible";

      document.body.innerHTML = `
        <div
          style="
            min-height:100vh;
            display:flex;
            align-items:center;
            justify-content:center;
            background:#faf7f7;
            font-family:Inter,system-ui,sans-serif;
            padding:24px;
            box-sizing:border-box;
          "
        >
          <div
            style="
              width:100%;
              max-width:560px;
              background:#ffffff;
              border:1px solid #e8dee1;
              padding:40px;
              text-align:center;
              box-shadow:0 10px 22px rgba(51,9,20,.11);
              box-sizing:border-box;
            "
          >
            <div
              style="
                width:54px;
                height:54px;
                margin:0 auto 18px;
                border-radius:50%;
                display:flex;
                align-items:center;
                justify-content:center;
                background:#f5e8eb;
                color:#7c1830;
                font-size:24px;
                font-weight:700;
              "
            >
              !
            </div>

            <h1
              style="
                margin:0;
                color:#4a0d1c;
                font-size:24px;
              "
            >
              Access Restricted
            </h1>

            <p
              style="
                margin:12px 0 0;
                color:#7c6165;
                line-height:1.7;
              "
            >
              You do not have permission to access
              this module.
            </p>

            <p
              style="
                margin:8px 0 24px;
                color:#a58a8e;
                font-size:13px;
              "
            >
              Required permission:
              <strong>
                ${String(
                  permissionCode
                )}
              </strong>
            </p>

            <button
              type="button"
              onclick="window.location.href='dashboard.html'"
              style="
                border:1px solid #7c1830;
                background:#7c1830;
                color:#ffffff;
                padding:10px 18px;
                cursor:pointer;
                font-weight:600;
              "
            >
              Return to Dashboard
            </button>
          </div>
        </div>
      `;

      return false;

    } catch (error) {

      console.error(
        "RBAC page protection failed:",
        error
      );

      return false;
    }
  }

  /* ============================================================
     ROLES API
  ============================================================ */

  async function listRoles() {
    return request(
      "/roles"
    );
  }

  async function getRole(
    roleId
  ) {

    return request(
      `/roles/${encodeURIComponent(
        roleId
      )}`
    );

  }

  async function listPermissions() {

    return request(
      "/roles/permissions"
    );

  }

  async function getRolePermissions(
    roleId
  ) {

    return request(
      `/roles/${encodeURIComponent(
        roleId
      )}/permissions`
    );

  }

  async function createRole(
    payload
  ) {

    return request(
      "/roles",
      {
        method:
          "POST",

        body:
          JSON.stringify(
            payload
          )
      }
    );

  }

  async function updateRole(
    roleId,
    payload
  ) {

    return request(
      `/roles/${encodeURIComponent(
        roleId
      )}`,
      {
        method:
          "PATCH",

        body:
          JSON.stringify(
            payload
          )
      }
    );

  }

  async function assignPermission(
    roleId,
    permissionId
  ) {

    return request(
      `/roles/${encodeURIComponent(
        roleId
      )}/permissions`,
      {
        method:
          "POST",

        body:
          JSON.stringify({
            permissionId
          })
      }
    );

  }

  async function removePermission(
    roleId,
    permissionId
  ) {

    return request(
      `/roles/${encodeURIComponent(
        roleId
      )}/permissions/${encodeURIComponent(
        permissionId
      )}`,
      {
        method:
          "DELETE"
      }
    );

  }

  /* ============================================================
     DEBUG / STATE
     ------------------------------------------------------------
     Useful for diagnosing frontend RBAC without exposing tokens.
  ============================================================ */

  function getRBACState() {

    return {
      loaded:
        rbacLoaded,

      user:
        currentUser,

      roles:
        [...currentRoles],

      permissions:
        Array.from(
          currentPermissions
        ),

      permissionCount:
        currentPermissions.size,

      roleCount:
        currentRoles.length
    };
  }

  /* ============================================================
     PUBLIC API
  ============================================================ */

  window.IDMC_RBAC_API = {

    request,

    loadCurrentUserRBAC,

    ensureRBACLoaded,

    hasPermission,

    hasAnyPermission,

    hasAllPermissions,

    hasRole,

    hasAnyRole,

    requireRBACPage,

    listRoles,

    getRole,

    listPermissions,

    getRolePermissions,

    createRole,

    updateRole,

    assignPermission,

    removePermission,

    applyPermissionVisibility,

    getSessionToken,

    getStoredUser,

    getRBACState

  };

  /* ============================================================
     AUTO APPLY
  ============================================================ */

  async function autoApplyRBAC() {

    try {

      /*
       * Only apply UI permissions if a session exists.
       * This prevents an empty RBAC state from immediately
       * hiding everything before authentication finishes.
       */

      if (
        getSessionToken()
      ) {

        await ensureRBACLoaded();

        applyPermissionVisibility();

      }

    } catch (error) {

      console.error(
        "RBAC UI initialization failed:",
        error
      );

    }
  }

  if (
    document.readyState ===
    "loading"
  ) {

    document.addEventListener(
      "DOMContentLoaded",
      autoApplyRBAC,
      {
        once: true
      }
    );

  } else {

    autoApplyRBAC();

  }

})();