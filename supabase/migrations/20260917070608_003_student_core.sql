-- ============================================================
-- IDMC iMIS
-- MIGRATION 003
-- STUDENT CORE
-- ============================================================

create extension if not exists pgcrypto;

-- ============================================================
-- STUDENTS TABLE
-- ============================================================

create table if not exists public.students (
    id uuid primary key default gen_random_uuid(),
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
    constraint students_student_number_unique unique (student_number)
);

-- Hakikisha columns zote za msingi zipo hata kama table ilikuwepo tangu awali
alter table public.students add column if not exists institution_id uuid;
alter table public.students add column if not exists user_id uuid;
alter table public.students add column if not exists student_number varchar(50);
alter table public.students add column if not exists first_name varchar(100);
alter table public.students add column if not exists middle_name varchar(100);
alter table public.students add column if not exists last_name varchar(100);
alter table public.students add column if not exists gender varchar(30);
alter table public.students add column if not exists date_of_birth date;
alter table public.students add column if not exists nationality varchar(100);
alter table public.students add column if not exists national_id varchar(100);
alter table public.students add column if not exists passport_number varchar(100);
alter table public.students add column if not exists phone varchar(50);
alter table public.students add column if not exists email varchar(255);
alter table public.students add column if not exists physical_address text;
alter table public.students add column if not exists postal_address text;
alter table public.students add column if not exists emergency_contact_name varchar(200);
alter table public.students add column if not exists emergency_contact_phone varchar(50);
alter table public.students add column if not exists admission_year integer;
alter table public.students add column if not exists entry_type varchar(50);
alter table public.students add column if not exists student_status varchar(50) default 'ACTIVE';
alter table public.students add column if not exists profile_photo_url text;
alter table public.students add column if not exists notes text;
alter table public.students add column if not exists created_at timestamptz default now();
alter table public.students add column if not exists updated_at timestamptz default now();

-- Ongeza Foreign Keys kwa usalama
alter table public.students drop constraint if exists fk_students_institution;
alter table public.students drop constraint if exists fk_students_user;

alter table public.students 
    add constraint fk_students_institution 
    foreign key (institution_id) references public.institutions(id) 
    on update cascade on delete restrict;

alter table public.students 
    add constraint fk_students_user 
    foreign key (user_id) references public.users(id) 
    on update cascade on delete set null;

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
-- UPDATED_AT TRIGGER
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

drop trigger if exists trg_students_updated_at on public.students;

create trigger trg_students_updated_at
before update on public.students
for each row
execute function public.set_students_updated_at();

-- ============================================================
-- PERMISSIONS & ROLES
-- ============================================================

insert into public.permissions (
    permission_code, permission_name, module_code, action_code
)
values
    ('students.view', 'View students', 'students', 'view'),
    ('students.manage', 'Manage students', 'students', 'manage'),
    ('registration.view', 'View student registration', 'registration', 'view'),
    ('registration.manage', 'Manage student registration', 'registration', 'manage'),
    ('attendance.view', 'View attendance', 'attendance', 'view'),
    ('attendance.manage', 'Manage attendance', 'attendance', 'manage'),
    ('portal.student', 'Access student portal', 'portal', 'student')
on conflict (permission_code) do nothing;

insert into public.roles (
    role_code, role_name, description, is_system_role, status
)
values
    ('STUDENT', 'Student', 'Student self-service account', true, 'ACTIVE')
on conflict (role_code) do nothing;
