-- ============================================================
-- IDMC iMIS
-- Migration 013: Transcript & Academic Standing Core
-- ============================================================

BEGIN;

-- ============================================================
-- 1. ACADEMIC STANDING RULES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.academic_standing_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    rule_code varchar(50) NOT NULL UNIQUE,
    rule_name varchar(150) NOT NULL,

    minimum_gpa numeric(6,3),
    maximum_gpa numeric(6,3),

    minimum_cgpa numeric(6,3),
    maximum_cgpa numeric(6,3),

    standing_code varchar(50) NOT NULL,
    standing_name varchar(150) NOT NULL,

    description text,

    priority integer NOT NULL DEFAULT 100,

    status varchar(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE','INACTIVE','ARCHIVED')),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT standing_gpa_range_valid
        CHECK (
            (minimum_gpa IS NULL OR minimum_gpa >= 0)
            AND
            (maximum_gpa IS NULL OR maximum_gpa <= 5)
            AND
            (
                minimum_gpa IS NULL
                OR maximum_gpa IS NULL
                OR maximum_gpa >= minimum_gpa
            )
        ),

    CONSTRAINT standing_cgpa_range_valid
        CHECK (
            (minimum_cgpa IS NULL OR minimum_cgpa >= 0)
            AND
            (maximum_cgpa IS NULL OR maximum_cgpa <= 5)
            AND
            (
                minimum_cgpa IS NULL
                OR maximum_cgpa IS NULL
                OR maximum_cgpa >= minimum_cgpa
            )
        )
);


-- ============================================================
-- 2. DEFAULT ACADEMIC STANDING RULES
-- ============================================================

INSERT INTO public.academic_standing_rules (
    rule_code,
    rule_name,
    minimum_gpa,
    maximum_gpa,
    standing_code,
    standing_name,
    description,
    priority
)
VALUES
(
    'GOOD_STANDING',
    'Good Academic Standing',
    2.00,
    5.00,
    'GOOD_STANDING',
    'Good Academic Standing',
    'Initial configurable rule for students meeting the minimum academic performance threshold.',
    10
),
(
    'ACADEMIC_WARNING',
    'Academic Warning',
    1.50,
    1.99,
    'ACADEMIC_WARNING',
    'Academic Warning',
    'Initial configurable warning category.',
    20
),
(
    'ACADEMIC_PROBATION',
    'Academic Probation',
    0.00,
    1.49,
    'ACADEMIC_PROBATION',
    'Academic Probation',
    'Initial configurable probation category.',
    30
)
ON CONFLICT (rule_code) DO NOTHING;


-- ============================================================
-- 3. ACADEMIC STANDING RECORDS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_academic_standings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL
        REFERENCES public.students(id)
        ON DELETE RESTRICT,

    academic_year_id uuid NOT NULL
        REFERENCES public.academic_years(id)
        ON DELETE RESTRICT,

    semester_id uuid NOT NULL
        REFERENCES public.semesters(id)
        ON DELETE RESTRICT,

    semester_result_id uuid
        REFERENCES public.student_semester_results(id)
        ON DELETE RESTRICT,

    gpa numeric(6,3),
    cgpa numeric(6,3),

    standing_rule_id uuid
        REFERENCES public.academic_standing_rules(id)
        ON DELETE RESTRICT,

    standing_code varchar(50),
    standing_name varchar(150),

    remarks text,

    status varchar(20) NOT NULL DEFAULT 'CALCULATED'
        CHECK (status IN (
            'CALCULATED',
            'REVIEW',
            'APPROVED',
            'PUBLISHED',
            'LOCKED'
        )),

    calculated_at timestamptz NOT NULL DEFAULT now(),

    approved_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    approved_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE (
        student_id,
        academic_year_id,
        semester_id
    ),

    CONSTRAINT academic_standing_gpa_valid
        CHECK (
            gpa IS NULL OR (gpa >= 0 AND gpa <= 5)
        ),

    CONSTRAINT academic_standing_cgpa_valid
        CHECK (
            cgpa IS NULL OR (cgpa >= 0 AND cgpa <= 5)
        )
);


-- ============================================================
-- 4. STUDENT COURSE ATTEMPTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_course_attempts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL
        REFERENCES public.students(id)
        ON DELETE RESTRICT,

    course_id uuid
        REFERENCES public.courses(id)
        ON DELETE RESTRICT,

    course_offering_id uuid
        REFERENCES public.course_offerings(id)
        ON DELETE RESTRICT,

    course_registration_id uuid
        REFERENCES public.course_registrations(id)
        ON DELETE RESTRICT,

    course_result_id uuid
        REFERENCES public.course_results(id)
        ON DELETE RESTRICT,

    academic_year_id uuid NOT NULL
        REFERENCES public.academic_years(id)
        ON DELETE RESTRICT,

    semester_id uuid NOT NULL
        REFERENCES public.semesters(id)
        ON DELETE RESTRICT,

    attempt_number integer NOT NULL DEFAULT 1,

    attempt_type varchar(30) NOT NULL DEFAULT 'NORMAL'
        CHECK (attempt_type IN (
            'NORMAL',
            'SUPPLEMENTARY',
            'SPECIAL',
            'RESIT',
            'RETAKE',
            'REPEAT',
            'CARRY_FORWARD',
            'MAKEUP'
        )),

    attempt_status varchar(30) NOT NULL DEFAULT 'ACTIVE'
        CHECK (attempt_status IN (
            'ACTIVE',
            'PASSED',
            'FAILED',
            'REPLACED',
            'WITHDRAWN',
            'CANCELLED'
        )),

    total_mark numeric(8,2),
    grade_code varchar(10),
    grade_point numeric(5,2),

    credits numeric(6,2),

    started_at timestamptz,
    completed_at timestamptz,

    remarks text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT course_attempt_number_valid
        CHECK (attempt_number > 0),

    CONSTRAINT course_attempt_mark_valid
        CHECK (
            total_mark IS NULL
            OR (
                total_mark >= 0
                AND total_mark <= 100
            )
        ),

    CONSTRAINT course_attempt_grade_point_valid
        CHECK (
            grade_point IS NULL
            OR grade_point >= 0
        )
);


-- ============================================================
-- 5. FAILED / OUTSTANDING COURSES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_academic_deficiencies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL
        REFERENCES public.students(id)
        ON DELETE RESTRICT,

    course_id uuid
        REFERENCES public.courses(id)
        ON DELETE RESTRICT,

    course_offering_id uuid
        REFERENCES public.course_offerings(id)
        ON DELETE RESTRICT,

    course_result_id uuid
        REFERENCES public.course_results(id)
        ON DELETE RESTRICT,

    deficiency_type varchar(40) NOT NULL
        CHECK (deficiency_type IN (
            'FAILED',
            'SUPPLEMENTARY_REQUIRED',
            'RETAKE_REQUIRED',
            'REPEAT_REQUIRED',
            'CARRY_FORWARD',
            'INCOMPLETE',
            'WITHHELD'
        )),

    deficiency_status varchar(30) NOT NULL DEFAULT 'OPEN'
        CHECK (deficiency_status IN (
            'OPEN',
            'IN_PROGRESS',
            'RESOLVED',
            'WAIVED',
            'CANCELLED'
        )),

    first_recorded_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,

    resolution_course_result_id uuid
        REFERENCES public.course_results(id)
        ON DELETE RESTRICT,

    remarks text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 6. TRANSCRIPT HEADER
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_transcripts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    transcript_number varchar(80) NOT NULL UNIQUE,

    student_id uuid NOT NULL
        REFERENCES public.students(id)
        ON DELETE RESTRICT,

    programme_version_id uuid
        REFERENCES public.programme_versions(id)
        ON DELETE RESTRICT,

    transcript_type varchar(30) NOT NULL DEFAULT 'OFFICIAL'
        CHECK (transcript_type IN (
            'OFFICIAL',
            'UNOFFICIAL',
            'PROVISIONAL',
            'REPLACEMENT',
            'FINAL'
        )),

    issue_reason varchar(100),

    cumulative_credits numeric(10,2) NOT NULL DEFAULT 0,
    cumulative_earned_credits numeric(10,2) NOT NULL DEFAULT 0,
    cumulative_quality_points numeric(12,3) NOT NULL DEFAULT 0,

    cgpa numeric(6,3),

    final_academic_standing varchar(100),

    transcript_status varchar(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (transcript_status IN (
            'DRAFT',
            'GENERATED',
            'REVIEW',
            'APPROVED',
            'ISSUED',
            'REVOKED',
            'SUPERSEDED'
        )),

    generated_at timestamptz,
    generated_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    approved_at timestamptz,
    approved_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    issued_at timestamptz,
    issued_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    revoked_at timestamptz,
    revoked_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    replacement_of uuid
        REFERENCES public.student_transcripts(id)
        ON DELETE RESTRICT,

    document_file_id uuid,

    verification_code varchar(120) UNIQUE,

    remarks text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 7. TRANSCRIPT SEMESTER LINES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_transcript_semesters (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    transcript_id uuid NOT NULL
        REFERENCES public.student_transcripts(id)
        ON DELETE CASCADE,

    academic_year_id uuid NOT NULL
        REFERENCES public.academic_years(id)
        ON DELETE RESTRICT,

    semester_id uuid NOT NULL
        REFERENCES public.semesters(id)
        ON DELETE RESTRICT,

    semester_result_id uuid
        REFERENCES public.student_semester_results(id)
        ON DELETE RESTRICT,

    gpa numeric(6,3),

    registered_credits numeric(8,2) NOT NULL DEFAULT 0,
    attempted_credits numeric(8,2) NOT NULL DEFAULT 0,
    earned_credits numeric(8,2) NOT NULL DEFAULT 0,

    quality_points numeric(10,3) NOT NULL DEFAULT 0,

    academic_standing varchar(100),

    sequence_no integer NOT NULL,

    created_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE (
        transcript_id,
        academic_year_id,
        semester_id
    ),

    UNIQUE (
        transcript_id,
        sequence_no
    )
);


-- ============================================================
-- 8. TRANSCRIPT COURSE LINES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_transcript_courses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    transcript_id uuid NOT NULL
        REFERENCES public.student_transcripts(id)
        ON DELETE CASCADE,

    transcript_semester_id uuid
        REFERENCES public.student_transcript_semesters(id)
        ON DELETE CASCADE,

    course_result_id uuid
        REFERENCES public.course_results(id)
        ON DELETE RESTRICT,

    course_registration_id uuid
        REFERENCES public.course_registrations(id)
        ON DELETE RESTRICT,

    course_id uuid
        REFERENCES public.courses(id)
        ON DELETE RESTRICT,

    course_code varchar(50),
    course_name varchar(255),

    credits numeric(6,2),

    coursework_mark numeric(8,2),
    examination_mark numeric(8,2),
    total_mark numeric(8,2),

    grade_code varchar(10),
    grade_point numeric(5,2),

    result_type varchar(30),
    attempt_number integer,

    pass_status varchar(30),

    display_sequence integer NOT NULL DEFAULT 1,

    created_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 9. TRANSCRIPT NUMBER GENERATOR
-- ============================================================

CREATE OR REPLACE FUNCTION public.generate_transcript_number()
RETURNS varchar
LANGUAGE plpgsql
AS $$
DECLARE
    v_year varchar(4);
    v_sequence integer;
    v_number varchar(80);
BEGIN

    v_year := to_char(current_date, 'YYYY');

    PERFORM pg_advisory_xact_lock(
        hashtext('IDMC_TRANSCRIPT_' || v_year)
    );

    SELECT
        COALESCE(
            MAX(
                substring(
                    transcript_number
                    from '[0-9]+$'
                )::integer
            ),
            0
        ) + 1
    INTO v_sequence
    FROM public.student_transcripts
    WHERE transcript_number LIKE 'IDMC/TR/' || v_year || '/%';

    v_number :=
        'IDMC/TR/'
        || v_year
        || '/'
        || lpad(v_sequence::text, 6, '0');

    RETURN v_number;
END;
$$;


-- ============================================================
-- 10. VERIFICATION CODE GENERATOR
-- ============================================================

CREATE OR REPLACE FUNCTION public.generate_transcript_verification_code()
RETURNS varchar
LANGUAGE plpgsql
AS $$
DECLARE
    v_code varchar;
BEGIN

    v_code :=
        'IDMC-TR-'
        || upper(substr(
            replace(gen_random_uuid()::text, '-', ''),
            1,
            16
        ));

    RETURN v_code;
END;
$$;


-- ============================================================
-- 11. TRANSCRIPT AUTO-NUMBER
-- ============================================================

CREATE OR REPLACE FUNCTION public.prepare_student_transcript()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.transcript_number IS NULL
       OR trim(NEW.transcript_number) = '' THEN

        NEW.transcript_number :=
            public.generate_transcript_number();

    END IF;

    IF NEW.verification_code IS NULL
       OR trim(NEW.verification_code) = '' THEN

        NEW.verification_code :=
            public.generate_transcript_verification_code();

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prepare_student_transcript
ON public.student_transcripts;

CREATE TRIGGER trg_prepare_student_transcript
BEFORE INSERT
ON public.student_transcripts
FOR EACH ROW
EXECUTE FUNCTION public.prepare_student_transcript();


-- ============================================================
-- 12. TRANSCRIPT STATUS WORKFLOW
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_transcript_status_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.transcript_status = OLD.transcript_status THEN
        RETURN NEW;
    END IF;

    IF OLD.transcript_status = 'DRAFT'
       AND NEW.transcript_status = 'GENERATED' THEN
        RETURN NEW;
    END IF;

    IF OLD.transcript_status = 'GENERATED'
       AND NEW.transcript_status IN ('REVIEW','DRAFT') THEN
        RETURN NEW;
    END IF;

    IF OLD.transcript_status = 'REVIEW'
       AND NEW.transcript_status IN ('APPROVED','DRAFT') THEN
        RETURN NEW;
    END IF;

    IF OLD.transcript_status = 'APPROVED'
       AND NEW.transcript_status = 'ISSUED' THEN
        RETURN NEW;
    END IF;

    IF OLD.transcript_status = 'ISSUED'
       AND NEW.transcript_status IN ('REVOKED','SUPERSEDED') THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION
        'Invalid transcript status transition: % -> %',
        OLD.transcript_status,
        NEW.transcript_status;

END;
$$;

DROP TRIGGER IF EXISTS trg_validate_transcript_status_transition
ON public.student_transcripts;

CREATE TRIGGER trg_validate_transcript_status_transition
BEFORE UPDATE
ON public.student_transcripts
FOR EACH ROW
EXECUTE FUNCTION public.validate_transcript_status_transition();


-- ============================================================
-- 13. ISSUED TRANSCRIPT PROTECTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_issued_transcript_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.transcript_status = 'ISSUED' THEN

        IF NEW.student_id <> OLD.student_id
           OR NEW.transcript_number <> OLD.transcript_number
           OR NEW.cgpa IS DISTINCT FROM OLD.cgpa
           OR NEW.cumulative_credits IS DISTINCT FROM OLD.cumulative_credits
           OR NEW.cumulative_earned_credits IS DISTINCT FROM OLD.cumulative_earned_credits
           OR NEW.cumulative_quality_points IS DISTINCT FROM OLD.cumulative_quality_points
           OR NEW.verification_code <> OLD.verification_code THEN

            RAISE EXCEPTION
                'Issued transcript cannot be directly modified. Generate a replacement transcript.';

        END IF;

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_issued_transcript_change
ON public.student_transcripts;

CREATE TRIGGER trg_prevent_issued_transcript_change
BEFORE UPDATE
ON public.student_transcripts
FOR EACH ROW
EXECUTE FUNCTION public.prevent_issued_transcript_change();


-- ============================================================
-- 14. TRANSCRIPT CANNOT BE ISSUED WITHOUT APPROVAL
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_transcript_issue()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.transcript_status = 'ISSUED' THEN

        IF OLD.transcript_status <> 'APPROVED' THEN
            RAISE EXCEPTION
                'Only approved transcripts can be issued';
        END IF;

        IF NEW.approved_at IS NULL THEN
            RAISE EXCEPTION
                'Transcript approval timestamp is required before issuing';
        END IF;

        NEW.issued_at := COALESCE(NEW.issued_at, now());

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_transcript_issue
ON public.student_transcripts;

CREATE TRIGGER trg_validate_transcript_issue
BEFORE UPDATE
ON public.student_transcripts
FOR EACH ROW
EXECUTE FUNCTION public.validate_transcript_issue();


-- ============================================================
-- 15. ACADEMIC STANDING CALCULATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.calculate_student_academic_standing(
    p_student_id uuid,
    p_academic_year_id uuid,
    p_semester_id uuid
)
RETURNS public.student_academic_standings
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE

    v_record public.student_academic_standings%ROWTYPE;

    v_gpa numeric;
    v_cgpa numeric;

    v_rule_id uuid;
    v_standing_code varchar(50);
    v_standing_name varchar(150);

BEGIN

    SELECT gpa
    INTO v_gpa
    FROM public.student_gpa_records
    WHERE student_id = p_student_id
      AND academic_year_id = p_academic_year_id
      AND semester_id = p_semester_id
    LIMIT 1;


    SELECT cgpa
    INTO v_cgpa
    FROM public.student_cgpa_records
    WHERE student_id = p_student_id
      AND academic_year_id IS NOT DISTINCT FROM p_academic_year_id
      AND semester_id IS NOT DISTINCT FROM p_semester_id
    LIMIT 1;


    SELECT
        id,
        standing_code,
        standing_name
    INTO
        v_rule_id,
        v_standing_code,
        v_standing_name
    FROM public.academic_standing_rules
    WHERE status = 'ACTIVE'
      AND (minimum_gpa IS NULL OR v_gpa >= minimum_gpa)
      AND (maximum_gpa IS NULL OR v_gpa <= maximum_gpa)
      AND (minimum_cgpa IS NULL OR v_cgpa >= minimum_cgpa)
      AND (maximum_cgpa IS NULL OR v_cgpa <= maximum_cgpa)
    ORDER BY priority
    LIMIT 1;


    INSERT INTO public.student_academic_standings (
        student_id,
        academic_year_id,
        semester_id,
        gpa,
        cgpa,
        standing_rule_id,
        standing_code,
        standing_name,
        status,
        calculated_at
    )
    VALUES (
        p_student_id,
        p_academic_year_id,
        p_semester_id,
        v_gpa,
        v_cgpa,
        v_rule_id,
        v_standing_code,
        v_standing_name,
        'CALCULATED',
        now()
    )
    ON CONFLICT (
        student_id,
        academic_year_id,
        semester_id
    )
    DO UPDATE SET
        gpa = EXCLUDED.gpa,
        cgpa = EXCLUDED.cgpa,
        standing_rule_id = EXCLUDED.standing_rule_id,
        standing_code = EXCLUDED.standing_code,
        standing_name = EXCLUDED.standing_name,
        calculated_at = now(),
        updated_at = now()
    RETURNING * INTO v_record;


    RETURN v_record;

END;
$$;


-- ============================================================
-- 16. DEFICIENCY CREATION FROM FAILED RESULT
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_result_deficiency()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id uuid;
    v_type varchar(40);
BEGIN

    IF NEW.result_status IN ('APPROVED','PUBLISHED','LOCKED')
       AND NEW.pass_status IN (
           'FAIL',
           'SUPPLEMENTARY',
           'INCOMPLETE',
           'WITHHELD'
       ) THEN

        SELECT course_id
        INTO v_course_id
        FROM public.course_offerings
        WHERE id = NEW.course_offering_id;


        v_type :=
            CASE
                WHEN NEW.pass_status = 'FAIL'
                    THEN 'FAILED'
                WHEN NEW.pass_status = 'SUPPLEMENTARY'
                    THEN 'SUPPLEMENTARY_REQUIRED'
                WHEN NEW.pass_status = 'INCOMPLETE'
                    THEN 'INCOMPLETE'
                WHEN NEW.pass_status = 'WITHHELD'
                    THEN 'WITHHELD'
                ELSE 'FAILED'
            END;


        INSERT INTO public.student_academic_deficiencies (
            student_id,
            course_id,
            course_offering_id,
            course_result_id,
            deficiency_type,
            deficiency_status
        )
        VALUES (
            NEW.student_id,
            v_course_id,
            NEW.course_offering_id,
            NEW.id,
            v_type,
            'OPEN'
        )
        ON CONFLICT DO NOTHING;

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_result_deficiency
ON public.course_results;

CREATE TRIGGER trg_create_result_deficiency
AFTER INSERT OR UPDATE
ON public.course_results
FOR EACH ROW
EXECUTE FUNCTION public.create_result_deficiency();


-- ============================================================
-- 17. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS
idx_academic_standings_student
ON public.student_academic_standings(student_id);

CREATE INDEX IF NOT EXISTS
idx_academic_standings_status
ON public.student_academic_standings(status);

CREATE INDEX IF NOT EXISTS
idx_course_attempts_student
ON public.student_course_attempts(student_id);

CREATE INDEX IF NOT EXISTS
idx_course_attempts_course
ON public.student_course_attempts(course_id);

CREATE INDEX IF NOT EXISTS
idx_course_attempts_result
ON public.student_course_attempts(course_result_id);

CREATE INDEX IF NOT EXISTS
idx_deficiencies_student
ON public.student_academic_deficiencies(student_id);

CREATE INDEX IF NOT EXISTS
idx_deficiencies_status
ON public.student_academic_deficiencies(deficiency_status);

CREATE INDEX IF NOT EXISTS
idx_transcripts_student
ON public.student_transcripts(student_id);

CREATE INDEX IF NOT EXISTS
idx_transcripts_status
ON public.student_transcripts(transcript_status);

CREATE INDEX IF NOT EXISTS
idx_transcripts_verification
ON public.student_transcripts(verification_code);

CREATE INDEX IF NOT EXISTS
idx_transcript_semesters_transcript
ON public.student_transcript_semesters(transcript_id);

CREATE INDEX IF NOT EXISTS
idx_transcript_courses_transcript
ON public.student_transcript_courses(transcript_id);

CREATE INDEX IF NOT EXISTS
idx_transcript_courses_result
ON public.student_transcript_courses(course_result_id);


-- ============================================================
-- 18. UPDATED_AT TRIGGERS
-- ============================================================

DROP TRIGGER IF EXISTS trg_academic_standing_rules_updated_at
ON public.academic_standing_rules;

CREATE TRIGGER trg_academic_standing_rules_updated_at
BEFORE UPDATE
ON public.academic_standing_rules
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_student_academic_standings_updated_at
ON public.student_academic_standings;

CREATE TRIGGER trg_student_academic_standings_updated_at
BEFORE UPDATE
ON public.student_academic_standings
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_student_course_attempts_updated_at
ON public.student_course_attempts;

CREATE TRIGGER trg_student_course_attempts_updated_at
BEFORE UPDATE
ON public.student_course_attempts
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_student_academic_deficiencies_updated_at
ON public.student_academic_deficiencies;

CREATE TRIGGER trg_student_academic_deficiencies_updated_at
BEFORE UPDATE
ON public.student_academic_deficiencies
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_student_transcripts_updated_at
ON public.student_transcripts;

CREATE TRIGGER trg_student_transcripts_updated_at
BEFORE UPDATE
ON public.student_transcripts
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 19. RLS
-- ============================================================

ALTER TABLE public.academic_standing_rules
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_academic_standings
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_course_attempts
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_academic_deficiencies
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_transcripts
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_transcript_semesters
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_transcript_courses
ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 20. COMMENTS
-- ============================================================

COMMENT ON TABLE public.academic_standing_rules IS
'Configurable institutional rules used to determine academic standing.';

COMMENT ON TABLE public.student_academic_standings IS
'Semester-level academic standing calculated from GPA and CGPA.';

COMMENT ON TABLE public.student_course_attempts IS
'Historical record of every academic attempt made by a student for a course.';

COMMENT ON TABLE public.student_academic_deficiencies IS
'Tracks failed, supplementary, repeat, carry-forward, incomplete and withheld academic obligations.';

COMMENT ON TABLE public.student_transcripts IS
'Official and controlled student transcript records.';

COMMENT ON TABLE public.student_transcript_semesters IS
'Semester summaries included in a transcript.';

COMMENT ON TABLE public.student_transcript_courses IS
'Course-level transcript records.';


COMMIT;
