create extension if not exists pgcrypto;

create table if not exists public.academic_records (
    id uuid primary key default gen_random_uuid(),

    institution_id uuid not null,
    student_id uuid not null,

    academic_year text,
    semester text,

    programme_id uuid,
    course_code text,
    course_name text,

    registration_status text not null default 'ACTIVE'
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

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists academic_records_institution_idx
    on public.academic_records(institution_id);

create index if not exists academic_records_student_idx
    on public.academic_records(student_id);

create index if not exists academic_records_year_idx
    on public.academic_records(academic_year);

create index if not exists academic_records_course_idx
    on public.academic_records(course_code);

create index if not exists academic_records_status_idx
    on public.academic_records(registration_status);

create or replace function public.set_academic_records_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists academic_records_updated_at
on public.academic_records;

create trigger academic_records_updated_at
before update on public.academic_records
for each row
execute function public.set_academic_records_updated_at();
