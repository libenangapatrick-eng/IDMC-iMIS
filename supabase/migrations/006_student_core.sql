-- ============================================================
-- IDMC iMIS
-- MIGRATION 003
-- STUDENT CORE
-- ============================================================

create extension if not exists pgcrypto;

-- ============================================================
-- STUDENTS
-- ============================================================

create table if not exists public.students (

    id uuid primary key default gen_random_uuid(),

    institution_id uuid not null
        references public.institutions(id)
        on update cascade
        on delete restrict,

    user_id uuid null
        references public.users(id)
        on update cascade
        on delete set null,

    student_number varchar(50) not null,

    first_name varchar(100) not null,

    middle_name varchar(100),

    last_name varchar(100) not null,

    gender varchar(30),

    date_of_birth date,

    nationality varchar(100),

    national_id varchar(100),

    passport_number varchar(100),

    phone varchar(50),

    email varchar(255),

    physical_address text,

    postal_address text,

    emergency_contact_name varchar(200),

    emergency_contact_phone varchar(50),

    admission_year integer,

    entry_type varchar(50),

    student_status varchar(50) not null default 'ACTIVE',

    profile_photo_url text,

    notes text,

    created_at timestamptz not null default now(),

    updated_at timestamptz not null default now(),

    constraint students_student_number_unique
        unique (student_number)
);

-- ============================================================
-- INDEXES
-- ============================================================

create index if not exists idx_students_institution_id
    on public.students(institution_id);

create index if not exists idx_students_user_id
    on public.students(user_id);

create index if not exists idx_students_student_number
    on public.students(student_number);

create index if not exists idx_students_email
    on public.students(email);

create index if not exists idx_students_status
    on public.students(student_status);

create index if not exists idx_students_names
    on public.students(last_name, first_name);

-- ============================================================
-- UPDATED AT
-- ============================================================

create or replace function public.set_students_updated_at()
returns trigger
language plpgsql
as $$
begin

    new.updated_at = now();

    return new;

end;
$$;

drop trigger if exists trg_students_updated_at
on public.students;

create trigger trg_students_updated_at

before update
on public.students

for each row
execute function public.set_students_updated_at();

-- ============================================================
-- STUDENT MANAGEMENT PERMISSIONS
-- ============================================================

insert into public.permissions (
    permission_code,
    permission_name,
    module_code,
    action_code
)

values

(
    'students.view',
    'View students',
    'students',
    'view'
),

(
    'students.manage',
    'Manage students',
    'students',
    'manage'
),

(
    'registration.view',
    'View student registration',
    'registration',
    'view'
),

(
    'registration.manage',
    'Manage student registration',
    'registration',
    'manage'
),

(
    'attendance.view',
    'View attendance',
    'attendance',
    'view'
),

(
    'attendance.manage',
    'Manage attendance',
    'attendance',
    'manage'
),

(
    'students.self.view',
    'View own student record',
    'students',
    'self_view'
),

(
    'portal.student',
    'Access student portal',
    'portal',
    'student'
)

on conflict (permission_code)
do nothing;

-- ============================================================
-- STUDENT ROLE
-- ============================================================

insert into public.roles (
    role_code,
    role_name,
    description,
    is_system_role,
    status
)

values (

    'STUDENT',

    'Student',

    'Student self-service account',

    true,

    'ACTIVE'

)

on conflict (role_code)
do nothing;

-- ============================================================
-- GET ROLE IDS
-- ============================================================

-- STUDENT SELF-SERVICE PERMISSIONS

insert into public.role_permissions (
    role_id,
    permission_id
)

select

    r.id,

    p.id

from public.roles r

cross join public.permissions p

where r.role_code = 'STUDENT'

and p.permission_code in (
    'portal.student',
    'students.self.view'
)

on conflict do nothing;

-- ============================================================
-- ADMIN STUDENT MANAGEMENT PERMISSIONS
-- ============================================================

insert into public.role_permissions (
    role_id,
    permission_id
)

select

    r.id,

    p.id

from public.roles r

cross join public.permissions p

where r.role_code = 'ADMIN'

and p.permission_code in (
    'students.view',
    'students.manage',
    'registration.view',
    'registration.manage',
    'attendance.view',
    'attendance.manage'
)

on conflict do nothing;
