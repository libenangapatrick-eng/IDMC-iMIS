-- ============================================================
-- IDMC iMIS
-- Migration: 202609150015_function_dependency_fixes
--
-- Fixes:
-- 1. convert_accepted_application_to_student
-- 2. calculate_course_result
-- ============================================================

BEGIN;


-- ============================================================
-- 1. APPLICATION -> STUDENT CONVERSION
-- ============================================================

CREATE OR REPLACE FUNCTION public.convert_accepted_application_to_student(
    p_application_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$

DECLARE

    v_application public.applications%ROWTYPE;
    v_offer       public.admission_offers%ROWTYPE;
    v_choice      public.application_choices%ROWTYPE;

    v_student_id     uuid;
    v_student_number varchar(50);

BEGIN

    -- Lock application
    SELECT *
    INTO v_application
    FROM public.applications
    WHERE id = p_application_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Application % does not exist',
            p_application_id;
    END IF;


    -- Already converted?
    SELECT id
    INTO v_student_id
    FROM public.students
    WHERE source_application_id = p_application_id
    LIMIT 1;

    IF FOUND THEN
        RETURN v_student_id;
    END IF;


    -- Actual column is applications.status
    IF v_application.status <> 'ACCEPTED' THEN
        RAISE EXCEPTION
            'Application % cannot be converted because its status is %; expected ACCEPTED',
            p_application_id,
            v_application.status;
    END IF;


    -- Find accepted offer
    SELECT ao.*
    INTO v_offer
    FROM public.admission_offers ao
    INNER JOIN public.admission_acceptances aa
        ON aa.admission_offer_id = ao.id
    WHERE ao.application_id = p_application_id
      AND aa.acceptance_status = 'ACCEPTED'
    ORDER BY
        aa.accepted_at DESC NULLS LAST,
        aa.created_at DESC
    LIMIT 1
    FOR UPDATE OF ao;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Application % has no accepted admission offer',
            p_application_id;
    END IF;


    -- Offer must be accepted
    IF v_offer.offer_status <> 'ACCEPTED' THEN
        RAISE EXCEPTION
            'Admission offer % is not in ACCEPTED status',
            v_offer.id;
    END IF;


    -- Check expiry
    IF v_offer.expiry_date IS NOT NULL
       AND v_offer.expiry_date < CURRENT_DATE THEN
        RAISE EXCEPTION
            'Admission offer % has expired',
            v_offer.id;
    END IF;


    -- admission_offers has programme_id, not application_choice_id
    SELECT ac.*
    INTO v_choice
    FROM public.application_choices ac
    WHERE ac.application_id = p_application_id
      AND ac.programme_id = v_offer.programme_id
    ORDER BY ac.choice_number ASC
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Application % has no application choice matching programme %',
            p_application_id,
            v_offer.programme_id;
    END IF;


    -- Serialize student number generation
    PERFORM pg_advisory_xact_lock(
        hashtextextended(
            'IDMC_STUDENT_NUMBER',
            0
        )
    );


    -- Generate student number
    SELECT
        'IDMC/' ||
        EXTRACT(YEAR FROM CURRENT_DATE)::integer::text ||
        '/' ||
        LPAD(
            (
                COALESCE(
                    MAX(
                        NULLIF(
                            substring(
                                student_number
                                FROM '[0-9]+$'
                            ),
                            ''
                        )::bigint
                    ),
                    0
                ) + 1
            )::text,
            5,
            '0'
        )
    INTO v_student_number
    FROM public.students
    WHERE student_number LIKE
        'IDMC/' ||
        EXTRACT(YEAR FROM CURRENT_DATE)::integer::text ||
        '/%';


    -- Create student
    INSERT INTO public.students (
        student_number,
        applicant_id,
        source_application_id,
        admission_offer_id,
        programme_id,
        programme_version_id,
        student_status,
        admission_date,
        enrollment_date
    )
    VALUES (
        v_student_number,
        v_application.applicant_id,
        p_application_id,
        v_offer.id,
        v_offer.programme_id,
        NULL,
        'PENDING_ACTIVATION',
        CURRENT_DATE,
        NULL
    )
    RETURNING id
    INTO v_student_id;


    -- Initial programme history
    INSERT INTO public.student_programme_history (
        student_id,
        programme_id,
        programme_version_id,
        change_type,
        effective_from,
        reason
    )
    VALUES (
        v_student_id,
        v_offer.programme_id,
        NULL,
        'INITIAL',
        CURRENT_DATE,
        'Initial programme assigned during admission conversion'
    );


    -- Actual column is applications.status
    UPDATE public.applications
    SET
        status = 'CONVERTED_TO_STUDENT',
        updated_at = now()
    WHERE id = p_application_id;


    RETURN v_student_id;

END;

$function$;


-- ============================================================
-- 2. COURSE RESULT CALCULATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.calculate_course_result(
    p_course_result_id uuid
)
RETURNS public.course_results
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$

DECLARE

    v_result public.course_results%ROWTYPE;
    v_policy public.course_result_policies%ROWTYPE;

    v_coursework numeric(8,2) := 0;
    v_exam      numeric(8,2) := 0;
    v_total     numeric(8,2) := 0;

    v_assessment_weight numeric(8,2) := 0;

    v_exam_marks numeric(12,4) := 0;
    v_exam_max   numeric(12,4) := 0;

    v_grade_code     varchar(10);
    v_grade_point    numeric(5,2);
    v_pass_status    varchar(30);
    v_classification varchar(100);

BEGIN

    -- Load course result
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


    -- Load result policy
    SELECT *
    INTO v_policy
    FROM public.course_result_policies
    WHERE course_offering_id = v_result.course_offering_id
      AND status IN ('ACTIVE', 'LOCKED')
    ORDER BY
        CASE
            WHEN status = 'ACTIVE' THEN 1
            ELSE 2
        END,
        created_at DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'No active result policy exists for course offering %',
            v_result.course_offering_id;
    END IF;


    -- ========================================================
    -- COURSEWORK
    -- Actual columns:
    -- assessments.maximum_marks
    -- assessments.weight_percentage
    -- ========================================================

    SELECT
        COALESCE(
            SUM(
                (
                    am.marks /
                    NULLIF(a.maximum_marks, 0)
                )
                * 100
                * (
                    a.weight_percentage /
                    100
                )
            ),
            0
        ),
        COALESCE(
            SUM(a.weight_percentage),
            0
        )
    INTO
        v_coursework,
        v_assessment_weight
    FROM public.assessments a
    INNER JOIN public.assessment_marks am
        ON am.assessment_id = a.id
    WHERE a.course_offering_id = v_result.course_offering_id
      AND am.student_id = v_result.student_id
      AND a.status IN ('APPROVED', 'LOCKED')
      AND am.status IN ('APPROVED', 'LOCKED');


    -- Normalize coursework
    IF v_assessment_weight > 0 THEN
        v_coursework :=
            (
                v_coursework /
                v_assessment_weight
            )
            * v_policy.coursework_weight;
    ELSE
        v_coursework := 0;
    END IF;


    -- ========================================================
    -- EXAMINATION
    -- Actual column:
    -- examination_papers.maximum_marks
    -- ========================================================

    SELECT
        COALESCE(
            SUM(em.marks),
            0
        ),
        COALESCE(
            SUM(ep.maximum_marks),
            0
        )
    INTO
        v_exam_marks,
        v_exam_max
    FROM public.examination_marks em
    INNER JOIN public.examination_papers ep
        ON ep.id = em.examination_paper_id
    INNER JOIN public.examination_candidates ec
        ON ec.id = em.examination_candidate_id
    WHERE ep.course_offering_id = v_result.course_offering_id
      AND em.student_id = v_result.student_id
      AND em.status IN ('APPROVED', 'LOCKED')
      AND ec.eligibility_status = 'ELIGIBLE'
      AND ec.candidate_status = 'ACTIVE';


    -- Calculate examination component
    IF v_exam_max > 0 THEN

        v_exam :=
            (
                v_exam_marks /
                v_exam_max
            )
            * 100
            * (
                v_policy.examination_weight /
                100
            );

    ELSE

        v_exam := 0;

    END IF;


    -- Final total
    v_total :=
        ROUND(
            COALESCE(v_coursework, 0)
            +
            COALESCE(v_exam, 0),
            2
        );


    -- Safety bound
    v_total :=
        LEAST(
            GREATEST(v_total, 0),
            100
        );


    -- Get grade
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


    -- Update result
    UPDATE public.course_results
    SET
        coursework_mark = ROUND(v_coursework, 2),
        examination_mark = ROUND(v_exam, 2),
        total_mark = v_total,
        grade_code = v_grade_code,
        grade_point = v_grade_point,
        pass_status = v_pass_status,
        result_status = 'CALCULATED',
        calculated_at = now(),
        updated_at = now()
    WHERE id = p_course_result_id
    RETURNING *
    INTO v_result;


    RETURN v_result;

END;

$function$;


COMMIT;
