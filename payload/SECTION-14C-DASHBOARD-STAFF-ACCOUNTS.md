# IDMC iMIS Section 14C — Dashboard and Real Staff Accounts

## Result

Section 14C connects the Section 14B workspaces to the main dashboard and completes the missing identity chain for staff accounts:

`Supabase Auth → public.users → public.user_roles → public.staff → authorized portal`

Dashboard portal cards are permission-controlled and hidden by default when the authenticated account lacks the required permission.

| Operational role | Dashboard permission | Portal |
|---|---|---|
| `LECTURER` | `portal.lecturer` | Lecturer Portal |
| `FINANCE_OFFICER`, `ACCOUNTANT`, `FINANCE_MANAGER` | `portal.finance` | Finance Portal |
| `REGISTRAR`, `ACADEMIC_OFFICER` | `portal.registry` | Registry Portal |
| `SUPER_ADMIN`, `ADMIN`, `HR_OFFICER` | `staff.accounts.manage` | Staff Account Administration |

## Real-account provisioning

The Staff Accounts screen supports two safe modes:

1. **Create new account** — creates Supabase Auth, `public.users`, the approved role, and the `public.staff` record.
2. **Link existing account** — locates an existing IDMC account by exact email, username or user number, then connects its staff profile and role without duplicating Auth.

The operation rejects inactive institutions, a department from another institution, duplicate employee numbers, unsupported roles and short temporary passwords. Password values are never written to staff tables or audit logs. New-account cleanup removes the Auth identity if downstream staff provisioning fails.

## Data boundary

No human identity has been invented or pre-assigned. Enter only verified staff names, email addresses, employee numbers and role decisions in `staff-accounts.html`. Financial and academic authority must never be inferred from a generic email address.

## Additional correction

Finance and Registry workspace filtering now uses `staff.institution_id`. The earlier lookup used a non-existent `users.institution_id` field and could fail to apply the intended institution filter.

## Verification performed

- TypeScript backend build.
- JavaScript syntax validation.
- Dashboard permission contract checks.
- Admin endpoint permission checks.
- Role allow-list and staff-profile linkage checks.
- Section 14B migration dependency check.

