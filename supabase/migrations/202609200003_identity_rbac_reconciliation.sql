-- ============================================================
-- IDMC iMIS - Identity and RBAC reconciliation
-- ============================================================
-- This migration is intentionally free of account-specific email addresses.
-- Existing Auth-to-public user links are reconciled by the audited Section
-- 13C maintenance script because that operation requires Supabase Admin API.

insert into public.roles (
    role_code, role_name, description, is_system_role, status
)
values
    ('SUPER_ADMIN', 'Super Administrator', 'Full system administration', true, 'ACTIVE'),
    ('ADMIN', 'Administrator', 'System administration', true, 'ACTIVE'),
    ('STUDENT', 'Student', 'Student self-service account', true, 'ACTIVE')
on conflict (role_code) do update
set status = 'ACTIVE', updated_at = now();

insert into public.permissions (
    permission_code, permission_name, module_code, action_code, description, status
)
values
    ('portal.student', 'Access student portal', 'portal', 'student',
        'Open the authenticated student self-service portal', 'ACTIVE'),
    ('students.self.view', 'View own student profile', 'students', 'self_view',
        'Read the student record linked to the authenticated user', 'ACTIVE')
on conflict (permission_code) do update
set permission_name = excluded.permission_name,
    description = excluded.description,
    status = 'ACTIVE',
    updated_at = now();

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p
  on p.permission_code in ('portal.student', 'students.self.view')
where r.role_code = 'STUDENT'
on conflict (role_id, permission_id) do nothing;

-- Earlier migrations add permissions after the original SUPER_ADMIN grant.
-- Re-run the intended full-access rule after all current permissions exist.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.role_code = 'SUPER_ADMIN'
  and r.status = 'ACTIVE'
  and p.status = 'ACTIVE'
on conflict (role_id, permission_id) do nothing;

create index if not exists idx_users_email_lower
    on public.users (lower(email));

create index if not exists idx_users_username_lower
    on public.users (lower(username));

create index if not exists idx_students_student_number_lower
    on public.students (lower(student_number));

comment on table public.users is
    'Application identities mapped one-to-one to auth.users through auth_user_id.';
