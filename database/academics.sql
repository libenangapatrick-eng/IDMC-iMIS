-- ============================================================
-- IDMC iMIS
-- ACADEMICS DATABASE
-- ============================================================

create extension if not exists pgcrypto;

-- ============================================================
-- ACADEMIC RECORDS
-- ============================================================

create table if not exists public.academic_records (

    id uuid primary key default gen_random_uuid(),

    institution_id uuid not null,

    student_id uuid not null,

    academic_year text,

    semester text,

    programme_id uuid,

    course_code text,

    course_name text,

    registration_status text
        not null default 'ACTIVE'
        check (
            registration_status in (
                'ACTIVE',
                'INACTIVE',
                'COMPLETED',
                'SUSPENDED',
                'WITHDRAWN'
            )
        ),

    credits numeric,

    grade text,

    grade_point numeric,

    notes text,

    created_at timestamptz
        not null default now(),

    updated_at timestamptz
        not null default now()
);

-- ============================================================
-- INDEXES
-- ============================================================

create index if not exists
academic_records_institution_idx
on public.academic_records(institution_id);

create index if not exists
academic_records_student_idx
on public.academic_records(student_id);

create index if not exists
academic_records_course_idx
on public.academic_records(course_code);

create index if not exists
academic_records_year_idx
on public.academic_records(academic_year);

-- ============================================================
-- UPDATED_AT TRIGGER
-- ============================================================

create or replace function
public.set_academic_records_updated_at()
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
execute function
public.set_academic_records_updated_at();

-- ============================================================
-- RLS
-- ============================================================

alter table public.academic_records
enable row level security;

-- ============================================================
-- NOTE
-- Existing project RBAC remains responsible for API access.
-- These policies allow authenticated API operation.
-- Tighten them further if the project uses user-specific
-- institution ownership policies.
-- ============================================================

drop policy if exists
academic_records_authenticated_select
on public.academic_records;

create policy
academic_records_authenticated_select
on public.academic_records
for select
to authenticated
using (true);

drop policy if exists
academic_records_authenticated_insert
on public.academic_records;

create policy
academic_records_authenticated_insert
on public.academic_records
for insert
to authenticated
with check (true);

drop policy if exists
academic_records_authenticated_update
on public.academic_records;

create policy
academic_records_authenticated_update
on public.academic_records
for update
to authenticated
using (true)
with check (true);

drop policy if exists
academic_records_authenticated_delete
on public.academic_records;

create policy
academic_records_authenticated_delete
on public.academic_records
for delete
to authenticated
using (true);

-- ============================================================
-- COMMENTS
-- ============================================================

comment on table public.academic_records
is 'IDMC iMIS student academic records';

comment on column public.academic_records.student_id
is 'Student associated with the academic record';

comment on column public.academic_records.institution_id
is 'Institution owning the academic record';

comment on column public.academic_records.course_code
is 'Course/module code';

comment on column public.academic_records.grade
is 'Academic grade';

comment on column public.academic_records.grade_point
is 'Numeric grade point';

comment on column public.academic_records.credits
is 'Course credit value';
