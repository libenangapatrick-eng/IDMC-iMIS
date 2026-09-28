-- ============================================================
-- IDMC iMIS corrective migration
-- Historical students, cohorts, programme linkage and attempts
-- Additive only: no historical migration or institutional data is deleted.
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.student_cohorts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions(id) ON DELETE RESTRICT,
    cohort_code varchar(30) NOT NULL,
    cohort_name varchar(120) NOT NULL,
    entry_year integer NOT NULL CHECK (entry_year BETWEEN 1900 AND 2200),
    default_academic_year_id uuid REFERENCES public.academic_years(id) ON DELETE RESTRICT,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','CLOSED','ARCHIVED')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (institution_id, cohort_code),
    UNIQUE (institution_id, entry_year)
);

ALTER TABLE public.students ADD COLUMN IF NOT EXISTS cohort_id uuid REFERENCES public.student_cohorts(id) ON DELETE RESTRICT;
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS programme_id uuid REFERENCES public.programmes(id) ON DELETE RESTRICT;
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS programme_version_id uuid REFERENCES public.programme_versions(id) ON DELETE RESTRICT;
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS curriculum_id uuid REFERENCES public.curricula(id) ON DELETE RESTRICT;
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS entry_academic_year_id uuid REFERENCES public.academic_years(id) ON DELETE RESTRICT;
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS source_type varchar(30) NOT NULL DEFAULT 'NORMAL_ADMISSION';
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS source_reference varchar(150);
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS archived_at timestamptz;
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS archived_by uuid REFERENCES public.users(id) ON DELETE SET NULL;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='students_source_type_check') THEN
    ALTER TABLE public.students ADD CONSTRAINT students_source_type_check
      CHECK (source_type IN ('NORMAL_ADMISSION','HISTORICAL_IMPORT','MANUAL_ENTRY'));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.historical_import_batches (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_number varchar(60) NOT NULL UNIQUE,
    institution_id uuid NOT NULL REFERENCES public.institutions(id) ON DELETE RESTRICT,
    source_format varchar(20) NOT NULL CHECK (source_format IN ('CSV','XLSX','MANUAL')),
    source_file_name varchar(255),
    source_file_sha256 varchar(64),
    cohort_year integer CHECK (cohort_year BETWEEN 2023 AND 2026),
    status varchar(30) NOT NULL DEFAULT 'UPLOADED'
      CHECK (status IN ('UPLOADED','VALIDATED','READY','IMPORTING','COMPLETED','COMPLETED_WITH_ERRORS','FAILED','ROLLED_BACK')),
    total_rows integer NOT NULL DEFAULT 0 CHECK (total_rows >= 0),
    valid_rows integer NOT NULL DEFAULT 0 CHECK (valid_rows >= 0),
    invalid_rows integer NOT NULL DEFAULT 0 CHECK (invalid_rows >= 0),
    duplicate_rows integer NOT NULL DEFAULT 0 CHECK (duplicate_rows >= 0),
    imported_rows integer NOT NULL DEFAULT 0 CHECK (imported_rows >= 0),
    skipped_rows integer NOT NULL DEFAULT 0 CHECK (skipped_rows >= 0),
    uploaded_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    validated_at timestamptz,
    confirmed_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    confirmed_at timestamptz,
    completed_at timestamptz,
    rolled_back_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    rolled_back_at timestamptz,
    rollback_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.historical_import_rows (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id uuid NOT NULL REFERENCES public.historical_import_batches(id) ON DELETE RESTRICT,
    row_number integer NOT NULL CHECK (row_number > 0),
    raw_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    normalized_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    validation_status varchar(20) NOT NULL DEFAULT 'PENDING'
      CHECK (validation_status IN ('PENDING','VALID','INVALID','DUPLICATE','IMPORTED','SKIPPED','ROLLED_BACK')),
    validation_errors jsonb NOT NULL DEFAULT '[]'::jsonb,
    student_id uuid REFERENCES public.students(id) ON DELETE RESTRICT,
    imported_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (batch_id, row_number)
);

CREATE TABLE IF NOT EXISTS public.student_course_attempts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE RESTRICT,
    programme_version_id uuid REFERENCES public.programme_versions(id) ON DELETE RESTRICT,
    curriculum_id uuid REFERENCES public.curricula(id) ON DELETE RESTRICT,
    academic_year_id uuid NOT NULL REFERENCES public.academic_years(id) ON DELETE RESTRICT,
    semester_id uuid NOT NULL REFERENCES public.semesters(id) ON DELETE RESTRICT,
    course_id uuid NOT NULL REFERENCES public.courses(id) ON DELETE RESTRICT,
    course_registration_id uuid REFERENCES public.course_registrations(id) ON DELETE RESTRICT,
    course_result_id uuid REFERENCES public.course_results(id) ON DELETE RESTRICT,
    import_row_id uuid REFERENCES public.historical_import_rows(id) ON DELETE RESTRICT,
    attempt_number integer NOT NULL DEFAULT 1 CHECK (attempt_number > 0),
    attempt_date date,
    coursework_mark numeric(8,2) CHECK (coursework_mark IS NULL OR coursework_mark BETWEEN 0 AND 100),
    examination_mark numeric(8,2) CHECK (examination_mark IS NULL OR examination_mark BETWEEN 0 AND 100),
    total_mark numeric(8,2) CHECK (total_mark IS NULL OR total_mark BETWEEN 0 AND 100),
    grade_code varchar(10),
    grade_point numeric(5,2) CHECK (grade_point IS NULL OR grade_point >= 0),
    credits numeric(6,2) NOT NULL DEFAULT 0 CHECK (credits >= 0),
    pass_status varchar(30) CHECK (pass_status IS NULL OR pass_status IN ('PASS','FAIL','SUPPLEMENTARY','INCOMPLETE','WITHHELD','WITHDRAWN')),
    attempt_status varchar(30) NOT NULL DEFAULT 'RECORDED'
      CHECK (attempt_status IN ('REGISTERED','ATTEMPTED','RECORDED','PUBLISHED','LOCKED','WITHDRAWN','CANCELLED')),
    result_type varchar(30) NOT NULL DEFAULT 'NORMAL'
      CHECK (result_type IN ('NORMAL','SUPPLEMENTARY','SPECIAL','RESIT','RETAKE','REPEAT','CARRY_FORWARD','MAKEUP')),
    source_type varchar(30) NOT NULL DEFAULT 'NORMAL_ADMISSION'
      CHECK (source_type IN ('NORMAL_ADMISSION','HISTORICAL_IMPORT','MANUAL_ENTRY')),
    recorded_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    locked_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    locked_at timestamptz,
    remarks text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (student_id, academic_year_id, semester_id, course_id, attempt_number)
);

ALTER TABLE public.student_status_history ADD COLUMN IF NOT EXISTS supporting_document_id uuid;
ALTER TABLE public.student_status_history ADD COLUMN IF NOT EXISTS import_batch_id uuid REFERENCES public.historical_import_batches(id) ON DELETE RESTRICT;
ALTER TABLE public.student_programme_history ADD COLUMN IF NOT EXISTS previous_programme_id uuid REFERENCES public.programmes(id) ON DELETE RESTRICT;
ALTER TABLE public.student_programme_history ADD COLUMN IF NOT EXISTS previous_programme_version_id uuid REFERENCES public.programme_versions(id) ON DELETE RESTRICT;
ALTER TABLE public.student_programme_history ADD COLUMN IF NOT EXISTS import_batch_id uuid REFERENCES public.historical_import_batches(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_students_cohort ON public.students(cohort_id);
CREATE INDEX IF NOT EXISTS idx_students_source_type ON public.students(source_type);
CREATE INDEX IF NOT EXISTS idx_students_programme_version ON public.students(programme_version_id);
CREATE INDEX IF NOT EXISTS idx_import_batches_status ON public.historical_import_batches(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_import_rows_batch_status ON public.historical_import_rows(batch_id, validation_status);
CREATE INDEX IF NOT EXISTS idx_attempts_student_period ON public.student_course_attempts(student_id, academic_year_id, semester_id);
CREATE INDEX IF NOT EXISTS idx_attempts_course ON public.student_course_attempts(course_id);

INSERT INTO public.student_cohorts (institution_id, cohort_code, cohort_name, entry_year, default_academic_year_id)
SELECT i.id, y::text, 'Cohort ' || y::text, y, ay.id
FROM public.institutions i
CROSS JOIN generate_series(2023, 2026) y
LEFT JOIN public.academic_years ay ON ay.year_code = y::text || '/' || (y + 1)::text
WHERE i.institution_code = 'IDMS'
ON CONFLICT (institution_id, entry_year) DO UPDATE SET
  default_academic_year_id = COALESCE(public.student_cohorts.default_academic_year_id, EXCLUDED.default_academic_year_id),
  updated_at = now();

INSERT INTO public.permissions(permission_code, permission_name, module_code, action_code, description, status)
VALUES
 ('historical_students.view','View historical students and data quality','historical_students','view','View cohorts, imports and reconciliation reports','ACTIVE'),
 ('historical_students.validate','Validate historical student imports','historical_students','validate','Upload, validate and preview historical student data','ACTIVE'),
 ('historical_students.import','Confirm historical student imports','historical_students','import','Create students from a validated historical batch','ACTIVE'),
 ('historical_students.rollback','Reconcile or roll back historical imports','historical_students','rollback','Deactivate records created by an incorrect import while preserving audit history','ACTIVE')
ON CONFLICT (permission_code) DO UPDATE SET permission_name=EXCLUDED.permission_name, description=EXCLUDED.description, status='ACTIVE', updated_at=now();

INSERT INTO public.role_permissions(role_id, permission_id)
SELECT r.id, p.id FROM public.roles r CROSS JOIN public.permissions p
WHERE r.role_code IN ('SUPER_ADMIN','ADMIN','REGISTRAR','ACADEMIC_OFFICER')
  AND p.permission_code IN ('historical_students.view','historical_students.validate','historical_students.import')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions(role_id, permission_id)
SELECT r.id, p.id FROM public.roles r CROSS JOIN public.permissions p
WHERE r.role_code IN ('SUPER_ADMIN','REGISTRAR') AND p.permission_code='historical_students.rollback'
ON CONFLICT (role_id, permission_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.record_student_status_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.student_status IS DISTINCT FROM OLD.student_status THEN
    INSERT INTO public.student_status_history(student_id, old_status, new_status, reason, changed_at)
    VALUES (NEW.id, OLD.student_status, NEW.student_status, 'Status changed through IDMC iMIS', now());
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_record_student_status_change ON public.students;
CREATE TRIGGER trg_record_student_status_change AFTER UPDATE OF student_status ON public.students
FOR EACH ROW EXECUTE FUNCTION public.record_student_status_change();

CREATE OR REPLACE VIEW public.historical_student_quality_v AS
SELECT
  s.id, s.student_number, s.first_name, s.middle_name, s.last_name,
  s.admission_year AS cohort_year, s.student_status, s.source_type,
  s.programme_id, s.programme_version_id, s.curriculum_id, s.entry_academic_year_id,
  (s.programme_id IS NOT NULL) AS has_programme,
  (s.programme_version_id IS NOT NULL) AS has_programme_version,
  (s.curriculum_id IS NOT NULL) AS has_curriculum,
  (s.entry_academic_year_id IS NOT NULL) AS has_academic_year,
  EXISTS (SELECT 1 FROM public.student_course_attempts a WHERE a.student_id=s.id) AS has_academic_records,
  EXISTS (SELECT 1 FROM public.graduation_candidates g WHERE g.student_id=s.id) AS has_graduation_record,
  EXISTS (SELECT 1 FROM public.alumni_records ar WHERE ar.student_id=s.id) AS has_alumni_record
FROM public.students s
WHERE s.source_type IN ('HISTORICAL_IMPORT','MANUAL_ENTRY') OR s.admission_year BETWEEN 2023 AND 2026;

ALTER TABLE public.student_cohorts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.historical_import_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.historical_import_rows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_course_attempts ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.historical_import_batches IS 'Auditable upload/validation/confirmation batches for legacy students; never replaces Admissions.';
COMMENT ON TABLE public.student_course_attempts IS 'Preserves every academic attempt without overwriting earlier failures or repeats.';

COMMIT;
