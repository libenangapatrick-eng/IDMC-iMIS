-- ============================================================
-- IDMC iMIS
-- Migration 011: Results, Grading, GPA & CGPA Core
-- ============================================================

BEGIN;

-- ============================================================
-- 1. GRADE SCALES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.grade_scales (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    scale_code varchar(50) NOT NULL UNIQUE,
    scale_name varchar(150) NOT NULL,

    description text,

    minimum_total numeric(5,2) NOT NULL DEFAULT 0,
    maximum_total numeric(5,2) NOT NULL DEFAULT 100,

    status varchar(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE','INACTIVE','ARCHIVED')),

    is_default boolean NOT NULL DEFAULT false,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 2. GRADE SCALE DETAILS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.grade_scale_details (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    grade_scale_id uuid NOT NULL
        REFERENCES public.grade_scales(id)
        ON DELETE RESTRICT,

    grade_code varchar(10) NOT NULL,

    grade_name varchar(100),

    minimum_mark numeric(5,2) NOT NULL,
    maximum_mark numeric(5,2) NOT NULL,

    grade_point numeric(5,2) NOT NULL,

    pass_status varchar(20) NOT NULL DEFAULT 'PASS'
        CHECK (pass_status IN (
            'PASS',
            'FAIL',
            'SUPPLEMENTARY',
            'INCOMPLETE',
            'WITHHELD'
        )),

    result_classification varchar(100),

    status varchar(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE','INACTIVE','ARCHIVED')),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT grade_range_valid
        CHECK (minimum_mark >= 0 AND maximum_mark <= 100),

    CONSTRAINT grade_range_order_valid
        CHECK (maximum_mark >= minimum_mark),

    CONSTRAINT grade_point_valid
        CHECK (grade_point >= 0),

    UNIQUE (grade_scale_id, grade_code)
);


-- ============================================================
-- 3. DEFAULT IDMC GRADING SCALE
-- ============================================================

INSERT INTO public.grade_scales (
    scale_code,
    scale_name,
    description,
    minimum_total,
    maximum_total,
    status,
    is_default
)
VALUES (
    'IDMC_DEFAULT',
    'IDMC Default Grading Scale',
    'Configurable institutional grading scale for initial IDMC iMIS setup.',
    0,
    100,
    'ACTIVE',
    true
)
ON CONFLICT (scale_code) DO NOTHING;


INSERT INTO public.grade_scale_details (
    grade_scale_id,
    grade_code,
    grade_name,
    minimum_mark,
    maximum_mark,
    grade_point,
    pass_status,
    result_classification
)
SELECT
    gs.id,
    x.grade_code,
    x.grade_name,
    x.minimum_mark,
    x.maximum_mark,
    x.grade_point,
    x.pass_status,
    x.result_classification
FROM public.grade_scales gs
CROSS JOIN (
    VALUES
        ('A',  'Excellent',       80.00, 100.00, 5.00, 'PASS', 'Excellent'),
        ('B+', 'Very Good',       70.00,  79.99, 4.00, 'PASS', 'Very Good'),
        ('B',  'Good',            60.00,  69.99, 3.00, 'PASS', 'Good'),
        ('C',  'Satisfactory',    50.00,  59.99, 2.00, 'PASS', 'Satisfactory'),
        ('D',  'Marginal Pass',   40.00,  49.99, 1.00, 'PASS', 'Marginal Pass'),
        ('F',  'Fail',             0.00,  39.99, 0.00, 'FAIL', 'Fail')
) AS x(
    grade_code,
    grade_name,
    minimum_mark,
    maximum_mark,
    grade_point,
    pass_status,
    result_classification
)
WHERE gs.scale_code = 'IDMC_DEFAULT'
ON CONFLICT (grade_scale_id, grade_code) DO NOTHING;


-- ============================================================
-- 4. COURSE RESULT POLICIES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.course_result_policies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    course_offering_id uuid NOT NULL
        REFERENCES public.course_offerings(id)
        ON DELETE RESTRICT,

    grade_scale_id uuid NOT NULL
        REFERENCES public.grade_scales(id)
        ON DELETE RESTRICT,

    coursework_weight numeric(5,2) NOT NULL DEFAULT 40.00,
    examination_weight numeric(5,2) NOT NULL DEFAULT 60.00,

    minimum_coursework_required numeric(5,2),
    minimum_exam_required numeric(5,2),

    minimum_pass_mark numeric(5,2) NOT NULL DEFAULT 40.00,

    status varchar(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('DRAFT','ACTIVE','LOCKED','ARCHIVED')),

    created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    approved_by uuid REFERENCES public.users(id) ON DELETE SET NULL,

    approved_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT result_policy_weight_valid
        CHECK (
            coursework_weight >= 0
            AND examination_weight >= 0
            AND coursework_weight + examination_weight = 100
        ),

    CONSTRAINT result_policy_pass_mark_valid
        CHECK (
            minimum_pass_mark >= 0
            AND minimum_pass_mark <= 100
        ),

    UNIQUE (course_offering_id)
);


-- ============================================================
-- 5. COURSE RESULTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.course_results (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL
        REFERENCES public.students(id)
        ON DELETE RESTRICT,

    course_offering_id uuid NOT NULL
        REFERENCES public.course_offerings(id)
        ON DELETE RESTRICT,

    course_registration_id uuid NOT NULL
        REFERENCES public.course_registrations(id)
        ON DELETE RESTRICT,

    academic_year_id uuid NOT NULL
        REFERENCES public.academic_years(id)
        ON DELETE RESTRICT,

    semester_id uuid NOT NULL
        REFERENCES public.semesters(id)
        ON DELETE RESTRICT,

    credits numeric(6,2) NOT NULL DEFAULT 0,

    coursework_mark numeric(8,2),
    examination_mark numeric(8,2),

    total_mark numeric(8,2),

    grade_code varchar(10),
    grade_point numeric(5,2),

    pass_status varchar(30),

    result_status varchar(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (result_status IN (
            'DRAFT',
            'CALCULATED',
            'SUBMITTED',
            'UNDER_REVIEW',
            'APPROVED',
            'PUBLISHED',
            'LOCKED',
            'WITHHELD',
            'INCOMPLETE',
            'CANCELLED'
        )),

    attempt_number integer NOT NULL DEFAULT 1,

    result_type varchar(30) NOT NULL DEFAULT 'NORMAL'
        CHECK (result_type IN (
            'NORMAL',
            'SUPPLEMENTARY',
            'SPECIAL',
            'RESIT',
            'RETAKE',
            'REPEAT',
            'CARRY_FORWARD',
            'MAKEUP'
        )),

    calculated_at timestamptz,

    submitted_at timestamptz,
    submitted_by uuid REFERENCES public.users(id) ON DELETE SET NULL,

    approved_at timestamptz,
    approved_by uuid REFERENCES public.users(id) ON DELETE SET NULL,

    published_at timestamptz,
    published_by uuid REFERENCES public.users(id) ON DELETE SET NULL,

    locked_at timestamptz,
    locked_by uuid REFERENCES public.users(id) ON DELETE SET NULL,

    remarks text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT course_result_marks_valid
        CHECK (
            (coursework_mark IS NULL OR coursework_mark >= 0)
            AND
            (examination_mark IS NULL OR examination_mark >= 0)
            AND
            (total_mark IS NULL OR total_mark >= 0)
        ),

    CONSTRAINT course_result_attempt_valid
        CHECK (attempt_number > 0),

    UNIQUE (
        student_id,
        course_offering_id,
        course_registration_id
    )
);


-- ============================================================
-- 6. STUDENT SEMESTER RESULTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_semester_results (
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

    programme_version_id uuid
        REFERENCES public.programme_versions(id)
        ON DELETE RESTRICT,

    total_registered_credits numeric(8,2) NOT NULL DEFAULT 0,
    total_attempted_credits numeric(8,2) NOT NULL DEFAULT 0,
    total_earned_credits numeric(8,2) NOT NULL DEFAULT 0,

    total_quality_points numeric(10,3) NOT NULL DEFAULT 0,

    gpa numeric(6,3),

    courses_attempted integer NOT NULL DEFAULT 0,
    courses_passed integer NOT NULL DEFAULT 0,
    courses_failed integer NOT NULL DEFAULT 0,

    academic_standing varchar(50),

    result_status varchar(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (result_status IN (
            'DRAFT',
            'CALCULATED',
            'SUBMITTED',
            'UNDER_REVIEW',
            'APPROVED',
            'PUBLISHED',
            'LOCKED',
            'WITHHELD'
        )),

    calculated_at timestamptz,

    submitted_at timestamptz,
    submitted_by uuid REFERENCES public.users(id) ON DELETE SET NULL,

    approved_at timestamptz,
    approved_by uuid REFERENCES public.users(id) ON DELETE SET NULL,

    published_at timestamptz,
    published_by uuid REFERENCES public.users(id) ON DELETE SET NULL,

    locked_at timestamptz,
    locked_by uuid REFERENCES public.users(id) ON DELETE SET NULL,

    remarks text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE (
        student_id,
        academic_year_id,
        semester_id
    )
);


-- ============================================================
-- 7. STUDENT GPA RECORDS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_gpa_records (
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

    gpa numeric(6,3) NOT NULL DEFAULT 0,

    total_credits numeric(8,2) NOT NULL DEFAULT 0,
    total_quality_points numeric(10,3) NOT NULL DEFAULT 0,

    calculation_version varchar(30) NOT NULL DEFAULT '1.0',

    calculated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE (
        student_id,
        academic_year_id,
        semester_id
    )
);


-- ============================================================
-- 8. STUDENT CGPA RECORDS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_cgpa_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL
        REFERENCES public.students(id)
        ON DELETE RESTRICT,

    academic_year_id uuid
        REFERENCES public.academic_years(id)
        ON DELETE RESTRICT,

    semester_id uuid
        REFERENCES public.semesters(id)
        ON DELETE RESTRICT,

    cumulative_credits numeric(10,2) NOT NULL DEFAULT 0,

    cumulative_earned_credits numeric(10,2) NOT NULL DEFAULT 0,

    cumulative_quality_points numeric(12,3) NOT NULL DEFAULT 0,

    cgpa numeric(6,3) NOT NULL DEFAULT 0,

    calculation_version varchar(30) NOT NULL DEFAULT '1.0',

    calculated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE (
        student_id,
        academic_year_id,
        semester_id
    )
);


-- ============================================================
-- 9. RESULT CORRECTIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.course_result_corrections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    course_result_id uuid NOT NULL
        REFERENCES public.course_results(id)
        ON DELETE RESTRICT,

    requested_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    requested_at timestamptz NOT NULL DEFAULT now(),

    old_coursework_mark numeric(8,2),
    new_coursework_mark numeric(8,2),

    old_examination_mark numeric(8,2),
    new_examination_mark numeric(8,2),

    old_total_mark numeric(8,2),
    new_total_mark numeric(8,2),

    old_grade_code varchar(10),
    new_grade_code varchar(10),

    old_grade_point numeric(5,2),
    new_grade_point numeric(5,2),

    reason text NOT NULL,

    evidence_file_id uuid,

    status varchar(30) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN (
            'PENDING',
            'APPROVED',
            'REJECTED',
            'CANCELLED'
        )),

    reviewed_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    reviewed_at timestamptz,
    review_comment text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS
uq_pending_course_result_correction
ON public.course_result_corrections(course_result_id)
WHERE status = 'PENDING';


-- ============================================================
-- 10. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS
idx_grade_scale_details_scale
ON public.grade_scale_details(grade_scale_id);

CREATE INDEX IF NOT EXISTS
idx_course_result_policies_offering
ON public.course_result_policies(course_offering_id);

CREATE INDEX IF NOT EXISTS
idx_course_results_student
ON public.course_results(student_id);

CREATE INDEX IF NOT EXISTS
idx_course_results_offering
ON public.course_results(course_offering_id);

CREATE INDEX IF NOT EXISTS
idx_course_results_registration
ON public.course_results(course_registration_id);

CREATE INDEX IF NOT EXISTS
idx_course_results_status
ON public.course_results(result_status);

CREATE INDEX IF NOT EXISTS
idx_semester_results_student
ON public.student_semester_results(student_id);

CREATE INDEX IF NOT EXISTS
idx_gpa_records_student
ON public.student_gpa_records(student_id);

CREATE INDEX IF NOT EXISTS
idx_cgpa_records_student
ON public.student_cgpa_records(student_id);

CREATE INDEX IF NOT EXISTS
idx_result_corrections_result
ON public.course_result_corrections(course_result_id);


-- ============================================================
-- 11. GRADE CALCULATION FUNCTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_grade_for_mark(
    p_grade_scale_id uuid,
    p_total_mark numeric
)
RETURNS TABLE (
    grade_code varchar,
    grade_point numeric,
    pass_status varchar,
    result_classification varchar
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN

    RETURN QUERY
    SELECT
        gsd.grade_code,
        gsd.grade_point,
        gsd.pass_status,
        gsd.result_classification
    FROM public.grade_scale_details gsd
    WHERE gsd.grade_scale_id = p_grade_scale_id
      AND gsd.status = 'ACTIVE'
      AND p_total_mark >= gsd.minimum_mark
      AND p_total_mark <= gsd.maximum_mark
    ORDER BY gsd.minimum_mark DESC
    LIMIT 1;

END;
$$;


-- ============================================================
-- 12. COURSE RESULT CALCULATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.calculate_course_result(
    p_course_result_id uuid
)
RETURNS public.course_results
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE

    v_result public.course_results%ROWTYPE;

    v_policy public.course_result_policies%ROWTYPE;

    v_coursework numeric(8,2) := 0;
    v_exam numeric(8,2) := 0;
    v_total numeric(8,2) := 0;

    v_assessment_weight numeric(8,2) := 0;

    v_exam_marks numeric(12,4) := 0;
    v_exam_max numeric(12,4) := 0;

    v_grade_code varchar(10);
    v_grade_point numeric(5,2);
    v_pass_status varchar(30);
    v_classification varchar(100);

BEGIN

    SELECT *
    INTO v_result
    FROM public.course_results
    WHERE id = p_course_result_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Course result % does not exist',
            p_course_result_id;
    END IF;


    SELECT *
    INTO v_policy
    FROM public.course_result_policies
    WHERE course_offering_id = v_result.course_offering_id
      AND status IN ('ACTIVE','LOCKED');

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'No active result policy exists for course offering %',
            v_result.course_offering_id;
    END IF;


    -- ========================================================
    -- COURSEWORK
    -- Each assessment contributes according to its weight.
    -- ========================================================

    SELECT
        COALESCE(
            SUM(
                (am.marks / NULLIF(a.max_marks,0))
                * 100
                * (a.weight_percent / 100)
            ),
            0
        ),
        COALESCE(SUM(a.weight_percent),0)
    INTO
        v_coursework,
        v_assessment_weight
    FROM public.assessments a
    JOIN public.assessment_marks am
        ON am.assessment_id = a.id
    WHERE a.course_offering_id = v_result.course_offering_id
      AND am.student_id = v_result.student_id
      AND a.status IN ('APPROVED','LOCKED')
      AND am.status IN ('APPROVED','LOCKED');


    -- ========================================================
    -- EXAMINATION
    -- Aggregate all valid examination papers for this student.
    -- ========================================================

    SELECT
        COALESCE(SUM(em.marks),0),
        COALESCE(SUM(ep.max_marks),0)
    INTO
        v_exam_marks,
        v_exam_max
    FROM public.examination_marks em
    JOIN public.examination_papers ep
        ON ep.id = em.examination_paper_id
    JOIN public.examination_candidates ec
        ON ec.id = em.examination_candidate_id
    WHERE ep.course_offering_id = v_result.course_offering_id
      AND em.student_id = v_result.student_id
      AND em.status IN ('APPROVED','LOCKED')
      AND ec.eligibility_status = 'ELIGIBLE'
      AND ec.candidate_status = 'ACTIVE';


    IF v_assessment_weight > 0 THEN

        -- Normalize coursework to the configured coursework component.
        v_coursework :=
            v_coursework
            / v_assessment_weight
            * v_policy.coursework_weight;

    ELSE

        v_coursework := 0;

    END IF;


    IF v_exam_max > 0 THEN

        v_exam :=
            (v_exam_marks / v_exam_max)
            * 100
            * (v_policy.examination_weight / 100);

    ELSE

        v_exam := 0;

    END IF;


    v_total := ROUND(
        COALESCE(v_coursework,0)
        +
        COALESCE(v_exam,0),
        2
    );


    SELECT
        g.grade_code,
        g.grade_point,
        g.pass_status,
        g.result_classification
    INTO
        v_grade_code,
        v_grade_point,
        v_pass_status,
        v_classification
    FROM public.get_grade_for_mark(
        v_policy.grade_scale_id,
        v_total
    ) g;


    IF v_grade_code IS NULL THEN
        RAISE EXCEPTION
            'No grade definition found for total mark %',
            v_total;
    END IF;


    UPDATE public.course_results
    SET
        coursework_mark = ROUND(v_coursework,2),
        examination_mark = ROUND(v_exam,2),
        total_mark = v_total,
        grade_code = v_grade_code,
        grade_point = v_grade_point,
        pass_status = v_pass_status,
        result_status = 'CALCULATED',
        calculated_at = now(),
        updated_at = now()
    WHERE id = p_course_result_id
    RETURNING * INTO v_result;


    RETURN v_result;

END;
$$;


-- ============================================================
-- 13. SEMESTER GPA CALCULATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.calculate_student_semester_gpa(
    p_student_id uuid,
    p_academic_year_id uuid,
    p_semester_id uuid
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE

    v_total_quality_points numeric := 0;
    v_total_credits numeric := 0;
    v_gpa numeric := 0;

BEGIN

    SELECT
        COALESCE(
            SUM(
                cr.grade_point * cr.credits
            ),
            0
        ),
        COALESCE(
            SUM(
                cr.credits
            ),
            0
        )
    INTO
        v_total_quality_points,
        v_total_credits
    FROM public.course_results cr
    WHERE cr.student_id = p_student_id
      AND cr.academic_year_id = p_academic_year_id
      AND cr.semester_id = p_semester_id
      AND cr.result_status IN (
          'APPROVED',
          'PUBLISHED',
          'LOCKED'
      )
      AND cr.pass_status IS NOT NULL
      AND cr.pass_status NOT IN (
          'WITHHELD',
          'INCOMPLETE'
      );


    IF v_total_credits > 0 THEN

        v_gpa :=
            ROUND(
                v_total_quality_points / v_total_credits,
                3
            );

    ELSE

        v_gpa := 0;

    END IF;


    INSERT INTO public.student_gpa_records (
        student_id,
        academic_year_id,
        semester_id,
        gpa,
        total_credits,
        total_quality_points,
        calculated_at
    )
    VALUES (
        p_student_id,
        p_academic_year_id,
        p_semester_id,
        v_gpa,
        v_total_credits,
        v_total_quality_points,
        now()
    )
    ON CONFLICT (
        student_id,
        academic_year_id,
        semester_id
    )
    DO UPDATE SET
        gpa = EXCLUDED.gpa,
        total_credits = EXCLUDED.total_credits,
        total_quality_points = EXCLUDED.total_quality_points,
        calculated_at = now();


    RETURN v_gpa;

END;
$$;


-- ============================================================
-- 14. CGPA CALCULATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.calculate_student_cgpa(
    p_student_id uuid,
    p_academic_year_id uuid DEFAULT NULL,
    p_semester_id uuid DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE

    v_quality_points numeric := 0;
    v_credits numeric := 0;
    v_cgpa numeric := 0;

BEGIN

    SELECT
        COALESCE(
            SUM(
                cr.grade_point * cr.credits
            ),
            0
        ),
        COALESCE(
            SUM(
                cr.credits
            ),
            0
        )
    INTO
        v_quality_points,
        v_credits
    FROM public.course_results cr
    WHERE cr.student_id = p_student_id
      AND cr.result_status IN (
          'APPROVED',
          'PUBLISHED',
          'LOCKED'
      )
      AND cr.pass_status IS NOT NULL
      AND cr.pass_status NOT IN (
          'WITHHELD',
          'INCOMPLETE'
      );


    IF v_credits > 0 THEN

        v_cgpa :=
            ROUND(
                v_quality_points / v_credits,
                3
            );

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
        v_credits,
        v_quality_points,
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
-- 15. LOCK PROTECTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_locked_course_result_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.result_status IN ('PUBLISHED','LOCKED') THEN

        IF NEW.student_id <> OLD.student_id
           OR NEW.course_offering_id <> OLD.course_offering_id
           OR NEW.course_registration_id <> OLD.course_registration_id
           OR NEW.academic_year_id <> OLD.academic_year_id
           OR NEW.semester_id <> OLD.semester_id
           OR NEW.credits <> OLD.credits
           OR NEW.coursework_mark IS DISTINCT FROM OLD.coursework_mark
           OR NEW.examination_mark IS DISTINCT FROM OLD.examination_mark
           OR NEW.total_mark IS DISTINCT FROM OLD.total_mark
           OR NEW.grade_code IS DISTINCT FROM OLD.grade_code
           OR NEW.grade_point IS DISTINCT FROM OLD.grade_point THEN

            RAISE EXCEPTION
                'Published or locked course result cannot be directly modified. Use result correction workflow.';

        END IF;

    END IF;

    RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS trg_prevent_locked_course_result_change
ON public.course_results;

CREATE TRIGGER trg_prevent_locked_course_result_change
BEFORE UPDATE
ON public.course_results
FOR EACH ROW
EXECUTE FUNCTION public.prevent_locked_course_result_change();


-- ============================================================
-- 16. PREVENT DELETE OF PUBLISHED/LOCKED RESULTS
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_course_result_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.result_status IN ('PUBLISHED','LOCKED') THEN

        RAISE EXCEPTION
            'Published or locked course result cannot be deleted.';

    END IF;

    RETURN OLD;

END;
$$;


DROP TRIGGER IF EXISTS trg_prevent_course_result_delete
ON public.course_results;

CREATE TRIGGER trg_prevent_course_result_delete
BEFORE DELETE
ON public.course_results
FOR EACH ROW
EXECUTE FUNCTION public.prevent_course_result_delete();


-- ============================================================
-- 17. RESULT CORRECTION VALIDATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_course_result_correction()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE

    v_status varchar(30);
    v_current_coursework numeric;
    v_current_exam numeric;
    v_current_total numeric;

BEGIN

    SELECT
        result_status,
        coursework_mark,
        examination_mark,
        total_mark
    INTO
        v_status,
        v_current_coursework,
        v_current_exam,
        v_current_total
    FROM public.course_results
    WHERE id = NEW.course_result_id;


    IF v_status IS NULL THEN

        RAISE EXCEPTION
            'Course result does not exist';

    END IF;


    IF v_status NOT IN (
        'APPROVED',
        'PUBLISHED',
        'LOCKED'
    ) THEN

        RAISE EXCEPTION
            'Course result is not eligible for formal correction';

    END IF;


    IF NEW.old_coursework_mark IS DISTINCT FROM v_current_coursework
       OR NEW.old_examination_mark IS DISTINCT FROM v_current_exam
       OR NEW.old_total_mark IS DISTINCT FROM v_current_total THEN

        RAISE EXCEPTION
            'Correction old values do not match the current result';

    END IF;


    IF trim(COALESCE(NEW.reason,'')) = '' THEN

        RAISE EXCEPTION
            'Correction reason is required';

    END IF;


    RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS trg_validate_course_result_correction
ON public.course_result_corrections;

CREATE TRIGGER trg_validate_course_result_correction
BEFORE INSERT OR UPDATE
ON public.course_result_corrections
FOR EACH ROW
EXECUTE FUNCTION public.validate_course_result_correction();


-- ============================================================
-- 18. REVIEWED CORRECTIONS ARE IMMUTABLE
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_reviewed_course_result_correction_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.status IN (
        'APPROVED',
        'REJECTED',
        'CANCELLED'
    ) THEN

        IF NEW.status <> OLD.status
           OR NEW.old_coursework_mark IS DISTINCT FROM OLD.old_coursework_mark
           OR NEW.new_coursework_mark IS DISTINCT FROM OLD.new_coursework_mark
           OR NEW.old_examination_mark IS DISTINCT FROM OLD.old_examination_mark
           OR NEW.new_examination_mark IS DISTINCT FROM OLD.new_examination_mark
           OR NEW.old_total_mark IS DISTINCT FROM OLD.old_total_mark
           OR NEW.new_total_mark IS DISTINCT FROM OLD.new_total_mark
           OR NEW.reason <> OLD.reason THEN

            RAISE EXCEPTION
                'Reviewed result correction cannot be modified';

        END IF;

    END IF;

    RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS trg_prevent_reviewed_course_result_correction_change
ON public.course_result_corrections;

CREATE TRIGGER trg_prevent_reviewed_course_result_correction_change
BEFORE UPDATE
ON public.course_result_corrections
FOR EACH ROW
EXECUTE FUNCTION public.prevent_reviewed_course_result_correction_change();


-- ============================================================
-- 19. UPDATED_AT
-- ============================================================

DROP TRIGGER IF EXISTS trg_grade_scales_updated_at
ON public.grade_scales;

CREATE TRIGGER trg_grade_scales_updated_at
BEFORE UPDATE
ON public.grade_scales
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_grade_scale_details_updated_at
ON public.grade_scale_details;

CREATE TRIGGER trg_grade_scale_details_updated_at
BEFORE UPDATE
ON public.grade_scale_details
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_course_result_policies_updated_at
ON public.course_result_policies;

CREATE TRIGGER trg_course_result_policies_updated_at
BEFORE UPDATE
ON public.course_result_policies
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_course_results_updated_at
ON public.course_results;

CREATE TRIGGER trg_course_results_updated_at
BEFORE UPDATE
ON public.course_results
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_student_semester_results_updated_at
ON public.student_semester_results;

CREATE TRIGGER trg_student_semester_results_updated_at
BEFORE UPDATE
ON public.student_semester_results
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_course_result_corrections_updated_at
ON public.course_result_corrections;

CREATE TRIGGER trg_course_result_corrections_updated_at
BEFORE UPDATE
ON public.course_result_corrections
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 20. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE public.grade_scales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.grade_scale_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_result_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_semester_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_gpa_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_cgpa_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_result_corrections ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 21. COMMENTS
-- ============================================================

COMMENT ON TABLE public.grade_scales IS
'Institutional grading scale definitions.';

COMMENT ON TABLE public.grade_scale_details IS
'Individual grade bands and grade points.';

COMMENT ON TABLE public.course_result_policies IS
'Defines coursework and examination weighting for each course offering.';

COMMENT ON TABLE public.course_results IS
'Authoritative calculated result for a student in a course offering.';

COMMENT ON TABLE public.student_semester_results IS
'Semester-level academic summary including GPA and academic standing.';

COMMENT ON TABLE public.student_gpa_records IS
'Calculated semester GPA snapshots.';

COMMENT ON TABLE public.student_cgpa_records IS
'Cumulative GPA snapshots used for transcripts and graduation.';

COMMENT ON TABLE public.course_result_corrections IS
'Formal correction workflow for approved, published or locked course results.';


COMMIT;
