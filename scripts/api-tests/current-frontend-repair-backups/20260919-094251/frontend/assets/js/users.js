(() => {
    "use strict";

    const API_BASE =
        window.IDMC_CONFIG?.API_BASE_URL ||
        "http://localhost:4000/api/v1";

    let users = [];
    let roles = [];
    let selectedUser = null;

    const $ = (selector) => document.querySelector(selector);

    function getToken() {
        return window.IDMCAuth?.getAccessToken?.() || "";
    }

    async function apiRequest(url, options = {}) {
        const headers = {
            "Content-Type": "application/json",
            Authorization: `Bearer ${getToken()}`,
            ...(options.headers || {})
        };

        const response = await fetch(`${API_BASE}${url}`, {
            ...options,
            headers
        });

        let result = {};

        try {
            result = await response.json();
        } catch {
            result = {};
        }

        if (!response.ok) {
            throw new Error(
                result.message ||
                result.error ||
                `Request failed (${response.status})`
            );
        }

        return result;
    }

    function escapeHtml(value) {
        return String(value ?? "")
            .replaceAll("&", "&amp;")
            .replaceAll("<", "&lt;")
            .replaceAll(">", "&gt;")
            .replaceAll('"', "&quot;")
            .replaceAll("'", "&#039;");
    }

    function getUserDisplayName(user) {
        return (
            user.display_name ||
            `${user.first_name || ""} ${user.middle_name || ""} ${user.last_name || ""}`
                .replace(/\s+/g, " ")
                .trim() ||
            user.email ||
            "Unnamed User"
        );
    }

    function initials(user) {
        const name = getUserDisplayName(user);

        return (
            name
                .split(/\s+/)
                .filter(Boolean)
                .slice(0, 2)
                .map((part) => part.charAt(0).toUpperCase())
                .join("") || "U"
        );
    }

    function formatDate(value) {
        if (!value) {
            return "—";
        }

        const date = new Date(value);

        if (Number.isNaN(date.getTime())) {
            return String(value);
        }

        return new Intl.DateTimeFormat("en-GB", {
            day: "2-digit",
            month: "short",
            year: "numeric"
        }).format(date);
    }

    function statusClass(status) {
        return String(status || "")
            .toLowerCase()
            .replaceAll("_", "-");
    }

    function roleNames(user) {
        if (!Array.isArray(user.roles) || !user.roles.length) {
            return "No role";
        }

        return user.roles
            .map((role) => role.role_name || role.role_code)
            .filter(Boolean)
            .join(", ");
    }

    function hasPermission(permission) {
        return Boolean(
            window.IDMCAuth?.hasPermission?.(permission)
        );
    }

    function showToast(message, type = "success") {
        const toast = $("#toast");

        if (!toast) {
            return;
        }

        toast.className = `toast ${type}`;
        toast.textContent = message;
        toast.classList.add("show");

        window.clearTimeout(showToast.timer);

        showToast.timer = window.setTimeout(() => {
            toast.classList.remove("show");
        }, 3500);
    }

    function updateStatistics(list = users) {
        const totalElement = $("#totalUsers");
        const activeElement = $("#activeUsers");
        const suspendedElement = $("#suspendedUsers");
        const pendingElement = $("#pendingUsers");

        const total = list.length;

        const active = list.filter(
            (user) => user.status === "ACTIVE"
        ).length;

        const suspended = list.filter(
            (user) => user.status === "SUSPENDED"
        ).length;

        const pending = list.filter(
            (user) => user.status === "PENDING"
        ).length;

        if (totalElement) {
            totalElement.textContent = total;
        }

        if (activeElement) {
            activeElement.textContent = active;
        }

        if (suspendedElement) {
            suspendedElement.textContent = suspended;
        }

        if (pendingElement) {
            pendingElement.textContent = pending;
        }
    }

    function renderUsers() {
        const tbody = $("#usersTableBody");

        if (!tbody) {
            return;
        }

        const searchInput = $("#searchUsers");
        const statusFilter = $("#statusFilter");
        const resultCount = $("#resultCount");

        const search = (
            searchInput?.value || ""
        )
            .trim()
            .toLowerCase();

        const status =
            statusFilter?.value || "ALL";

        const filtered = users.filter((user) => {
            const searchable = [
                user.user_number,
                user.username,
                user.display_name,
                user.first_name,
                user.middle_name,
                user.last_name,
                user.email,
                user.phone,
                roleNames(user)
            ]
                .filter(Boolean)
                .join(" ")
                .toLowerCase();

            const matchesSearch =
                !search ||
                searchable.includes(search);

            const matchesStatus =
                status === "ALL" ||
                user.status === status;

            return matchesSearch && matchesStatus;
        });

        updateStatistics(filtered);

        if (resultCount) {
            resultCount.textContent =
                `${filtered.length} user${filtered.length === 1 ? "" : "s"}`;
        }

        if (!filtered.length) {
            tbody.innerHTML = `
                <tr>
                    <td colspan="7" class="empty-state">
                        <div class="empty-icon">
                            <i class="fa-solid fa-users"></i>
                        </div>
                        <strong>No users found</strong>
                        <span>
                            Try changing your search or filter.
                        </span>
                    </td>
                </tr>
            `;

            return;
        }

        tbody.innerHTML = filtered
            .map((user) => {
                const displayName =
                    getUserDisplayName(user);

                const photo = user.profile_photo_url
                    ? `
                        <img
                            class="user-avatar"
                            src="${escapeHtml(user.profile_photo_url)}"
                            alt="${escapeHtml(displayName)}"
                            loading="lazy"
                            decoding="async"
                            onerror="this.style.display='none'; this.nextElementSibling.style.display='grid';"
                        >
                        <div
                            class="user-avatar initials"
                            style="display:none"
                        >
                            ${escapeHtml(initials(user))}
                        </div>
                    `
                    : `
                        <div class="user-avatar initials">
                            ${escapeHtml(initials(user))}
                        </div>
                    `;

                const editButton =
                    hasPermission("users.update")
                        ? `
                            <button
                                type="button"
                                class="icon-btn"
                                title="Edit user"
                                aria-label="Edit user"
                                data-action="edit"
                                data-id="${escapeHtml(user.id)}"
                            >
                                <i class="fa-regular fa-pen-to-square"></i>
                            </button>
                        `
                        : "";

                const rolesButton =
                    hasPermission("roles.manage")
                        ? `
                            <button
                                type="button"
                                class="icon-btn"
                                title="Manage roles"
                                aria-label="Manage roles"
                                data-action="roles"
                                data-id="${escapeHtml(user.id)}"
                            >
                                <i class="fa-solid fa-user-shield"></i>
                            </button>
                        `
                        : "";

                const roleChips =
                    Array.isArray(user.roles) &&
                    user.roles.length
                        ? user.roles
                            .slice(0, 2)
                            .map(
                                (role) => `
                                    <span class="role-chip">
                                        ${escapeHtml(
                                            role.role_name ||
                                            role.role_code ||
                                            "Role"
                                        )}
                                    </span>
                                `
                            )
                            .join("")
                        : `
                            <span class="muted">
                                No role
                            </span>
                        `;

                const roleMore =
                    Array.isArray(user.roles) &&
                    user.roles.length > 2
                        ? `
                            <span class="role-more">
                                +${user.roles.length - 2}
                            </span>
                        `
                        : "";

                return `
                    <tr>
                        <td>
                            <div class="user-cell">
                                ${photo}

                                <div class="user-primary">
                                    <strong>
                                        ${escapeHtml(displayName)}
                                    </strong>

                                    <span>
                                        ${escapeHtml(
                                            user.email ||
                                            "No email"
                                        )}
                                    </span>
                                </div>
                            </div>
                        </td>

                        <td>
                            <span class="user-number">
                                ${escapeHtml(
                                    user.user_number || "—"
                                )}
                            </span>
                        </td>

                        <td>
                            <div class="role-list">
                                ${roleChips}
                                ${roleMore}
                            </div>
                        </td>

                        <td>
                            <span
                                class="status-badge ${statusClass(user.status)}"
                            >
                                <span class="status-dot"></span>
                                ${escapeHtml(
                                    user.status || "UNKNOWN"
                                )}
                            </span>
                        </td>

                        <td>
                            ${escapeHtml(
                                user.phone || "—"
                            )}
                        </td>

                        <td>
                            <span class="date-value">
                                ${formatDate(
                                    user.created_at
                                )}
                            </span>
                        </td>

                        <td>
                            <div class="row-actions">

                                <button
                                    type="button"
                                    class="icon-btn"
                                    title="View user"
                                    aria-label="View user"
                                    data-action="view"
                                    data-id="${escapeHtml(user.id)}"
                                >
                                    <i class="fa-regular fa-eye"></i>
                                </button>

                                ${editButton}

                                ${rolesButton}

                            </div>
                        </td>
                    </tr>
                `;
            })
            .join("");
    }

    function setLoading(loading) {
        const button = $("#refreshUsers");

        if (!button) {
            return;
        }

        if (loading) {
            button.classList.add("loading");
            button.disabled = true;
            button.innerHTML = `
                <i class="fa-solid fa-spinner fa-spin"></i>
                Loading
            `;
        } else {
            button.classList.remove("loading");
            button.disabled = false;
            button.innerHTML = `
                <i class="fa-solid fa-rotate"></i>
                Refresh
            `;
        }
    }

    async function loadUsers() {
        try {
            setLoading(true);

            const result =
                await apiRequest("/users");

            users =
                Array.isArray(result.data)
                    ? result.data
                    : [];

            renderUsers();

        } catch (error) {
            console.error(
                "Failed to load users:",
                error
            );

            showToast(
                error.message ||
                "Failed to load users",
                "error"
            );

            const tbody =
                $("#usersTableBody");

            if (tbody) {
                tbody.innerHTML = `
                    <tr>
                        <td
                            colspan="7"
                            class="empty-state error-state"
                        >
                            <div class="empty-icon">
                                <i class="fa-solid fa-triangle-exclamation"></i>
                            </div>

                            <strong>
                                Unable to load users
                            </strong>

                            <span>
                                ${escapeHtml(
                                    error.message ||
                                    "Unknown error"
                                )}
                            </span>
                        </td>
                    </tr>
                `;
            }

        } finally {
            setLoading(false);
        }
    }

    async function loadRoles() {
        try {
            const result =
                await apiRequest("/users/roles");

            roles =
                Array.isArray(result.data)
                    ? result.data
                    : [];

            populateRoleSelect(
                $("#roleSelect"),
                roles,
                "Select role"
            );

        } catch (error) {
            console.error(
                "Failed to load roles:",
                error
            );
        }
    }

    function populateRoleSelect(
        select,
        roleData,
        emptyText = "Select role"
    ) {
        if (!select) {
            return;
        }

        select.innerHTML = `
            <option value="">
                ${escapeHtml(emptyText)}
            </option>
        `;

        roleData.forEach((role) => {
            const option =
                document.createElement("option");

            option.value = role.id;

            option.textContent =
                role.role_name ||
                role.role_code ||
                "Role";

            select.appendChild(option);
        });
    }

    function openModal(id) {
        const modal =
            document.getElementById(id);

        if (!modal) {
            return;
        }

        modal.classList.add("open");
        document.body.classList.add("modal-open");

        const firstInput =
            modal.querySelector(
                "input:not([type='hidden']), select"
            );

        if (firstInput) {
            window.setTimeout(() => {
                try {
                    firstInput.focus();
                } catch {
                    return;
                }
            }, 100);
        }
    }

    function closeModal(id) {
        const modal =
            document.getElementById(id);

        if (!modal) {
            return;
        }

        modal.classList.remove("open");

        if (
            !document.querySelector(
                ".modal-overlay.open"
            )
        ) {
            document.body.classList.remove(
                "modal-open"
            );
        }
    }

    function closeAllModals() {
        document
            .querySelectorAll(
                ".modal-overlay.open"
            )
            .forEach((modal) => {
                modal.classList.remove("open");
            });

        document.body.classList.remove(
            "modal-open"
        );
    }

    function findUser(id) {
        return users.find(
            (user) =>
                String(user.id) === String(id)
        );
    }

    function openViewUser(user) {
        selectedUser = user;

        const displayName =
            getUserDisplayName(user);

        const nameElement =
            $("#viewUserName");

        const numberElement =
            $("#viewUserNumber");

        const emailElement =
            $("#viewEmail");

        const phoneElement =
            $("#viewPhone");

        const usernameElement =
            $("#viewUsername");

        const statusElement =
            $("#viewStatus");

        const createdElement =
            $("#viewCreated");

        const lastLoginElement =
            $("#viewLastLogin");

        const rolesElement =
            $("#viewRoles");

        const initialsElement =
            $("#viewInitials");

        if (nameElement) {
            nameElement.textContent =
                displayName;
        }

        if (numberElement) {
            numberElement.textContent =
                user.user_number || "—";
        }

        if (emailElement) {
            emailElement.textContent =
                user.email || "—";
        }

        if (phoneElement) {
            phoneElement.textContent =
                user.phone || "—";
        }

        if (usernameElement) {
            usernameElement.textContent =
                user.username || "—";
        }

        if (statusElement) {
            statusElement.innerHTML = `
                <span
                    class="status-badge ${statusClass(user.status)}"
                >
                    <span class="status-dot"></span>
                    ${escapeHtml(
                        user.status || "UNKNOWN"
                    )}
                </span>
            `;
        }

        if (createdElement) {
            createdElement.textContent =
                formatDate(user.created_at);
        }

        if (lastLoginElement) {
            lastLoginElement.textContent =
                formatDate(user.last_login_at);
        }

        if (initialsElement) {
            initialsElement.textContent =
                initials(user);
        }

        if (rolesElement) {
            rolesElement.innerHTML =
                Array.isArray(user.roles) &&
                user.roles.length
                    ? user.roles
                        .map(
                            (role) => `
                                <span class="role-chip large">
                                    ${escapeHtml(
                                        role.role_name ||
                                        role.role_code ||
                                        "Role"
                                    )}
                                </span>
                            `
                        )
                        .join("")
                    : `
                        <span class="muted">
                            No assigned roles
                        </span>
                    `;
        }

        openModal("viewModal");
    }

    function openEditUser(user) {
        selectedUser = user;

        const fields = {
            "#editUserId": user.id,
            "#editFirstName": user.first_name || "",
            "#editMiddleName": user.middle_name || "",
            "#editLastName": user.last_name || "",
            "#editDisplayName": user.display_name || "",
            "#editUsername": user.username || "",
            "#editEmail": user.email || "",
            "#editPhone": user.phone || "",
            "#editStatus": user.status || "ACTIVE"
        };

        Object.entries(fields).forEach(
            ([selector, value]) => {
                const element = $(selector);

                if (element) {
                    element.value = value;
                }
            }
        );

        const title =
            $("#editUserTitle");

        if (title) {
            title.textContent =
                getUserDisplayName(user);
        }

        openModal("editModal");
    }

    function openRoles(user) {
        selectedUser = user;

        const nameElement =
            $("#roleUserName");

        if (nameElement) {
            nameElement.textContent =
                getUserDisplayName(user);
        }

        renderAssignedRoles(user);

        openModal("rolesModal");
    }

    function renderAssignedRoles(user) {
    const container =
        $("#assignedRoles");

    if (!container) {
        return;
    }

    /*
     * =====================================================
     * NORMALIZE USER ROLES
     * Backend returns:
     *
     * user.user_roles[].roles
     *
     * Frontend uses:
     *
     * user.roles[]
     * =====================================================
     */

    const rawAssignments =
        Array.isArray(user?.user_roles)
            ? user.user_roles
            : [];

    const assignedRoles =
        rawAssignments
            .filter((assignment) => {
                const status =
                    String(
                        assignment?.status ||
                        "ACTIVE"
                    ).toUpperCase();

                return status === "ACTIVE";
            })
            .map((assignment) => {
                const role =
                    assignment?.roles || {};

                return {
                    id:
                        assignment?.id ||
                        "",

                    initialRole:
                        role?.id ||
                        assignment?.role_id ||
                        "",

                    role_code:
                        role?.role_code ||
                        role?.code ||
                        "",

                    role_name:
                        role?.role_name ||
                        role?.name ||
                        "Unknown Role",

                    status:
                        assignment?.status ||
                        "ACTIVE",

                    expires_at:
                        assignment?.expires_at ||
                        null,

                    assigned_at:
                        assignment?.assigned_at ||
                        null
                };
            })
            .filter((role) => role.role_code);

    /*
     * Save normalized roles back to the user.
     *
     * This allows the rest of the frontend to use:
     *
     * user.roles[]
     *
     * consistently.
     */

    user.roles = assignedRoles;

    /*
     * =====================================================
     * EMPTY STATE
     * =====================================================
     */

    if (!assignedRoles.length) {
        container.innerHTML = `
            <div class="roles-empty">
                <i class="fa-solid fa-user-shield"></i>

                <span>
                    No roles assigned.
                </span>
            </div>
        `;

        return;
    }

    /*
     * =====================================================
     * RENDER ACTIVE ROLES
     * =====================================================
     */

    container.innerHTML =
        assignedRoles
            .map((role) => {
                const roleName =
                    escapeHtml(
                        role.role_name
                    );

                const roleCode =
                    escapeHtml(
                        role.role_code
                    );

                const status =
                    String(
                        role.status ||
                        "ACTIVE"
                    ).toUpperCase();

                let expiryText =
                    "No expiry";

                if (role.expires_at) {
                    const expiryDate =
                        new Date(
                            role.expires_at
                        );

                    if (
                        !Number.isNaN(
                            expiryDate.getTime()
                        )
                    ) {
                        expiryText =
                            `Expires ${formatDate(
                                role.expires_at
                            )}`;
                    }
                }

                return `
                    <div
                        class="assigned-role"
                        data-role-id="${escapeHtml(
                            role.id
                        )}"
                    >

                        <div class="assigned-role-info">

                            <div class="assigned-role-icon">
                                <i class="fa-solid fa-shield-halved"></i>
                            </div>

                            <div class="assigned-role-details">

                                <strong>
                                    ${roleName}
                                </strong>

                                <span>
                                    ${roleCode}
                                </span>

                                <small>
                                    ${escapeHtml(
                                        expiryText
                                    )}
                                </small>

                            </div>

                        </div>

                        <div class="assigned-role-actions">

                            <span
                                class="role-status active"
                            >
                                ${escapeHtml(
                                    status
                                )}
                            </span>

                            <button
                                type="button"
                                class="remove-role"
                                data-role-id="${escapeHtml(
                                    role.id ||
                                    role.role_id
                                )}"
                                title="Remove role"
                                aria-label="Remove role"
                            >
                                <i class="fa-solid fa-trash"></i>
                            </button>

                        </div>

                    </div>
                `;
            })
            .join("");
}
    async function saveUser(event) {
        event.preventDefault();

        if (!selectedUser) {
            return;
        }

        const button =
            $("#saveUserButton");

        try {
            if (button) {
                button.disabled = true;
                button.innerHTML = `
                    <i class="fa-solid fa-spinner fa-spin"></i>
                    Saving...
                `;
            }

            const body = {
                firstName:
                    $("#editFirstName")?.value.trim() ||
                    null,

                middleName:
                    $("#editMiddleName")?.value.trim() ||
                    null,

                lastName:
                    $("#editLastName")?.value.trim() ||
                    null,

                displayName:
                    $("#editDisplayName")?.value.trim() ||
                    null,

                username:
                    $("#editUsername")?.value.trim() ||
                    null,

                email:
                    $("#editEmail")?.value.trim() ||
                    null,

                phone:
                    $("#editPhone")?.value.trim() ||
                    null,

                status:
                    $("#editStatus")?.value ||
                    "ACTIVE"
            };

            await apiRequest(
                `/users/${encodeURIComponent(
                    selectedUser.id
                )}`,
                {
                    method: "PATCH",
                    body: JSON.stringify(body)
                }
            );

            closeModal("editModal");

            showToast(
                "User updated successfully."
            );

            await loadUsers();

        } catch (error) {
            console.error(
                "Failed to update user:",
                error
            );

            showToast(
                error.message ||
                "Failed to update user",
                "error"
            );

        } finally {
            if (button) {
                button.disabled = false;
                button.innerHTML = `
                    <i class="fa-solid fa-check"></i>
                    Save Changes
                `;
            }
        }
    }

    async function assignRole(event) {
        event.preventDefault();

        if (!selectedUser) {
            return;
        }

        const roleSelect =
            $("#roleSelect");

        const roleId =
            roleSelect?.value || "";

        if (!roleId) {
            showToast(
                "Please select a role.",
                "error"
            );

            return;
        }

        const selectedRole =
            roles.find(
                (role) =>
                    String(role.id) ===
                    String(roleId)
            );

        const roleCode =
            selectedRole?.role_code ||
            selectedRole?.roleCode ||
            roleId;

        const expiresAt = null;

        const payload = {
            roleCode: roleCode,
            expiresAt: expiresAt
        };

        console.log(
            "Assign role payload:",
            payload
        );

        const button =
            $("#assignRoleButton");

        try {
            if (button) {
                button.disabled = true;
                button.innerHTML = `
                    <i class="fa-solid fa-spinner fa-spin"></i>
                    Assigning...
                `;
            }

            await apiRequest(
                `/users/${encodeURIComponent(
                    selectedUser.id
                )}/roles`,
                {
                    method: "POST",
                    body: JSON.stringify(payload)
                }
            );

            showToast(
                "Role assigned successfully."
            );

            if (roleSelect) {
                roleSelect.value = "";
            }

            await loadUsers();

            selectedUser =
                findUser(selectedUser.id);

            if (selectedUser) {
                renderAssignedRoles(
                    selectedUser
                );
            }

        } catch (error) {
            console.error(
                "Failed to assign role:",
                error
            );

            showToast(
                error.message ||
                "Failed to assign role",
                "error"
            );

        } finally {
            if (button) {
                button.disabled = false;
                button.innerHTML = `
                    <i class="fa-solid fa-plus"></i>
                    Assign Role
                `;
            }
        }
    }

    async function removeRole(roleId) {
        if (!selectedUser || !roleId) {
            return;
        }

        const confirmed =
            window.confirm(
                "Are you sure you want to remove this role from the user?"
            );

        if (!confirmed) {
            return;
        }

        try {
            await apiRequest(
                `/users/${encodeURIComponent(
                    selectedUser.id
                )}/roles/${encodeURIComponent(
                    roleId
                )}`,
                {
                    method: "DELETE"
                }
            );

            showToast(
                "Role removed successfully."
            );

            await loadUsers();

            selectedUser =
                findUser(selectedUser.id);

            if (selectedUser) {
                renderAssignedRoles(
                    selectedUser
                );
            }

        } catch (error) {
            console.error(
                "Failed to remove role:",
                error
            );

            showToast(
                error.message ||
                "Failed to remove role",
                "error"
            );
        }
    }

    function createOpenModal() {
        const modal =
            document.getElementById(
                "createUserModal"
            );

        if (!modal) {
            return;
        }

        modal.classList.add("open");
        document.body.classList.add(
            "modal-open"
        );

        const success =
            document.getElementById(
                "createUserSuccess"
            );

        if (success) {
            success.classList.remove("show");
        }
    }

    function createCloseModal() {
        closeModal("createUserModal");
    }

    function resetCreateForm() {
        const form =
            document.getElementById(
                "createUserForm"
            );

        if (form) {
            form.reset();
        }

        const success =
            document.getElementById(
                "createUserSuccess"
            );

        if (success) {
            success.classList.remove("show");
        }

        const message =
            document.getElementById(
                "createdUserMessage"
            );

        if (message) {
            message.textContent = "";
        }

        const password =
            document.getElementById(
                "createPassword"
            );

        if (password) {
            password.type = "password";
        }

        const toggle =
            document.getElementById(
                "toggleCreatePassword"
            );

        if (toggle) {
            toggle.innerHTML = `
                <i class="fa-solid fa-eye"></i>
            `;
        }

        populateRoleSelect(
            document.getElementById(
                "createRole"
            ),
            roles,
            "No role"
        );
    }

    async function loadCreateRoles() {
        const select =
            document.getElementById(
                "createRole"
            );

        if (!select) {
            return;
        }

        try {
            const result =
                await apiRequest(
                    "/users/roles"
                );

            const roleData =
                Array.isArray(result.data)
                    ? result.data
                    : [];

            roles = roleData;

            populateRoleSelect(
                select,
                roleData,
                "No role"
            );

        } catch (error) {
            console.error(
                "Failed to load creation roles:",
                error
            );
        }
    }

    async function submitCreateUser(event) {
        event.preventDefault();

        const button =
            document.getElementById(
                "createUserButton"
            );

        const emailInput =
            document.getElementById(
                "createEmail"
            );

        const passwordInput =
            document.getElementById(
                "createPassword"
            );

        const email =
            emailInput?.value.trim() || "";

        const password =
            passwordInput?.value || "";

        if (!email) {
            showToast(
                "Email is required.",
                "error"
            );

            emailInput?.focus();

            return;
        }

        if (password.length < 6) {
            showToast(
                "Password must contain at least 6 characters.",
                "error"
            );

            passwordInput?.focus();

            return;
        }

        const getValue = (id) =>
            document
                .getElementById(id)
                ?.value
                .trim() || null;

        const payload = {
            email,
            password,

            username:
                getValue("createUsername"),

            firstName:
                getValue("createFirstName"),

            middleName:
                getValue("createMiddleName"),

            lastName:
                getValue("createLastName"),

            displayName:
                getValue("createDisplayName"),

            phone:
                getValue("createPhone"),

            initialRole:
                document.getElementById(
                    "createRole"
                )?.value || null,

            status:
                document.getElementById(
                    "createStatus"
                )?.value ||
                "ACTIVE"
        };

        try {
            if (button) {
                button.disabled = true;
                button.innerHTML = `
                    <i class="fa-solid fa-spinner fa-spin"></i>
                    Creating...
                `;
            }

            const result =
                await apiRequest(
                    "/users",
                    {
                        method: "POST",
                        body: JSON.stringify(
                            payload
                        )
                    }
                );

            const user =
                result.data || {};

            const success =
                document.getElementById(
                    "createUserSuccess"
                );

            const message =
                document.getElementById(
                    "createdUserMessage"
                );

            if (message) {
                message.innerHTML = `
                    User Number:
                    <strong>
                        ${escapeHtml(
                            user.user_number ||
                            "—"
                        )}
                    </strong>
                `;
            }

            if (success) {
                success.classList.add(
                    "show"
                );
            }

            window.dispatchEvent(
                new CustomEvent(
                    "idmc:user-created",
                    {
                        detail: user
                    }
                )
            );

            await loadUsers();

            if (button) {
                button.innerHTML = `
                    <i class="fa-solid fa-circle-check"></i>
                    Created
                `;
            }

            window.setTimeout(() => {
                resetCreateForm();
                createCloseModal();

                if (button) {
                    button.disabled = false;
                    button.innerHTML = `
                        <i class="fa-solid fa-user-plus"></i>
                        Create User
                    `;
                }
            }, 1200);

            showToast(
                "User created successfully."
            );

        } catch (error) {
            console.error(
                "Failed to create user:",
                error
            );

            showToast(
                error.message ||
                "Failed to create user.",
                "error"
            );

            if (button) {
                button.disabled = false;
                button.innerHTML = `
                    <i class="fa-solid fa-user-plus"></i>
                    Create User
                `;
            }
        }
    }

    async function initializeCreateUser() {
        const addButton =
            document.getElementById(
                "addUserButton"
            );

        if (
            addButton &&
            hasPermission("users.create")
        ) {
            addButton.style.display =
                "inline-flex";

            if (
                !addButton.dataset.bound
            ) {
                addButton.dataset.bound =
                    "true";

                addButton.addEventListener(
                    "click",
                    async () => {
                        resetCreateForm();
                        createOpenModal();
                        await loadCreateRoles();
                    }
                );
            }

        } else if (addButton) {
            addButton.style.display =
                "none";
        }

        const form =
            document.getElementById(
                "createUserForm"
            );

        if (
            form &&
            !form.dataset.bound
        ) {
            form.dataset.bound = "true";

            form.addEventListener(
                "submit",
                submitCreateUser
            );
        }

        const toggle =
            document.getElementById(
                "toggleCreatePassword"
            );

        if (
            toggle &&
            !toggle.dataset.bound
        ) {
            toggle.dataset.bound = "true";

            toggle.addEventListener(
                "click",
                () => {
                    const input =
                        document.getElementById(
                            "createPassword"
                        );

                    if (!input) {
                        return;
                    }

                    if (
                        input.type ===
                        "password"
                    ) {
                        input.type = "text";

                        toggle.innerHTML = `
                            <i class="fa-solid fa-eye-slash"></i>
                        `;

                        toggle.title =
                            "Hide password";

                    } else {
                        input.type = "password";

                        toggle.innerHTML = `
                            <i class="fa-solid fa-eye"></i>
                        `;

                        toggle.title =
                            "Show password";
                    }
                }
            );
        }
    }

    function bindModalCloseButtons() {
        document
            .querySelectorAll(
                "[data-close-modal]"
            )
            .forEach((button) => {
                if (button.dataset.bound) {
                    return;
                }

                button.dataset.bound = "true";

                button.addEventListener(
                    "click",
                    () => {
                        closeModal(
                            button.dataset
                                .closeModal
                        );
                    }
                );
            });
    }

    function bindModalOverlayEvents() {
        document
            .querySelectorAll(
                ".modal-overlay"
            )
            .forEach((modal) => {
                if (modal.dataset.bound) {
                    return;
                }

                modal.dataset.bound = "true";

                modal.addEventListener(
                    "click",
                    (event) => {
                        if (
                            event.target ===
                            modal
                        ) {
                            closeModal(
                                modal.id
                            );
                        }
                    }
                );
            });
    }

    function bindEvents() {
        const search =
            $("#searchUsers");

        if (
            search &&
            !search.dataset.bound
        ) {
            search.dataset.bound = "true";

            search.addEventListener(
                "input",
                renderUsers
            );
        }

        const status =
            $("#statusFilter");

        if (
            status &&
            !status.dataset.bound
        ) {
            status.dataset.bound = "true";

            status.addEventListener(
                "change",
                renderUsers
            );
        }

        const refresh =
            $("#refreshUsers");

        if (
            refresh &&
            !refresh.dataset.bound
        ) {
            refresh.dataset.bound = "true";

            refresh.addEventListener(
                "click",
                loadUsers
            );
        }

        const editForm =
            $("#editForm");

        if (
            editForm &&
            !editForm.dataset.bound
        ) {
            editForm.dataset.bound = "true";

            editForm.addEventListener(
                "submit",
                saveUser
            );
        }

        const roleForm =
            $("#roleForm");

        if (
            roleForm &&
            !roleForm.dataset.bound
        ) {
            roleForm.dataset.bound = "true";

            roleForm.addEventListener(
                "submit",
                assignRole
            );
        }

        const usersTableBody =
            $("#usersTableBody");

        if (
            usersTableBody &&
            !usersTableBody.dataset.bound
        ) {
            usersTableBody.dataset.bound =
                "true";

            usersTableBody.addEventListener(
                "click",
                (event) => {
                    const button =
                        event.target.closest(
                            "[data-action]"
                        );

                    if (!button) {
                        return;
                    }

                    const user =
                        findUser(
                            button.dataset.id
                        );

                    if (!user) {
                        return;
                    }

                    const action =
                        button.dataset.action;

                    if (
                        action === "view"
                    ) {
                        openViewUser(user);
                    }

                    if (
                        action === "edit"
                    ) {
                        if (
                            hasPermission(
                                "users.update"
                            )
                        ) {
                            openEditUser(
                                user
                            );
                        }
                    }

                    if (
                        action === "roles"
                    ) {
                        if (
                            hasPermission(
                                "roles.manage"
                            )
                        ) {
                            openRoles(user);
                        }
                    }
                }
            );
        }

        const assignedRoles =
            $("#assignedRoles");

        if (
            assignedRoles &&
            !assignedRoles.dataset.bound
        ) {
            assignedRoles.dataset.bound =
                "true";

            assignedRoles.addEventListener(
                "click",
                (event) => {
                    const button =
                        event.target.closest(
                            ".remove-role"
                        );

                    if (!button) {
                        return;
                    }

                    removeRole(
                        button.dataset
                            .roleId
                    );
                }
            );
        }

        bindModalCloseButtons();
        bindModalOverlayEvents();

        if (
            !document.body.dataset
                .idmcEscapeBound
        ) {
            document.body.dataset
                .idmcEscapeBound =
                "true";

            document.addEventListener(
                "keydown",
                (event) => {
                    if (
                        event.key ===
                        "Escape"
                    ) {
                        closeAllModals();
                    }
                }
            );
        }
    }

    async function initialize() {
        try {
            if (
                window.IDMCAuth &&
                typeof window.IDMCAuth.requireAuth ===
                    "function"
            ) {
                const authenticatedUser =
                    await window.IDMCAuth.requireAuth();

                if (!authenticatedUser) {
                    return;
                }
            }

            bindEvents();

            await initializeCreateUser();

            await Promise.all([
                loadUsers(),
                loadRoles()
            ]);

        } catch (error) {
            console.error(
                "Users initialization failed:",
                error
            );

            showToast(
                error.message ||
                "Failed to initialize Users page.",
                "error"
            );
        }
    }

    window.IDMC_USERS_RELOAD =
        async function () {
            try {
                await loadUsers();
            } catch (error) {
                console.error(
                    "Failed to reload users:",
                    error
                );
            }
        };

    window.IDMC_USERS = {
        reload: window.IDMC_USERS_RELOAD,
        loadUsers,
        loadRoles,
        findUser
    };

    if (
        document.readyState ===
        "loading"
    ) {
        document.addEventListener(
            "DOMContentLoaded",
            initialize,
            {
                once: true
            }
        );
    } else {
        initialize();
    }

})();
