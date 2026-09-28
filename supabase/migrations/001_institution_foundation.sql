-- ============================================================
-- IDMC iMIS
-- Migration 001: Institution Foundation
-- ============================================================

create extension if not exists pgcrypto;

-- ============================================================
-- Institutions
-- ============================================================

create table if not exists public.institutions (
    id uuid primary key default gen_random_uuid(),
    institution_code varchar(30) not null unique,
    institution_name varchar(255) not null,
    short_name varchar(100),
    registration_number varchar(100),
    accreditation_number varchar(100),
    institution_type varchar(50),
    ownership_type varchar(50),
    email varchar(255),
    phone varchar(50),
    website varchar(255),
    physical_address text,
    postal_address text,
    city varchar(100),
    region varchar(100),
    country varchar(100) default 'Tanzania',
    logo_url text,
    status varchar(30) not null default 'ACTIVE',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- ============================================================
-- Campuses
-- ============================================================

create table if not exists public.campuses (
    id uuid primary key default gen_random_uuid(),
    institution_id uuid not null references public.institutions(id) on delete restrict,
    campus_code varchar(30) not null,
    campus_name varchar(255) not null,
    campus_type varchar(50),
    physical_address text,
    city varchar(100),
    region varchar(100),
    phone varchar(50),
    email varchar(255),
    status varchar(30) not null default 'ACTIVE',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint uq_campus_code_per_institution
        unique (institution_id, campus_code)
);

-- ============================================================
-- Schools / Faculties
-- ============================================================

create table if not exists public.schools (
    id uuid primary key default gen_random_uuid(),
    institution_id uuid not null references public.institutions(id) on delete restrict,
    campus_id uuid references public.campuses(id) on delete restrict,
    school_code varchar(30) not null,
    school_name varchar(255) not null,
    dean_title varchar(100) default 'Dean',
    email varchar(255),
    phone varchar(50),
    status varchar(30) not null default 'ACTIVE',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint uq_school_code_per_institution
        unique (institution_id, school_code)
);

-- ============================================================
-- Departments
-- ============================================================

create table if not exists public.departments (
    id uuid primary key default gen_random_uuid(),
    institution_id uuid not null references public.institutions(id) on delete restrict,
    school_id uuid not null references public.schools(id) on delete restrict,
    department_code varchar(30) not null,
    department_name varchar(255) not null,
    head_title varchar(100) default 'Head of Department',
    email varchar(255),
    phone varchar(50),
    status varchar(30) not null default 'ACTIVE',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint uq_department_code_per_school
        unique (school_id, department_code)
);

-- ============================================================
-- Indexes
-- ============================================================

create index if not exists idx_campuses_institution
    on public.campuses(institution_id);

create index if not exists idx_schools_institution
    on public.schools(institution_id);

create index if not exists idx_schools_campus
    on public.schools(campus_id);

create index if not exists idx_departments_institution
    on public.departments(institution_id);

create index if not exists idx_departments_school
    on public.departments(school_id);

-- ============================================================
-- Updated-at trigger function
-- ============================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists trg_institutions_updated_at
    on public.institutions;

create trigger trg_institutions_updated_at
before update on public.institutions
for each row
execute function public.set_updated_at();

drop trigger if exists trg_campuses_updated_at
    on public.campuses;

create trigger trg_campuses_updated_at
before update on public.campuses
for each row
execute function public.set_updated_at();

drop trigger if exists trg_schools_updated_at
    on public.schools;

create trigger trg_schools_updated_at
before update on public.schools
for each row
execute function public.set_updated_at();

drop trigger if exists trg_departments_updated_at
    on public.departments;

create trigger trg_departments_updated_at
before update on public.departments
for each row
execute function public.set_updated_at();


