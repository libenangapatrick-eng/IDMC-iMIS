-- ============================================================
-- IDMC iMIS
-- ACADEMICS MODULE
-- DATABASE SCHEMA
-- ============================================================

create extension if not exists pgcrypto;

create table if not exists public.academic_records (

    id uuid primary key default gen_random_uuid(),

    institution_id uuid not null,

    student_id uuid not null,

    academic_year text null,

    semester text null,

    programme_id uuid null,

    course_code text null,

    course_name text null,

    registration_status text
        not null
        default 'ACTIVE',

    credits numeric null,

    grade text null,

    grade_point numeric null,

    notes text null,

    created_at timestamptz
        not null
        default now(),

    updated_at timestamptz
        not null
        default now(),

    constraint academic_records_status_check
        check (
            registration_status in (
                'ACTIVE',
                'INACTIVE',
                'COMPLETED',
                'SUSPENDED',
                'WITHDRAWN'
            )
        )
);

create index if not exists
academic_records_institution_id_idx
on public.academic_records(institution_id);

create index if not exists
academic_records_student_id_idx
on public.academic_records(student_id);

create index if not exists
academic_records_academic_year_idx
on public.academic_records(academic_year);

create index if not exists
academic_records_course_code_idx
on public.academic_records(course_code);

create index if not exists
academic_records_status_idx
on public.academic_records(registration_status);

-- ============================================================
-- UPDATED_AT
-- ============================================================

create or replace function public.set_academic_records_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists
academic_records_updated_at
on public.academic_records;

create trigger
academic_records_updated_at
before update on public.academic_records
for each row
execute function public.set_academic_records_updated_at();

-- ============================================================
-- RLS
-- ============================================================

alter table public.academic_records
enable row level security;

-- Backend service-role access remains available.
-- Additional user-level policies can be added according
-- to the IDMC iMIS RBAC/security model.
