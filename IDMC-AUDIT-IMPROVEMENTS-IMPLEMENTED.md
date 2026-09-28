# IDMC iMIS Audit Improvements Implemented

Implemented from the 26 September 2026 source-code integration audit.

## Completed in source

- Runtime/same-origin frontend API configuration; no fixed production localhost target.
- Applicant forms use the shared API base.
- Exact CORS allowlist with HTTPS-only production validation.
- Login rate limiting and generic invalid-credential response.
- Request/correlation IDs returned in `X-Request-Id` and structured JSON logs with recursive secret redaction.
- Liveness (`/api/v1/health`), dependency readiness (`/api/v1/ready`) and OpenAPI (`/api/v1/openapi.json`).
- Scoped aliases for assets, procurement, documents and helpdesk; unrelated child paths no longer leak through a whole-router alias.
- Real `npm test`: bearer parsing, RBAC active/expiry behavior, CORS, log redaction, request IDs, rate limiting and source contracts.
- Generated route inventory (588 records), form inventory (18 forms) and migration manifest (55 authoritative migrations).
- `supabase/migrations` declared as the deployment source of truth; `database/migrations` is reference-only.
- Safe-release PowerShell excludes `.env`, build caches, archives and secrets and verifies the ZIP.
- Read-only data-quality/reconciliation SQL and deployment/rollback runbook.
- CI workflow for audit, tests, typecheck, build and frontend secret checks.

## Verified locally

- Integration audit: PASS, zero source failures.
- Automated tests: 10 passed, 0 failed.
- TypeScript typecheck: PASS.
- Backend build: PASS.
- Runtime liveness, request ID and OpenAPI: PASS.
- Database readiness: PASS in the configured development environment.
- Protected alias routes and student summary return 401 without credentials: PASS.

## Requires the institution staging/production environment

The following cannot be truthfully certified from source alone: credential rotation,
remote migration-history parity, backup restore, real email delivery, production
storage/RLS, payment-provider interoperability, performance query plans, browser
workflows with real role accounts, and formal UAT approval. The supplied manifests,
diagnostics, E2E script and runbook are the controls used to complete those checks.
