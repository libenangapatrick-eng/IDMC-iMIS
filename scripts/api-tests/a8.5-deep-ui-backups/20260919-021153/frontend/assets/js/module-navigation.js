(() => {
    "use strict";

    const MODULES = [{"Key":"admissions","Title":"Admissions","Permission":"admissions.view","Icon":"AD","Group":"Academic"},{"Key":"registration","Title":"Registration","Permission":"registration.view","Icon":"RG","Group":"Academic"},{"Key":"attendance","Title":"Attendance","Permission":"attendance.view","Icon":"AT","Group":"Academic"},{"Key":"assessment","Title":"Assessment","Permission":"examinations.view","Icon":"AS","Group":"Academic"},{"Key":"examinations","Title":"Examinations","Permission":"examinations.view","Icon":"EX","Group":"Academic"},{"Key":"results","Title":"Results","Permission":"results.view","Icon":"RS","Group":"Academic"},{"Key":"timetable","Title":"Timetable","Permission":"timetable.view","Icon":"TT","Group":"Academic"},{"Key":"finance","Title":"Finance","Permission":"finance.view","Icon":"FN","Group":"Administration"},{"Key":"communications","Title":"Communications","Permission":"communications.view","Icon":"CM","Group":"Administration"},{"Key":"library","Title":"Library","Permission":"library.view","Icon":"LB","Group":"Services"},{"Key":"hostel","Title":"Hostel","Permission":"hostel.view","Icon":"HS","Group":"Services"},{"Key":"hr","Title":"Human Resources","Permission":"hr.view","Icon":"HR","Group":"Administration"},{"Key":"research","Title":"Research","Permission":"research.view","Icon":"RE","Group":"Academic"},{"Key":"graduation","Title":"Graduation","Permission":"graduation.view","Icon":"GR","Group":"Academic"},{"Key":"alumni","Title":"Alumni","Permission":"alumni.view","Icon":"AL","Group":"Services"},{"Key":"transcripts","Title":"Transcripts","Permission":"documents.view","Icon":"TR","Group":"Academic"},{"Key":"operations","Title":"Operations","Permission":"procurement.view","Icon":"OP","Group":"Administration"},{"Key":"reports","Title":"Reports","Permission":"audit.view","Icon":"RP","Group":"System"},{"Key":"system","Title":"System","Permission":"system.view","Icon":"SY","Group":"System"}];

    const state = {
        permissions: new Map(),
        visibleModules: []
    };

    function normalize(value) {
        return String(
            value ?? ""
        ).trim();
    }

    function currentFile() {
        const path =
            window.location.pathname
                .split("/")
                .pop();

        return normalize(path)
            .toLowerCase();
    }

    function currentModule() {
        const file = currentFile();

        const match =
            MODULES.find(
                item =>
                    `${item.Key}.html`
                        .toLowerCase() === file
            );

        return match?.Key || null;
    }

    async function permissionAllowed(permission) {

        if (!permission) {
            return true;
        }

        if (
            state.permissions.has(
                permission
            )
        ) {
            return state.permissions.get(
                permission
            );
        }

        let allowed = false;

        try {

            const api =
                window.IDMC_RBAC_API;

            if (
                api &&
                typeof api.hasPermission ===
                    "function"
            ) {
                allowed =
                    Boolean(
                        await api.hasPermission(
                            permission
                        )
                    );
            }
            else {
                /*
                 * Fail closed when permission state
                 * cannot be verified.
                 */
                allowed = false;
            }
        }
        catch (error) {

            console.error(
                "Navigation permission check failed:",
                permission,
                error
            );

            allowed = false;
        }

        state.permissions.set(
            permission,
            allowed
        );

        return allowed;
    }

    async function resolveVisibleModules() {

        const visible = [];

        for (const module of MODULES) {

            const allowed =
                await permissionAllowed(
                    module.Permission
                );

            if (allowed) {
                visible.push(module);
            }
        }

        state.visibleModules =
            visible;

        return visible;
    }

    function groupModules(modules) {

        const groups =
            new Map();

        for (const module of modules) {

            const group =
                normalize(
                    module.Group
                ) || "Modules";

            if (!groups.has(group)) {
                groups.set(
                    group,
                    []
                );
            }

            groups
                .get(group)
                .push(module);
        }

        return groups;
    }

    function createModuleLink(module) {

        const link =
            document.createElement(
                "a"
            );

        link.className =
            "idmc-module-nav-link";

        link.href =
            `${module.Key}.html`;

        link.dataset.module =
            module.Key;

        link.dataset.permission =
            module.Permission || "";

        if (
            currentModule() ===
            module.Key
        ) {
            link.setAttribute(
                "aria-current",
                "page"
            );
        }

        const icon =
            document.createElement(
                "span"
            );

        icon.className =
            "idmc-module-nav-icon";

        icon.textContent =
            module.Icon ||
            module.Title
                .slice(0, 2)
                .toUpperCase();

        const copy =
            document.createElement(
                "span"
            );

        copy.className =
            "idmc-module-nav-copy";

        const title =
            document.createElement(
                "span"
            );

        title.className =
            "idmc-module-nav-title";

        title.textContent =
            module.Title;

        const subtitle =
            document.createElement(
                "span"
            );

        subtitle.className =
            "idmc-module-nav-subtitle";

        subtitle.textContent =
            module.Group;

        copy.append(
            title,
            subtitle
        );

        link.append(
            icon,
            copy
        );

        return link;
    }

    function renderInto(
        host,
        modules
    ) {

        if (!host) {
            return;
        }

        host.innerHTML = "";

        host.classList.add(
            "idmc-module-navigation"
        );

        if (!modules.length) {

            const empty =
                document.createElement(
                    "div"
                );

            empty.className =
                "idmc-module-navigation-empty";

            empty.textContent =
                "No modules are available for the current account.";

            host.appendChild(empty);

            return;
        }

        const groups =
            groupModules(modules);

        for (
            const [group, items]
            of groups
        ) {

            const section =
                document.createElement(
                    "section"
                );

            section.className =
                "idmc-module-nav-group";

            const heading =
                document.createElement(
                    "h3"
                );

            heading.className =
                "idmc-module-nav-heading";

            heading.textContent =
                group;

            const list =
                document.createElement(
                    "div"
                );

            list.className =
                "idmc-module-nav-list";

            for (const module of items) {

                list.appendChild(
                    createModuleLink(
                        module
                    )
                );
            }

            section.append(
                heading,
                list
            );

            host.appendChild(
                section
            );
        }
    }

    function ensureDashboardHost() {

        if (
            currentFile() !==
            "dashboard.html"
        ) {
            return null;
        }

        let host =
            document.querySelector(
                "[data-idmc-dashboard-modules]"
            );

        if (host) {
            return host;
        }

        const shell =
            document.createElement(
                "section"
            );

        shell.className =
            "idmc-dashboard-module-shell";

        shell.dataset
            .idmcDashboardModuleShell =
            "true";

        const header =
            document.createElement(
                "div"
            );

        header.className =
            "idmc-dashboard-module-header";

        const copy =
            document.createElement(
                "div"
            );

        const heading =
            document.createElement(
                "h2"
            );

        heading.textContent =
            "Modules";

        const description =
            document.createElement(
                "p"
            );

        description.textContent =
            "Open the modules available to your account.";

        copy.append(
            heading,
            description
        );

        const count =
            document.createElement(
                "span"
            );

        count.className =
            "idmc-dashboard-module-count";

        count.dataset
            .idmcModuleCount =
            "true";

        count.textContent = "0";

        header.append(
            copy,
            count
        );

        host =
            document.createElement(
                "div"
            );

        host.dataset
            .idmcDashboardModules =
            "true";

        const loading =
            document.createElement(
                "div"
            );

        loading.className =
            "idmc-module-navigation-loading";

        loading.textContent =
            "Loading modules...";

        host.appendChild(
            loading
        );

        shell.append(
            header,
            host
        );

        const main =
            document.querySelector(
                "main"
            ) ||
            document.querySelector(
                "[role='main']"
            ) ||
            document.body;

        main.appendChild(shell);

        return host;
    }

    function renderModulePageNavigation(
        modules
    ) {

        const hosts =
            document.querySelectorAll(
                "[data-idmc-module-navigation]"
            );

        for (const host of hosts) {
            renderInto(
                host,
                modules
            );
        }
    }

    async function boot() {

        const dashboardHost =
            ensureDashboardHost();

        const modules =
            await resolveVisibleModules();

        if (dashboardHost) {

            renderInto(
                dashboardHost,
                modules
            );

            const count =
                document.querySelector(
                    "[data-idmc-module-count]"
                );

            if (count) {
                count.textContent =
                    String(
                        modules.length
                    );
            }
        }

        renderModulePageNavigation(
            modules
        );

        window.dispatchEvent(
            new CustomEvent(
                "idmc:navigation:ready",
                {
                    detail: {
                        modules,
                        currentModule:
                            currentModule()
                    }
                }
            )
        );
    }

    window.IDMCModuleNavigation = {
        boot,

        getModules() {
            return [
                ...state.visibleModules
            ];
        },

        getCurrentModule() {
            return currentModule();
        },

        async canAccess(moduleKey) {

            const module =
                MODULES.find(
                    item =>
                        item.Key ===
                        moduleKey
                );

            if (!module) {
                return false;
            }

            return permissionAllowed(
                module.Permission
            );
        }
    };

    if (
        document.readyState ===
        "loading"
    ) {
        document.addEventListener(
            "DOMContentLoaded",
            boot
        );
    }
    else {
        boot();
    }
})();