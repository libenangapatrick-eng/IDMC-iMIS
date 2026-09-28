begin;

alter table public.applicants
    add column if not exists profile_photo_url text;

create table if not exists public.academic_records (
    id uuid primary key default gen_random_uuid(), institution_id uuid not null,
    student_id uuid not null, academic_year text, semester text, programme_id uuid,
    course_code text, course_name text,
    registration_status text not null default 'ACTIVE' check (registration_status in ('ACTIVE','INACTIVE','COMPLETED','SUSPENDED','WITHDRAWN')),
    credits numeric, grade text, grade_point numeric, notes text,
    created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists academic_records_institution_idx on public.academic_records(institution_id);
create index if not exists academic_records_student_idx on public.academic_records(student_id);

create table if not exists public.student_coursework_responses (
    id uuid primary key default gen_random_uuid(),
    student_id uuid not null references public.students(id) on delete cascade,
    course_result_id uuid not null references public.course_results(id) on delete cascade,
    response_status varchar(20) not null check (response_status in ('ACCEPTED','QUERY')),
    student_comment text, responded_at timestamptz not null default now(),
    updated_at timestamptz not null default now(), unique (student_id, course_result_id)
);

create table if not exists public.student_course_evaluations (
    id uuid primary key default gen_random_uuid(),
    student_id uuid not null references public.students(id) on delete cascade,
    course_offering_id uuid not null references public.course_offerings(id) on delete cascade,
    rating smallint not null check (rating between 1 and 5),
    lecturer_preparation smallint check (lecturer_preparation between 1 and 5),
    content_delivery smallint check (content_delivery between 1 and 5),
    learning_resources smallint check (learning_resources between 1 and 5),
    student_comment text, submitted_at timestamptz not null default now(),
    updated_at timestamptz not null default now(), unique (student_id, course_offering_id)
);

create table if not exists public.student_service_requests (
    id uuid primary key default gen_random_uuid(), request_number varchar(80) not null unique,
    student_id uuid not null references public.students(id) on delete cascade,
    request_type varchar(40) not null check (request_type in ('RESULT_APPEAL','POSTPONEMENT','TRANSCRIPT','ID_CARD','CERTIFICATE','GRADUATION_GOWN','GENERAL')),
    academic_year_id uuid references public.academic_years(id),
    semester_id uuid references public.semesters(id), subject varchar(200) not null,
    reason text not null, evidence_url text, request_data jsonb not null default '{}'::jsonb,
    status varchar(30) not null default 'SUBMITTED' check (status in ('DRAFT','SUBMITTED','UNDER_REVIEW','APPROVED','REJECTED','COMPLETED','CANCELLED')),
    submitted_at timestamptz not null default now(), reviewed_by uuid references public.users(id),
    reviewed_at timestamptz, review_comment text,
    created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create index if not exists idx_coursework_response_student on public.student_coursework_responses(student_id, responded_at desc);
create index if not exists idx_course_evaluation_student on public.student_course_evaluations(student_id, submitted_at desc);
create index if not exists idx_student_service_request_student on public.student_service_requests(student_id, submitted_at desc);
alter table public.academic_records enable row level security;
alter table public.student_coursework_responses enable row level security;
alter table public.student_course_evaluations enable row level security;
alter table public.student_service_requests enable row level security;

insert into public.roles (role_code, role_name, description, is_system_role, status)
values ('STUDENT','Student','Student self-service account',true,'ACTIVE')
on conflict (role_code) do update set status = 'ACTIVE', updated_at = now();

insert into public.permissions (permission_code, permission_name, module_code, action_code, description, status)
values ('students.self.manage','Manage own student self-service','students','self_manage','Submit only the authenticated student profile changes, evaluations and requests','ACTIVE')
on conflict (permission_code) do update set permission_name=excluded.permission_name, description=excluded.description, status='ACTIVE', updated_at=now();

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.role_code='STUDENT' and p.permission_code in ('portal.student','students.self.view','students.self.manage')
on conflict do nothing;

commit;
