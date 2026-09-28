-- IDMC iMIS Section 17C: student engagement services
BEGIN;

CREATE TABLE IF NOT EXISTS public.scholarship_applications (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), student_id uuid NOT NULL REFERENCES public.students(id),
 application_number varchar(80) NOT NULL UNIQUE, scholarship_name varchar(200) NOT NULL,
 sponsor_name varchar(200), requested_amount numeric(18,2) CHECK(requested_amount IS NULL OR requested_amount>0),
 academic_year varchar(20), reason text NOT NULL, supporting_document_path text,
 status varchar(30) NOT NULL DEFAULT 'SUBMITTED' CHECK(status IN('DRAFT','SUBMITTED','UNDER_REVIEW','APPROVED','REJECTED','CANCELLED')),
 decision_notes text, submitted_at timestamptz DEFAULT now(), reviewed_by uuid REFERENCES public.users(id), reviewed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_scholarship_applications_student ON public.scholarship_applications(student_id,created_at DESC);

CREATE TABLE IF NOT EXISTS public.placement_logbook_entries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), student_id uuid NOT NULL REFERENCES public.students(id),
 clinical_placement_id uuid REFERENCES public.clinical_placements(id) ON DELETE CASCADE,
 field_practical_id uuid REFERENCES public.field_practicals(id) ON DELETE CASCADE,
 entry_date date NOT NULL, activity_title varchar(200) NOT NULL, activity_description text NOT NULL,
 hours_completed numeric(6,2) NOT NULL DEFAULT 0 CHECK(hours_completed>=0 AND hours_completed<=24),
 competencies text, evidence_path text, student_status varchar(20) NOT NULL DEFAULT 'SUBMITTED' CHECK(student_status IN('DRAFT','SUBMITTED','RETURNED','VERIFIED')),
 supervisor_comment text, verified_by uuid REFERENCES public.users(id), verified_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK ((clinical_placement_id IS NOT NULL) <> (field_practical_id IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS idx_placement_logbook_student ON public.placement_logbook_entries(student_id,entry_date DESC);

CREATE TABLE IF NOT EXISTS public.graduation_applications (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), student_id uuid NOT NULL REFERENCES public.students(id),
 graduation_period_id uuid REFERENCES public.graduation_periods(id), application_number varchar(80) NOT NULL UNIQUE,
 attendance_choice varchar(30) NOT NULL DEFAULT 'ATTENDING' CHECK(attendance_choice IN('ATTENDING','ABSENTIA')),
 gown_required boolean NOT NULL DEFAULT true, certificate_name varchar(250) NOT NULL,
 status varchar(30) NOT NULL DEFAULT 'SUBMITTED' CHECK(status IN('DRAFT','SUBMITTED','UNDER_REVIEW','ELIGIBLE','NOT_ELIGIBLE','APPROVED','CANCELLED')),
 notes text, submitted_at timestamptz DEFAULT now(), reviewed_by uuid REFERENCES public.users(id), reviewed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(student_id,graduation_period_id)
);

CREATE TABLE IF NOT EXISTS public.hostel_service_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), student_id uuid NOT NULL REFERENCES public.students(id),
 allocation_id uuid REFERENCES public.hostel_allocations(id), request_number varchar(80) NOT NULL UNIQUE,
 request_type varchar(30) NOT NULL CHECK(request_type IN('ROOM_APPLICATION','TRANSFER','MAINTENANCE','CHECKOUT')),
 subject varchar(200) NOT NULL, description text NOT NULL, preferred_hostel_id uuid REFERENCES public.hostels(id),
 status varchar(30) NOT NULL DEFAULT 'SUBMITTED' CHECK(status IN('SUBMITTED','UNDER_REVIEW','APPROVED','REJECTED','COMPLETED','CANCELLED')),
 decision_notes text, submitted_at timestamptz DEFAULT now(), reviewed_by uuid REFERENCES public.users(id), reviewed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.academic_calendar_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), institution_id uuid REFERENCES public.institutions(id),
 academic_year_id uuid REFERENCES public.academic_years(id), semester_id uuid REFERENCES public.semesters(id),
 event_code varchar(80) NOT NULL UNIQUE, title varchar(200) NOT NULL, event_type varchar(50) NOT NULL,
 start_at timestamptz NOT NULL, end_at timestamptz, location varchar(200), description text,
 audience varchar(30) NOT NULL DEFAULT 'ALL' CHECK(audience IN('ALL','STUDENTS','STAFF')),
 status varchar(20) NOT NULL DEFAULT 'PUBLISHED' CHECK(status IN('DRAFT','PUBLISHED','CANCELLED')),
 created_by uuid REFERENCES public.users(id), created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(end_at IS NULL OR end_at>=start_at)
);

COMMIT;
