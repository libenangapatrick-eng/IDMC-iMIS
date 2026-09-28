# Migration Policy

`supabase/migrations/` is the only authoritative deployment source. Files in
`database/migrations/` are historical/reference diagnostics and MUST NOT be
executed by deployment automation.

Rules:

1. Every filename starts with a globally unique numeric version.
2. Applied migrations are immutable; corrections use a new migration.
3. `node scripts/audit-integration.mjs --write` regenerates the manifest and fails duplicate versions.
4. Deployment runs `supabase db push` only after the integration audit passes.
5. Production requires a database backup, staging dry run and approved rollback plan.
6. `supabase migration repair` is not an automatic recovery action; it requires a verified remote/local history investigation.

`supabase/migration-manifest.json` records filename, version, byte size and SHA-256 for review. Applied status remains authoritative in `supabase_migrations.schema_migrations` on the target database.
