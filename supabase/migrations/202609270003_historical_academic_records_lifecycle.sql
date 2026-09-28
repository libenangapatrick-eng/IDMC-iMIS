-- ============================================================
-- IDMC iMIS corrective migration - Section 21B
-- Historical academic attempts, import audit and lifecycle view.
-- Additive only. Existing admissions, results and registrations remain intact.
-- ============================================================

BEGIN;

-- Compatibility with installations where the official attempt table was
-- created by the transcript module before Section 21A.
ALTER TABLE public.student_course_attempts ADD COLUMN IF NOT EXISTS programme_version_id uuid REFERENCES public.programme_versions(id) ON DELETE RESTRICT;
ALTER TABLE public.student_course_attempts ADD COLUMN IF NOT EXISTS curriculum_id uuid REFERENCES public.curricula(id) ON DELETE RESTRICT;
ALTER TABLE public.student_course_attempts ADD COLUMN IF NOT EXISTS attempt_date date;
ALTER TABLE public.student_course_attempts ADD COLUMN IF NOT EXISTS coursework_mark numeric(8,2);
ALTER TABLE public.student_course_attempts ADD COLUMN IF NOT EXISTS examination_mark numeric(8,2);
ALTER TABLE public.student_course_attempts ADD COLUMN IF NOT EXISTS pass_status varchar(30);
ALTER TABLE public.student_course_attempts ADD COLUMN IF NOT EXISTS result_type varchar(30) NOT NULL DEFAULT 'NORMAL';
ALTER TABLE public.student_course_attempts ADD COLUMN IF NOT EXISTS source_type varchar(30) NOT NULL DEFAULT 'NORMAL_ADMISSION';
ALTER TABLE public.student_course_attempts ADD COLUMN IF NOT EXISTS recorded_by uuid REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.student_course_attempts ADD COLUMN IF NOT EXISTS recorded_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.student_course_attempts ADD COLUMN IF NOT EXISTS locked_by uuid REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.student_course_attempts ADD COLUMN IF NOT EXISTS locked_at timestamptz;
ALTER TABLE public.student_course_attempts DROP CONSTRAINT IF EXISTS student_course_attempts_attempt_status_check;
ALTER TABLE public.student_course_attempts ADD CONSTRAINT student_course_attempts_attempt_status_check CHECK
 (attempt_status IN ('ACTIVE','PASSED','FAILED','REPLACED','WITHDRAWN','CANCELLED','REGISTERED','ATTEMPTED','RECORDED','PUBLISHED','LOCKED'));
ALTER TABLE public.student_course_attempts DROP CONSTRAINT IF EXISTS student_course_attempts_pass_status_check;
ALTER TABLE public.student_course_attempts ADD CONSTRAINT student_course_attempts_pass_status_check CHECK
 (pass_status IS NULL OR pass_status IN ('PASS','FAIL','SUPPLEMENTARY','INCOMPLETE','WITHHELD','WITHDRAWN'));
ALTER TABLE public.student_course_attempts DROP CONSTRAINT IF EXISTS student_course_attempts_result_type_check;
ALTER TABLE public.student_course_attempts ADD CONSTRAINT student_course_attempts_result_type_check CHECK
 (result_type IN ('NORMAL','SUPPLEMENTARY','SPECIAL','RESIT','RETAKE','REPEAT','CARRY_FORWARD','MAKEUP'));
ALTER TABLE public.student_course_attempts DROP CONSTRAINT IF EXISTS student_course_attempts_source_type_check;
ALTER TABLE public.student_course_attempts ADD CONSTRAINT student_course_attempts_source_type_check CHECK
 (source_type IN ('NORMAL_ADMISSION','HISTORICAL_IMPORT','MANUAL_ENTRY'));

CREATE TABLE IF NOT EXISTS public.historical_academic_import_batches (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_number varchar(70) NOT NULL UNIQUE,
    institution_id uuid NOT NULL REFERENCES public.institutions(id) ON DELETE RESTRICT,
    source_format varchar(20) NOT NULL CHECK (source_format IN ('CSV','XLSX','MANUAL')),
    source_file_name varchar(255),
    source_file_sha256 varchar(64),
    status varchar(30) NOT NULL DEFAULT 'UPLOADED'
      CHECK (status IN ('UPLOADED','VALIDATED','READY','IMPORTING','COMPLETED','COMPLETED_WITH_ERRORS','FAILED','ROLLED_BACK')),
    total_rows integer NOT NULL DEFAULT 0 CHECK (total_rows >= 0),
    valid_rows integer NOT NULL DEFAULT 0 CHECK (valid_rows >= 0),
    invalid_rows integer NOT NULL DEFAULT 0 CHECK (invalid_rows >= 0),
    duplicate_rows integer NOT NULL DEFAULT 0 CHECK (duplicate_rows >= 0),
    imported_rows integer NOT NULL DEFAULT 0 CHECK (imported_rows >= 0),
    skipped_rows integer NOT NULL DEFAULT 0 CHECK (skipped_rows >= 0),
    created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    validated_at timestamptz,
    confirmed_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    confirmed_at timestamptz,
    completed_at timestamptz,
    rolled_back_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    rolled_back_at timestamptz,
    rollback_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (confirmed_by IS NULL OR created_by IS NULL OR confirmed_by <> created_by)
);

CREATE TABLE IF NOT EXISTS public.historical_academic_import_rows (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id uuid NOT NULL REFERENCES public.historical_academic_import_batches(id) ON DELETE RESTRICT,
    row_number integer NOT NULL CHECK (row_number > 0),
    raw_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    normalized_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    validation_status varchar(20) NOT NULL DEFAULT 'PENDING'
      CHECK (validation_status IN ('PENDING','VALID','INVALID','DUPLICATE','IMPORTED','SKIPPED','ROLLED_BACK')),
    validation_errors jsonb NOT NULL DEFAULT '[]'::jsonb,
    course_attempt_id uuid REFERENCES public.student_course_attempts(id) ON DELETE RESTRICT,
    imported_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (batch_id, row_number)
);

ALTER TABLE public.student_course_attempts
  ADD COLUMN IF NOT EXISTS import_row_id uuid REFERENCES public.historical_academic_import_rows(id) ON DELETE RESTRICT;

ALTER TABLE public.student_course_attempts
  ADD COLUMN IF NOT EXISTS academic_import_batch_id uuid REFERENCES public.historical_academic_import_batches(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_historical_academic_batch_status
  ON public.historical_academic_import_batches(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_historical_academic_rows_batch_status
  ON public.historical_academic_import_rows(batch_id, validation_status);
CREATE INDEX IF NOT EXISTS idx_attempts_academic_import_batch
  ON public.student_course_attempts(academic_import_batch_id);

INSERT INTO public.permissions(permission_code, permission_name, module_code, action_code, description, status)
VALUES
 ('historical_academics.view','View historical academic records','historical_academics','view','View academic import batches and student lifecycle reports','ACTIVE'),
 ('historical_academics.validate','Validate historical academic imports','historical_academics','validate','Upload, validate and preview legacy course attempts','ACTIVE'),
 ('historical_academics.import','Confirm historical academic imports','historical_academics','import','Confirm validated attempts using four-eyes approval','ACTIVE'),
 ('historical_academics.rollback','Reconcile historical academic imports','historical_academics','rollback','Cancel an incorrect imported batch without deleting history','ACTIVE'),
 ('student_lifecycle.view','View student academic lifecycle report','student_lifecycle','view','View programme, attempts, GPA, graduation and alumni history','ACTIVE')
ON CONFLICT (permission_code) DO UPDATE SET
  permission_name=EXCLUDED.permission_name,
  description=EXCLUDED.description,
  status='ACTIVE',
  updated_at=now();

INSERT INTO public.role_permissions(role_id, permission_id)
SELECT r.id, p.id FROM public.roles r CROSS JOIN public.permissions p
WHERE r.role_code IN ('SUPER_ADMIN','ADMIN','REGISTRAR','ACADEMIC_OFFICER','EXAMINATION_OFFICER')
  AND p.permission_code IN ('historical_academics.view','historical_academics.validate','historical_academics.import','student_lifecycle.view')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions(role_id, permission_id)
SELECT r.id, p.id FROM public.roles r CROSS JOIN public.permissions p
WHERE r.role_code IN ('SUPER_ADMIN','REGISTRAR')
  AND p.permission_code='historical_academics.rollback'
ON CONFLICT (role_id, permission_id) DO NOTHING;

CREATE OR REPLACE VIEW public.student_academic_lifecycle_v AS
SELECT
  s.id AS student_id,
  s.student_number,
  concat_ws(' ', s.first_name, s.middle_name, s.last_name) AS student_name,
  s.source_type,
  s.student_status,
  s.admission_year AS cohort_year,
  p.programme_code,
  p.programme_name,
  pv.version_code AS programme_version_code,
  pv.version_name AS programme_version_name,
  c.curriculum_code,
  (SELECT count(*) FROM public.student_course_attempts a WHERE a.student_id=s.id AND a.attempt_status <> 'CANCELLED') AS course_attempts,
  (SELECT count(DISTINCT a.course_id) FROM public.student_course_attempts a WHERE a.student_id=s.id AND a.attempt_status <> 'CANCELLED') AS distinct_courses,
  COALESCE((SELECT sum(a.credits) FROM public.student_course_attempts a WHERE a.student_id=s.id AND a.attempt_status <> 'CANCELLED'),0) AS credits_attempted,
  COALESCE((SELECT sum(a.credits) FROM public.student_course_attempts a WHERE a.student_id=s.id AND a.pass_status='PASS' AND a.attempt_status <> 'CANCELLED'),0) AS passed_attempt_credits,
  (SELECT count(*) FROM public.student_course_attempts a WHERE a.student_id=s.id AND a.pass_status='FAIL' AND a.attempt_status <> 'CANCELLED') AS failed_attempts,
  (SELECT cg.cgpa FROM public.student_cgpa_records cg WHERE cg.student_id=s.id ORDER BY cg.calculated_at DESC LIMIT 1) AS latest_cgpa,
  EXISTS (SELECT 1 FROM public.graduation_candidates gc WHERE gc.student_id=s.id AND gc.candidate_status='GRADUATED') AS has_graduated_award,
  EXISTS (SELECT 1 FROM public.alumni_records ar WHERE ar.student_id=s.id) AS has_alumni_record
FROM public.students s
LEFT JOIN public.programmes p ON p.id=s.programme_id
LEFT JOIN public.programme_versions pv ON pv.id=s.programme_version_id
LEFT JOIN public.curricula c ON c.id=s.curriculum_id
;

ALTER TABLE public.historical_academic_import_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.historical_academic_import_rows ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.historical_academic_import_batches IS 'Four-eyes controlled import batches for legacy academic attempts.';
COMMENT ON VIEW public.student_academic_lifecycle_v IS 'Read model joining the official student lifecycle without overwriting historical attempts.';

COMMIT;
