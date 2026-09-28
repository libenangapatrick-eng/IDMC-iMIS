# Deployment and Rollback Runbook

## Before deployment

- Confirm production `.env` is stored outside the release archive.
- Run `npm run audit:write`, `npm run test:ci` and backend build.
- Compare `supabase migration list` with `supabase/migration-manifest.json`.
- Take and verify a database backup. Restore it into staging at least once.
- Run migrations on staging and execute authenticated E2E workflows.
- Record the release ZIP SHA-256, database backup identifier and approver.

## Deployment

1. Put the application in a maintenance window.
2. Deploy immutable source/build artifacts.
3. Run `supabase db push` from `supabase/migrations/` only.
4. Start backend and verify `/api/v1/health`, `/api/v1/ready` and `/api/v1/openapi.json`.
5. Verify login and one read/write workflow for Registry, Finance, Academics and Student Portal.

## Rollback

- Application-only failure: redeploy the previous immutable release; do not modify migration history.
- Forward-compatible schema failure: deploy a new corrective migration.
- Destructive/data failure: stop writes, preserve logs, restore the approved backup into a controlled target, validate reconciliation totals, then switch traffic with written approval.
- Never delete ledger, issued transcript, published result or migration-history rows to make deployment appear successful.
