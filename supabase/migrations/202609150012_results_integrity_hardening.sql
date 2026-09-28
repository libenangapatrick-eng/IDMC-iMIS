-- ============================================================
-- IDMC iMIS
-- Migration 012: Results Integrity Hardening
-- ============================================================

BEGIN;

-- ============================================================
-- 1. VALIDATE COURSE RESULT CONTEXT
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_course_result_context()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_registration_student uuid;
    v_registration_offering uuid;
    v_offering_year uuid;
    v_offering_semester uuid;
BEGIN

    SELECT
        sr.student_id,
        cr.course_offering_id
    INTO
        v_registration_student,
        v_registration_offering
    FROM public.course_registrations cr
    JOIN public.student_registrations sr
        ON sr.id = cr.student_registration_id
    WHERE cr.id = NEW.course_registration_id;

    IF v_registration_student IS NULL THEN
        RAISE EXCEPTION
            'Course result course registration does not exist';
    END IF;

    IF v_registration_student <> NEW.student_id THEN
        RAISE EXCEPTION
            'Course result student does not match course registration student';
    END IF;

    IF v_registration_offering <> NEW.course_offering_id THEN
        RAISE EXCEPTION
            'Course result course offering does not match course registration';
    END IF;

    SELECT academic_year_id, semester_id
    INTO v_offering_year, v_offering_semester
    FROM public.course_offerings
    WHERE id = NEW.course_offering_id;

    IF v_offering_year IS NULL OR v_offering_semester IS NULL THEN
        RAISE EXCEPTION
            'Course result course offering does not exist';
    END IF;

    IF NEW.academic_year_id <> v_offering_year
       OR NEW.semester_id <> v_offering_semester THEN
        RAISE EXCEPTION
            'Course result academic context does not match course offering';
    END IF;

    IF NEW.credits < 0 THEN
        RAISE EXCEPTION
            'Course result credits cannot be negative';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_course_result_context
ON public.course_results;

CREATE TRIGGER trg_validate_course_result_context
BEFORE INSERT OR UPDATE
ON public.course_results
FOR EACH ROW
EXECUTE FUNCTION public.validate_course_result_context();


-- ============================================================
-- 2. RESULT STATUS TRANSITIONS
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_course_result_status_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.result_status = OLD.result_status THEN
        RETURN NEW;
    END IF;

    IF OLD.result_status = 'DRAFT'
       AND NEW.result_status IN ('CALCULATED','CANCELLED') THEN
        RETURN NEW;
    END IF;

    IF OLD.result_status = 'CALCULATED'
       AND NEW.result_status IN ('SUBMITTED','DRAFT','CANCELLED') THEN
        RETURN NEW;
    END IF;

    IF OLD.result_status = 'SUBMITTED'
       AND NEW.result_status IN ('UNDER_REVIEW','CALCULATED') THEN
        RETURN NEW;
    END IF;

    IF OLD.result_status = 'UNDER_REVIEW'
       AND NEW.result_status IN ('APPROVED','CALCULATED','WITHHELD') THEN
        RETURN NEW;
    END IF;

    IF OLD.result_status = 'APPROVED'
       AND NEW.result_status IN ('PUBLISHED','WITHHELD') THEN
        RETURN NEW;
    END IF;

    IF OLD.result_status = 'PUBLISHED'
       AND NEW.result_status = 'LOCKED' THEN
        RETURN NEW;
    END IF;

    IF OLD.result_status = 'WITHHELD'
       AND NEW.result_status IN ('UNDER_REVIEW','APPROVED') THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION
        'Invalid course result status transition: % -> %',
        OLD.result_status,
        NEW.result_status;

END;
$$;

DROP TRIGGER IF EXISTS trg_validate_course_result_status_transition
ON public.course_results;

CREATE TRIGGER trg_validate_course_result_status_transition
BEFORE UPDATE
ON public.course_results
FOR EACH ROW
EXECUTE FUNCTION public.validate_course_result_status_transition();


-- ============================================================
-- 3. ONLY CALCULATED RESULTS MAY BE SUBMITTED
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_course_result_submission()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.result_status = 'SUBMITTED' THEN

        IF NEW.total_mark IS NULL
           OR NEW.grade_code IS NULL
           OR NEW.grade_point IS NULL THEN

            RAISE EXCEPTION
                'Course result cannot be submitted before calculation is complete';

        END IF;

        NEW.submitted_at := COALESCE(NEW.submitted_at, now());

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_course_result_submission
ON public.course_results;

CREATE TRIGGER trg_validate_course_result_submission
BEFORE INSERT OR UPDATE
ON public.course_results
FOR EACH ROW
EXECUTE FUNCTION public.validate_course_result_submission();


-- ============================================================
-- 4. APPROVAL REQUIRES COMPLETE RESULT
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_course_result_approval()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.result_status = 'APPROVED' THEN

        IF NEW.total_mark IS NULL
           OR NEW.grade_code IS NULL
           OR NEW.grade_point IS NULL
           OR NEW.pass_status IS NULL THEN

            RAISE EXCEPTION
                'Course result cannot be approved while calculated result data is incomplete';

        END IF;

        NEW.approved_at := COALESCE(NEW.approved_at, now());

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_course_result_approval
ON public.course_results;

CREATE TRIGGER trg_validate_course_result_approval
BEFORE INSERT OR UPDATE
ON public.course_results
FOR EACH ROW
EXECUTE FUNCTION public.validate_course_result_approval();


-- ============================================================
-- 5. PUBLICATION REQUIRES APPROVAL
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_course_result_publication()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.result_status = 'PUBLISHED' THEN

        IF OLD.result_status <> 'APPROVED' THEN
            RAISE EXCEPTION
                'Only approved course results can be published';
        END IF;

        IF NEW.approved_at IS NULL THEN
            RAISE EXCEPTION
                'Approved timestamp is required before publication';
        END IF;

        NEW.published_at := COALESCE(NEW.published_at, now());

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_course_result_publication
ON public.course_results;

CREATE TRIGGER trg_validate_course_result_publication
BEFORE UPDATE
ON public.course_results
FOR EACH ROW
EXECUTE FUNCTION public.validate_course_result_publication();


-- ============================================================
-- 6. LOCK REQUIRES PUBLICATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_course_result_lock()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.result_status = 'LOCKED' THEN

        IF OLD.result_status <> 'PUBLISHED' THEN
            RAISE EXCEPTION
                'Only published course results can be locked';
        END IF;

        NEW.locked_at := COALESCE(NEW.locked_at, now());

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_course_result_lock
ON public.course_results;

CREATE TRIGGER trg_validate_course_result_lock
BEFORE UPDATE
ON public.course_results
FOR EACH ROW
EXECUTE FUNCTION public.validate_course_result_lock();


-- ============================================================
-- 7. RESULT TOTAL MUST BE BETWEEN 0 AND 100
-- ============================================================

ALTER TABLE public.course_results
DROP CONSTRAINT IF EXISTS course_result_total_range;

ALTER TABLE public.course_results
ADD CONSTRAINT course_result_total_range
CHECK (
    total_mark IS NULL
    OR (
        total_mark >= 0
        AND total_mark <= 100
    )
);


-- ============================================================
-- 8. GPA RANGE
-- ============================================================

ALTER TABLE public.student_gpa_records
DROP CONSTRAINT IF EXISTS student_gpa_range;

ALTER TABLE public.student_gpa_records
ADD CONSTRAINT student_gpa_range
CHECK (gpa >= 0 AND gpa <= 5);


-- ============================================================
-- 9. CGPA RANGE
-- ============================================================

ALTER TABLE public.student_cgpa_records
DROP CONSTRAINT IF EXISTS student_cgpa_range;

ALTER TABLE public.student_cgpa_records
ADD CONSTRAINT student_cgpa_range
CHECK (cgpa >= 0 AND cgpa <= 5);


-- ============================================================
-- 10. GPA RECORD MUST MATCH SEMESTER RESULT
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_gpa_record()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_gpa numeric;
BEGIN

    IF NEW.semester_result_id IS NOT NULL THEN

        SELECT gpa
        INTO v_gpa
        FROM public.student_semester_results
        WHERE id = NEW.semester_result_id;

        IF v_gpa IS NOT NULL
           AND ROUND(NEW.gpa,3) <> ROUND(v_gpa,3) THEN

            RAISE EXCEPTION
                'GPA record does not match semester result GPA';

        END IF;

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_gpa_record
ON public.student_gpa_records;

CREATE TRIGGER trg_validate_gpa_record
BEFORE INSERT OR UPDATE
ON public.student_gpa_records
FOR EACH ROW
EXECUTE FUNCTION public.validate_gpa_record();


-- ============================================================
-- 11. SEMESTER RESULT STATUS TRANSITIONS
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_semester_result_status_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.result_status = OLD.result_status THEN
        RETURN NEW;
    END IF;

    IF OLD.result_status = 'DRAFT'
       AND NEW.result_status IN ('CALCULATED','WITHHELD') THEN
        RETURN NEW;
    END IF;

    IF OLD.result_status = 'CALCULATED'
       AND NEW.result_status IN ('SUBMITTED','DRAFT') THEN
        RETURN NEW;
    END IF;

    IF OLD.result_status = 'SUBMITTED'
       AND NEW.result_status IN ('UNDER_REVIEW','CALCULATED') THEN
        RETURN NEW;
    END IF;

    IF OLD.result_status = 'UNDER_REVIEW'
       AND NEW.result_status IN ('APPROVED','WITHHELD') THEN
        RETURN NEW;
    END IF;

    IF OLD.result_status = 'APPROVED'
       AND NEW.result_status = 'PUBLISHED' THEN
        RETURN NEW;
    END IF;

    IF OLD.result_status = 'PUBLISHED'
       AND NEW.result_status = 'LOCKED' THEN
        RETURN NEW;
    END IF;

    IF OLD.result_status = 'WITHHELD'
       AND NEW.result_status IN ('UNDER_REVIEW','APPROVED') THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION
        'Invalid semester result status transition: % -> %',
        OLD.result_status,
        NEW.result_status;

END;
$$;

DROP TRIGGER IF EXISTS trg_validate_semester_result_status_transition
ON public.student_semester_results;

CREATE TRIGGER trg_validate_semester_result_status_transition
BEFORE UPDATE
ON public.student_semester_results
FOR EACH ROW
EXECUTE FUNCTION public.validate_semester_result_status_transition();


-- ============================================================
-- 12. SEMESTER RESULT LOCK PROTECTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_locked_semester_result_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.result_status IN ('PUBLISHED','LOCKED') THEN

        IF NEW.student_id <> OLD.student_id
           OR NEW.academic_year_id <> OLD.academic_year_id
           OR NEW.semester_id <> OLD.semester_id
           OR NEW.gpa IS DISTINCT FROM OLD.gpa
           OR NEW.total_registered_credits IS DISTINCT FROM OLD.total_registered_credits
           OR NEW.total_attempted_credits IS DISTINCT FROM OLD.total_attempted_credits
           OR NEW.total_earned_credits IS DISTINCT FROM OLD.total_earned_credits
           OR NEW.total_quality_points IS DISTINCT FROM OLD.total_quality_points THEN

            RAISE EXCEPTION
                'Published or locked semester result cannot be modified';

        END IF;

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_locked_semester_result_change
ON public.student_semester_results;

CREATE TRIGGER trg_prevent_locked_semester_result_change
BEFORE UPDATE
ON public.student_semester_results
FOR EACH ROW
EXECUTE FUNCTION public.prevent_locked_semester_result_change();


-- ============================================================
-- 13. SEMESTER GPA CALCULATION FUNCTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.calculate_and_store_semester_result(
    p_student_id uuid,
    p_academic_year_id uuid,
    p_semester_id uuid
)
RETURNS public.student_semester_results
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE

    v_result public.student_semester_results%ROWTYPE;

    v_registered numeric := 0;
    v_attempted numeric := 0;
    v_earned numeric := 0;
    v_quality numeric := 0;

    v_courses integer := 0;
    v_passed integer := 0;
    v_failed integer := 0;

    v_gpa numeric := 0;

BEGIN

    SELECT
        COALESCE(SUM(credits),0),
        COALESCE(SUM(
            CASE
                WHEN result_status IN
                    ('APPROVED','PUBLISHED','LOCKED')
                THEN credits
                ELSE 0
            END
        ),0),
        COALESCE(SUM(
            CASE
                WHEN result_status IN
                    ('APPROVED','PUBLISHED','LOCKED')
                     AND pass_status = 'PASS'
                THEN credits
                ELSE 0
            END
        ),0),
        COALESCE(SUM(
            CASE
                WHEN result_status IN
                    ('APPROVED','PUBLISHED','LOCKED')
                THEN credits * COALESCE(grade_point,0)
                ELSE 0
            END
        ),0),
        COUNT(*),
        COUNT(*) FILTER (
            WHERE pass_status = 'PASS'
        ),
        COUNT(*) FILTER (
            WHERE pass_status = 'FAIL'
        )
    INTO
        v_registered,
        v_attempted,
        v_earned,
        v_quality,
        v_courses,
        v_passed,
        v_failed
    FROM public.course_results
    WHERE student_id = p_student_id
      AND academic_year_id = p_academic_year_id
      AND semester_id = p_semester_id
      AND result_status NOT IN ('CANCELLED');


    IF v_attempted > 0 THEN
        v_gpa := ROUND(v_quality / v_attempted, 3);
    ELSE
        v_gpa := 0;
    END IF;


    INSERT INTO public.student_semester_results (
        student_id,
        academic_year_id,
        semester_id,
        total_registered_credits,
        total_attempted_credits,
        total_earned_credits,
        total_quality_points,
        gpa,
        courses_attempted,
        courses_passed,
        courses_failed,
        result_status,
        calculated_at
    )
    VALUES (
        p_student_id,
        p_academic_year_id,
        p_semester_id,
        v_registered,
        v_attempted,
        v_earned,
        v_quality,
        v_gpa,
        v_courses,
        v_passed,
        v_failed,
        'CALCULATED',
        now()
    )
    ON CONFLICT (
        student_id,
        academic_year_id,
        semester_id
    )
    DO UPDATE SET
        total_registered_credits = EXCLUDED.total_registered_credits,
        total_attempted_credits = EXCLUDED.total_attempted_credits,
        total_earned_credits = EXCLUDED.total_earned_credits,
        total_quality_points = EXCLUDED.total_quality_points,
        gpa = EXCLUDED.gpa,
        courses_attempted = EXCLUDED.courses_attempted,
        courses_passed = EXCLUDED.courses_passed,
        courses_failed = EXCLUDED.courses_failed,
        result_status =
            CASE
                WHEN public.student_semester_results.result_status
                    IN ('PUBLISHED','LOCKED')
                THEN public.student_semester_results.result_status
                ELSE 'CALCULATED'
            END,
        calculated_at = now(),
        updated_at = now()
    RETURNING * INTO v_result;


    INSERT INTO public.student_gpa_records (
        student_id,
        academic_year_id,
        semester_id,
        semester_result_id,
        gpa,
        total_credits,
        total_quality_points,
        calculated_at
    )
    VALUES (
        p_student_id,
        p_academic_year_id,
        p_semester_id,
        v_result.id,
        v_gpa,
        v_attempted,
        v_quality,
        now()
    )
    ON CONFLICT (
        student_id,
        academic_year_id,
        semester_id
    )
    DO UPDATE SET
        semester_result_id = EXCLUDED.semester_result_id,
        gpa = EXCLUDED.gpa,
        total_credits = EXCLUDED.total_credits,
        total_quality_points = EXCLUDED.total_quality_points,
        calculated_at = now();


    RETURN v_result;

END;
$$;


-- ============================================================
-- 14. CGPA CALCULATION AND STORAGE
-- ============================================================

CREATE OR REPLACE FUNCTION public.calculate_and_store_cgpa(
    p_student_id uuid,
    p_academic_year_id uuid DEFAULT NULL,
    p_semester_id uuid DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE

    v_quality numeric := 0;
    v_credits numeric := 0;
    v_earned numeric := 0;
    v_cgpa numeric := 0;

BEGIN

    SELECT
        COALESCE(SUM(
            cr.grade_point * cr.credits
        ),0),
        COALESCE(SUM(cr.credits),0),
        COALESCE(SUM(
            CASE
                WHEN cr.pass_status = 'PASS'
                THEN cr.credits
                ELSE 0
            END
        ),0)
    INTO
        v_quality,
        v_credits,
        v_earned
    FROM public.course_results cr
    WHERE cr.student_id = p_student_id
      AND cr.result_status IN (
          'APPROVED',
          'PUBLISHED',
          'LOCKED'
      )
      AND cr.pass_status NOT IN (
          'WITHHELD',
          'INCOMPLETE'
      );


    IF v_credits > 0 THEN
        v_cgpa := ROUND(v_quality / v_credits, 3);
    ELSE
        v_cgpa := 0;
    END IF;


    INSERT INTO public.student_cgpa_records (
        student_id,
        academic_year_id,
        semester_id,
        cumulative_credits,
        cumulative_earned_credits,
        cumulative_quality_points,
        cgpa,
        calculated_at
    )
    VALUES (
        p_student_id,
        p_academic_year_id,
        p_semester_id,
        v_credits,
        v_earned,
        v_quality,
        v_cgpa,
        now()
    )
    ON CONFLICT (
        student_id,
        academic_year_id,
        semester_id
    )
    DO UPDATE SET
        cumulative_credits = EXCLUDED.cumulative_credits,
        cumulative_earned_credits = EXCLUDED.cumulative_earned_credits,
        cumulative_quality_points = EXCLUDED.cumulative_quality_points,
        cgpa = EXCLUDED.cgpa,
        calculated_at = now();


    RETURN v_cgpa;

END;
$$;


-- ============================================================
-- 15. PREVENT DUPLICATE ACTIVE RESULT ATTEMPTS
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS
uq_course_result_active_attempt
ON public.course_results (
    student_id,
    course_offering_id
)
WHERE result_status IN (
    'DRAFT',
    'CALCULATED',
    'SUBMITTED',
    'UNDER_REVIEW',
    'APPROVED',
    'PUBLISHED',
    'LOCKED',
    'WITHHELD',
    'INCOMPLETE'
);


-- ============================================================
-- 16. UPDATED_AT
-- ============================================================

DROP TRIGGER IF EXISTS trg_course_result_corrections_updated_at
ON public.course_result_corrections;

CREATE TRIGGER trg_course_result_corrections_updated_at
BEFORE UPDATE
ON public.course_result_corrections
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 17. RLS CONFIRMATION
-- ============================================================

ALTER TABLE public.course_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_semester_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_gpa_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_cgpa_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_result_corrections ENABLE ROW LEVEL SECURITY;


COMMIT;
