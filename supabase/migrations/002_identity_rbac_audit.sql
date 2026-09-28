-- ============================================================
-- IDMC iMIS
-- Migration 002: Identity, RBAC and Audit Logging
-- ============================================================

create extension if not exists pgcrypto;

-- ============================================================
-- USERS
-- Application-level user profile linked to Supabase Auth
-- ============================================================

create table if not exists public.users (
    id uuid primary key default gen_random_uuid(),

    auth_user_id uuid not null unique
        references auth.users(id) on delete cascade,

    user_number varchar(50) not null unique,

    username varchar(100) unique,

    first_name varchar(100) not null,
    middle_name varchar(100),
    last_name varchar(100) not null,

    display_name varchar(255),

    email varchar(255) not null,
    phone varchar(50),

    profile_photo_url text,

    status varchar(30) not null default 'ACTIVE'
        check (status in (
            'PENDING',
            'ACTIVE',
            'SUSPENDED',
            'LOCKED',
            'INACTIVE',
            'DISABLED'
        )),

    last_login_at timestamptz,
    password_changed_at timestamptz,

    failed_login_attempts integer not null default 0
        check (failed_login_attempts >= 0),

    locked_until timestamptz,

    email_verified_at timestamptz,
    phone_verified_at timestamptz,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists idx_users_auth_user_id
    on public.users(auth_user_id);

create index if not exists idx_users_email
    on public.users(email);

create index if not exists idx_users_status
    on public.users(status);

-- ============================================================
-- ROLES
-- ============================================================

create table if not exists public.roles (
    id uuid primary key default gen_random_uuid(),

    role_code varchar(80) not null unique,
    role_name varchar(150) not null,
    description text,

    is_system_role boolean not null default false,
    status varchar(30) not null default 'ACTIVE'
        check (status in ('ACTIVE', 'INACTIVE')),

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- ============================================================
-- PERMISSIONS
-- ============================================================

create table if not exists public.permissions (
    id uuid primary key default gen_random_uuid(),

    permission_code varchar(150) not null unique,
    permission_name varchar(200) not null,

    module_code varchar(100) not null,

    action_code varchar(50) not null,

    description text,

    status varchar(30) not null default 'ACTIVE'
        check (status in ('ACTIVE', 'INACTIVE')),

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint uq_permission_module_action
        unique (module_code, action_code)
);

create index if not exists idx_permissions_module
    on public.permissions(module_code);

create index if not exists idx_permissions_action
    on public.permissions(action_code);

-- ============================================================
-- ROLE PERMISSIONS
-- ============================================================

create table if not exists public.role_permissions (
    id uuid primary key default gen_random_uuid(),

    role_id uuid not null
        references public.roles(id) on delete cascade,

    permission_id uuid not null
        references public.permissions(id) on delete cascade,

    created_at timestamptz not null default now(),

    constraint uq_role_permission
        unique (role_id, permission_id)
);

create index if not exists idx_role_permissions_role
    on public.role_permissions(role_id);

create index if not exists idx_role_permissions_permission
    on public.role_permissions(permission_id);

-- ============================================================
-- USER ROLES
-- A user can have multiple roles
-- ============================================================

create table if not exists public.user_roles (
    id uuid primary key default gen_random_uuid(),

    user_id uuid not null
        references public.users(id) on delete cascade,

    role_id uuid not null
        references public.roles(id) on delete restrict,

    assigned_by uuid
        references public.users(id) on delete set null,

    assigned_at timestamptz not null default now(),

    expires_at timestamptz,

    status varchar(30) not null default 'ACTIVE'
        check (status in ('ACTIVE', 'INACTIVE', 'EXPIRED')),

    constraint uq_user_role
        unique (user_id, role_id)
);

create index if not exists idx_user_roles_user
    on public.user_roles(user_id);

create index if not exists idx_user_roles_role
    on public.user_roles(role_id);

-- ============================================================
-- USER SCOPES
-- Controls institutional access boundaries
-- ============================================================

create table if not exists public.user_scopes (
    id uuid primary key default gen_random_uuid(),

    user_id uuid not null
        references public.users(id) on delete cascade,

    institution_id uuid
        references public.institutions(id) on delete restrict,

    campus_id uuid
        references public.campuses(id) on delete restrict,

    school_id uuid
        references public.schools(id) on delete restrict,

    department_id uuid
        references public.departments(id) on delete restrict,

    scope_type varchar(50) not null
        check (scope_type in (
            'GLOBAL',
            'INSTITUTION',
            'CAMPUS',
            'SCHOOL',
            'DEPARTMENT'
        )),

    created_at timestamptz not null default now(),

    constraint chk_user_scope_reference
        check (
            (scope_type = 'GLOBAL'
                and institution_id is null
                and campus_id is null
                and school_id is null
                and department_id is null)
            or
            (scope_type = 'INSTITUTION'
                and institution_id is not null)
            or
            (scope_type = 'CAMPUS'
                and campus_id is not null)
            or
            (scope_type = 'SCHOOL'
                and school_id is not null)
            or
            (scope_type = 'DEPARTMENT'
                and department_id is not null)
        )
);

create index if not exists idx_user_scopes_user
    on public.user_scopes(user_id);

create index if not exists idx_user_scopes_institution
    on public.user_scopes(institution_id);

create index if not exists idx_user_scopes_campus
    on public.user_scopes(campus_id);

create index if not exists idx_user_scopes_school
    on public.user_scopes(school_id);

create index if not exists idx_user_scopes_department
    on public.user_scopes(department_id);

-- ============================================================
-- AUDIT LOGS
-- Central immutable audit trail
-- ============================================================

create table if not exists public.audit_logs (
    id uuid primary key default gen_random_uuid(),

    user_id uuid
        references public.users(id) on delete set null,

    action_code varchar(100) not null,

    module_code varchar(100) not null,

    entity_type varchar(100),
    entity_id uuid,

    old_values jsonb,
    new_values jsonb,

    description text,

    ip_address inet,
    user_agent text,

    request_id varchar(100),

    created_at timestamptz not null default now()
);

create index if not exists idx_audit_logs_user
    on public.audit_logs(user_id);

create index if not exists idx_audit_logs_module
    on public.audit_logs(module_code);

create index if not exists idx_audit_logs_action
    on public.audit_logs(action_code);

create index if not exists idx_audit_logs_entity
    on public.audit_logs(entity_type, entity_id);

create index if not exists idx_audit_logs_created_at
    on public.audit_logs(created_at);

create index if not exists idx_audit_logs_request_id
    on public.audit_logs(request_id);

-- ============================================================
-- SECURITY / LOGIN EVENTS
-- ============================================================

create table if not exists public.security_logs (
    id uuid primary key default gen_random_uuid(),

    user_id uuid
        references public.users(id) on delete set null,

    event_code varchar(100) not null,

    success boolean not null default true,

    ip_address inet,
    user_agent text,

    details jsonb,

    created_at timestamptz not null default now()
);

create index if not exists idx_security_logs_user
    on public.security_logs(user_id);

create index if not exists idx_security_logs_event
    on public.security_logs(event_code);

create index if not exists idx_security_logs_created_at
    on public.security_logs(created_at);

-- ============================================================
-- SYSTEM ROLES
-- ============================================================

insert into public.roles
    (role_code, role_name, description, is_system_role)
values
    ('SUPER_ADMIN', 'Super Administrator',
        'Full system administration access', true),

    ('ADMIN', 'Administrator',
        'Institutional administration access', true),

    ('ACADEMIC_OFFICER', 'Academic Officer',
        'Academic administration and academic records', true),

    ('ADMISSIONS_OFFICER', 'Admissions Officer',
        'Applicant and admission management', true),

    ('FINANCE_OFFICER', 'Finance Officer',
        'Finance, invoices, payments and financial records', true),

    ('EXAMINATION_OFFICER', 'Examination Officer',
        'Examination and examination administration', true),

    ('LECTURER', 'Lecturer',
        'Teaching, attendance, assessments and course activities', true),

    ('STUDENT', 'Student',
        'Student self-service access', true),

    ('LIBRARIAN', 'Librarian',
        'Library administration', true),

    ('HR_OFFICER', 'Human Resources Officer',
        'Human resources and employee management', true),

    ('PROCUREMENT_OFFICER', 'Procurement Officer',
        'Procurement management', true),

    ('STORE_OFFICER', 'Store Officer',
        'Inventory and stores management', true),

    ('QUALITY_ASSURANCE', 'Quality Assurance Officer',
        'Quality assurance management', true),

    ('RESEARCH_OFFICER', 'Research Officer',
        'Research administration', true),

    ('AUDITOR', 'Auditor',
        'Audit and compliance access', true),

    ('STAFF', 'Staff',
        'General staff access', true)

on conflict (role_code) do nothing;

-- ============================================================
-- CORE PERMISSIONS
-- ============================================================

insert into public.permissions
    (permission_code, permission_name, module_code, action_code, description)
values

    ('system.view', 'View System', 'system', 'view',
        'Access system information'),

    ('system.manage', 'Manage System', 'system', 'manage',
        'Manage system configuration'),

    ('users.view', 'View Users', 'users', 'view',
        'View users'),

    ('users.create', 'Create Users', 'users', 'create',
        'Create users'),

    ('users.update', 'Update Users', 'users', 'update',
        'Update users'),

    ('users.delete', 'Delete Users', 'users', 'delete',
        'Delete or disable users'),

    ('roles.view', 'View Roles', 'rbac', 'view',
        'View roles'),

    ('roles.manage', 'Manage Roles', 'rbac', 'manage',
        'Manage roles and role assignments'),

    ('permissions.view', 'View Permissions', 'rbac', 'view_permissions',
        'View permissions'),

    ('audit.view', 'View Audit Logs', 'audit', 'view',
        'View audit logs'),

    ('audit.export', 'Export Audit Logs', 'audit', 'export',
        'Export audit logs'),

    ('institutions.view', 'View Institutions', 'institution', 'view',
        'View institutions'),

    ('institutions.manage', 'Manage Institutions', 'institution', 'manage',
        'Manage institutional configuration'),

    ('campuses.view', 'View Campuses', 'campus', 'view',
        'View campuses'),

    ('campuses.manage', 'Manage Campuses', 'campus', 'manage',
        'Manage campuses'),

    ('schools.view', 'View Schools', 'school', 'view',
        'View schools'),

    ('schools.manage', 'Manage Schools', 'school', 'manage',
        'Manage schools'),

    ('departments.view', 'View Departments', 'department', 'view',
        'View departments'),

    ('departments.manage', 'Manage Departments', 'department', 'manage',
        'Manage departments')

on conflict (permission_code) do nothing;

-- ============================================================
-- SUPER ADMIN PERMISSIONS
-- ============================================================

insert into public.role_permissions (role_id, permission_id)
select
    r.id,
    p.id
from public.roles r
cross join public.permissions p
where r.role_code = 'SUPER_ADMIN'
on conflict (role_id, permission_id) do nothing;

-- ============================================================
-- ADMIN PERMISSIONS
-- ============================================================

insert into public.role_permissions (role_id, permission_id)
select
    r.id,
    p.id
from public.roles r
join public.permissions p
    on p.permission_code in (
        'system.view',
        'users.view',
        'users.create',
        'users.update',
        'roles.view',
        'roles.manage',
        'permissions.view',
        'audit.view',
        'institutions.view',
        'institutions.manage',
        'campuses.view',
        'campuses.manage',
        'schools.view',
        'schools.manage',
        'departments.view',
        'departments.manage'
    )
where r.role_code = 'ADMIN'
on conflict (role_id, permission_id) do nothing;

-- ============================================================
-- AUDITOR PERMISSIONS
-- ============================================================

insert into public.role_permissions (role_id, permission_id)
select
    r.id,
    p.id
from public.roles r
join public.permissions p
    on p.permission_code in (
        'system.view',
        'users.view',
        'roles.view',
        'permissions.view',
        'audit.view',
        'audit.export',
        'institutions.view',
        'campuses.view',
        'schools.view',
        'departments.view'
    )
where r.role_code = 'AUDITOR'
on conflict (role_id, permission_id) do nothing;

-- ============================================================
-- ROW LEVEL SECURITY
-- Backend service role can operate across these tables.
-- Additional user-facing policies will be added when
-- authentication/API authorization is implemented.
-- ============================================================

alter table public.users enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.user_scopes enable row level security;
alter table public.audit_logs enable row level security;
alter table public.security_logs enable row level security;

-- ============================================================
-- COMMENTS
-- ============================================================

comment on table public.users is
    'Application users linked to Supabase Auth identities.';

comment on table public.roles is
    'System roles used by the IDMC iMIS RBAC framework.';

comment on table public.permissions is
    'Fine-grained permissions for system modules and actions.';

comment on table public.user_roles is
    'Many-to-many relationship between users and roles.';

comment on table public.user_scopes is
    'Defines institutional access scope for users.';

comment on table public.audit_logs is
    'Central audit trail for important system operations.';

comment on table public.security_logs is
    'Security and authentication event history.';
