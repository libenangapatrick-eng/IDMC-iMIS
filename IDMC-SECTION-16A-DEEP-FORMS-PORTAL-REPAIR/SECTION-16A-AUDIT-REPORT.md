# IDMC iMIS Section 16A audit

## Confirmed root cause

The applicant form used the relative URL `/api/v1`. Because the frontend is served by Live Server on port 5500, the browser sent the request to port 5500 instead of the Express backend on port 4000. Live Server therefore returned HTML `Cannot GET` for reads and HTTP 405 for writes. The Express admissions CRUD route itself was present and supports GET, POST, PATCH and DELETE.

## Repairs included

- Uses `IDMC_CONFIG.API_BASE_URL` with a safe port-4000 fallback.
- Separates staff applicant administration from ownership-scoped applicant self-service.
- Adds active academic-year and programme lookups; raw UUID entry is removed.
- Adds required-email validation, controlled qualification/document types, profile photo and document upload validation.
- Prevents edits/deletes after application submission and validates minimum data before submission.
- Removes the duplicate applicant form from the admissions decision page.
- Adds the APPLICANT role and `portal.applicant` permission without assigning it to unrelated users.
- Restores fail-closed, permission-controlled dashboard portal cards.
- Routes APPLICANT, HOD and DEPUTY_HOD users to the correct portal.
- Applies a consistent maroon/white institutional form style using Times New Roman.

## Verification performed

- Frontend JavaScript syntax checks.
- Full backend TypeScript typecheck/build.
- Static route-mount and API-base contract checks.
- Installer performs backup before copying, database migration, build, exact-project process restart and health checks.

## Scope note

No existing student, applicant, staff, course, result or finance record is deleted or rewritten by this repair. Role assignment remains an explicit administrator action.
