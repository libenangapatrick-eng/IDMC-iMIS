-- ============================================================
-- IDMC iMIS
-- MIGRATION 017
-- GRADUATION, CLEARANCE & CERTIFICATION CORE
--
-- Includes:
--   - Dependency validation
--   - Graduation periods
--   - Graduation candidates
--   - Clearance workflow
--   - Approval workflow
--   - Graduation awards
--   - Certificates
--   - Certificate verification
--   - Alumni
--   - Integrity functions
--   - Status transition protection
--   - Certificate immutability
--   - RLS baseline
-- ============================================================

BEGIN;


-- ============================================================
-- 0. DEPENDENCY VALIDATION
--
-- These objects must already exist because Migration 017
-- depends on the academic/student foundation.
-- ============================================================

DO $dependency_check$
DECLARE
    v_missing text[];
BEGIN

    SELECT ARRAY_AGG(x.object_name)
    INTO v_missing
    FROM (
        SELECT 'public.academic_years' AS object_name
        WHERE to_regclass('public.academic_years') IS NULL

        UNION ALL

        SELECT 'public.students'
        WHERE to_regclass('public.students') IS NULL

        UNION ALL

        SELECT 'public.programmes'
        WHERE to_regclass('public.programmes') IS NULL

        UNION ALL

        SELECT 'public.programme_versions'
        WHERE to_regclass('public.programme_versions') IS NULL

        UNION ALL

        SELECT 'public.student_transcripts'
        WHERE to_regclass('public.student_transcripts') IS NULL

        UNION ALL

        SELECT 'public.set_updated_at()'
        WHERE NOT EXISTS (
            SELECT 1
            FROM pg_proc p
            JOIN pg_namespace n
              ON n.oid = p.pronamespace
            WHERE n.nspname = 'public'
              AND p.proname = 'set_updated_at'
        )
    ) x;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION
            'Migration 017 dependency check failed. Missing: %',
            array_to_string(v_missing, ', ');
    END IF;

END;
$dependency_check$;


-- ============================================================
-- 0.1 COLUMN DEPENDENCY VALIDATION
-- ============================================================

DO $column_check$
DECLARE
    v_missing text[];
BEGIN

    SELECT ARRAY_AGG(x.object_name)
    INTO v_missing
    FROM (
        SELECT 'students.id' AS object_name
        WHERE NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema='public'
              AND table_name='students'
              AND column_name='id'
        )

        UNION ALL

        SELECT 'students.programme_id'
        WHERE NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema='public'
              AND table_name='students'
              AND column_name='programme_id'
        )

        UNION ALL

        SELECT 'students.programme_version_id'
        WHERE NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema='public'
              AND table_name='students'
              AND column_name='programme_version_id'
        )

        UNION ALL

        SELECT 'students.student_status'
        WHERE NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema='public'
              AND table_name='students'
              AND column_name='student_status'
        )

        UNION ALL

        SELECT 'student_transcripts.id'
        WHERE NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema='public'
              AND table_name='student_transcripts'
              AND column_name='id'
        )
    ) x;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION
            'Migration 017 column dependency check failed. Missing: %',
            array_to_string(v_missing, ', ');
    END IF;

END;
$column_check$;


-- ============================================================
-- 1. GRADUATION PERIODS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.graduation_periods (

    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    academic_year_id uuid NOT NULL
        REFERENCES public.academic_years(id),

    graduation_number varchar(50) NOT NULL UNIQUE,

    graduation_name varchar(200) NOT NULL,

    graduation_date date NOT NULL,

    application_open_at timestamptz,

    application_close_at timestamptz,

    status varchar(30) NOT NULL DEFAULT 'DRAFT',

    remarks text,

    created_by uuid,

    updated_by uuid,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT graduation_periods_status_chk
    CHECK (
        status IN (
            'DRAFT',
            'OPEN',
            'CLOSED',
            'APPROVED',
            'COMPLETED',
            'CANCELLED'
        )
    ),

    CONSTRAINT graduation_periods_dates_chk
    CHECK (
        application_close_at IS NULL
        OR application_open_at IS NULL
        OR application_close_at >= application_open_at
    )
);


-- ============================================================
-- 2. GRADUATION CANDIDATES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.graduation_candidates (

    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    graduation_period_id uuid NOT NULL
        REFERENCES public.graduation_periods(id),

    student_id uuid NOT NULL
        REFERENCES public.students(id),

    programme_id uuid NOT NULL
        REFERENCES public.programmes(id),

    programme_version_id uuid
        REFERENCES public.programme_versions(id),

    eligibility_status varchar(30) NOT NULL DEFAULT 'PENDING',

    academic_completion_status varchar(30) NOT NULL DEFAULT 'PENDING',

    final_cgpa numeric(5,2),

    award_classification varchar(100),

    candidate_status varchar(30) NOT NULL DEFAULT 'PENDING',

    eligible_at timestamptz,

    approved_at timestamptz,

    approved_by uuid,

    remarks text,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT graduation_candidates_eligibility_chk
    CHECK (
        eligibility_status IN (
            'PENDING',
            'ELIGIBLE',
            'INELIGIBLE',
            'REVIEW'
        )
    ),

    CONSTRAINT graduation_candidates_academic_chk
    CHECK (
        academic_completion_status IN (
            'PENDING',
            'COMPLETE',
            'INCOMPLETE'
        )
    ),

    CONSTRAINT graduation_candidates_status_chk
    CHECK (
        candidate_status IN (
            'PENDING',
            'CLEARED',
            'APPROVED',
            'GRADUATED',
            'WITHDRAWN',
            'REJECTED'
        )
    ),

    CONSTRAINT graduation_candidates_cgpa_chk
    CHECK (
        final_cgpa IS NULL
        OR (
            final_cgpa >= 0
            AND final_cgpa <= 5
        )
    ),

    CONSTRAINT graduation_candidates_unique_student
    UNIQUE (
        graduation_period_id,
        student_id
    )
);


-- ============================================================
-- 3. GRADUATION CLEARANCES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.graduation_clearances (

    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    graduation_candidate_id uuid NOT NULL
        REFERENCES public.graduation_candidates(id)
        ON DELETE CASCADE,

    clearance_type varchar(30) NOT NULL,

    status varchar(30) NOT NULL DEFAULT 'PENDING',

    amount_due numeric(14,2) NOT NULL DEFAULT 0,

    amount_cleared numeric(14,2) NOT NULL DEFAULT 0,

    remarks text,

    cleared_by uuid,

    cleared_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT graduation_clearances_type_chk
    CHECK (
        clearance_type IN (
            'ACADEMIC',
            'FINANCE',
            'LIBRARY',
            'HOSTEL',
            'DEPARTMENT',
            'DISCIPLINE',
            'DOCUMENTS'
        )
    ),

    CONSTRAINT graduation_clearances_status_chk
    CHECK (
        status IN (
            'PENDING',
            'CLEARED',
            'NOT_CLEARED',
            'WAIVED'
        )
    ),

    CONSTRAINT graduation_clearances_amount_chk
    CHECK (
        amount_due >= 0
        AND amount_cleared >= 0
    ),

    CONSTRAINT graduation_clearances_unique_type
    UNIQUE (
        graduation_candidate_id,
        clearance_type
    )
);


-- ============================================================
-- 4. CLEARANCE ITEMS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.graduation_clearance_items (

    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    graduation_clearance_id uuid NOT NULL
        REFERENCES public.graduation_clearances(id)
        ON DELETE CASCADE,

    item_code varchar(50),

    item_name varchar(200) NOT NULL,

    status varchar(30) NOT NULL DEFAULT 'PENDING',

    amount_due numeric(14,2) NOT NULL DEFAULT 0,

    amount_cleared numeric(14,2) NOT NULL DEFAULT 0,

    remarks text,

    resolved_by uuid,

    resolved_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT graduation_clearance_items_status_chk
    CHECK (
        status IN (
            'PENDING',
            'CLEARED',
            'NOT_CLEARED',
            'WAIVED'
        )
    ),

    CONSTRAINT graduation_clearance_items_amount_chk
    CHECK (
        amount_due >= 0
        AND amount_cleared >= 0
    )
);


-- ============================================================
-- 5. GRADUATION APPROVALS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.graduation_approvals (

    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    graduation_candidate_id uuid NOT NULL
        REFERENCES public.graduation_candidates(id)
        ON DELETE CASCADE,

    approval_stage varchar(40) NOT NULL,

    decision varchar(30) NOT NULL DEFAULT 'PENDING',

    comments text,

    approved_by uuid,

    approved_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT graduation_approvals_stage_chk
    CHECK (
        approval_stage IN (
            'DEPARTMENT',
            'HOD',
            'ACADEMIC',
            'EXAMINATION',
            'MANAGEMENT'
        )
    ),

    CONSTRAINT graduation_approvals_decision_chk
    CHECK (
        decision IN (
            'PENDING',
            'APPROVED',
            'REJECTED',
            'RETURNED'
        )
    ),

    CONSTRAINT graduation_approvals_unique_stage
    UNIQUE (
        graduation_candidate_id,
        approval_stage
    )
);


-- ============================================================
-- 6. GRADUATION AWARDS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.graduation_awards (

    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    graduation_candidate_id uuid NOT NULL UNIQUE
        REFERENCES public.graduation_candidates(id),

    award_name varchar(200) NOT NULL,

    award_classification varchar(100),

    final_cgpa numeric(5,2),

    graduation_date date NOT NULL,

    certificate_number varchar(100) UNIQUE,

    transcript_id uuid
        REFERENCES public.student_transcripts(id),

    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT graduation_awards_cgpa_chk
    CHECK (
        final_cgpa IS NULL
        OR (
            final_cgpa >= 0
            AND final_cgpa <= 5
        )
    )
);


-- ============================================================
-- 7. CERTIFICATES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.certificates (

    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    graduation_award_id uuid NOT NULL
        REFERENCES public.graduation_awards(id),

    student_id uuid NOT NULL
        REFERENCES public.students(id),

    certificate_number varchar(100) NOT NULL UNIQUE,

    certificate_type varchar(50) NOT NULL DEFAULT 'ACADEMIC',

    award_name varchar(200) NOT NULL,

    programme_id uuid
        REFERENCES public.programmes(id),

    programme_version_id uuid
        REFERENCES public.programme_versions(id),

    issue_date date,

    verification_code varchar(100) NOT NULL UNIQUE,

    document_file_id uuid,

    status varchar(30) NOT NULL DEFAULT 'DRAFT',

    issued_by uuid,

    issued_at timestamptz,

    revoked_by uuid,

    revoked_at timestamptz,

    revocation_reason text,

    replacement_of uuid
        REFERENCES public.certificates(id),

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT certificates_status_chk
    CHECK (
        status IN (
            'DRAFT',
            'APPROVED',
            'ISSUED',
            'REVOKED',
            'REPLACED'
        )
    )
);


-- ============================================================
-- 8. CERTIFICATE VERIFICATIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.certificate_verifications (

    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    certificate_id uuid NOT NULL
        REFERENCES public.certificates(id),

    verification_code varchar(100) NOT NULL,

    verified_at timestamptz NOT NULL DEFAULT now(),

    verification_result varchar(30) NOT NULL,

    ip_address inet,

    user_agent text,

    CONSTRAINT certificate_verifications_result_chk
    CHECK (
        verification_result IN (
            'VALID',
            'INVALID',
            'REVOKED',
            'REPLACED'
        )
    )
);


-- ============================================================
-- 9. ALUMNI
-- ============================================================

CREATE TABLE IF NOT EXISTS public.alumni_records (

    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL UNIQUE
        REFERENCES public.students(id),

    graduation_candidate_id uuid
        REFERENCES public.graduation_candidates(id),

    graduation_award_id uuid
        REFERENCES public.graduation_awards(id),

    alumni_number varchar(100) NOT NULL UNIQUE,

    graduation_year integer NOT NULL,

    status varchar(30) NOT NULL DEFAULT 'ACTIVE',

    current_employer varchar(200),

    current_position varchar(200),

    phone varchar(50),

    email varchar(255),

    address text,

    linkedin_url text,

    website_url text,

    joined_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT alumni_records_status_chk
    CHECK (
        status IN (
            'ACTIVE',
            'INACTIVE',
            'DECEASED',
            'UNSUBSCRIBED'
        )
    )
);


-- ============================================================
-- 10. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_graduation_candidates_period
ON public.graduation_candidates(graduation_period_id);

CREATE INDEX IF NOT EXISTS idx_graduation_candidates_student
ON public.graduation_candidates(student_id);

CREATE INDEX IF NOT EXISTS idx_graduation_candidates_status
ON public.graduation_candidates(candidate_status);

CREATE INDEX IF NOT EXISTS idx_graduation_candidates_eligibility
ON public.graduation_candidates(eligibility_status);

CREATE INDEX IF NOT EXISTS idx_graduation_clearances_candidate
ON public.graduation_clearances(graduation_candidate_id);

CREATE INDEX IF NOT EXISTS idx_graduation_clearances_status
ON public.graduation_clearances(status);

CREATE INDEX IF NOT EXISTS idx_graduation_approvals_candidate
ON public.graduation_approvals(graduation_candidate_id);

CREATE INDEX IF NOT EXISTS idx_certificates_student
ON public.certificates(student_id);

CREATE INDEX IF NOT EXISTS idx_certificates_verification
ON public.certificates(verification_code);

CREATE INDEX IF NOT EXISTS idx_certificate_verifications_code
ON public.certificate_verifications(verification_code);

CREATE INDEX IF NOT EXISTS idx_alumni_graduation_year
ON public.alumni_records(graduation_year);


-- ============================================================
-- 11. UPDATED_AT TRIGGERS
-- ============================================================

DROP TRIGGER IF EXISTS trg_graduation_periods_updated_at
ON public.graduation_periods;

CREATE TRIGGER trg_graduation_periods_updated_at
BEFORE UPDATE ON public.graduation_periods
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_graduation_candidates_updated_at
ON public.graduation_candidates;

CREATE TRIGGER trg_graduation_candidates_updated_at
BEFORE UPDATE ON public.graduation_candidates
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_graduation_clearances_updated_at
ON public.graduation_clearances;

CREATE TRIGGER trg_graduation_clearances_updated_at
BEFORE UPDATE ON public.graduation_clearances
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_graduation_clearance_items_updated_at
ON public.graduation_clearance_items;

CREATE TRIGGER trg_graduation_clearance_items_updated_at
BEFORE UPDATE ON public.graduation_clearance_items
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_certificates_updated_at
ON public.certificates;

CREATE TRIGGER trg_certificates_updated_at
BEFORE UPDATE ON public.certificates
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_alumni_records_updated_at
ON public.alumni_records;

CREATE TRIGGER trg_alumni_records_updated_at
BEFORE UPDATE ON public.alumni_records
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 12. GENERATE REQUIRED CLEARANCES
-- ============================================================

CREATE OR REPLACE FUNCTION public.generate_graduation_clearances(
    p_graduation_candidate_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$

DECLARE
    v_type varchar(30);
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM public.graduation_candidates
        WHERE id = p_graduation_candidate_id
    ) THEN
        RAISE EXCEPTION
            'Graduation candidate % does not exist',
            p_graduation_candidate_id;
    END IF;


    FOREACH v_type IN ARRAY ARRAY[
        'ACADEMIC',
        'FINANCE',
        'LIBRARY',
        'HOSTEL',
        'DEPARTMENT',
        'DISCIPLINE',
        'DOCUMENTS'
    ]
    LOOP

        INSERT INTO public.graduation_clearances (
            graduation_candidate_id,
            clearance_type
        )
        VALUES (
            p_graduation_candidate_id,
            v_type
        )
        ON CONFLICT (
            graduation_candidate_id,
            clearance_type
        )
        DO NOTHING;

    END LOOP;

END;

$function$;


-- ============================================================
-- 13. AUTO-GENERATE CLEARANCES FOR NEW CANDIDATES
-- ============================================================

CREATE OR REPLACE FUNCTION public.trg_generate_graduation_clearances()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN

    PERFORM public.generate_graduation_clearances(NEW.id);

    RETURN NEW;

END;
$function$;


DROP TRIGGER IF EXISTS trg_generate_graduation_clearances
ON public.graduation_candidates;

CREATE TRIGGER trg_generate_graduation_clearances
AFTER INSERT ON public.graduation_candidates
FOR EACH ROW
EXECUTE FUNCTION public.trg_generate_graduation_clearances();


-- ============================================================
-- 14. CLEARANCE INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_graduation_clearance()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN

    IF NEW.status = 'CLEARED' THEN

        IF NEW.cleared_by IS NULL THEN
            RAISE EXCEPTION
                'Cleared graduation clearance must have cleared_by';
        END IF;

        IF NEW.cleared_at IS NULL THEN
            NEW.cleared_at := now();
        END IF;

        IF NEW.amount_cleared < NEW.amount_due THEN

            IF NEW.clearance_type = 'FINANCE' THEN
                RAISE EXCEPTION
                    'Finance clearance cannot be CLEARED while amount cleared (%) is below amount due (%)',
                    NEW.amount_cleared,
                    NEW.amount_due;
            END IF;

        END IF;

    END IF;


    IF NEW.status = 'WAIVED'
       AND NULLIF(trim(COALESCE(NEW.remarks, '')), '') IS NULL THEN

        RAISE EXCEPTION
            'Waived clearance requires remarks';
    END IF;


    RETURN NEW;

END;
$function$;


DROP TRIGGER IF EXISTS trg_validate_graduation_clearance
ON public.graduation_clearances;

CREATE TRIGGER trg_validate_graduation_clearance
BEFORE INSERT OR UPDATE
ON public.graduation_clearances
FOR EACH ROW
EXECUTE FUNCTION public.validate_graduation_clearance();


-- ============================================================
-- 15. CANDIDATE ELIGIBILITY INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_graduation_candidate()
RETURNS trigger
LANGUAGE plpgsql
AS $function$

DECLARE
    v_student_programme uuid;
    v_student_version uuid;
BEGIN

    SELECT
        programme_id,
        programme_version_id
    INTO
        v_student_programme,
        v_student_version
    FROM public.students
    WHERE id = NEW.student_id;


    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Student % does not exist',
            NEW.student_id;
    END IF;


    -- Candidate programme must match current student programme
    IF NEW.programme_id <> v_student_programme THEN
        RAISE EXCEPTION
            'Graduation candidate programme % does not match student programme %',
            NEW.programme_id,
            v_student_programme;
    END IF;


    -- If both programme versions are available, they must match
    IF NEW.programme_version_id IS NOT NULL
       AND v_student_version IS NOT NULL
       AND NEW.programme_version_id <> v_student_version THEN

        RAISE EXCEPTION
            'Graduation candidate programme version does not match student programme version';

    END IF;


    -- Eligible candidate must have complete academics
    IF NEW.eligibility_status = 'ELIGIBLE'
       AND NEW.academic_completion_status <> 'COMPLETE' THEN

        RAISE EXCEPTION
            'Student cannot be marked ELIGIBLE before academic completion is COMPLETE';

    END IF;


    -- Approved candidate must be eligible
    IF NEW.candidate_status = 'APPROVED'
       AND NEW.eligibility_status <> 'ELIGIBLE' THEN

        RAISE EXCEPTION
            'Graduation candidate cannot be APPROVED unless eligibility is ELIGIBLE';

    END IF;


    -- Graduated candidate must have approval
    IF NEW.candidate_status = 'GRADUATED'
       AND NEW.eligibility_status <> 'ELIGIBLE' THEN

        RAISE EXCEPTION
            'Graduation candidate cannot be GRADUATED unless eligibility is ELIGIBLE';

    END IF;


    RETURN NEW;

END;
$function$;


DROP TRIGGER IF EXISTS trg_validate_graduation_candidate
ON public.graduation_candidates;

CREATE TRIGGER trg_validate_graduation_candidate
BEFORE INSERT OR UPDATE
ON public.graduation_candidates
FOR EACH ROW
EXECUTE FUNCTION public.validate_graduation_candidate();


-- ============================================================
-- 16. GRADUATION STATUS TRANSITIONS
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_graduation_candidate_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN

    IF OLD.candidate_status = NEW.candidate_status THEN
        RETURN NEW;
    END IF;


    IF OLD.candidate_status = 'PENDING'
       AND NEW.candidate_status NOT IN (
           'CLEARED',
           'REJECTED',
           'WITHDRAWN'
       ) THEN

        RAISE EXCEPTION
            'Invalid graduation candidate transition: % -> %',
            OLD.candidate_status,
            NEW.candidate_status;

    END IF;


    IF OLD.candidate_status = 'CLEARED'
       AND NEW.candidate_status NOT IN (
           'APPROVED',
           'REJECTED',
           'WITHDRAWN'
       ) THEN

        RAISE EXCEPTION
            'Invalid graduation candidate transition: % -> %',
            OLD.candidate_status,
            NEW.candidate_status;

    END IF;


    IF OLD.candidate_status = 'APPROVED'
       AND NEW.candidate_status <> 'GRADUATED' THEN

        RAISE EXCEPTION
            'Approved graduation candidate can only transition to GRADUATED';

    END IF;


    IF OLD.candidate_status IN (
        'GRADUATED',
        'REJECTED',
        'WITHDRAWN'
    ) THEN

        RAISE EXCEPTION
            'Final graduation candidate status % cannot be changed',
            OLD.candidate_status;

    END IF;


    RETURN NEW;

END;
$function$;


DROP TRIGGER IF EXISTS trg_graduation_candidate_transition
ON public.graduation_candidates;

CREATE TRIGGER trg_graduation_candidate_transition
BEFORE UPDATE
ON public.graduation_candidates
FOR EACH ROW
EXECUTE FUNCTION public.validate_graduation_candidate_transition();


-- ============================================================
-- 17. APPROVAL INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_graduation_approval()
RETURNS trigger
LANGUAGE plpgsql
AS $function$

DECLARE
    v_status varchar(30);
BEGIN

    SELECT candidate_status
    INTO v_status
    FROM public.graduation_candidates
    WHERE id = NEW.graduation_candidate_id;


    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Graduation candidate does not exist';
    END IF;


    IF NEW.decision = 'APPROVED' THEN

        IF NEW.approved_by IS NULL THEN
            RAISE EXCEPTION
                'Approved graduation stage requires approved_by';
        END IF;

        IF NEW.approved_at IS NULL THEN
            NEW.approved_at := now();
        END IF;

    END IF;


    RETURN NEW;

END;
$function$;


DROP TRIGGER IF EXISTS trg_validate_graduation_approval
ON public.graduation_approvals;

CREATE TRIGGER trg_validate_graduation_approval
BEFORE INSERT OR UPDATE
ON public.graduation_approvals
FOR EACH ROW
EXECUTE FUNCTION public.validate_graduation_approval();


-- ============================================================
-- 18. CERTIFICATE INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_certificate()
RETURNS trigger
LANGUAGE plpgsql
AS $function$

DECLARE
    v_candidate_status varchar(30);
    v_student_id uuid;
BEGIN

    SELECT
        gc.candidate_status,
        gc.student_id
    INTO
        v_candidate_status,
        v_student_id
    FROM public.graduation_candidates gc
    INNER JOIN public.graduation_awards ga
        ON ga.graduation_candidate_id = gc.id
    WHERE ga.id = NEW.graduation_award_id;


    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Certificate requires a valid graduation award';
    END IF;


    -- Certificate student must match graduation candidate
    IF NEW.student_id <> v_student_id THEN
        RAISE EXCEPTION
            'Certificate student does not match graduation award student';
    END IF;


    -- Certificate cannot be issued before graduation
    IF NEW.status = 'ISSUED' THEN

        IF v_candidate_status <> 'GRADUATED' THEN
            RAISE EXCEPTION
                'Certificate cannot be ISSUED before graduation candidate is GRADUATED';
        END IF;


        IF NEW.issued_by IS NULL THEN
            RAISE EXCEPTION
                'Issued certificate requires issued_by';
        END IF;


        IF NEW.issue_date IS NULL THEN
            NEW.issue_date := CURRENT_DATE;
        END IF;


        IF NEW.issued_at IS NULL THEN
            NEW.issued_at := now();
        END IF;

    END IF;


    -- Revocation requires reason and actor
    IF NEW.status = 'REVOKED' THEN

        IF NEW.revoked_by IS NULL THEN
            RAISE EXCEPTION
                'Revoked certificate requires revoked_by';
        END IF;

        IF NULLIF(
            trim(
                COALESCE(
                    NEW.revocation_reason,
                    ''
                )
            ),
            ''
        ) IS NULL THEN

            RAISE EXCEPTION
                'Certificate revocation requires a reason';

        END IF;


        IF NEW.revoked_at IS NULL THEN
            NEW.revoked_at := now();
        END IF;

    END IF;


    RETURN NEW;

END;
$function$;


DROP TRIGGER IF EXISTS trg_validate_certificate
ON public.certificates;

CREATE TRIGGER trg_validate_certificate
BEFORE INSERT OR UPDATE
ON public.certificates
FOR EACH ROW
EXECUTE FUNCTION public.validate_certificate();


-- ============================================================
-- 19. CERTIFICATE IMMUTABILITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_issued_certificate_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN

    IF OLD.status = 'ISSUED' THEN

        IF NEW.student_id IS DISTINCT FROM OLD.student_id
           OR NEW.certificate_number IS DISTINCT FROM OLD.certificate_number
           OR NEW.verification_code IS DISTINCT FROM OLD.verification_code
           OR NEW.award_name IS DISTINCT FROM OLD.award_name
           OR NEW.programme_id IS DISTINCT FROM OLD.programme_id
           OR NEW.programme_version_id IS DISTINCT FROM OLD.programme_version_id
           OR NEW.issue_date IS DISTINCT FROM OLD.issue_date
           OR NEW.graduation_award_id IS DISTINCT FROM OLD.graduation_award_id THEN

            RAISE EXCEPTION
                'Issued certificate cannot have its academic identity or verification data modified';

        END IF;

    END IF;


    IF OLD.status IN ('REVOKED', 'REPLACED')
       AND NEW.status <> OLD.status THEN

        RAISE EXCEPTION
            'Final certificate status % cannot be changed',
            OLD.status;

    END IF;


    RETURN NEW;

END;
$function$;


DROP TRIGGER IF EXISTS trg_prevent_issued_certificate_change
ON public.certificates;

CREATE TRIGGER trg_prevent_issued_certificate_change
BEFORE UPDATE
ON public.certificates
FOR EACH ROW
EXECUTE FUNCTION public.prevent_issued_certificate_change();


-- ============================================================
-- 20. CERTIFICATE REPLACEMENT INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_certificate_replacement()
RETURNS trigger
LANGUAGE plpgsql
AS $function$

DECLARE
    v_old_status varchar(30);
BEGIN

    IF NEW.replacement_of IS NULL THEN
        RETURN NEW;
    END IF;


    IF NEW.replacement_of = NEW.id THEN
        RAISE EXCEPTION
            'Certificate cannot replace itself';
    END IF;


    SELECT status
    INTO v_old_status
    FROM public.certificates
    WHERE id = NEW.replacement_of;


    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Replacement certificate references a certificate that does not exist';
    END IF;


    IF v_old_status NOT IN (
        'ISSUED',
        'REVOKED',
        'REPLACED'
    ) THEN

        RAISE EXCEPTION
            'A replacement must reference an issued/final certificate';

    END IF;


    RETURN NEW;

END;
$function$;


DROP TRIGGER IF EXISTS trg_validate_certificate_replacement
ON public.certificates;

CREATE TRIGGER trg_validate_certificate_replacement
BEFORE INSERT OR UPDATE
ON public.certificates
FOR EACH ROW
EXECUTE FUNCTION public.validate_certificate_replacement();


-- ============================================================
-- 21. ALUMNI INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_alumni_record()
RETURNS trigger
LANGUAGE plpgsql
AS $function$

DECLARE
    v_status varchar(30);
BEGIN

    SELECT student_status
    INTO v_status
    FROM public.students
    WHERE id = NEW.student_id;


    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Alumni record references a student that does not exist';
    END IF;


    IF v_status <> 'GRADUATED' THEN
        RAISE EXCEPTION
            'Only GRADUATED students can become alumni';
    END IF;


    IF NEW.graduation_year < 2000
       OR NEW.graduation_year >
          EXTRACT(YEAR FROM CURRENT_DATE)::integer + 1 THEN

        RAISE EXCEPTION
            'Invalid graduation year %',
            NEW.graduation_year;

    END IF;


    RETURN NEW;

END;
$function$;


DROP TRIGGER IF EXISTS trg_validate_alumni_record
ON public.alumni_records;

CREATE TRIGGER trg_validate_alumni_record
BEFORE INSERT OR UPDATE
ON public.alumni_records
FOR EACH ROW
EXECUTE FUNCTION public.validate_alumni_record();


-- ============================================================
-- 22. GRADUATION AWARD INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_graduation_award()
RETURNS trigger
LANGUAGE plpgsql
AS $function$

DECLARE
    v_status varchar(30);
BEGIN

    SELECT candidate_status
    INTO v_status
    FROM public.graduation_candidates
    WHERE id = NEW.graduation_candidate_id;


    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Graduation award requires a valid graduation candidate';
    END IF;


    IF v_status <> 'GRADUATED' THEN
        RAISE EXCEPTION
            'Graduation award can only be created for a GRADUATED candidate';
    END IF;


    IF NEW.final_cgpa IS NULL THEN

        RAISE EXCEPTION
            'Graduation award requires final CGPA';

    END IF;


    RETURN NEW;

END;
$function$;


DROP TRIGGER IF EXISTS trg_validate_graduation_award
ON public.graduation_awards;

CREATE TRIGGER trg_validate_graduation_award
BEFORE INSERT OR UPDATE
ON public.graduation_awards
FOR EACH ROW
EXECUTE FUNCTION public.validate_graduation_award();


-- ============================================================
-- 23. RLS
-- ============================================================

ALTER TABLE public.graduation_periods ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.graduation_candidates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.graduation_clearances ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.graduation_clearance_items ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.graduation_approvals ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.graduation_awards ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.certificates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.certificate_verifications ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.alumni_records ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 24. BASIC INDEX FOR ACTIVE CERTIFICATE
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS ux_certificates_active_award
ON public.certificates(graduation_award_id)
WHERE status IN (
    'DRAFT',
    'APPROVED',
    'ISSUED'
);


-- ============================================================
-- 25. ACTIVE GRADUATION PERIOD
-- Only one OPEN period per academic year.
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS ux_graduation_period_open_year
ON public.graduation_periods(academic_year_id)
WHERE status = 'OPEN';


COMMIT;
