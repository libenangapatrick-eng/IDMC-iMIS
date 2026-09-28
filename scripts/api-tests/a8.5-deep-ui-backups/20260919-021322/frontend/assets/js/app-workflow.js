(function () {
    "use strict";

    if (window.IDMCWorkflow) {
        return;
    }

    const state = {
        toastRegion: null,
        activeModal: null,
        lastFocused: null,
        booted: false
    };

    function text(value) {
        if (value === null || value === undefined) {
            return "";
        }

        return String(value);
    }

    function currentFile() {
        const path =
            window.location.pathname
                .split("/")
                .filter(Boolean);

        return path.length
            ? path[path.length - 1]
            : "dashboard.html";
    }

    function pageTitle() {
        const heading =
            document.querySelector(
                "h1"
            );

        if (
            heading &&
            heading.textContent.trim()
        ) {
            return heading.textContent.trim();
        }

        const title =
            document.title
                .replace(
                    /\s*[|\-â€“]\s*IDMC.*$/i,
                    ""
                )
                .trim();

        if (title) {
            return title;
        }

        return currentFile()
            .replace(/\.html$/i, "")
            .replace(/[-_]+/g, " ")
            .replace(
                /\b\w/g,
                char => char.toUpperCase()
            );
    }

    function ensureToastRegion() {
        if (state.toastRegion) {
            return state.toastRegion;
        }

        let region =
            document.querySelector(
                "[data-idmc-toast-region]"
            );

        if (!region) {
            region =
                document.createElement(
                    "div"
                );

            region.className =
                "idmc-toast-region";

            region.dataset.idmcToastRegion =
                "true";

            region.setAttribute(
                "role",
                "region"
            );

            region.setAttribute(
                "aria-label",
                "Notifications"
            );

            document.body.appendChild(
                region
            );
        }

        state.toastRegion = region;

        return region;
    }

    function toast(
        message,
        options = {}
    ) {
        const region =
            ensureToastRegion();

        const type =
            options.type ||
            "info";

        const item =
            document.createElement(
                "div"
            );

        item.className =
            "idmc-toast idmc-toast-" +
            type;

        item.setAttribute(
            "role",
            type === "error"
                ? "alert"
                : "status"
        );

        const copy =
            document.createElement(
                "div"
            );

        const title =
            document.createElement(
                "div"
            );

        title.className =
            "idmc-toast-title";

        title.textContent =
            options.title ||
            (
                type === "success"
                    ? "Completed"
                    : type === "error"
                        ? "Something went wrong"
                        : type === "warning"
                            ? "Attention"
                            : "Information"
            );

        const body =
            document.createElement(
                "p"
            );

        body.className =
            "idmc-toast-message";

        body.textContent =
            text(message);

        copy.append(
            title,
            body
        );

        const close =
            document.createElement(
                "button"
            );

        close.type = "button";
        close.className =
            "idmc-toast-close";

        close.setAttribute(
            "aria-label",
            "Dismiss notification"
        );

        close.textContent = "Ã—";

        close.addEventListener(
            "click",
            () => item.remove()
        );

        item.append(
            copy,
            close
        );

        region.appendChild(
            item
        );

        const timeout =
            Number(
                options.timeout ??
                (
                    type === "error"
                        ? 8000
                        : 4500
                )
            );

        if (
            Number.isFinite(timeout) &&
            timeout > 0
        ) {
            window.setTimeout(
                () => {
                    if (item.isConnected) {
                        item.remove();
                    }
                },
                timeout
            );
        }

        return item;
    }

    function closeModal(result) {
        const modal =
            state.activeModal;

        if (!modal) {
            return;
        }

        state.activeModal = null;

        document.body.classList.remove(
            "idmc-modal-open"
        );

        modal.backdrop.remove();

        if (
            state.lastFocused &&
            typeof state.lastFocused.focus ===
                "function"
        ) {
            state.lastFocused.focus();
        }

        const resolve =
            modal.resolve;

        state.lastFocused = null;

        resolve(result);
    }

    function confirm(options = {}) {
        if (state.activeModal) {
            closeModal(false);
        }

        state.lastFocused =
            document.activeElement;

        return new Promise(resolve => {
            const backdrop =
                document.createElement(
                    "div"
                );

            backdrop.className =
                "idmc-modal-backdrop";

            const modal =
                document.createElement(
                    "div"
                );

            modal.className =
                "idmc-modal";

            modal.setAttribute(
                "role",
                "dialog"
            );

            modal.setAttribute(
                "aria-modal",
                "true"
            );

            const header =
                document.createElement(
                    "div"
                );

            header.className =
                "idmc-modal-header";

            const title =
                document.createElement(
                    "h2"
                );

            title.className =
                "idmc-modal-title";

            title.textContent =
                options.title ||
                "Confirm action";

            const close =
                document.createElement(
                    "button"
                );

            close.type = "button";
            close.className =
                "idmc-modal-close";

            close.setAttribute(
                "aria-label",
                "Close"
            );

            close.textContent = "Ã—";

            header.append(
                title,
                close
            );

            const body =
                document.createElement(
                    "div"
                );

            body.className =
                "idmc-modal-body";

            body.textContent =
                options.message ||
                "Are you sure you want to continue?";

            const actions =
                document.createElement(
                    "div"
                );

            actions.className =
                "idmc-modal-actions";

            const cancel =
                document.createElement(
                    "button"
                );

            cancel.type = "button";
            cancel.className =
                "idmc-ui-button";

            cancel.textContent =
                options.cancelText ||
                "Cancel";

            const accept =
                document.createElement(
                    "button"
                );

            accept.type = "button";

            accept.className =
                options.danger
                    ? "idmc-ui-button idmc-ui-button-danger"
                    : "idmc-ui-button idmc-ui-button-primary";

            accept.textContent =
                options.confirmText ||
                "Continue";

            actions.append(
                cancel,
                accept
            );

            modal.append(
                header,
                body,
                actions
            );

            backdrop.appendChild(
                modal
            );

            document.body.appendChild(
                backdrop
            );

            document.body.classList.add(
                "idmc-modal-open"
            );

            state.activeModal = {
                backdrop,
                resolve
            };

            function cancelModal() {
                closeModal(false);
            }

            function acceptModal() {
                closeModal(true);
            }

            close.addEventListener(
                "click",
                cancelModal
            );

            cancel.addEventListener(
                "click",
                cancelModal
            );

            accept.addEventListener(
                "click",
                acceptModal
            );

            backdrop.addEventListener(
                "mousedown",
                event => {
                    if (
                        event.target ===
                        backdrop
                    ) {
                        cancelModal();
                    }
                }
            );

            modal.addEventListener(
                "keydown",
                event => {
                    if (
                        event.key ===
                        "Escape"
                    ) {
                        event.preventDefault();
                        cancelModal();
                        return;
                    }

                    if (
                        event.key !==
                        "Tab"
                    ) {
                        return;
                    }

                    const focusable =
                        Array.from(
                            modal.querySelectorAll(
                                "button:not([disabled]), " +
                                "[href], " +
                                "input:not([disabled]), " +
                                "select:not([disabled]), " +
                                "textarea:not([disabled]), " +
                                "[tabindex]:not([tabindex='-1'])"
                            )
                        );

                    if (!focusable.length) {
                        return;
                    }

                    const first =
                        focusable[0];

                    const last =
                        focusable[
                            focusable.length - 1
                        ];

                    if (
                        event.shiftKey &&
                        document.activeElement ===
                            first
                    ) {
                        event.preventDefault();
                        last.focus();
                    }
                    else if (
                        !event.shiftKey &&
                        document.activeElement ===
                            last
                    ) {
                        event.preventDefault();
                        first.focus();
                    }
                }
            );

            accept.focus();
        });
    }

    function setBusy(
        element,
        busy = true
    ) {
        if (!element) {
            return;
        }

        if (busy) {
            element.classList.add(
                "idmc-busy"
            );

            element.setAttribute(
                "aria-busy",
                "true"
            );

            if (
                "disabled" in element
            ) {
                element.dataset
                    .idmcPreviousDisabled =
                    element.disabled
                        ? "true"
                        : "false";

                element.disabled = true;
            }
        }
        else {
            element.classList.remove(
                "idmc-busy"
            );

            element.removeAttribute(
                "aria-busy"
            );

            if (
                "disabled" in element
            ) {
                const wasDisabled =
                    element.dataset
                        .idmcPreviousDisabled ===
                    "true";

                element.disabled =
                    wasDisabled;

                delete element.dataset
                    .idmcPreviousDisabled;
            }
        }
    }

    function clearFieldError(field) {
        if (!field) {
            return;
        }

        field.classList.remove(
            "idmc-invalid"
        );

        field.removeAttribute(
            "aria-invalid"
        );

        const id =
            field.dataset
                .idmcErrorId;

        if (id) {
            const node =
                document.getElementById(
                    id
                );

            if (node) {
                node.remove();
            }

            delete field.dataset
                .idmcErrorId;
        }
    }

    function fieldError(
        field,
        message
    ) {
        if (!field) {
            return;
        }

        clearFieldError(field);

        field.classList.add(
            "idmc-invalid"
        );

        field.setAttribute(
            "aria-invalid",
            "true"
        );

        const error =
            document.createElement(
                "div"
            );

        const id =
            "idmc-error-" +
            Math.random()
                .toString(36)
                .slice(2);

        error.id = id;
        error.className =
            "idmc-field-error";

        error.textContent =
            text(message);

        field.dataset.idmcErrorId =
            id;

        field.insertAdjacentElement(
            "afterend",
            error
        );
    }

    function validateForm(form) {
        if (!form) {
            return true;
        }

        let valid = true;
        let firstInvalid = null;

        const fields =
            form.querySelectorAll(
                "input, select, textarea"
            );

        for (const field of fields) {
            clearFieldError(field);

            if (
                field.disabled ||
                field.type === "hidden"
            ) {
                continue;
            }

            if (
                field.required &&
                !text(field.value).trim()
            ) {
                valid = false;

                fieldError(
                    field,
                    "This field is required."
                );

                firstInvalid =
                    firstInvalid ||
                    field;

                continue;
            }

            if (
                field.type === "email" &&
                field.value &&
                !field.validity.valid
            ) {
                valid = false;

                fieldError(
                    field,
                    "Enter a valid email address."
                );

                firstInvalid =
                    firstInvalid ||
                    field;

                continue;
            }

            if (
                !field.validity.valid
            ) {
                valid = false;

                fieldError(
                    field,
                    field.validationMessage ||
                    "Check this value."
                );

                firstInvalid =
                    firstInvalid ||
                    field;
            }
        }

        if (firstInvalid) {
            firstInvalid.focus();
        }

        return valid;
    }

    function wrapTables() {
        const tables =
            document.querySelectorAll(
                "table"
            );

        for (const table of tables) {
            if (
                table.parentElement &&
                table.parentElement
                    .classList.contains(
                        "idmc-table-scroll"
                    )
            ) {
                continue;
            }

            const wrapper =
                document.createElement(
                    "div"
                );

            wrapper.className =
                "idmc-table-scroll";

            table.parentNode.insertBefore(
                wrapper,
                table
            );

            wrapper.appendChild(
                table
            );
        }
    }

    function enhanceForms() {
        const forms =
            document.querySelectorAll(
                "form"
            );

        for (const form of forms) {
            form.setAttribute(
                "novalidate",
                "novalidate"
            );

            form.addEventListener(
                "input",
                event => {
                    const field =
                        event.target.closest(
                            "input, select, textarea"
                        );

                    if (field) {
                        clearFieldError(
                            field
                        );
                    }
                }
            );

            form.addEventListener(
                "submit",
                event => {
                    if (
                        !validateForm(form)
                    ) {
                        event.preventDefault();
                        event.stopImmediatePropagation();

                        toast(
                            "Please correct the highlighted fields.",
                            {
                                type: "warning",
                                title: "Form incomplete"
                            }
                        );
                    }
                },
                true
            );
        }
    }

    function buildToolbar() {
        if (
            document.querySelector(
                "[data-idmc-workflow-toolbar]"
            )
        ) {
            return;
        }

        const main =
            document.querySelector(
                "main"
            ) ||
            document.querySelector(
                "[role='main']"
            );

        if (!main) {
            return;
        }

        const toolbar =
            document.createElement(
                "section"
            );

        toolbar.className =
            "idmc-workflow-toolbar";

        toolbar.dataset
            .idmcWorkflowToolbar =
            "true";

        const left =
            document.createElement(
                "div"
            );

        left.className =
            "idmc-workflow-toolbar-left";

        const breadcrumb =
            document.createElement(
                "nav"
            );

        breadcrumb.className =
            "idmc-breadcrumb";

        breadcrumb.setAttribute(
            "aria-label",
            "Breadcrumb"
        );

        const dashboard =
            document.createElement(
                "a"
            );

        dashboard.href =
            "dashboard.html";

        dashboard.textContent =
            "Dashboard";

        const separator =
            document.createElement(
                "span"
            );

        separator.setAttribute(
            "aria-hidden",
            "true"
        );

        separator.textContent = "â€º";

        const current =
            document.createElement(
                "span"
            );

        current.className =
            "idmc-breadcrumb-current";

        current.textContent =
            pageTitle();

        breadcrumb.append(
            dashboard,
            separator,
            current
        );

        left.appendChild(
            breadcrumb
        );

        const right =
            document.createElement(
                "div"
            );

        right.className =
            "idmc-workflow-toolbar-right";

        const status =
            document.createElement(
                "span"
            );

        status.className =
            "idmc-page-status";

        const dot =
            document.createElement(
                "span"
            );

        dot.className =
            "idmc-page-status-dot";

        dot.setAttribute(
            "aria-hidden",
            "true"
        );

        const statusText =
            document.createElement(
                "span"
            );

        statusText.textContent =
            navigator.onLine
                ? "Online"
                : "Offline";

        status.append(
            dot,
            statusText
        );

        const refresh =
            document.createElement(
                "button"
            );

        refresh.type = "button";
        refresh.className =
            "idmc-ui-button";

        refresh.textContent =
            "Refresh";

        refresh.addEventListener(
            "click",
            () => {
                window.location.reload();
            }
        );

        right.append(
            status,
            refresh
        );

        toolbar.append(
            left,
            right
        );

        main.insertBefore(
            toolbar,
            main.firstChild
        );
    }

    function networkBanner(
        offline
    ) {
        let banner =
            document.querySelector(
                "[data-idmc-network-banner]"
            );

        if (!offline) {
            if (banner) {
                banner.remove();
            }

            return;
        }

        if (banner) {
            return;
        }

        banner =
            document.createElement(
                "div"
            );

        banner.className =
            "idmc-network-banner";

        banner.dataset
            .idmcNetworkBanner =
            "true";

        banner.setAttribute(
            "role",
            "status"
        );

        banner.textContent =
            "You are offline. Some actions may be unavailable.";

        document.body.appendChild(
            banner
        );
    }

    function bindNetworkState() {
        function update() {
            const offline =
                !navigator.onLine;

            networkBanner(
                offline
            );

            const status =
                document.querySelector(
                    ".idmc-page-status span:last-child"
                );

            if (status) {
                status.textContent =
                    offline
                        ? "Offline"
                        : "Online";
            }
        }

        window.addEventListener(
            "online",
            () => {
                update();

                toast(
                    "Connection restored.",
                    {
                        type: "success"
                    }
                );
            }
        );

        window.addEventListener(
            "offline",
            () => {
                update();

                toast(
                    "Network connection lost.",
                    {
                        type: "warning"
                    }
                );
            }
        );

        update();
    }

    function mutationAction(element) {
        const value =
            (
                element.dataset.action ||
                element.dataset.idmcRecordAction ||
                element.dataset.idmcAction ||
                ""
            )
                .toLowerCase();

        return value;
    }

    function bindDestructiveConfirmation() {
        document.addEventListener(
            "click",
            async event => {
                const target =
                    event.target.closest(
                        "[data-action], " +
                        "[data-idmc-record-action], " +
                        "[data-idmc-action]"
                    );

                if (!target) {
                    return;
                }

                if (
                    target.dataset
                        .idmcConfirmed ===
                    "true"
                ) {
                    delete target.dataset
                        .idmcConfirmed;

                    return;
                }

                const action =
                    mutationAction(
                        target
                    );

                if (
                    action !== "delete" &&
                    action !== "remove"
                ) {
                    return;
                }

                event.preventDefault();
                event.stopImmediatePropagation();

                const accepted =
                    await confirm({
                        title:
                            "Delete record?",
                        message:
                            "This action may permanently remove the selected record. Continue only if you are sure.",
                        confirmText:
                            "Delete",
                        cancelText:
                            "Cancel",
                        danger:
                            true
                    });

                if (!accepted) {
                    return;
                }

                target.dataset
                    .idmcConfirmed =
                    "true";

                target.click();
            },
            true
        );
    }

    function bindRuntimeEvents() {
        const successEvents = [
            "idmc:crud:created",
            "idmc:crud:updated",
            "idmc:crud:deleted",
            "idmc:record:created",
            "idmc:record:updated",
            "idmc:record:deleted"
        ];

        for (
            const eventName
            of successEvents
        ) {
            window.addEventListener(
                eventName,
                event => {
                    const action =
                        eventName
                            .split(":")
                            .pop();

                    toast(
                        "Record " +
                        action +
                        " successfully.",
                        {
                            type:
                                "success",
                            title:
                                "Saved"
                        }
                    );
                }
            );
        }

        const errorEvents = [
            "idmc:crud:error",
            "idmc:record:error",
            "idmc:api:error"
        ];

        for (
            const eventName
            of errorEvents
        ) {
            window.addEventListener(
                eventName,
                event => {
                    const detail =
                        event.detail ||
                        {};

                    toast(
                        detail.message ||
                        detail.error ||
                        "The operation could not be completed.",
                        {
                            type:
                                "error"
                        }
                    );
                }
            );
        }
    }

    function globalErrorHandling() {
        window.addEventListener(
            "unhandledrejection",
            event => {
                const reason =
                    event.reason;

                const message =
                    reason &&
                    reason.message
                        ? reason.message
                        : "An unexpected operation failed.";

                console.error(
                    "Unhandled promise rejection:",
                    reason
                );

                toast(
                    message,
                    {
                        type:
                            "error"
                    }
                );
            }
        );
    }

    function enhanceAccessibility() {
        const buttons =
            document.querySelectorAll(
                "button"
            );

        for (const button of buttons) {
            if (
                !button.getAttribute(
                    "type"
                ) &&
                !button.closest(
                    "form"
                )
            ) {
                button.type =
                    "button";
            }
        }

        const images =
            document.querySelectorAll(
                "img:not([alt])"
            );

        for (const image of images) {
            image.alt = "";
        }

        const main =
            document.querySelector(
                "main"
            );

        if (
            main &&
            !main.id
        ) {
            main.id =
                "idmc-main-content";
        }
    }

    function exposePageState() {
        document.body.dataset
            .idmcPage =
            currentFile()
                .replace(
                    /\.html$/i,
                    ""
                );

        document.body.classList.add(
            "idmc-ui-ready"
        );
    }

    function boot() {
        if (state.booted) {
            return;
        }

        state.booted = true;

        ensureToastRegion();
        exposePageState();
        enhanceAccessibility();
        buildToolbar();
        wrapTables();
        enhanceForms();
        bindNetworkState();
        bindDestructiveConfirmation();
        bindRuntimeEvents();
        globalErrorHandling();

        window.dispatchEvent(
            new CustomEvent(
                "idmc:workflow:ready",
                {
                    detail: {
                        page:
                            currentFile()
                    }
                }
            )
        );
    }

    window.IDMCWorkflow = {
        boot,
        toast,
        confirm,
        setBusy,
        validateForm,
        fieldError,
        clearFieldError
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