# IDMC Login Startup Fix

Date: 26 September 2026

## Root cause

The `/login/` URL was a placeholder page that attempted to redirect to
`/login.html`. The generic static server could report itself as ready while it
was only serving that placeholder. In the affected browser the redirect did
not complete, leaving the page at “Opening IDMC iMIS Login...”.

## Implemented fix

- Added `apps/frontend/server.mjs`, a deterministic static server that maps
  `/`, `/login`, `/login/`, and `/login.html` directly to the real login form.
- Added a document base URL so login assets resolve correctly from `/login/`.
- Updated `Start-IDMC.ps1` to use the deterministic frontend server.
- Strengthened the startup health check: it now requires the actual
  `loginForm` marker and rejects the old placeholder page.
- Updated both npm frontend commands to use the same server.
- Added a regression contract test for the login route and startup command.

## Verification completed

- `/`, `/login`, `/login/`, and `/login.html`: HTTP 200 with the real form.
- `assets/js/config.js` and `assets/js/auth.js`: HTTP 200.
- Backend `/api/v1/health`: HTTP 200 with `success: true`.
- Backend TypeScript typecheck: passed.
- Automated backend/security/source-contract tests: 12 passed, 0 failed.

Use `Start-IDMC.ps1` from the project root. The expected URL is:

`http://127.0.0.1:5500/login/`
