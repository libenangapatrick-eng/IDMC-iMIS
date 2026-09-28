


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."calculate_and_store_cgpa"("p_student_id" "uuid", "p_academic_year_id" "uuid" DEFAULT NULL::"uuid", "p_semester_id" "uuid" DEFAULT NULL::"uuid") RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."calculate_and_store_cgpa"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."student_semester_results" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "academic_year_id" "uuid" NOT NULL,
    "semester_id" "uuid" NOT NULL,
    "programme_version_id" "uuid",
    "total_registered_credits" numeric(8,2) DEFAULT 0 NOT NULL,
    "total_attempted_credits" numeric(8,2) DEFAULT 0 NOT NULL,
    "total_earned_credits" numeric(8,2) DEFAULT 0 NOT NULL,
    "total_quality_points" numeric(10,3) DEFAULT 0 NOT NULL,
    "gpa" numeric(6,3),
    "courses_attempted" integer DEFAULT 0 NOT NULL,
    "courses_passed" integer DEFAULT 0 NOT NULL,
    "courses_failed" integer DEFAULT 0 NOT NULL,
    "academic_standing" character varying(50),
    "result_status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "calculated_at" timestamp with time zone,
    "submitted_at" timestamp with time zone,
    "submitted_by" "uuid",
    "approved_at" timestamp with time zone,
    "approved_by" "uuid",
    "published_at" timestamp with time zone,
    "published_by" "uuid",
    "locked_at" timestamp with time zone,
    "locked_by" "uuid",
    "remarks" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "student_semester_results_result_status_check" CHECK ((("result_status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'CALCULATED'::character varying, 'SUBMITTED'::character varying, 'UNDER_REVIEW'::character varying, 'APPROVED'::character varying, 'PUBLISHED'::character varying, 'LOCKED'::character varying, 'WITHHELD'::character varying])::"text"[])))
);


ALTER TABLE "public"."student_semester_results" OWNER TO "postgres";


COMMENT ON TABLE "public"."student_semester_results" IS 'Semester-level academic summary including GPA and academic standing.';



CREATE OR REPLACE FUNCTION "public"."calculate_and_store_semester_result"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") RETURNS "public"."student_semester_results"
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."calculate_and_store_semester_result"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."course_results" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "course_offering_id" "uuid" NOT NULL,
    "course_registration_id" "uuid" NOT NULL,
    "academic_year_id" "uuid" NOT NULL,
    "semester_id" "uuid" NOT NULL,
    "credits" numeric(6,2) DEFAULT 0 NOT NULL,
    "coursework_mark" numeric(8,2),
    "examination_mark" numeric(8,2),
    "total_mark" numeric(8,2),
    "grade_code" character varying(10),
    "grade_point" numeric(5,2),
    "pass_status" character varying(30),
    "result_status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "attempt_number" integer DEFAULT 1 NOT NULL,
    "result_type" character varying(30) DEFAULT 'NORMAL'::character varying NOT NULL,
    "calculated_at" timestamp with time zone,
    "submitted_at" timestamp with time zone,
    "submitted_by" "uuid",
    "approved_at" timestamp with time zone,
    "approved_by" "uuid",
    "published_at" timestamp with time zone,
    "published_by" "uuid",
    "locked_at" timestamp with time zone,
    "locked_by" "uuid",
    "remarks" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "course_result_attempt_valid" CHECK (("attempt_number" > 0)),
    CONSTRAINT "course_result_marks_valid" CHECK (((("coursework_mark" IS NULL) OR ("coursework_mark" >= (0)::numeric)) AND (("examination_mark" IS NULL) OR ("examination_mark" >= (0)::numeric)) AND (("total_mark" IS NULL) OR ("total_mark" >= (0)::numeric)))),
    CONSTRAINT "course_result_total_range" CHECK ((("total_mark" IS NULL) OR (("total_mark" >= (0)::numeric) AND ("total_mark" <= (100)::numeric)))),
    CONSTRAINT "course_results_result_status_check" CHECK ((("result_status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'CALCULATED'::character varying, 'SUBMITTED'::character varying, 'UNDER_REVIEW'::character varying, 'APPROVED'::character varying, 'PUBLISHED'::character varying, 'LOCKED'::character varying, 'WITHHELD'::character varying, 'INCOMPLETE'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "course_results_result_type_check" CHECK ((("result_type")::"text" = ANY ((ARRAY['NORMAL'::character varying, 'SUPPLEMENTARY'::character varying, 'SPECIAL'::character varying, 'RESIT'::character varying, 'RETAKE'::character varying, 'REPEAT'::character varying, 'CARRY_FORWARD'::character varying, 'MAKEUP'::character varying])::"text"[])))
);


ALTER TABLE "public"."course_results" OWNER TO "postgres";


COMMENT ON TABLE "public"."course_results" IS 'Authoritative calculated result for a student in a course offering.';



CREATE OR REPLACE FUNCTION "public"."calculate_course_result"("p_course_result_id" "uuid") RETURNS "public"."course_results"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$

DECLARE

    v_result public.course_results%ROWTYPE;
    v_policy public.course_result_policies%ROWTYPE;

    v_coursework numeric(8,2) := 0;
    v_exam      numeric(8,2) := 0;
    v_total     numeric(8,2) := 0;

    v_assessment_weight numeric(8,2) := 0;

    v_exam_marks numeric(12,4) := 0;
    v_exam_max   numeric(12,4) := 0;

    v_grade_code  varchar(10);
    v_grade_point numeric(5,2);
    v_pass_status varchar(30);

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


    SELECT
        COALESCE(SUM(em.marks), 0),
        COALESCE(SUM(ep.maximum_marks), 0)
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


    v_total :=
        ROUND(
            COALESCE(v_coursework, 0)
            +
            COALESCE(v_exam, 0),
            2
        );


    v_total :=
        LEAST(
            GREATEST(v_total, 0),
            100
        );


    SELECT
        g.grade_code,
        g.grade_point,
        g.pass_status
    INTO
        v_grade_code,
        v_grade_point,
        v_pass_status
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

$$;


ALTER FUNCTION "public"."calculate_course_result"("p_course_result_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."student_academic_standings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "academic_year_id" "uuid" NOT NULL,
    "semester_id" "uuid" NOT NULL,
    "semester_result_id" "uuid",
    "gpa" numeric(6,3),
    "cgpa" numeric(6,3),
    "standing_rule_id" "uuid",
    "standing_code" character varying(50),
    "standing_name" character varying(150),
    "remarks" "text",
    "status" character varying(20) DEFAULT 'CALCULATED'::character varying NOT NULL,
    "calculated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "academic_standing_cgpa_valid" CHECK ((("cgpa" IS NULL) OR (("cgpa" >= (0)::numeric) AND ("cgpa" <= (5)::numeric)))),
    CONSTRAINT "academic_standing_gpa_valid" CHECK ((("gpa" IS NULL) OR (("gpa" >= (0)::numeric) AND ("gpa" <= (5)::numeric)))),
    CONSTRAINT "student_academic_standings_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['CALCULATED'::character varying, 'REVIEW'::character varying, 'APPROVED'::character varying, 'PUBLISHED'::character varying, 'LOCKED'::character varying])::"text"[])))
);


ALTER TABLE "public"."student_academic_standings" OWNER TO "postgres";


COMMENT ON TABLE "public"."student_academic_standings" IS 'Semester-level academic standing calculated from GPA and CGPA.';



CREATE OR REPLACE FUNCTION "public"."calculate_student_academic_standing"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") RETURNS "public"."student_academic_standings"
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."calculate_student_academic_standing"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_student_cgpa"("p_student_id" "uuid", "p_academic_year_id" "uuid" DEFAULT NULL::"uuid", "p_semester_id" "uuid" DEFAULT NULL::"uuid") RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."calculate_student_cgpa"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_student_semester_gpa"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."calculate_student_semester_gpa"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."convert_accepted_application_to_student"("p_application_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$

DECLARE

    v_application public.applications%ROWTYPE;
    v_offer       public.admission_offers%ROWTYPE;

    v_student_id     uuid;
    v_student_number varchar(50);

BEGIN

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


    SELECT id
    INTO v_student_id
    FROM public.students
    WHERE source_application_id = p_application_id
    LIMIT 1;

    IF FOUND THEN
        RETURN v_student_id;
    END IF;


    IF v_application.status <> 'ACCEPTED' THEN
        RAISE EXCEPTION
            'Application % cannot be converted because its status is %; expected ACCEPTED',
            p_application_id,
            v_application.status;
    END IF;


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


    IF v_offer.offer_status <> 'ACCEPTED' THEN
        RAISE EXCEPTION
            'Admission offer % is not in ACCEPTED status',
            v_offer.id;
    END IF;


    IF v_offer.expiry_date IS NOT NULL
       AND v_offer.expiry_date < CURRENT_DATE THEN
        RAISE EXCEPTION
            'Admission offer % has expired',
            v_offer.id;
    END IF;


    -- Verify that the offered programme was actually selected
    -- by the applicant.
    IF NOT EXISTS (
        SELECT 1
        FROM public.application_choices ac
        WHERE ac.application_id = p_application_id
          AND ac.programme_id = v_offer.programme_id
    ) THEN
        RAISE EXCEPTION
            'Application % has no application choice matching programme %',
            p_application_id,
            v_offer.programme_id;
    END IF;


    PERFORM pg_advisory_xact_lock(
        hashtextextended(
            'IDMC_STUDENT_NUMBER',
            0
        )
    );


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


    UPDATE public.applications
    SET
        status = 'CONVERTED_TO_STUDENT',
        updated_at = now()
    WHERE id = p_application_id;


    RETURN v_student_id;

END;

$_$;


ALTER FUNCTION "public"."convert_accepted_application_to_student"("p_application_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."convert_accepted_application_to_student"("p_application_id" "uuid") IS 'Atomically converts one accepted admission application into exactly one student record.';



CREATE OR REPLACE FUNCTION "public"."create_result_deficiency"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."create_result_deficiency"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_student_financial_account"("p_student_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    v_id uuid;
begin

    if p_student_id is null then
        raise exception 'student_id is required';
    end if;

    insert into public.student_financial_accounts(student_id)
    values (p_student_id)
    on conflict (student_id)
    do nothing;

    select id
    into v_id
    from public.student_financial_accounts
    where student_id = p_student_id;

    return v_id;
end;
$$;


ALTER FUNCTION "public"."ensure_student_financial_account"("p_student_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."expire_admission_offers"() RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_count integer;
BEGIN

    UPDATE public.admission_offers
    SET offer_status = 'EXPIRED',
        updated_at = now()
    WHERE offer_status = 'ISSUED'
      AND expiry_date < CURRENT_DATE;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN v_count;
END;
$$;


ALTER FUNCTION "public"."expire_admission_offers"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."expire_admission_offers"() IS 'Automatically changes expired ISSUED admission offers to EXPIRED.';



CREATE OR REPLACE FUNCTION "public"."generate_graduation_clearances"("p_graduation_candidate_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$

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

$$;


ALTER FUNCTION "public"."generate_graduation_clearances"("p_graduation_candidate_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_library_loan_number"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    next_number bigint;
BEGIN

    IF NEW.loan_number IS NULL
       OR btrim(NEW.loan_number) = '' THEN

        next_number := nextval(
            'public.library_loan_number_seq'
        );

        NEW.loan_number :=
            'LIB/' ||
            to_char(current_date, 'YYYY') ||
            '/' ||
            lpad(next_number::text, 6, '0');

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_library_loan_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_procurement_request_number"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    next_number bigint;
BEGIN

    IF NEW.request_number IS NULL
       OR btrim(NEW.request_number) = '' THEN

        next_number := nextval(
            'public.procurement_request_number_seq'
        );

        NEW.request_number :=
            'PR/' ||
            to_char(current_date, 'YYYY') ||
            '/' ||
            lpad(next_number::text, 6, '0');

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_procurement_request_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_purchase_order_number"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    next_number bigint;
BEGIN

    IF NEW.purchase_order_number IS NULL
       OR btrim(NEW.purchase_order_number) = '' THEN

        next_number := nextval(
            'public.purchase_order_number_seq'
        );

        NEW.purchase_order_number :=
            'PO/' ||
            to_char(current_date, 'YYYY') ||
            '/' ||
            lpad(next_number::text, 6, '0');

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_purchase_order_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_staff_employee_number"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    next_number bigint;
BEGIN

    IF NEW.employee_number IS NULL
       OR btrim(NEW.employee_number) = '' THEN

        next_number := nextval(
            'public.staff_employee_number_seq'
        );

        NEW.employee_number :=
            'EMP/' ||
            to_char(current_date, 'YYYY') ||
            '/' ||
            lpad(next_number::text, 6, '0');

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_staff_employee_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_staff_leave_request_number"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    next_number bigint;
BEGIN

    IF NEW.request_number IS NULL
       OR btrim(NEW.request_number) = '' THEN

        next_number := nextval(
            'public.staff_leave_request_number_seq'
        );

        NEW.request_number :=
            'LEAVE/' ||
            COALESCE(NEW.leave_year::text, to_char(current_date, 'YYYY')) ||
            '/' ||
            lpad(next_number::text, 6, '0');

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_staff_leave_request_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_transcript_number"() RETURNS character varying
    LANGUAGE "plpgsql"
    AS $_$
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
$_$;


ALTER FUNCTION "public"."generate_transcript_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_transcript_verification_code"() RETURNS character varying
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."generate_transcript_verification_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_grade_for_mark"("p_grade_scale_id" "uuid", "p_total_mark" numeric) RETURNS TABLE("grade_code" character varying, "grade_point" numeric, "pass_status" character varying, "result_classification" character varying)
    LANGUAGE "plpgsql" STABLE
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


ALTER FUNCTION "public"."get_grade_for_mark"("p_grade_scale_id" "uuid", "p_total_mark" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."post_financial_transaction"("p_transaction_number" character varying, "p_student_id" "uuid", "p_transaction_type" character varying, "p_debit" numeric, "p_credit" numeric, "p_reference" character varying, "p_description" "text", "p_created_by" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_transaction_id uuid;
BEGIN

    -- Transaction number is required
    IF NULLIF(trim(p_transaction_number), '') IS NULL THEN
        RAISE EXCEPTION 'Transaction number is required';
    END IF;

    -- Transaction type is required
    IF NULLIF(trim(p_transaction_type), '') IS NULL THEN
        RAISE EXCEPTION 'Transaction type is required';
    END IF;

    -- Amounts must not be negative
    IF COALESCE(p_debit, 0) < 0 THEN
        RAISE EXCEPTION 'Debit amount cannot be negative';
    END IF;

    IF COALESCE(p_credit, 0) < 0 THEN
        RAISE EXCEPTION 'Credit amount cannot be negative';
    END IF;

    -- Exactly one side must contain an amount
    IF COALESCE(p_debit, 0) = 0
       AND COALESCE(p_credit, 0) = 0 THEN
        RAISE EXCEPTION 'Either debit or credit must be greater than zero';
    END IF;

    IF COALESCE(p_debit, 0) > 0
       AND COALESCE(p_credit, 0) > 0 THEN
        RAISE EXCEPTION 'Debit and credit cannot both be greater than zero';
    END IF;

    -- Prevent duplicate transaction numbers
    IF EXISTS (
        SELECT 1
        FROM public.financial_transactions
        WHERE transaction_number = p_transaction_number
    ) THEN
        RAISE EXCEPTION
            'Financial transaction number already exists: %',
            p_transaction_number;
    END IF;

    -- Insert using the ACTUAL column name: reference_number
    INSERT INTO public.financial_transactions (
        transaction_number,
        student_id,
        transaction_type,
        debit_amount,
        credit_amount,
        transaction_date,
        reference_number,
        description,
        status,
        created_by
    )
    VALUES (
        p_transaction_number,
        p_student_id,
        p_transaction_type,
        COALESCE(p_debit, 0),
        COALESCE(p_credit, 0),
        now(),
        p_reference,
        p_description,
        'POSTED',
        p_created_by
    )
    RETURNING id
    INTO v_transaction_id;

    -- Refresh student financial account where applicable
    IF p_student_id IS NOT NULL THEN
        PERFORM public.refresh_student_financial_account(p_student_id);
    END IF;

    RETURN v_transaction_id;
END;
$$;


ALTER FUNCTION "public"."post_financial_transaction"("p_transaction_number" character varying, "p_student_id" "uuid", "p_transaction_type" character varying, "p_debit" numeric, "p_credit" numeric, "p_reference" character varying, "p_description" "text", "p_created_by" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prepare_student_transcript"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."prepare_student_transcript"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_add_drop_after_lock"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
    v_status varchar(40);
BEGIN

    SELECT registration_status
    INTO v_status
    FROM public.student_registrations
    WHERE id = COALESCE(
        NEW.student_registration_id,
        OLD.student_registration_id
    );

    IF v_status IN (
        'LOCKED',
        'CANCELLED'
    )
    THEN
        RAISE EXCEPTION
            'Add/Drop requests are not allowed for locked or cancelled registration';
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION "public"."prevent_add_drop_after_lock"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_alumni_hard_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    RAISE EXCEPTION
        'Alumni records cannot be physically deleted. Change status instead.';

END
$$;


ALTER FUNCTION "public"."prevent_alumni_hard_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_assessment_mark_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_status varchar(30);
BEGIN
    SELECT status
    INTO v_status
    FROM public.assessments
    WHERE id = OLD.assessment_id;

    IF v_status IN ('APPROVED', 'LOCKED') THEN
        RAISE EXCEPTION
            'Approved or locked assessment marks cannot be deleted.';
    END IF;

    RAISE EXCEPTION
        'Assessment marks cannot be deleted. Use the correction workflow.';
END;
$$;


ALTER FUNCTION "public"."prevent_assessment_mark_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_course_result_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF OLD.result_status IN ('PUBLISHED','LOCKED') THEN

        RAISE EXCEPTION
            'Published or locked course result cannot be deleted.';

    END IF;

    RETURN OLD;

END;
$$;


ALTER FUNCTION "public"."prevent_course_result_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_examination_mark_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    RAISE EXCEPTION
        'Examination marks cannot be deleted. Use the formal correction workflow.';
END;
$$;


ALTER FUNCTION "public"."prevent_examination_mark_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_financial_account_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    raise exception
        'Student financial accounts cannot be deleted';
end;
$$;


ALTER FUNCTION "public"."prevent_financial_account_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_financial_history_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RAISE EXCEPTION
        'Financial records cannot be hard deleted. Use reversal, cancellation, refund, or adjustment workflow.';
END;
$$;


ALTER FUNCTION "public"."prevent_financial_history_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_financial_transaction_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RAISE EXCEPTION
        'Financial transactions cannot be hard deleted. Use reversal/adjustment workflow.';
END;
$$;


ALTER FUNCTION "public"."prevent_financial_transaction_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_invalid_offer_status_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF OLD.offer_status = 'ACCEPTED'
       AND NEW.offer_status = 'ISSUED' THEN
        RAISE EXCEPTION
            'An ACCEPTED admission offer cannot return to ISSUED';
    END IF;


    IF OLD.offer_status = 'EXPIRED'
       AND NEW.offer_status = 'ISSUED' THEN
        RAISE EXCEPTION
            'An EXPIRED admission offer cannot return to ISSUED';
    END IF;


    IF OLD.offer_status = 'CANCELLED'
       AND NEW.offer_status = 'ISSUED' THEN
        RAISE EXCEPTION
            'A CANCELLED admission offer cannot return to ISSUED';
    END IF;


    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_invalid_offer_status_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_issued_certificate_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF OLD.status IN ('REVOKED', 'REPLACED') THEN
        IF NEW.status <> OLD.status THEN
            RAISE EXCEPTION
                'Final certificate status cannot be changed';
        END IF;
    END IF;

    IF OLD.status = 'ISSUED' THEN

        IF NEW.student_id <> OLD.student_id
           OR NEW.graduation_award_id <> OLD.graduation_award_id
           OR NEW.certificate_number <> OLD.certificate_number
           OR NEW.verification_code <> OLD.verification_code THEN
            RAISE EXCEPTION
                'Issued certificate identity fields are immutable';
        END IF;

    END IF;

    IF NEW.replacement_of = NEW.id THEN
        RAISE EXCEPTION
            'A certificate cannot replace itself';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_issued_certificate_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_issued_transcript_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF OLD.transcript_status IN ('ISSUED', 'SUPERSEDED') THEN

        -- Only status/audit lifecycle fields may change.
        IF NEW.student_id IS DISTINCT FROM OLD.student_id
           OR NEW.transcript_number IS DISTINCT FROM OLD.transcript_number
           OR NEW.programme_version_id IS DISTINCT FROM OLD.programme_version_id
           OR NEW.transcript_type IS DISTINCT FROM OLD.transcript_type
           OR NEW.issue_reason IS DISTINCT FROM OLD.issue_reason
           OR NEW.cumulative_credits IS DISTINCT FROM OLD.cumulative_credits
           OR NEW.cumulative_earned_credits IS DISTINCT FROM OLD.cumulative_earned_credits
           OR NEW.cumulative_quality_points IS DISTINCT FROM OLD.cumulative_quality_points
           OR NEW.cgpa IS DISTINCT FROM OLD.cgpa
           OR NEW.final_academic_standing IS DISTINCT FROM OLD.final_academic_standing
           OR NEW.verification_code IS DISTINCT FROM OLD.verification_code
           OR NEW.document_file_id IS DISTINCT FROM OLD.document_file_id THEN

            RAISE EXCEPTION
                'Issued/Superseded transcript is immutable. '
                'Create a replacement transcript instead.';

        END IF;

    END IF;


    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_issued_transcript_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_locked_assessment_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_status varchar;
BEGIN

    SELECT status
    INTO v_status
    FROM public.assessments
    WHERE id = COALESCE(
        NEW.assessment_id,
        OLD.assessment_id
    );

    IF v_status = 'LOCKED' THEN
        RAISE EXCEPTION
            'Assessment is LOCKED and cannot be modified';
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION "public"."prevent_locked_assessment_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_locked_assessment_mark_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_assessment_status varchar(30);
BEGIN
    SELECT status
    INTO v_assessment_status
    FROM public.assessments
    WHERE id = OLD.assessment_id;

    IF v_assessment_status = 'LOCKED' THEN

        IF NEW.marks IS DISTINCT FROM OLD.marks
           OR NEW.grade IS DISTINCT FROM OLD.grade
           OR NEW.remarks IS DISTINCT FROM OLD.remarks
           OR NEW.student_id IS DISTINCT FROM OLD.student_id
           OR NEW.course_registration_id IS DISTINCT FROM OLD.course_registration_id THEN

            RAISE EXCEPTION
                'Locked assessment marks cannot be modified directly. Submit a correction request.';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_locked_assessment_mark_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_locked_attendance_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_status varchar;
BEGIN
    SELECT status
    INTO v_status
    FROM public.attendance_sessions
    WHERE id = COALESCE(
        NEW.attendance_session_id,
        OLD.attendance_session_id
    );

    IF v_status = 'LOCKED' THEN
        RAISE EXCEPTION
            'Attendance session % is LOCKED and cannot be modified',
            COALESCE(
                NEW.attendance_session_id,
                OLD.attendance_session_id
            );
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION "public"."prevent_locked_attendance_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_locked_course_registration_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
    v_status varchar(40);
BEGIN

    SELECT registration_status
    INTO v_status
    FROM public.student_registrations
    WHERE id = COALESCE(
        NEW.student_registration_id,
        OLD.student_registration_id
    );

    IF v_status IN ('LOCKED')
    THEN
        RAISE EXCEPTION
            'Cannot modify course registration for a locked student registration';
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION "public"."prevent_locked_course_registration_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_locked_course_result_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."prevent_locked_course_result_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_locked_examination_mark_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF OLD.status = 'LOCKED' THEN

        IF NEW.marks <> OLD.marks
           OR NEW.grade <> OLD.grade
           OR NEW.percentage <> OLD.percentage
           OR NEW.student_id <> OLD.student_id
           OR NEW.course_registration_id <> OLD.course_registration_id
           OR NEW.examination_paper_id <> OLD.examination_paper_id THEN

            RAISE EXCEPTION
                'Locked examination mark cannot be directly modified. Use examination mark correction workflow.';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_locked_examination_mark_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_locked_examination_paper_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF OLD.status = 'LOCKED' THEN

        IF NEW.status <> OLD.status
           OR NEW.examination_period_id <> OLD.examination_period_id
           OR NEW.course_offering_id <> OLD.course_offering_id
           OR NEW.paper_code <> OLD.paper_code
           OR NEW.max_marks <> OLD.max_marks
           OR NEW.duration_minutes <> OLD.duration_minutes THEN

            RAISE EXCEPTION
                'Locked examination paper cannot be modified';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_locked_examination_paper_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_locked_examination_session_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF OLD.status = 'LOCKED' THEN
        IF NEW.status <> OLD.status
           OR NEW.examination_paper_id <> OLD.examination_paper_id
           OR NEW.room_id <> OLD.room_id
           OR NEW.start_at <> OLD.start_at
           OR NEW.end_at <> OLD.end_at THEN

            RAISE EXCEPTION
                'Locked examination session cannot be modified';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_locked_examination_session_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_locked_semester_result_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."prevent_locked_semester_result_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_locked_timetable_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
    v_status varchar(30);
BEGIN

    SELECT status
    INTO v_status
    FROM public.timetables
    WHERE id = COALESCE(
        NEW.timetable_id,
        OLD.timetable_id
    );

    IF v_status = 'LOCKED' THEN
        RAISE EXCEPTION
            'Locked timetable cannot be modified';
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION "public"."prevent_locked_timetable_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_notification_history_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RAISE EXCEPTION
        'Notification history cannot be physically deleted. Use status changes instead.';
END
$$;


ALTER FUNCTION "public"."prevent_notification_history_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_reviewed_assessment_correction_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF OLD.status IN ('APPROVED', 'REJECTED') THEN

        IF NEW.status IS DISTINCT FROM OLD.status
           OR NEW.old_marks IS DISTINCT FROM OLD.old_marks
           OR NEW.new_marks IS DISTINCT FROM OLD.new_marks
           OR NEW.old_grade IS DISTINCT FROM OLD.old_grade
           OR NEW.new_grade IS DISTINCT FROM OLD.new_grade
           OR NEW.reason IS DISTINCT FROM OLD.reason
           OR NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by
           OR NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at
           OR NEW.review_comment IS DISTINCT FROM OLD.review_comment THEN

            RAISE EXCEPTION
                'Reviewed assessment correction requests are immutable.';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_reviewed_assessment_correction_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_reviewed_course_result_correction_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."prevent_reviewed_course_result_correction_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_reviewed_examination_correction_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF OLD.status IN ('APPROVED','REJECTED','CANCELLED') THEN

        IF NEW.status <> OLD.status
           OR NEW.old_marks <> OLD.old_marks
           OR NEW.new_marks <> OLD.new_marks
           OR NEW.old_grade IS DISTINCT FROM OLD.old_grade
           OR NEW.new_grade IS DISTINCT FROM OLD.new_grade
           OR NEW.reason <> OLD.reason THEN

            RAISE EXCEPTION
                'Reviewed examination mark correction cannot be modified';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_reviewed_examination_correction_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_alumni_identity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF TG_OP = 'UPDATE' THEN

        IF NEW.student_id IS DISTINCT FROM OLD.student_id THEN
            RAISE EXCEPTION
                'Alumni identity is immutable: student_id cannot be changed';
        END IF;

        IF NEW.alumni_number IS DISTINCT FROM OLD.alumni_number THEN
            RAISE EXCEPTION
                'Alumni identity is immutable: alumni_number cannot be changed';
        END IF;

    END IF;

    RETURN NEW;

END
$$;


ALTER FUNCTION "public"."protect_alumni_identity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_posted_financial_transaction"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF OLD.status = 'POSTED' THEN

        IF NEW.transaction_number IS DISTINCT FROM OLD.transaction_number THEN
            RAISE EXCEPTION
                'Posted transaction number cannot be changed';
        END IF;

        IF NEW.student_id IS DISTINCT FROM OLD.student_id THEN
            RAISE EXCEPTION
                'Posted transaction student cannot be changed';
        END IF;

        IF NEW.transaction_type IS DISTINCT FROM OLD.transaction_type THEN
            RAISE EXCEPTION
                'Posted transaction type cannot be changed';
        END IF;

        IF NEW.debit_amount IS DISTINCT FROM OLD.debit_amount THEN
            RAISE EXCEPTION
                'Posted debit amount cannot be changed';
        END IF;

        IF NEW.credit_amount IS DISTINCT FROM OLD.credit_amount THEN
            RAISE EXCEPTION
                'Posted credit amount cannot be changed';
        END IF;

        IF NEW.reference_number IS DISTINCT FROM OLD.reference_number THEN
            RAISE EXCEPTION
                'Posted transaction reference cannot be changed';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."protect_posted_financial_transaction"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_student_status_history"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN

        INSERT INTO public.student_status_history (
            student_id,
            old_status,
            new_status,
            reason,
            changed_by
        )
        VALUES (
            NEW.id,
            NULL,
            NEW.student_status,
            'Student record created',
            NULL
        );

    ELSIF OLD.student_status IS DISTINCT FROM NEW.student_status THEN

        INSERT INTO public.student_status_history (
            student_id,
            old_status,
            new_status,
            reason,
            changed_by
        )
        VALUES (
            NEW.id,
            OLD.student_status,
            NEW.student_status,
            NULL,
            NULL
        );

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."record_student_status_history"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_all_invoice_financials"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    v_count integer := 0;
    r record;
begin

    for r in
        select id
        from public.invoices
        where status not in ('CANCELLED', 'VOID')
    loop

        perform public.refresh_invoice_financials(r.id);
        v_count := v_count + 1;

    end loop;

    return v_count;
end;
$$;


ALTER FUNCTION "public"."refresh_all_invoice_financials"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_invoice_financials"("p_invoice_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    v_total numeric(14,2) := 0;
    v_paid numeric(14,2) := 0;
    v_balance numeric(14,2) := 0;
    v_status varchar(30);
    v_due_date date;
    v_student_id uuid;
begin

    select
        student_id,
        due_date
    into
        v_student_id,
        v_due_date
    from public.invoices
    where id = p_invoice_id;

    if v_student_id is null then
        return;
    end if;


    select
        coalesce(sum(line_total), 0)
    into v_total
    from public.invoice_items
    where invoice_id = p_invoice_id;


    select
        coalesce(sum(allocated_amount), 0)
    into v_paid
    from public.payment_allocations
    where invoice_id = p_invoice_id
      and status = 'ACTIVE'
      and exists (
          select 1
          from public.payments p
          where p.id = payment_allocations.payment_id
            and p.status = 'CONFIRMED'
      );


    v_balance := greatest(v_total - v_paid, 0);


    select status
    into v_status
    from public.invoices
    where id = p_invoice_id;


    if v_status in ('CANCELLED', 'VOID') then

        update public.invoices
        set
            subtotal = v_total,
            amount_paid = v_paid,
            balance_amount = v_balance,
            updated_at = now()
        where id = p_invoice_id;

        return;
    end if;


    if v_total = 0 then
        v_status := 'DRAFT';

    elsif v_paid >= v_total then
        v_status := 'PAID';

    elsif v_paid > 0 then
        v_status := 'PARTIALLY_PAID';

    elsif v_due_date is not null
          and v_due_date < current_date then
        v_status := 'OVERDUE';

    else
        if v_status = 'DRAFT' then
            v_status := 'ISSUED';
        end if;
    end if;


    update public.invoices
    set
        subtotal = v_total,
        total_amount = greatest(
            v_total
            - coalesce(discount_amount, 0)
            - coalesce(scholarship_amount, 0)
            + coalesce(adjustment_amount, 0),
            0
        ),
        amount_paid = v_paid,
        balance_amount = greatest(
            greatest(
                v_total
                - coalesce(discount_amount, 0)
                - coalesce(scholarship_amount, 0)
                + coalesce(adjustment_amount, 0),
                0
            ) - v_paid,
            0
        ),
        status = v_status,
        updated_at = now()
    where id = p_invoice_id;


end;
$$;


ALTER FUNCTION "public"."refresh_invoice_financials"("p_invoice_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_registration_credits"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
    v_registration_id uuid;
BEGIN

    v_registration_id :=
        COALESCE(
            NEW.student_registration_id,
            OLD.student_registration_id
        );

    UPDATE public.student_registrations sr
    SET total_registered_credits = COALESCE(
        (
            SELECT SUM(cr.credits)
            FROM public.course_registrations cr
            WHERE cr.student_registration_id = sr.id
              AND cr.registration_status NOT IN (
                  'DROPPED',
                  'REJECTED',
                  'CANCELLED'
              )
        ),
        0
    ),
    updated_at = now()
    WHERE sr.id = v_registration_id;

    RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION "public"."refresh_registration_credits"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_student_financial_account"("p_student_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_total_charged numeric := 0;
    v_total_paid numeric := 0;
    v_total_refunded numeric := 0;
    v_total_scholarship numeric := 0;
    v_total_waiver numeric := 0;
    v_total_adjustments numeric := 0;
BEGIN

    IF p_student_id IS NULL THEN
        RAISE EXCEPTION 'Student ID cannot be null';
    END IF;

    /*
     * ----------------------------------------------------------
     * TOTAL CHARGED
     * ----------------------------------------------------------
     * student_charges.net_amount is authoritative because it
     * already represents the net charge after scholarship,
     * waiver and adjustments.
     */
    SELECT
        COALESCE(SUM(sc.net_amount), 0)
    INTO v_total_charged
    FROM public.student_charges sc
    WHERE sc.student_id = p_student_id
      AND COALESCE(sc.status, 'ACTIVE')
            NOT IN ('CANCELLED', 'VOID', 'REVERSED');


    /*
     * ----------------------------------------------------------
     * SCHOLARSHIP INFORMATION
     * ----------------------------------------------------------
     */
    SELECT
        COALESCE(SUM(sc.scholarship_amount), 0)
    INTO v_total_scholarship
    FROM public.student_charges sc
    WHERE sc.student_id = p_student_id
      AND COALESCE(sc.status, 'ACTIVE')
            NOT IN ('CANCELLED', 'VOID', 'REVERSED');


    /*
     * ----------------------------------------------------------
     * WAIVER INFORMATION
     * ----------------------------------------------------------
     */
    SELECT
        COALESCE(SUM(sc.waiver_amount), 0)
    INTO v_total_waiver
    FROM public.student_charges sc
    WHERE sc.student_id = p_student_id
      AND COALESCE(sc.status, 'ACTIVE')
            NOT IN ('CANCELLED', 'VOID', 'REVERSED');


    /*
     * ----------------------------------------------------------
     * ADJUSTMENT INFORMATION
     * ----------------------------------------------------------
     */
    SELECT
        COALESCE(SUM(sc.adjustment_amount), 0)
    INTO v_total_adjustments
    FROM public.student_charges sc
    WHERE sc.student_id = p_student_id
      AND COALESCE(sc.status, 'ACTIVE')
            NOT IN ('CANCELLED', 'VOID', 'REVERSED');


    /*
     * ----------------------------------------------------------
     * TOTAL PAID
     * ----------------------------------------------------------
     * payment_allocations does NOT contain student_id.
     *
     * Correct relationship:
     *
     * payment_allocations.payment_id
     *        ->
     * payments.id
     *        ->
     * payments.student_id
     */
    SELECT
        COALESCE(SUM(pa.allocated_amount), 0)
    INTO v_total_paid
    FROM public.payment_allocations pa
    JOIN public.payments p
      ON p.id = pa.payment_id
    WHERE p.student_id = p_student_id
      AND COALESCE(pa.status, 'ACTIVE')
            NOT IN ('CANCELLED', 'REVERSED')
      AND COALESCE(p.status, 'POSTED')
            NOT IN ('CANCELLED', 'REVERSED');


    /*
     * ----------------------------------------------------------
     * TOTAL REFUNDED
     * ----------------------------------------------------------
     */
    SELECT
        COALESCE(SUM(r.amount), 0)
    INTO v_total_refunded
    FROM public.refunds r
    WHERE r.student_id = p_student_id
      AND COALESCE(r.status, 'APPROVED')
            IN ('APPROVED', 'PROCESSED', 'COMPLETED', 'POSTED');


    /*
     * ----------------------------------------------------------
     * SAFETY NORMALIZATION
     * ----------------------------------------------------------
     */
    v_total_charged :=
        GREATEST(COALESCE(v_total_charged, 0), 0);

    v_total_paid :=
        GREATEST(COALESCE(v_total_paid, 0), 0);

    v_total_refunded :=
        GREATEST(COALESCE(v_total_refunded, 0), 0);

    v_total_scholarship :=
        GREATEST(COALESCE(v_total_scholarship, 0), 0);

    v_total_waiver :=
        GREATEST(COALESCE(v_total_waiver, 0), 0);

    v_total_adjustments :=
        COALESCE(v_total_adjustments, 0);


    /*
     * ----------------------------------------------------------
     * UPSERT STUDENT FINANCIAL ACCOUNT
     * ----------------------------------------------------------
     *
     * current_balance is GENERATED ALWAYS and therefore is NOT
     * written directly here.
     *
     * Current balance formula from migration 024:
     *
     * total_charged - total_paid + total_refunded
     *
     * Scholarship, waiver and adjustment values remain
     * informational because they are already incorporated into
     * student_charges.net_amount.
     */
    INSERT INTO public.student_financial_accounts (
        student_id,
        total_charged,
        total_paid,
        total_refunded,
        total_scholarship,
        total_waiver,
        total_adjustments,
        last_calculated_at,
        updated_at
    )
    VALUES (
        p_student_id,
        v_total_charged,
        v_total_paid,
        v_total_refunded,
        v_total_scholarship,
        v_total_waiver,
        v_total_adjustments,
        now(),
        now()
    )
    ON CONFLICT (student_id)
    DO UPDATE SET
        total_charged      = EXCLUDED.total_charged,
        total_paid        = EXCLUDED.total_paid,
        total_refunded    = EXCLUDED.total_refunded,
        total_scholarship = EXCLUDED.total_scholarship,
        total_waiver      = EXCLUDED.total_waiver,
        total_adjustments = EXCLUDED.total_adjustments,
        last_calculated_at = now(),
        updated_at = now();

END;
$$;


ALTER FUNCTION "public"."refresh_student_financial_account"("p_student_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."refresh_student_financial_account"("p_student_id" "uuid") IS 'Recalculates a student financial account using authoritative net charges, payment allocations linked through payments.student_id, and valid refunds.';



CREATE OR REPLACE FUNCTION "public"."set_students_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin

    new.updated_at = now();

    return new;

end;
$$;


ALTER FUNCTION "public"."set_students_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_admission_offer_after_acceptance"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF NEW.acceptance_status = 'ACCEPTED' THEN

        UPDATE public.admission_offers
        SET offer_status = 'ACCEPTED',
            updated_at = now()
        WHERE id = NEW.admission_offer_id;

    ELSIF NEW.acceptance_status = 'DECLINED' THEN

        UPDATE public.admission_offers
        SET offer_status = 'CANCELLED',
            updated_at = now()
        WHERE id = NEW.admission_offer_id;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_admission_offer_after_acceptance"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_application_after_admission_acceptance"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_application_id uuid;
BEGIN

    SELECT application_id
    INTO v_application_id
    FROM public.admission_offers
    WHERE id = NEW.admission_offer_id;


    IF NEW.acceptance_status = 'ACCEPTED' THEN

        UPDATE public.applications
        SET application_status = 'ACCEPTED',
            updated_at = now()
        WHERE id = v_application_id
          AND application_status IN ('SELECTED', 'ADMISSION_OFFERED');

    ELSIF NEW.acceptance_status = 'DECLINED' THEN

        UPDATE public.applications
        SET application_status = 'REJECTED',
            updated_at = now()
        WHERE id = v_application_id
          AND application_status IN ('SELECTED', 'ADMISSION_OFFERED');

    END IF;


    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_application_after_admission_acceptance"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_attendance_session_timestamps"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF NEW.status = 'OPEN'
       AND OLD.status <> 'OPEN'
       AND NEW.opened_at IS NULL THEN

        NEW.opened_at := now();
    END IF;

    IF NEW.status = 'SUBMITTED'
       AND OLD.status <> 'SUBMITTED'
       AND NEW.submitted_at IS NULL THEN

        NEW.submitted_at := now();
    END IF;

    IF NEW.status = 'LOCKED'
       AND OLD.status <> 'LOCKED'
       AND NEW.locked_at IS NULL THEN

        NEW.locked_at := now();
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_attendance_session_timestamps"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_alumni_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END
$$;


ALTER FUNCTION "public"."touch_alumni_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_finance_automation_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    new.updated_at = now();
    return new;
end;
$$;


ALTER FUNCTION "public"."touch_finance_automation_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_finance_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."touch_finance_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_notification_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END
$$;


ALTER FUNCTION "public"."touch_notification_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_generate_graduation_clearances"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN

    PERFORM public.generate_graduation_clearances(NEW.id);

    RETURN NEW;

END;
$$;


ALTER FUNCTION "public"."trg_generate_graduation_clearances"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_refresh_after_payment_status"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin

    if new.student_id is not null then
        perform public.refresh_student_financial_account(
            new.student_id
        );
    end if;

    return new;
end;
$$;


ALTER FUNCTION "public"."trg_refresh_after_payment_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_refresh_after_refund"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin

    if new.student_id is not null then
        perform public.refresh_student_financial_account(
            new.student_id
        );
    end if;

    return new;
end;
$$;


ALTER FUNCTION "public"."trg_refresh_after_refund"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_refresh_financials_after_allocation"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    v_student_id uuid;
    v_invoice_id uuid;
begin

    if tg_op = 'DELETE' then

        select student_id
        into v_student_id
        from public.payments
        where id = old.payment_id;

        v_invoice_id := old.invoice_id;

    else

        select student_id
        into v_student_id
        from public.payments
        where id = new.payment_id;

        v_invoice_id := new.invoice_id;

    end if;


    if v_invoice_id is not null then
        perform public.refresh_invoice_financials(v_invoice_id);
    end if;


    if v_student_id is not null then
        perform public.refresh_student_financial_account(v_student_id);
    end if;


    return coalesce(new, old);
end;
$$;


ALTER FUNCTION "public"."trg_refresh_financials_after_allocation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_refresh_invoice_after_item"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin

    if tg_op = 'DELETE' then

        perform public.refresh_invoice_financials(
            old.invoice_id
        );

        return old;

    else

        perform public.refresh_invoice_financials(
            new.invoice_id
        );

        if tg_op = 'UPDATE'
           and old.invoice_id is distinct from new.invoice_id then

            perform public.refresh_invoice_financials(
                old.invoice_id
            );

        end if;

        return new;

    end if;

end;
$$;


ALTER FUNCTION "public"."trg_refresh_invoice_after_item"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_refresh_student_financial_account"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin

    if tg_op = 'DELETE' then

        perform public.refresh_student_financial_account(
            old.student_id
        );

        return old;

    else

        perform public.refresh_student_financial_account(
            new.student_id
        );

        if tg_op = 'UPDATE'
           and old.student_id is distinct from new.student_id then

            perform public.refresh_student_financial_account(
                old.student_id
            );

        end if;

        return new;

    end if;

end;
$$;


ALTER FUNCTION "public"."trg_refresh_student_financial_account"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_library_loan_status"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF NEW.return_date IS NOT NULL THEN
        NEW.loan_status = 'RETURNED';

    ELSIF NEW.due_date < current_date
          AND NEW.loan_status = 'ACTIVE' THEN
        NEW.loan_status = 'OVERDUE';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_library_loan_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_admission_acceptance"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_offer_status varchar;
    v_expiry_date date;
BEGIN

    SELECT offer_status, expiry_date
    INTO v_offer_status, v_expiry_date
    FROM public.admission_offers
    WHERE id = NEW.admission_offer_id
    FOR UPDATE;


    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Admission offer does not exist';
    END IF;


    -- Only issued offers can be accepted
    IF NEW.acceptance_status = 'ACCEPTED'
       AND v_offer_status <> 'ISSUED' THEN
        RAISE EXCEPTION
            'Only an ISSUED admission offer can be accepted';
    END IF;


    -- Expired offer cannot be accepted
    IF NEW.acceptance_status = 'ACCEPTED'
       AND v_expiry_date < CURRENT_DATE THEN
        RAISE EXCEPTION
            'Admission offer has expired and cannot be accepted';
    END IF;


    -- Automatically record acceptance time
    IF NEW.acceptance_status = 'ACCEPTED'
       AND NEW.accepted_at IS NULL THEN
        NEW.accepted_at := now();
    END IF;


    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_admission_acceptance"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_admission_decision_application"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.application_choice_id IS NOT NULL THEN

        IF NOT EXISTS (
            SELECT 1
            FROM public.application_choices ac
            WHERE ac.id = NEW.application_choice_id
              AND ac.application_id = NEW.application_id
        ) THEN
            RAISE EXCEPTION
                'Admission decision choice does not belong to the specified application';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_admission_decision_application"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_admission_offer"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    -- Offer must reference a valid application choice
    IF NOT EXISTS (
        SELECT 1
        FROM public.application_choices ac
        WHERE ac.id = NEW.application_choice_id
          AND ac.application_id = NEW.application_id
    ) THEN
        RAISE EXCEPTION
            'Admission offer choice does not belong to the specified application';
    END IF;


    -- Offer must reference a valid approved decision
    IF NEW.admission_decision_id IS NOT NULL THEN

        IF NOT EXISTS (
            SELECT 1
            FROM public.admission_decisions ad
            WHERE ad.id = NEW.admission_decision_id
              AND ad.application_id = NEW.application_id
              AND ad.decision_status = 'APPROVED'
        ) THEN
            RAISE EXCEPTION
                'Admission offer must reference an approved decision belonging to the same application';
        END IF;

    END IF;


    -- Issued/accepted offers must have expiry date
    IF NEW.offer_status IN ('ISSUED', 'ACCEPTED')
       AND NEW.expiry_date IS NULL THEN
        RAISE EXCEPTION
            'Issued or accepted admission offers must have an expiry date';
    END IF;


    -- Cannot issue an already expired offer
    IF NEW.offer_status = 'ISSUED'
       AND NEW.expiry_date < CURRENT_DATE THEN
        RAISE EXCEPTION
            'Cannot issue an admission offer that has already expired';
    END IF;


    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_admission_offer"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_alumni_integrity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_status varchar;
BEGIN

    SELECT student_status
    INTO v_status
    FROM public.students
    WHERE id = NEW.student_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Alumni record requires a valid student';
    END IF;

    IF v_status <> 'GRADUATED' THEN
        RAISE EXCEPTION
            'Only GRADUATED students can have alumni records';
    END IF;

    IF NEW.graduation_year < 2000
       OR NEW.graduation_year > EXTRACT(YEAR FROM CURRENT_DATE)::integer + 1 THEN
        RAISE EXCEPTION
            'Invalid graduation year';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_alumni_integrity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_alumni_record"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$

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
$$;


ALTER FUNCTION "public"."validate_alumni_record"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_alumni_record_integrity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_candidate_student_id uuid;
    v_award_candidate_id uuid;
    v_candidate_year integer;
BEGIN

    -- Student must exist
    IF NOT EXISTS (
        SELECT 1
        FROM public.students s
        WHERE s.id = NEW.student_id
    ) THEN
        RAISE EXCEPTION
            'Alumni integrity error: student % does not exist',
            NEW.student_id;
    END IF;


    -- Graduation candidate relationship
    IF NEW.graduation_candidate_id IS NOT NULL THEN

        SELECT
            gc.student_id
        INTO
            v_candidate_student_id
        FROM public.graduation_candidates gc
        WHERE gc.id = NEW.graduation_candidate_id;

        IF v_candidate_student_id IS NULL THEN
            RAISE EXCEPTION
                'Alumni integrity error: graduation candidate % does not exist',
                NEW.graduation_candidate_id;
        END IF;

        IF v_candidate_student_id <> NEW.student_id THEN
            RAISE EXCEPTION
                'Alumni integrity error: student does not match graduation candidate';
        END IF;

    END IF;


    -- Graduation award relationship
    IF NEW.graduation_award_id IS NOT NULL THEN

        SELECT
            ga.graduation_candidate_id
        INTO
            v_award_candidate_id
        FROM public.graduation_awards ga
        WHERE ga.id = NEW.graduation_award_id;

        IF v_award_candidate_id IS NULL THEN
            RAISE EXCEPTION
                'Alumni integrity error: graduation award % does not exist',
                NEW.graduation_award_id;
        END IF;

        IF NEW.graduation_candidate_id IS NOT NULL
           AND v_award_candidate_id <> NEW.graduation_candidate_id THEN

            RAISE EXCEPTION
                'Alumni integrity error: graduation award does not match graduation candidate';

        END IF;

    END IF;


    -- Graduation year cannot be in the future
    IF NEW.graduation_year > EXTRACT(YEAR FROM CURRENT_DATE)::integer THEN
        RAISE EXCEPTION
            'Alumni integrity error: graduation year cannot be in the future';
    END IF;


    RETURN NEW;

END
$$;


ALTER FUNCTION "public"."validate_alumni_record_integrity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_assessment_correction_status"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF OLD.status = 'PENDING' THEN

        IF NEW.status NOT IN ('APPROVED', 'REJECTED', 'CANCELLED') THEN
            RAISE EXCEPTION
                'Pending correction can only become APPROVED, REJECTED or CANCELLED.';
        END IF;

    ELSIF OLD.status IN ('APPROVED', 'REJECTED', 'CANCELLED') THEN

        IF NEW.status <> OLD.status THEN
            RAISE EXCEPTION
                'Finalized correction requests cannot change status.';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_assessment_correction_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_assessment_course_offering"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_status varchar;
BEGIN
    SELECT status
    INTO v_status
    FROM public.course_offerings
    WHERE id = NEW.course_offering_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION
            'Course offering % does not exist',
            NEW.course_offering_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_assessment_course_offering"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_assessment_mark"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_maximum_marks numeric;
    v_course_offering_id uuid;
    v_registered_offering_id uuid;
    v_registered_student_id uuid;
BEGIN

    SELECT
        maximum_marks,
        course_offering_id
    INTO
        v_maximum_marks,
        v_course_offering_id
    FROM public.assessments
    WHERE id = NEW.assessment_id;

    IF v_maximum_marks IS NULL THEN
        RAISE EXCEPTION
            'Assessment % does not exist',
            NEW.assessment_id;
    END IF;

    IF NEW.marks > v_maximum_marks THEN
        RAISE EXCEPTION
            'Marks (%) cannot exceed maximum marks (%)',
            NEW.marks,
            v_maximum_marks;
    END IF;

    IF NEW.course_registration_id IS NOT NULL THEN

        SELECT
            cr.course_offering_id,
            sr.student_id
        INTO
            v_registered_offering_id,
            v_registered_student_id
        FROM public.course_registrations cr
        JOIN public.student_registrations sr
            ON sr.id = cr.student_registration_id
        WHERE cr.id = NEW.course_registration_id;

        IF v_registered_student_id IS NULL THEN
            RAISE EXCEPTION
                'Course registration % is invalid',
                NEW.course_registration_id;
        END IF;

        IF v_registered_student_id <> NEW.student_id THEN
            RAISE EXCEPTION
                'Student does not match course registration';
        END IF;

        IF v_registered_offering_id <> v_course_offering_id THEN
            RAISE EXCEPTION
                'Course registration does not match assessment course';
        END IF;

    END IF;

    NEW.percentage :=
        ROUND(
            (NEW.marks / v_maximum_marks) * 100,
            4
        );

    NEW.entered_at :=
        COALESCE(NEW.entered_at, now());

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_assessment_mark"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_assessment_mark_correction"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_current_marks numeric(8,2);
    v_current_grade varchar(20);
    v_assessment_id uuid;
    v_assessment_status varchar(30);
    v_max_marks numeric(8,2);
BEGIN

    SELECT
        am.marks,
        am.grade,
        am.assessment_id
    INTO
        v_current_marks,
        v_current_grade,
        v_assessment_id
    FROM public.assessment_marks am
    WHERE am.id = NEW.assessment_mark_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Assessment mark for correction does not exist.';
    END IF;

    SELECT
        status,
        maximum_marks
    INTO
        v_assessment_status,
        v_max_marks
    FROM public.assessments
    WHERE id = v_assessment_id;

    IF v_assessment_status NOT IN ('APPROVED', 'LOCKED') THEN
        RAISE EXCEPTION
            'Correction requests are only allowed for approved or locked assessments.';
    END IF;

    IF NEW.old_marks IS DISTINCT FROM v_current_marks THEN
        RAISE EXCEPTION
            'Correction old_marks does not match the current stored mark.';
    END IF;

    IF NEW.old_grade IS DISTINCT FROM v_current_grade THEN
        RAISE EXCEPTION
            'Correction old_grade does not match the current stored grade.';
    END IF;

    IF NEW.new_marks IS NULL THEN
        RAISE EXCEPTION
            'New marks are required.';
    END IF;

    IF NEW.new_marks < 0 OR NEW.new_marks > v_max_marks THEN
        RAISE EXCEPTION
            'Corrected marks must be between 0 and the assessment maximum marks.';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_assessment_mark_correction"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_assessment_mark_registration"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_registration_student uuid;
    v_registration_offering uuid;
    v_assessment_offering uuid;
BEGIN
    SELECT
        sr.student_id,
        cr.course_offering_id
    INTO
        v_registration_student,
        v_registration_offering
    FROM public.course_registrations cr
    INNER JOIN public.student_registrations sr
        ON sr.id = cr.student_registration_id
    WHERE cr.id = NEW.course_registration_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Assessment mark requires a valid course registration.';
    END IF;

    SELECT course_offering_id
    INTO v_assessment_offering
    FROM public.assessments
    WHERE id = NEW.assessment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Assessment does not exist.';
    END IF;

    IF NEW.student_id <> v_registration_student THEN
        RAISE EXCEPTION
            'Assessment mark student does not match course registration student.';
    END IF;

    IF v_registration_offering <> v_assessment_offering THEN
        RAISE EXCEPTION
            'Course registration does not belong to the assessment course offering.';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_assessment_mark_registration"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_assessment_mark_status"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF OLD.status = 'LOCKED'
       AND NEW.status <> 'LOCKED' THEN
        RAISE EXCEPTION
            'Locked assessment mark cannot be reopened';
    END IF;

    IF NEW.status = 'SUBMITTED'
       AND OLD.status <> 'SUBMITTED'
       AND OLD.status <> 'DRAFT' THEN
        RAISE EXCEPTION
            'Assessment mark must be DRAFT before submission';
    END IF;

    IF NEW.status = 'APPROVED'
       AND OLD.status NOT IN ('SUBMITTED', 'APPROVED') THEN
        RAISE EXCEPTION
            'Assessment mark must be SUBMITTED before approval';
    END IF;

    IF NEW.status = 'LOCKED'
       AND OLD.status NOT IN ('APPROVED', 'LOCKED') THEN
        RAISE EXCEPTION
            'Assessment mark must be APPROVED before locking';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_assessment_mark_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_assessment_status_transition"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF OLD.status = 'LOCKED'
       AND NEW.status <> 'LOCKED' THEN
        RAISE EXCEPTION
            'Locked assessment cannot be reopened';
    END IF;

    IF OLD.status = 'CANCELLED'
       AND NEW.status <> 'CANCELLED' THEN
        RAISE EXCEPTION
            'Cancelled assessment cannot be reopened';
    END IF;

    IF NEW.status = 'OPEN'
       AND OLD.status NOT IN ('DRAFT', 'OPEN') THEN
        RAISE EXCEPTION
            'Assessment must be DRAFT before opening';
    END IF;

    IF NEW.status = 'SUBMITTED'
       AND OLD.status NOT IN ('OPEN', 'SUBMITTED') THEN
        RAISE EXCEPTION
            'Assessment must be OPEN before submission';
    END IF;

    IF NEW.status = 'UNDER_REVIEW'
       AND OLD.status NOT IN ('SUBMITTED', 'UNDER_REVIEW') THEN
        RAISE EXCEPTION
            'Assessment must be SUBMITTED before review';
    END IF;

    IF NEW.status = 'APPROVED'
       AND OLD.status NOT IN ('UNDER_REVIEW', 'APPROVED') THEN
        RAISE EXCEPTION
            'Assessment must be UNDER_REVIEW before approval';
    END IF;

    IF NEW.status = 'LOCKED'
       AND OLD.status NOT IN ('APPROVED', 'LOCKED') THEN
        RAISE EXCEPTION
            'Assessment must be APPROVED before locking';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_assessment_status_transition"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_assessment_weight"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_total numeric;
BEGIN

    SELECT COALESCE(SUM(weight_percentage), 0)
    INTO v_total
    FROM public.assessments
    WHERE course_offering_id = NEW.course_offering_id
      AND id <> COALESCE(NEW.id, gen_random_uuid())
      AND status <> 'CANCELLED';

    v_total := v_total + NEW.weight_percentage;

    IF v_total > 100 THEN
        RAISE EXCEPTION
            'Total assessment weight for course offering cannot exceed 100%%. Current total: %',
            v_total;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_assessment_weight"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_attendance_record_status"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF NEW.attendance_status = 'PRESENT'
       AND NEW.check_in_time IS NULL THEN

        NEW.minutes_late := 0;
    END IF;

    IF NEW.attendance_status = 'ABSENT' THEN

        NEW.check_in_time := NULL;
        NEW.minutes_late := 0;
    END IF;

    IF NEW.attendance_status = 'EXCUSED' THEN

        NEW.minutes_late := 0;
    END IF;

    IF NEW.attendance_status = 'LATE'
       AND NEW.minutes_late <= 0 THEN

        RAISE EXCEPTION
            'LATE attendance must have minutes_late greater than zero';
    END IF;

    NEW.marked_at := COALESCE(NEW.marked_at, now());

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_attendance_record_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_attendance_record_student"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_session_class_id uuid;
    v_session_offering_id uuid;
    v_registered_offering_id uuid;
    v_registered_student_id uuid;
BEGIN
    SELECT
        class_id,
        course_offering_id
    INTO
        v_session_class_id,
        v_session_offering_id
    FROM public.attendance_sessions
    WHERE id = NEW.attendance_session_id;

    IF v_session_class_id IS NULL THEN
        RAISE EXCEPTION
            'Attendance session % does not exist',
            NEW.attendance_session_id;
    END IF;

    IF NEW.course_registration_id IS NOT NULL THEN

        SELECT
            cr.course_offering_id,
            sr.student_id
        INTO
            v_registered_offering_id,
            v_registered_student_id
        FROM public.course_registrations cr
        JOIN public.student_registrations sr
            ON sr.id = cr.student_registration_id
        WHERE cr.id = NEW.course_registration_id;

        IF v_registered_student_id IS NULL THEN
            RAISE EXCEPTION
                'Course registration % is invalid',
                NEW.course_registration_id;
        END IF;

        IF v_registered_student_id <> NEW.student_id THEN
            RAISE EXCEPTION
                'Attendance student does not match course registration student';
        END IF;

        IF v_registered_offering_id <> v_session_offering_id THEN
            RAISE EXCEPTION
                'Attendance course registration does not match session course offering';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_attendance_record_student"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_attendance_session_consistency"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_class_offering_id uuid;
BEGIN
    SELECT course_offering_id
    INTO v_class_offering_id
    FROM public.classes
    WHERE id = NEW.class_id;

    IF v_class_offering_id IS NULL THEN
        RAISE EXCEPTION
            'Class % does not exist or has no course offering',
            NEW.class_id;
    END IF;

    IF v_class_offering_id <> NEW.course_offering_id THEN
        RAISE EXCEPTION
            'Attendance session course offering does not match class course offering';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_attendance_session_consistency"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_attendance_status_transition"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF OLD.status = 'LOCKED'
       AND NEW.status <> 'LOCKED' THEN

        RAISE EXCEPTION
            'Locked attendance session cannot be reopened';
    END IF;

    IF OLD.status = 'CANCELLED'
       AND NEW.status <> 'CANCELLED' THEN

        RAISE EXCEPTION
            'Cancelled attendance session cannot be reopened';
    END IF;

    IF NEW.status = 'OPEN'
       AND OLD.status NOT IN ('DRAFT', 'OPEN') THEN

        RAISE EXCEPTION
            'Invalid attendance status transition from % to %',
            OLD.status,
            NEW.status;
    END IF;

    IF NEW.status = 'SUBMITTED'
       AND OLD.status NOT IN ('OPEN', 'SUBMITTED') THEN

        RAISE EXCEPTION
            'Attendance must be OPEN before submission';
    END IF;

    IF NEW.status = 'LOCKED'
       AND OLD.status NOT IN ('SUBMITTED', 'LOCKED') THEN

        RAISE EXCEPTION
            'Attendance must be SUBMITTED before locking';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_attendance_status_transition"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_attendance_timetable_entry"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_class_id uuid;
    v_course_offering_id uuid;
BEGIN
    IF NEW.timetable_entry_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT
        class_id,
        course_offering_id
    INTO
        v_class_id,
        v_course_offering_id
    FROM public.timetable_entries
    WHERE id = NEW.timetable_entry_id;

    IF v_class_id IS NULL THEN
        RAISE EXCEPTION
            'Timetable entry % does not exist',
            NEW.timetable_entry_id;
    END IF;

    IF v_class_id <> NEW.class_id THEN
        RAISE EXCEPTION
            'Timetable entry class does not match attendance session class';
    END IF;

    IF v_course_offering_id <> NEW.course_offering_id THEN
        RAISE EXCEPTION
            'Timetable entry course offering does not match attendance session course offering';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_attendance_timetable_entry"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_certificate"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$

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
$$;


ALTER FUNCTION "public"."validate_certificate"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_certificate_integrity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_candidate_id uuid;
    v_student_id uuid;
    v_candidate_status varchar;
BEGIN

    SELECT
        ga.graduation_candidate_id,
        gc.student_id,
        gc.candidate_status
    INTO
        v_candidate_id,
        v_student_id,
        v_candidate_status
    FROM public.graduation_awards ga
    INNER JOIN public.graduation_candidates gc
        ON gc.id = ga.graduation_candidate_id
    WHERE ga.id = NEW.graduation_award_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Certificate requires a valid graduation award';
    END IF;

    IF NEW.student_id <> v_student_id THEN
        RAISE EXCEPTION
            'Certificate student does not match graduation award student';
    END IF;

    IF NEW.status = 'ISSUED' THEN

        IF v_candidate_status <> 'GRADUATED' THEN
            RAISE EXCEPTION
                'Certificate cannot be ISSUED before candidate is GRADUATED';
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

    IF NEW.status = 'REVOKED' THEN

        IF NEW.revoked_by IS NULL THEN
            RAISE EXCEPTION
                'Revoked certificate requires revoked_by';
        END IF;

        IF NULLIF(trim(COALESCE(NEW.revocation_reason, '')), '') IS NULL THEN
            RAISE EXCEPTION
                'Revoked certificate requires revocation_reason';
        END IF;

        IF NEW.revoked_at IS NULL THEN
            NEW.revoked_at := now();
        END IF;

    END IF;

    IF NEW.status = 'REPLACED'
       AND NEW.replacement_of IS NULL THEN
        RAISE EXCEPTION
            'A REPLACED certificate must reference replacement_of';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_certificate_integrity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_certificate_replacement"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$

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
$$;


ALTER FUNCTION "public"."validate_certificate_replacement"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_certificate_verification_integrity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_code varchar(100);
BEGIN

    SELECT verification_code
    INTO v_code
    FROM public.certificates
    WHERE id = NEW.certificate_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Certificate verification requires a valid certificate';
    END IF;

    IF NEW.verification_code <> v_code THEN
        RAISE EXCEPTION
            'Certificate verification code does not match certificate';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_certificate_verification_integrity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_class_capacity_against_offering"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_offering_capacity integer;
BEGIN
    SELECT capacity
    INTO v_offering_capacity
    FROM public.course_offerings
    WHERE id = NEW.course_offering_id;

    IF v_offering_capacity IS NOT NULL
       AND NEW.capacity > v_offering_capacity THEN
        RAISE EXCEPTION
            'Class capacity (%) cannot exceed course offering capacity (%)',
            NEW.capacity,
            v_offering_capacity;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_class_capacity_against_offering"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_class_course_offering_consistency"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_class_offering_id uuid;
BEGIN
    SELECT course_offering_id
    INTO v_class_offering_id
    FROM public.classes
    WHERE id = NEW.class_id;

    IF v_class_offering_id IS NULL THEN
        RAISE EXCEPTION
            'Class % does not have a valid course offering',
            NEW.class_id;
    END IF;

    IF v_class_offering_id <> NEW.course_offering_id THEN
        RAISE EXCEPTION
            'Timetable entry course offering does not match the class course offering';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_class_course_offering_consistency"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_class_student_capacity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_class_capacity integer;
    v_current_count integer;
BEGIN
    PERFORM pg_advisory_xact_lock(
        hashtextextended(
            'IDMC_CLASS_CAPACITY:' || NEW.class_id::text,
            0
        )
    );

    SELECT capacity
    INTO v_class_capacity
    FROM public.classes
    WHERE id = NEW.class_id;

    SELECT COUNT(*)::integer
    INTO v_current_count
    FROM public.class_students
    WHERE class_id = NEW.class_id
      AND enrollment_status IN ('ACTIVE', 'ENROLLED');

    IF v_class_capacity IS NOT NULL
       AND v_current_count >= v_class_capacity THEN
        RAISE EXCEPTION
            'Class % has reached its capacity of % students',
            NEW.class_id,
            v_class_capacity;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_class_student_capacity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_class_student_registration"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_class_offering_id uuid;
    v_registration_offering_id uuid;
    v_registration_student_id uuid;
BEGIN
    SELECT course_offering_id
    INTO v_class_offering_id
    FROM public.classes
    WHERE id = NEW.class_id;

    SELECT
        cr.course_offering_id,
        sr.student_id
    INTO
        v_registration_offering_id,
        v_registration_student_id
    FROM public.course_registrations cr
    JOIN public.student_registrations sr
        ON sr.id = cr.student_registration_id
    WHERE cr.id = NEW.course_registration_id;

    IF v_class_offering_id IS NULL THEN
        RAISE EXCEPTION
            'Class % does not have a valid course offering',
            NEW.class_id;
    END IF;

    IF v_registration_offering_id IS NULL THEN
        RAISE EXCEPTION
            'Course registration % is invalid',
            NEW.course_registration_id;
    END IF;

    IF v_registration_offering_id <> v_class_offering_id THEN
        RAISE EXCEPTION
            'Student course registration does not match class course offering';
    END IF;

    IF v_registration_student_id <> NEW.student_id THEN
        RAISE EXCEPTION
            'Student does not match the student in course registration';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_class_student_registration"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_course_registration"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
    v_student_id uuid;
    v_programme_id uuid;
    v_registration_status varchar(40);
    v_course_status varchar(30);
    v_offering_status varchar(30);
BEGIN

    SELECT
        sr.student_id,
        sr.programme_id,
        sr.registration_status
    INTO
        v_student_id,
        v_programme_id,
        v_registration_status
    FROM public.student_registrations sr
    WHERE sr.id = NEW.student_registration_id;

    IF v_student_id IS NULL THEN
        RAISE EXCEPTION
            'Student registration does not exist';
    END IF;

    IF NEW.student_id <> v_student_id THEN
        RAISE EXCEPTION
            'Course registration student does not match student registration';
    END IF;

    IF v_registration_status IN (
        'LOCKED',
        'CANCELLED'
    )
    THEN
        RAISE EXCEPTION
            'Cannot add course to locked or cancelled registration';
    END IF;

    SELECT status
    INTO v_course_status
    FROM public.courses
    WHERE id = NEW.course_id;

    IF v_course_status IS NULL THEN
        RAISE EXCEPTION
            'Course does not exist';
    END IF;

    IF v_course_status <> 'ACTIVE' THEN
        RAISE EXCEPTION
            'Only ACTIVE courses can be registered';
    END IF;

    IF NEW.course_offering_id IS NOT NULL THEN

        SELECT status
        INTO v_offering_status
        FROM public.course_offerings
        WHERE id = NEW.course_offering_id
          AND course_id = NEW.course_id;

        IF v_offering_status IS NULL THEN
            RAISE EXCEPTION
                'Course offering does not match course';
        END IF;

        IF v_offering_status NOT IN ('OPEN', 'CLOSED') THEN
            RAISE EXCEPTION
                'Invalid course offering status for registration';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_course_registration"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_course_result_approval"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."validate_course_result_approval"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_course_result_context"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."validate_course_result_context"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_course_result_correction"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."validate_course_result_correction"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_course_result_lock"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."validate_course_result_lock"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_course_result_publication"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."validate_course_result_publication"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_course_result_status_transition"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."validate_course_result_status_transition"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_course_result_submission"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."validate_course_result_submission"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_examination_attendance"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_session_paper uuid;
    v_candidate_paper uuid;
BEGIN

    SELECT examination_paper_id
    INTO v_session_paper
    FROM public.examination_sessions
    WHERE id = NEW.examination_session_id;

    SELECT examination_paper_id
    INTO v_candidate_paper
    FROM public.examination_candidates
    WHERE id = NEW.examination_candidate_id;

    IF v_session_paper IS NULL
       OR v_candidate_paper IS NULL THEN
        RAISE EXCEPTION
            'Invalid examination attendance session or candidate';
    END IF;

    IF v_session_paper <> v_candidate_paper THEN
        RAISE EXCEPTION
            'Examination attendance candidate does not belong to this session paper';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.examination_candidate_sessions ecs
        WHERE ecs.examination_session_id = NEW.examination_session_id
          AND ecs.examination_candidate_id = NEW.examination_candidate_id
          AND ecs.assignment_status IN
              ('ASSIGNED','CONFIRMED','MOVED')
    ) THEN
        RAISE EXCEPTION
            'Candidate must be assigned to the examination session before attendance can be recorded';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_examination_attendance"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_examination_candidate"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_registration_student uuid;
    v_registration_offering uuid;
    v_paper_offering uuid;
    v_period_id uuid;
    v_candidate_count integer;
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
            'Invalid examination candidate: course registration does not exist';
    END IF;

    IF v_registration_student <> NEW.student_id THEN
        RAISE EXCEPTION
            'Examination candidate student does not match course registration student';
    END IF;

    SELECT
        ep.id,
        ep.course_offering_id
    INTO
        v_period_id,
        v_paper_offering
    FROM public.examination_papers ep
    WHERE ep.id = NEW.examination_paper_id;

    IF v_period_id IS NULL THEN
        RAISE EXCEPTION
            'Invalid examination candidate: examination paper does not exist';
    END IF;

    IF v_registration_offering <> v_paper_offering THEN
        RAISE EXCEPTION
            'Examination candidate course registration does not match examination paper course offering';
    END IF;

    SELECT COUNT(*)
    INTO v_candidate_count
    FROM public.examination_candidates ec
    WHERE ec.examination_paper_id = NEW.examination_paper_id
      AND ec.student_id = NEW.student_id
      AND ec.id <> COALESCE(NEW.id, gen_random_uuid());

    IF v_candidate_count > 0 THEN
        RAISE EXCEPTION
            'Student is already registered as a candidate for this examination paper';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_examination_candidate"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_examination_candidate_number"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_period_id uuid;
    v_existing integer;
BEGIN

    IF NEW.candidate_number IS NULL
       OR trim(NEW.candidate_number) = '' THEN
        RETURN NEW;
    END IF;

    SELECT examination_period_id
    INTO v_period_id
    FROM public.examination_papers
    WHERE id = NEW.examination_paper_id;

    SELECT COUNT(*)
    INTO v_existing
    FROM public.examination_candidates ec
    JOIN public.examination_papers ep
        ON ep.id = ec.examination_paper_id
    WHERE ep.examination_period_id = v_period_id
      AND ec.candidate_number = NEW.candidate_number
      AND ec.id <> COALESCE(NEW.id, gen_random_uuid());

    IF v_existing > 0 THEN
        RAISE EXCEPTION
            'Candidate number % is already in use within this examination period',
            NEW.candidate_number;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_examination_candidate_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_examination_candidate_registration"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_registration_status varchar;
BEGIN

    SELECT status
    INTO v_registration_status
    FROM public.course_registrations
    WHERE id = NEW.course_registration_id;

    IF v_registration_status IS NULL THEN
        RAISE EXCEPTION
            'Course registration does not exist';
    END IF;

    IF v_registration_status NOT IN
        ('APPROVED', 'REGISTERED', 'LOCKED') THEN

        RAISE EXCEPTION
            'Student course registration is not valid for examination eligibility. Current status: %',
            v_registration_status;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_examination_candidate_registration"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_examination_candidate_session"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_candidate_paper uuid;
    v_session_paper uuid;
    v_session_capacity integer;
    v_assigned_count integer;
BEGIN

    SELECT examination_paper_id
    INTO v_candidate_paper
    FROM public.examination_candidates
    WHERE id = NEW.examination_candidate_id;

    SELECT examination_paper_id, capacity
    INTO v_session_paper, v_session_capacity
    FROM public.examination_sessions
    WHERE id = NEW.examination_session_id;

    IF v_candidate_paper IS NULL THEN
        RAISE EXCEPTION
            'Examination candidate does not exist';
    END IF;

    IF v_session_paper IS NULL THEN
        RAISE EXCEPTION
            'Examination session does not exist';
    END IF;

    IF v_candidate_paper <> v_session_paper THEN
        RAISE EXCEPTION
            'Candidate and examination session belong to different examination papers';
    END IF;

    IF NEW.assignment_status IN ('ASSIGNED','CONFIRMED','MOVED') THEN

        PERFORM pg_advisory_xact_lock(
            hashtextextended(NEW.examination_session_id::text, 0)
        );

        SELECT COUNT(*)
        INTO v_assigned_count
        FROM public.examination_candidate_sessions ecs
        WHERE ecs.examination_session_id = NEW.examination_session_id
          AND ecs.assignment_status IN
              ('ASSIGNED','CONFIRMED','MOVED')
          AND ecs.id <> COALESCE(NEW.id, gen_random_uuid());

        IF v_assigned_count >= v_session_capacity THEN
            RAISE EXCEPTION
                'Examination session has reached its candidate capacity';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_examination_candidate_session"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_examination_invigilator_conflict"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_start timestamptz;
    v_end timestamptz;
    v_conflict integer;
BEGIN

    SELECT start_at, end_at
    INTO v_start, v_end
    FROM public.examination_sessions
    WHERE id = NEW.examination_session_id;

    IF v_start IS NULL OR v_end IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT COUNT(*)
    INTO v_conflict
    FROM public.examination_invigilators ei
    JOIN public.examination_sessions es
        ON es.id = ei.examination_session_id
    WHERE ei.user_id = NEW.user_id
      AND ei.status IN ('ASSIGNED','CONFIRMED')
      AND es.status NOT IN ('CANCELLED','COMPLETED','LOCKED')
      AND es.start_at < v_end
      AND es.end_at > v_start
      AND ei.id <> COALESCE(NEW.id, gen_random_uuid());

    IF v_conflict > 0 THEN
        RAISE EXCEPTION
            'Invigilator is already assigned to another overlapping examination session';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_examination_invigilator_conflict"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_examination_mark"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_candidate_student uuid;
    v_candidate_registration uuid;
    v_candidate_paper uuid;
    v_maximum_marks numeric(8,2);
BEGIN

    SELECT
        student_id,
        course_registration_id,
        examination_paper_id
    INTO
        v_candidate_student,
        v_candidate_registration,
        v_candidate_paper
    FROM public.examination_candidates
    WHERE id = NEW.examination_candidate_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Examination candidate does not exist.';
    END IF;

    SELECT maximum_marks
    INTO v_maximum_marks
    FROM public.examination_papers
    WHERE id = NEW.examination_paper_id;

    IF NEW.student_id <> v_candidate_student THEN
        RAISE EXCEPTION
            'Examination mark student does not match candidate.';
    END IF;

    IF NEW.course_registration_id <> v_candidate_registration THEN
        RAISE EXCEPTION
            'Examination mark registration does not match candidate registration.';
    END IF;

    IF NEW.examination_paper_id <> v_candidate_paper THEN
        RAISE EXCEPTION
            'Examination mark paper does not match candidate paper.';
    END IF;

    IF NEW.marks IS NOT NULL THEN

        IF NEW.marks > v_maximum_marks THEN
            RAISE EXCEPTION
                'Examination marks cannot exceed maximum marks.';
        END IF;

        NEW.percentage :=
            ROUND(
                (NEW.marks / v_maximum_marks) * 100,
                4
            );

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_examination_mark"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_examination_mark_correction"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_current_marks numeric(8,2);
    v_max_marks numeric(8,2);
    v_mark_status varchar;
BEGIN

    SELECT
        em.marks,
        ep.max_marks,
        em.status
    INTO
        v_current_marks,
        v_max_marks,
        v_mark_status
    FROM public.examination_marks em
    JOIN public.examination_papers ep
        ON ep.id = em.examination_paper_id
    WHERE em.id = NEW.examination_mark_id;

    IF v_current_marks IS NULL THEN
        RAISE EXCEPTION
            'Examination mark does not exist';
    END IF;

    IF v_mark_status NOT IN
        ('APPROVED','LOCKED','CORRECTION_PENDING') THEN

        RAISE EXCEPTION
            'Examination mark is not eligible for correction workflow';
    END IF;

    IF NEW.old_marks <> v_current_marks THEN
        RAISE EXCEPTION
            'Correction old_marks does not match the current examination mark';
    END IF;

    IF NEW.new_marks < 0
       OR NEW.new_marks > v_max_marks THEN
        RAISE EXCEPTION
            'New examination marks must be between 0 and the paper maximum marks';
    END IF;

    IF trim(COALESCE(NEW.reason,'')) = '' THEN
        RAISE EXCEPTION
            'Correction reason is required';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_examination_mark_correction"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_examination_paper_context"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_period_year uuid;
    v_period_semester uuid;
    v_offering_year uuid;
    v_offering_semester uuid;
BEGIN

    SELECT academic_year_id, semester_id
    INTO v_period_year, v_period_semester
    FROM public.examination_periods
    WHERE id = NEW.examination_period_id;

    IF v_period_year IS NULL OR v_period_semester IS NULL THEN
        RAISE EXCEPTION
            'Examination period is invalid or missing academic context';
    END IF;

    SELECT academic_year_id, semester_id
    INTO v_offering_year, v_offering_semester
    FROM public.course_offerings
    WHERE id = NEW.course_offering_id;

    IF v_offering_year IS NULL OR v_offering_semester IS NULL THEN
        RAISE EXCEPTION
            'Course offering is invalid or missing academic context';
    END IF;

    IF v_period_year <> v_offering_year
       OR v_period_semester <> v_offering_semester THEN
        RAISE EXCEPTION
            'Examination paper course offering does not belong to the examination period academic year and semester';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_examination_paper_context"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_examination_room_conflict"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF EXISTS (
        SELECT 1
        FROM public.examination_sessions es
        WHERE es.room_id = NEW.room_id
          AND es.examination_date = NEW.examination_date
          AND es.id <> NEW.id
          AND es.status <> 'CANCELLED'
          AND NEW.start_time < es.end_time
          AND NEW.end_time > es.start_time
    ) THEN

        RAISE EXCEPTION
            'Examination room conflict detected for the selected date and time.';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_examination_room_conflict"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_examination_session"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_paper_period uuid;
    v_period_start date;
    v_period_end date;
    v_room_campus uuid;
    v_room_capacity integer;
BEGIN

    SELECT
        ep.id,
        ep.start_date,
        ep.end_date
    INTO
        v_paper_period,
        v_period_start,
        v_period_end
    FROM public.examination_papers epaper
    JOIN public.examination_periods ep
        ON ep.id = epaper.examination_period_id
    WHERE epaper.id = NEW.examination_paper_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Examination paper or examination period does not exist.';
    END IF;

    IF NEW.examination_date < v_period_start
       OR NEW.examination_date > v_period_end THEN
        RAISE EXCEPTION
            'Examination session date must fall within the examination period.';
    END IF;

    SELECT campus_id, capacity
    INTO v_room_campus, v_room_capacity
    FROM public.rooms
    WHERE id = NEW.room_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Examination room does not exist.';
    END IF;

    IF v_room_campus <> NEW.campus_id THEN
        RAISE EXCEPTION
            'Examination room does not belong to the selected campus.';
    END IF;

    IF NEW.capacity > v_room_capacity THEN
        RAISE EXCEPTION
            'Examination session capacity cannot exceed room capacity.';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_examination_session"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_examination_session_capacity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_room_capacity integer;
BEGIN

    SELECT capacity
    INTO v_room_capacity
    FROM public.rooms
    WHERE id = NEW.room_id;

    IF v_room_capacity IS NULL THEN
        RAISE EXCEPTION
            'Examination session room does not exist';
    END IF;

    IF NEW.capacity IS NULL
       OR NEW.capacity <= 0 THEN
        RAISE EXCEPTION
            'Examination session capacity must be greater than zero';
    END IF;

    IF NEW.capacity > v_room_capacity THEN
        RAISE EXCEPTION
            'Examination session capacity (%) cannot exceed room capacity (%)',
            NEW.capacity,
            v_room_capacity;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_examination_session_capacity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_financial_transaction"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF NEW.transaction_type = 'PAYMENT'
       AND NEW.credit_amount <= 0 THEN
        RAISE EXCEPTION
            'Payment financial transaction must have a credit amount';
    END IF;

    IF NEW.transaction_type = 'CHARGE'
       AND NEW.debit_amount <= 0 THEN
        RAISE EXCEPTION
            'Charge financial transaction must have a debit amount';
    END IF;

    IF NEW.transaction_type = 'REFUND'
       AND NEW.debit_amount <= 0 THEN
        RAISE EXCEPTION
            'Refund financial transaction must have a debit amount';
    END IF;

    IF NEW.status = 'REVERSED'
       AND NEW.reversal_of IS NULL THEN
        RAISE EXCEPTION
            'A reversed transaction must reference the original transaction';
    END IF;

    IF NEW.reversal_of = NEW.id THEN
        RAISE EXCEPTION
            'A transaction cannot reverse itself';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_financial_transaction"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_financial_transaction_row"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF NULLIF(trim(NEW.transaction_number), '') IS NULL THEN
        RAISE EXCEPTION 'Transaction number is required';
    END IF;

    IF NEW.debit_amount < 0 THEN
        RAISE EXCEPTION 'Debit amount cannot be negative';
    END IF;

    IF NEW.credit_amount < 0 THEN
        RAISE EXCEPTION 'Credit amount cannot be negative';
    END IF;

    IF NEW.debit_amount = 0
       AND NEW.credit_amount = 0 THEN
        RAISE EXCEPTION
            'Either debit or credit must be greater than zero';
    END IF;

    IF NEW.debit_amount > 0
       AND NEW.credit_amount > 0 THEN
        RAISE EXCEPTION
            'Debit and credit cannot both be greater than zero';
    END IF;

    IF NEW.transaction_date IS NULL THEN
        NEW.transaction_date := now();
    END IF;

    IF NEW.status IS NULL
       OR NULLIF(trim(NEW.status), '') IS NULL THEN
        NEW.status := 'POSTED';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_financial_transaction_row"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_gpa_record"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."validate_gpa_record"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_graduation_academic_integrity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF NEW.eligibility_status = 'ELIGIBLE'
       AND NEW.academic_completion_status <> 'COMPLETE' THEN
        RAISE EXCEPTION
            'A graduation candidate can only be ELIGIBLE when academic completion is COMPLETE';
    END IF;

    IF NEW.candidate_status IN ('APPROVED', 'GRADUATED')
       AND NEW.eligibility_status <> 'ELIGIBLE' THEN
        RAISE EXCEPTION
            'A graduation candidate cannot be APPROVED or GRADUATED unless ELIGIBLE';
    END IF;

    IF NEW.final_cgpa IS NOT NULL
       AND (NEW.final_cgpa < 0 OR NEW.final_cgpa > 5) THEN
        RAISE EXCEPTION
            'final_cgpa must be between 0 and 5';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_graduation_academic_integrity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_graduation_approval"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$

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
$$;


ALTER FUNCTION "public"."validate_graduation_approval"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_graduation_approval_completeness"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_total integer;
    v_approved integer;
BEGIN

    IF NEW.candidate_status IN ('APPROVED', 'GRADUATED') THEN

        SELECT COUNT(*)
        INTO v_total
        FROM public.graduation_approvals
        WHERE graduation_candidate_id = NEW.id;

        SELECT COUNT(*)
        INTO v_approved
        FROM public.graduation_approvals
        WHERE graduation_candidate_id = NEW.id
          AND decision = 'APPROVED';

        IF v_total < 5 OR v_approved < 5 THEN
            RAISE EXCEPTION
                'Graduation candidate cannot become % until all required approval stages are APPROVED',
                NEW.candidate_status;
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_graduation_approval_completeness"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_graduation_approval_integrity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF NEW.decision = 'APPROVED'
       AND NEW.approved_by IS NULL THEN
        RAISE EXCEPTION
            'An APPROVED graduation approval requires approved_by';
    END IF;

    IF NEW.decision = 'REJECTED'
       AND NEW.approved_by IS NULL THEN
        RAISE EXCEPTION
            'A REJECTED graduation approval requires an approving actor';
    END IF;

    IF NEW.decision = 'APPROVED'
       AND NEW.approved_at IS NULL THEN
        NEW.approved_at := now();
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_graduation_approval_integrity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_graduation_award"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$

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
$$;


ALTER FUNCTION "public"."validate_graduation_award"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_graduation_award_integrity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_status varchar;
    v_cgpa numeric;
BEGIN

    SELECT
        candidate_status,
        final_cgpa
    INTO
        v_status,
        v_cgpa
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
            'Graduation award requires final_cgpa';
    END IF;

    IF NEW.final_cgpa < 0 OR NEW.final_cgpa > 5 THEN
        RAISE EXCEPTION
            'Graduation award final_cgpa must be between 0 and 5';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_graduation_award_integrity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_graduation_candidate"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$

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
$$;


ALTER FUNCTION "public"."validate_graduation_candidate"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_graduation_candidate_clearance_completeness"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_total integer;
    v_complete integer;
BEGIN

    IF NEW.candidate_status IN ('CLEARED', 'APPROVED', 'GRADUATED') THEN

        SELECT COUNT(*)
        INTO v_total
        FROM public.graduation_clearances
        WHERE graduation_candidate_id = NEW.id;

        SELECT COUNT(*)
        INTO v_complete
        FROM public.graduation_clearances
        WHERE graduation_candidate_id = NEW.id
          AND status IN ('CLEARED', 'WAIVED');

        IF v_total < 7 OR v_complete < 7 THEN
            RAISE EXCEPTION
                'Graduation candidate cannot become % until all required clearances are CLEARED or WAIVED',
                NEW.candidate_status;
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_graduation_candidate_clearance_completeness"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_graduation_candidate_transition"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
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
$$;


ALTER FUNCTION "public"."validate_graduation_candidate_transition"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_graduation_clearance"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
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
$$;


ALTER FUNCTION "public"."validate_graduation_clearance"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_graduation_clearance_integrity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    -- CLEARED must have an actor
    IF NEW.status = 'CLEARED'
       AND NEW.cleared_by IS NULL THEN
        RAISE EXCEPTION
            'A CLEARED graduation clearance requires cleared_by';
    END IF;

    -- WAIVED must have a reason
    IF NEW.status = 'WAIVED'
       AND NULLIF(trim(COALESCE(NEW.remarks, '')), '') IS NULL THEN
        RAISE EXCEPTION
            'A WAIVED graduation clearance requires remarks';
    END IF;

    -- Finance clearance cannot be cleared below amount due
    IF NEW.clearance_type = 'FINANCE'
       AND NEW.status = 'CLEARED'
       AND COALESCE(NEW.amount_cleared, 0)
           < COALESCE(NEW.amount_due, 0) THEN
        RAISE EXCEPTION
            'Finance clearance cannot be CLEARED until the required amount is cleared';
    END IF;

    IF NEW.status = 'CLEARED'
       AND NEW.cleared_at IS NULL THEN
        NEW.cleared_at := now();
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_graduation_clearance_integrity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_lecturer_assignment_consistency"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_assignment_offering_id uuid;
    v_assignment_class_id uuid;
BEGIN
    IF NEW.lecturer_assignment_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT
        course_offering_id,
        class_id
    INTO
        v_assignment_offering_id,
        v_assignment_class_id
    FROM public.lecturer_assignments
    WHERE id = NEW.lecturer_assignment_id;

    IF v_assignment_offering_id IS NULL THEN
        RAISE EXCEPTION
            'Lecturer assignment % does not exist',
            NEW.lecturer_assignment_id;
    END IF;

    IF v_assignment_offering_id <> NEW.course_offering_id THEN
        RAISE EXCEPTION
            'Lecturer assignment course offering does not match timetable entry course offering';
    END IF;

    IF v_assignment_class_id IS NOT NULL
       AND v_assignment_class_id <> NEW.class_id THEN
        RAISE EXCEPTION
            'Lecturer assignment class does not match timetable entry class';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_lecturer_assignment_consistency"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_notification_delivery"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.status = 'DELIVERED'
       AND NEW.delivered_at IS NULL THEN
        NEW.delivered_at = now();
    END IF;

    IF NEW.status = 'FAILED'
       AND NEW.failed_at IS NULL THEN
        NEW.failed_at = now();
    END IF;

    IF NEW.status IN ('SENT', 'DELIVERED')
       AND NEW.attempt_count = 0 THEN
        NEW.attempt_count = 1;
    END IF;

    RETURN NEW;
END
$$;


ALTER FUNCTION "public"."validate_notification_delivery"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_notification_number"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF length(trim(NEW.notification_number)) = 0 THEN
        RAISE EXCEPTION 'Notification number cannot be empty';
    END IF;

    RETURN NEW;
END
$$;


ALTER FUNCTION "public"."validate_notification_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_notification_queue"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.status = 'COMPLETED'
       AND NEW.completed_at IS NULL THEN
        NEW.completed_at = now();
    END IF;

    IF NEW.attempt_count > NEW.max_attempts THEN
        RAISE EXCEPTION
            'Notification queue attempt count cannot exceed max attempts';
    END IF;

    IF NEW.status = 'FAILED'
       AND NEW.last_error IS NULL THEN
        NEW.last_error = 'Notification delivery failed';
    END IF;

    RETURN NEW;
END
$$;


ALTER FUNCTION "public"."validate_notification_queue"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_payment_allocation_integrity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_payment_student uuid;
    v_invoice_student uuid;
    v_charge_student uuid;
    v_allocated numeric(18,2);
    v_payment_amount numeric(18,2);
BEGIN

    SELECT student_id, amount
    INTO v_payment_student, v_payment_amount
    FROM public.payments
    WHERE id = NEW.payment_id;

    IF v_payment_student IS NULL THEN
        RAISE EXCEPTION
            'Payment % does not exist',
            NEW.payment_id;
    END IF;

    IF NEW.invoice_id IS NOT NULL THEN

        SELECT student_id
        INTO v_invoice_student
        FROM public.invoices
        WHERE id = NEW.invoice_id;

        IF v_invoice_student IS NULL THEN
            RAISE EXCEPTION
                'Invoice % does not exist',
                NEW.invoice_id;
        END IF;

        IF v_invoice_student <> v_payment_student THEN
            RAISE EXCEPTION
                'Payment and invoice belong to different students';
        END IF;

    END IF;

    IF NEW.student_charge_id IS NOT NULL THEN

        SELECT student_id
        INTO v_charge_student
        FROM public.student_charges
        WHERE id = NEW.student_charge_id;

        IF v_charge_student IS NULL THEN
            RAISE EXCEPTION
                'Student charge % does not exist',
                NEW.student_charge_id;
        END IF;

        IF v_charge_student <> v_payment_student THEN
            RAISE EXCEPTION
                'Payment and student charge belong to different students';
        END IF;

    END IF;

    SELECT COALESCE(SUM(allocated_amount), 0)
    INTO v_allocated
    FROM public.payment_allocations
    WHERE payment_id = NEW.payment_id
      AND status = 'ACTIVE'
      AND id <> COALESCE(NEW.id, gen_random_uuid());

    IF v_allocated + NEW.allocated_amount > v_payment_amount THEN
        RAISE EXCEPTION
            'Payment allocation exceeds payment amount';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_payment_allocation_integrity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_payment_integrity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.status = 'CONFIRMED'
       AND NEW.confirmed_at IS NULL THEN
        NEW.confirmed_at = now();
    END IF;

    IF NEW.status = 'CONFIRMED'
       AND NEW.receipt_number IS NULL THEN
        NEW.receipt_number :=
            'IDMC-RCP-' ||
            to_char(CURRENT_DATE, 'YYYYMMDD') ||
            '-' ||
            upper(substr(replace(NEW.id::text, '-', ''), 1, 10));
    END IF;

    IF NEW.status = 'REVERSED'
       AND OLD.status = 'REVERSED' THEN
        RAISE EXCEPTION
            'Payment % is already reversed',
            NEW.payment_number;
    END IF;

    IF OLD.status = 'CONFIRMED'
       AND NEW.amount <> OLD.amount THEN
        RAISE EXCEPTION
            'Confirmed payment amount cannot be changed';
    END IF;

    IF OLD.status = 'CONFIRMED'
       AND NEW.student_id <> OLD.student_id THEN
        RAISE EXCEPTION
            'Confirmed payment student cannot be changed';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_payment_integrity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_refund_integrity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_payment_amount numeric(18,2);
    v_refunded numeric(18,2);
BEGIN

    SELECT amount
    INTO v_payment_amount
    FROM public.payments
    WHERE id = NEW.payment_id;

    IF v_payment_amount IS NULL THEN
        RAISE EXCEPTION
            'Refund payment does not exist';
    END IF;

    SELECT COALESCE(SUM(amount), 0)
    INTO v_refunded
    FROM public.refunds
    WHERE payment_id = NEW.payment_id
      AND status IN ('APPROVED', 'PROCESSING', 'PAID')
      AND id <> COALESCE(NEW.id, gen_random_uuid());

    IF v_refunded + NEW.amount > v_payment_amount THEN
        RAISE EXCEPTION
            'Total refunds cannot exceed payment amount';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_refund_integrity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_registration_credit_limit"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
    v_total numeric(8,2);
    v_maximum numeric(8,2);
BEGIN

    SELECT maximum_credits
    INTO v_maximum
    FROM public.student_registrations
    WHERE id = NEW.student_registration_id;

    SELECT COALESCE(
        SUM(credits),
        0
    )
    INTO v_total
    FROM public.course_registrations
    WHERE student_registration_id = NEW.student_registration_id
      AND registration_status NOT IN (
          'DROPPED',
          'REJECTED',
          'CANCELLED'
      )
      AND id <> NEW.id;

    v_total := v_total + NEW.credits;

    IF v_total > v_maximum THEN
        RAISE EXCEPTION
            'Credit limit exceeded. Maximum allowed: %, attempted total: %',
            v_maximum,
            v_total;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_registration_credit_limit"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_registration_status_transition"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN

    IF TG_OP = 'UPDATE'
       AND OLD.registration_status <> NEW.registration_status
    THEN

        IF OLD.registration_status = 'LOCKED' THEN
            RAISE EXCEPTION
                'Locked registration cannot change status';
        END IF;

        IF OLD.registration_status = 'CANCELLED'
           AND NEW.registration_status <> 'CANCELLED'
        THEN
            RAISE EXCEPTION
                'Cancelled registration cannot be reopened';
        END IF;

        IF OLD.registration_status = 'REGISTERED'
           AND NEW.registration_status NOT IN (
               'LOCKED',
               'CANCELLED'
           )
        THEN
            RAISE EXCEPTION
                'Registered registration can only be locked or cancelled';
        END IF;

        IF OLD.registration_status = 'APPROVED'
           AND NEW.registration_status NOT IN (
               'REGISTERED',
               'CANCELLED'
           )
        THEN
            RAISE EXCEPTION
                'Approved registration must proceed to REGISTERED or CANCELLED';
        END IF;

    END IF;

    IF NEW.registration_status IN (
        'SUBMITTED',
        'PENDING_APPROVAL'
    )
    AND NEW.submitted_at IS NULL
    THEN
        NEW.submitted_at := now();
    END IF;

    IF NEW.registration_status = 'APPROVED'
       AND OLD.registration_status IS DISTINCT FROM 'APPROVED'
    THEN
        NEW.approved_at := COALESCE(NEW.approved_at, now());
    END IF;

    IF NEW.registration_status = 'LOCKED'
       AND OLD.registration_status IS DISTINCT FROM 'LOCKED'
    THEN
        NEW.locked_at := COALESCE(NEW.locked_at, now());
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_registration_status_transition"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_semester_result_status_transition"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."validate_semester_result_status_transition"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_staff_leave_request"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF NEW.end_date < NEW.start_date THEN
        RAISE EXCEPTION
            'Leave end date cannot be before start date';
    END IF;


    IF NEW.days_requested <= 0 THEN
        RAISE EXCEPTION
            'Leave days requested must be greater than zero';
    END IF;


    IF NEW.request_status IN (
        'PENDING',
        'APPROVED',
        'PARTIALLY_APPROVED'
    ) THEN

        IF EXISTS (
            SELECT 1
            FROM public.staff_leave_requests existing
            WHERE existing.staff_id = NEW.staff_id
              AND existing.id <> NEW.id
              AND existing.request_status IN (
                  'PENDING',
                  'APPROVED',
                  'PARTIALLY_APPROVED'
              )
              AND NEW.start_date <= existing.end_date
              AND NEW.end_date >= existing.start_date
        ) THEN

            RAISE EXCEPTION
                'Staff member already has an overlapping leave request';

        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_staff_leave_request"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_student_registration"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
    v_student_status varchar(40);
    v_student_programme uuid;
BEGIN

    SELECT
        student_status,
        programme_id
    INTO
        v_student_status,
        v_student_programme
    FROM public.students
    WHERE id = NEW.student_id;

    IF v_student_status IS NULL THEN
        RAISE EXCEPTION
            'Student does not exist';
    END IF;

    IF v_student_status NOT IN (
        'ACTIVE',
        'PENDING_ACTIVATION',
        'DEFERRED'
    )
    THEN
        RAISE EXCEPTION
            'Student status % is not eligible for registration',
            v_student_status;
    END IF;

    IF v_student_programme IS NOT NULL
       AND NEW.programme_id <> v_student_programme
    THEN
        RAISE EXCEPTION
            'Registration programme does not match student programme';
    END IF;

    IF NEW.maximum_credits <= 0 THEN
        RAISE EXCEPTION
            'Maximum credits must be greater than zero';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_student_registration"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_student_status_transition"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN

    -- New students must start from PENDING_ACTIVATION
    IF TG_OP = 'INSERT'
       AND NEW.student_status <> 'PENDING_ACTIVATION' THEN

        RAISE EXCEPTION
            'A newly created student must start with PENDING_ACTIVATION';
    END IF;


    -- No status change
    IF TG_OP = 'UPDATE'
       AND OLD.student_status = NEW.student_status THEN

        RETURN NEW;
    END IF;


    -- Graduated students cannot become active again
    IF OLD.student_status = 'GRADUATED'
       AND NEW.student_status <> 'GRADUATED' THEN

        RAISE EXCEPTION
            'A GRADUATED student cannot return to another lifecycle state';
    END IF;


    -- Completed students cannot return to active
    IF OLD.student_status = 'COMPLETED'
       AND NEW.student_status IN (
           'ACTIVE',
           'PENDING_ACTIVATION',
           'DEFERRED'
       ) THEN

        RAISE EXCEPTION
            'A COMPLETED student cannot return to an active lifecycle state';
    END IF;


    -- Expelled students cannot return
    IF OLD.student_status = 'EXPELLED'
       AND NEW.student_status <> 'EXPELLED' THEN

        RAISE EXCEPTION
            'An EXPELLED student cannot return to another lifecycle state';
    END IF;


    -- Deceased students cannot return
    IF OLD.student_status = 'DECEASED'
       AND NEW.student_status <> 'DECEASED' THEN

        RAISE EXCEPTION
            'A DECEASED student cannot return to another lifecycle state';
    END IF;


    -- Set lifecycle timestamps
    IF NEW.student_status = 'ACTIVE'
       AND OLD.student_status <> 'ACTIVE'
       AND NEW.activated_at IS NULL THEN

        NEW.activated_at := now();
    END IF;


    IF NEW.student_status = 'SUSPENDED'
       AND OLD.student_status <> 'SUSPENDED'
       AND NEW.suspended_at IS NULL THEN

        NEW.suspended_at := now();
    END IF;


    IF NEW.student_status = 'WITHDRAWN'
       AND OLD.student_status <> 'WITHDRAWN'
       AND NEW.withdrawn_at IS NULL THEN

        NEW.withdrawn_at := now();
    END IF;


    IF NEW.student_status = 'GRADUATED'
       AND OLD.student_status <> 'GRADUATED'
       AND NEW.graduated_at IS NULL THEN

        NEW.graduated_at := now();
    END IF;


    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_student_status_transition"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_timetable_class_conflict"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN

    IF EXISTS (
        SELECT 1
        FROM public.timetable_entries te
        JOIN public.timetable_slots ts
            ON ts.id = te.timetable_slot_id
        JOIN public.timetable_slots ns
            ON ns.id = NEW.timetable_slot_id
        WHERE te.id <> NEW.id
          AND te.class_id = NEW.class_id
          AND te.timetable_id = NEW.timetable_id
          AND te.status <> 'CANCELLED'
          AND ts.day_of_week = ns.day_of_week
          AND ts.start_time < ns.end_time
          AND ts.end_time > ns.start_time
    )
    THEN
        RAISE EXCEPTION
            'Timetable class conflict detected';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_timetable_class_conflict"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_timetable_course_offering_status"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_status varchar;
BEGIN
    SELECT status
    INTO v_status
    FROM public.course_offerings
    WHERE id = NEW.course_offering_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION
            'Course offering % does not exist',
            NEW.course_offering_id;
    END IF;

    IF v_status NOT IN ('PLANNED', 'OPEN', 'ACTIVE') THEN
        RAISE EXCEPTION
            'Course offering % is not available for timetable scheduling',
            NEW.course_offering_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_timetable_course_offering_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_timetable_lecturer_conflict"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN

    IF NEW.lecturer_assignment_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.timetable_entries te
        JOIN public.lecturer_assignments la
            ON la.id = te.lecturer_assignment_id
        JOIN public.timetable_slots ts
            ON ts.id = te.timetable_slot_id
        JOIN public.timetable_slots ns
            ON ns.id = NEW.timetable_slot_id
        JOIN public.lecturer_assignments nla
            ON nla.id = NEW.lecturer_assignment_id
        WHERE te.id <> NEW.id
          AND la.lecturer_user_id = nla.lecturer_user_id
          AND te.timetable_id = NEW.timetable_id
          AND te.status <> 'CANCELLED'
          AND ts.day_of_week = ns.day_of_week
          AND ts.start_time < ns.end_time
          AND ts.end_time > ns.start_time
    )
    THEN
        RAISE EXCEPTION
            'Timetable lecturer conflict detected';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_timetable_lecturer_conflict"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_timetable_room_capacity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_room_capacity integer;
    v_class_capacity integer;
BEGIN
    SELECT capacity
    INTO v_room_capacity
    FROM public.rooms
    WHERE id = NEW.room_id;

    SELECT capacity
    INTO v_class_capacity
    FROM public.classes
    WHERE id = NEW.class_id;

    IF v_room_capacity IS NULL THEN
        RAISE EXCEPTION
            'Room % does not have a valid capacity',
            NEW.room_id;
    END IF;

    IF v_class_capacity IS NULL THEN
        RAISE EXCEPTION
            'Class % does not have a valid capacity',
            NEW.class_id;
    END IF;

    IF v_room_capacity < v_class_capacity THEN
        RAISE EXCEPTION
            'Room capacity (%) is smaller than class capacity (%)',
            v_room_capacity,
            v_class_capacity;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_timetable_room_capacity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_timetable_room_conflict"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN

    IF EXISTS (
        SELECT 1
        FROM public.timetable_entries te
        JOIN public.timetable_slots ts
            ON ts.id = te.timetable_slot_id
        WHERE te.id <> NEW.id
          AND te.room_id = NEW.room_id
          AND te.timetable_id = NEW.timetable_id
          AND te.status <> 'CANCELLED'
          AND ts.day_of_week = (
              SELECT day_of_week
              FROM public.timetable_slots
              WHERE id = NEW.timetable_slot_id
          )
          AND ts.start_time < (
              SELECT end_time
              FROM public.timetable_slots
              WHERE id = NEW.timetable_slot_id
          )
          AND ts.end_time > (
              SELECT start_time
              FROM public.timetable_slots
              WHERE id = NEW.timetable_slot_id
          )
    )
    THEN
        RAISE EXCEPTION
            'Timetable room conflict detected';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_timetable_room_conflict"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_timetable_room_status"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_room_status varchar;
BEGIN
    SELECT status
    INTO v_room_status
    FROM public.rooms
    WHERE id = NEW.room_id;

    IF v_room_status IS NULL THEN
        RAISE EXCEPTION
            'Room % does not exist',
            NEW.room_id;
    END IF;

    IF v_room_status NOT IN ('ACTIVE', 'AVAILABLE') THEN
        RAISE EXCEPTION
            'Room % is not available for timetable scheduling',
            NEW.room_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_timetable_room_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_timetable_status_transition"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN

    IF TG_OP = 'UPDATE'
       AND OLD.status <> NEW.status
    THEN

        IF OLD.status = 'LOCKED' THEN
            RAISE EXCEPTION
                'Locked timetable cannot change status';
        END IF;

        IF OLD.status = 'CANCELLED'
           AND NEW.status <> 'CANCELLED'
        THEN
            RAISE EXCEPTION
                'Cancelled timetable cannot be reopened';
        END IF;

    END IF;

    IF NEW.status = 'PUBLISHED'
       AND OLD.status IS DISTINCT FROM 'PUBLISHED'
    THEN
        NEW.published_at := COALESCE(
            NEW.published_at,
            now()
        );
    END IF;

    IF NEW.status = 'LOCKED'
       AND OLD.status IS DISTINCT FROM 'LOCKED'
    THEN
        NEW.locked_at := COALESCE(
            NEW.locked_at,
            now()
        );
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_timetable_status_transition"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_transcript_insert_status"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF NEW.transcript_status IS NULL THEN
        NEW.transcript_status := 'DRAFT';
    END IF;

    IF NEW.transcript_status NOT IN (
        'DRAFT',
        'GENERATED',
        'REVIEW'
    ) THEN

        RAISE EXCEPTION
            'New transcript cannot be inserted directly with status %. '
            'Transcript must enter through DRAFT, GENERATED or REVIEW workflow.',
            NEW.transcript_status;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_transcript_insert_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_transcript_issue"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF NEW.transcript_status = 'ISSUED'
       AND OLD.transcript_status <> 'ISSUED' THEN

        IF OLD.transcript_status <> 'APPROVED' THEN
            RAISE EXCEPTION
                'Only APPROVED transcripts can be ISSUED.';
        END IF;


        IF NEW.approved_at IS NULL THEN
            RAISE EXCEPTION
                'Transcript approval timestamp is required before issuing.';
        END IF;


        IF NEW.approved_by IS NULL THEN
            RAISE EXCEPTION
                'Transcript approver is required before issuing.';
        END IF;


        IF NEW.transcript_number IS NULL
           OR trim(NEW.transcript_number) = '' THEN

            RAISE EXCEPTION
                'Transcript number is required before issuing.';

        END IF;


        IF NEW.verification_code IS NULL
           OR trim(NEW.verification_code) = '' THEN

            RAISE EXCEPTION
                'Verification code is required before issuing.';

        END IF;


        IF NEW.issued_by IS NULL THEN
            RAISE EXCEPTION
                'Transcript issuer is required before issuing.';
        END IF;


        NEW.issued_at := COALESCE(
            NEW.issued_at,
            now()
        );

    END IF;


    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_transcript_issue"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_transcript_replacement"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_old_status varchar;
    v_old_student uuid;
BEGIN

    IF NEW.replacement_of IS NULL THEN
        RETURN NEW;
    END IF;


    IF NEW.replacement_of = NEW.id THEN
        RAISE EXCEPTION
            'A transcript cannot replace itself.';
    END IF;


    SELECT
        transcript_status,
        student_id
    INTO
        v_old_status,
        v_old_student
    FROM public.student_transcripts
    WHERE id = NEW.replacement_of;


    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Replacement transcript references a transcript that does not exist.';
    END IF;


    IF v_old_status NOT IN (
        'ISSUED',
        'REVOKED',
        'SUPERSEDED'
    ) THEN

        RAISE EXCEPTION
            'Only ISSUED, REVOKED or SUPERSEDED transcripts may be replaced.';

    END IF;


    IF v_old_student IS DISTINCT FROM NEW.student_id THEN
        RAISE EXCEPTION
            'Replacement transcript must belong to the same student.';
    END IF;


    -- Replacement must still follow the normal workflow.
    IF NEW.transcript_status NOT IN (
        'DRAFT',
        'GENERATED',
        'REVIEW'
    ) THEN

        RAISE EXCEPTION
            'Replacement transcript must enter the normal workflow before approval/issue.';

    END IF;


    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_transcript_replacement"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_transcript_replacement_cycle"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_current uuid;
    v_count integer := 0;
BEGIN

    IF NEW.replacement_of IS NULL THEN
        RETURN NEW;
    END IF;


    IF NEW.replacement_of = NEW.id THEN
        RAISE EXCEPTION
            'A transcript cannot replace itself.';
    END IF;


    v_current := NEW.replacement_of;


    WHILE v_current IS NOT NULL AND v_count < 50 LOOP

        SELECT replacement_of
        INTO v_current
        FROM public.student_transcripts
        WHERE id = v_current;

        v_count := v_count + 1;


        IF v_current = NEW.id THEN
            RAISE EXCEPTION
                'Transcript replacement cycle detected.';
        END IF;

    END LOOP;


    IF v_count >= 50 THEN
        RAISE EXCEPTION
            'Transcript replacement chain exceeds the permitted depth.';
    END IF;


    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_transcript_replacement_cycle"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_transcript_status_transition"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF NEW.transcript_status = OLD.transcript_status THEN
        RETURN NEW;
    END IF;


    -- DRAFT -> GENERATED
    IF OLD.transcript_status = 'DRAFT'
       AND NEW.transcript_status = 'GENERATED' THEN
        RETURN NEW;
    END IF;


    -- GENERATED -> REVIEW / DRAFT
    IF OLD.transcript_status = 'GENERATED'
       AND NEW.transcript_status IN ('REVIEW', 'DRAFT') THEN
        RETURN NEW;
    END IF;


    -- REVIEW -> APPROVED / DRAFT
    IF OLD.transcript_status = 'REVIEW'
       AND NEW.transcript_status IN ('APPROVED', 'DRAFT') THEN
        RETURN NEW;
    END IF;


    -- APPROVED -> ISSUED
    IF OLD.transcript_status = 'APPROVED'
       AND NEW.transcript_status = 'ISSUED' THEN
        RETURN NEW;
    END IF;


    -- ISSUED -> REVOKED / SUPERSEDED
    IF OLD.transcript_status = 'ISSUED'
       AND NEW.transcript_status IN ('REVOKED', 'SUPERSEDED') THEN
        RETURN NEW;
    END IF;


    -- REVOKED -> SUPERSEDED
    IF OLD.transcript_status = 'REVOKED'
       AND NEW.transcript_status = 'SUPERSEDED' THEN
        RETURN NEW;
    END IF;


    RAISE EXCEPTION
        'Invalid transcript status transition: % -> %',
        OLD.transcript_status,
        NEW.transcript_status;

END;
$$;


ALTER FUNCTION "public"."validate_transcript_status_transition"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."academic_qualifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "applicant_id" "uuid" NOT NULL,
    "qualification_type" character varying(50) NOT NULL,
    "institution_name" character varying(255) NOT NULL,
    "country" character varying(100),
    "award_name" character varying(200),
    "index_number" character varying(100),
    "registration_number" character varying(100),
    "start_year" integer,
    "completion_year" integer,
    "grade" character varying(100),
    "gpa" numeric(5,2),
    "field_of_study" character varying(200),
    "verification_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "verified_by" "uuid",
    "verified_at" timestamp with time zone,
    "verification_comments" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "academic_qualifications_gpa_check" CHECK ((("gpa" IS NULL) OR ("gpa" >= (0)::numeric))),
    CONSTRAINT "academic_qualifications_type_check" CHECK ((("qualification_type")::"text" = ANY ((ARRAY['PRIMARY'::character varying, 'SECONDARY'::character varying, 'CERTIFICATE'::character varying, 'DIPLOMA'::character varying, 'ADVANCED_DIPLOMA'::character varying, 'BACHELOR'::character varying, 'POSTGRADUATE_DIPLOMA'::character varying, 'MASTERS'::character varying, 'PHD'::character varying, 'PROFESSIONAL'::character varying, 'OTHER'::character varying])::"text"[]))),
    CONSTRAINT "academic_qualifications_verification_check" CHECK ((("verification_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'VERIFIED'::character varying, 'REJECTED'::character varying, 'REQUIRES_REVIEW'::character varying])::"text"[]))),
    CONSTRAINT "academic_qualifications_year_check" CHECK ((("completion_year" IS NULL) OR ("start_year" IS NULL) OR ("completion_year" >= "start_year")))
);


ALTER TABLE "public"."academic_qualifications" OWNER TO "postgres";


COMMENT ON TABLE "public"."academic_qualifications" IS 'Academic qualifications submitted by applicants.';



CREATE TABLE IF NOT EXISTS "public"."academic_standing_rules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rule_code" character varying(50) NOT NULL,
    "rule_name" character varying(150) NOT NULL,
    "minimum_gpa" numeric(6,3),
    "maximum_gpa" numeric(6,3),
    "minimum_cgpa" numeric(6,3),
    "maximum_cgpa" numeric(6,3),
    "standing_code" character varying(50) NOT NULL,
    "standing_name" character varying(150) NOT NULL,
    "description" "text",
    "priority" integer DEFAULT 100 NOT NULL,
    "status" character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "academic_standing_rules_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'ARCHIVED'::character varying])::"text"[]))),
    CONSTRAINT "standing_cgpa_range_valid" CHECK (((("minimum_cgpa" IS NULL) OR ("minimum_cgpa" >= (0)::numeric)) AND (("maximum_cgpa" IS NULL) OR ("maximum_cgpa" <= (5)::numeric)) AND (("minimum_cgpa" IS NULL) OR ("maximum_cgpa" IS NULL) OR ("maximum_cgpa" >= "minimum_cgpa")))),
    CONSTRAINT "standing_gpa_range_valid" CHECK (((("minimum_gpa" IS NULL) OR ("minimum_gpa" >= (0)::numeric)) AND (("maximum_gpa" IS NULL) OR ("maximum_gpa" <= (5)::numeric)) AND (("minimum_gpa" IS NULL) OR ("maximum_gpa" IS NULL) OR ("maximum_gpa" >= "minimum_gpa"))))
);


ALTER TABLE "public"."academic_standing_rules" OWNER TO "postgres";


COMMENT ON TABLE "public"."academic_standing_rules" IS 'Configurable institutional rules used to determine academic standing.';



CREATE TABLE IF NOT EXISTS "public"."academic_years" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "year_code" character varying(20) NOT NULL,
    "year_name" character varying(100) NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date" NOT NULL,
    "status" character varying(30) DEFAULT 'PLANNED'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "academic_years_date_check" CHECK (("end_date" > "start_date")),
    CONSTRAINT "academic_years_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['PLANNED'::character varying, 'ACTIVE'::character varying, 'CLOSED'::character varying, 'ARCHIVED'::character varying])::"text"[])))
);


ALTER TABLE "public"."academic_years" OWNER TO "postgres";


COMMENT ON TABLE "public"."academic_years" IS 'Institutional academic years used across academic operations.';



CREATE TABLE IF NOT EXISTS "public"."admission_acceptances" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "admission_offer_id" "uuid" NOT NULL,
    "acceptance_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "accepted_at" timestamp with time zone,
    "declined_at" timestamp with time zone,
    "decline_reason" "text",
    "acceptance_ip_address" "inet",
    "acceptance_user_agent" "text",
    "accepted_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "admission_acceptances_status_check" CHECK ((("acceptance_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'ACCEPTED'::character varying, 'DECLINED'::character varying, 'EXPIRED'::character varying])::"text"[])))
);


ALTER TABLE "public"."admission_acceptances" OWNER TO "postgres";


COMMENT ON TABLE "public"."admission_acceptances" IS 'Applicant acceptance or decline of an admission offer.';



CREATE TABLE IF NOT EXISTS "public"."admission_decisions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "application_id" "uuid" NOT NULL,
    "application_choice_id" "uuid",
    "decision_type" character varying(40) NOT NULL,
    "decision_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "decision_date" timestamp with time zone,
    "decision_reason" "text",
    "capacity_check" boolean DEFAULT false NOT NULL,
    "academic_check" boolean DEFAULT false NOT NULL,
    "document_check" boolean DEFAULT false NOT NULL,
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "admission_decisions_status_check" CHECK ((("decision_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "admission_decisions_type_check" CHECK ((("decision_type")::"text" = ANY ((ARRAY['SELECTED'::character varying, 'WAITLISTED'::character varying, 'REJECTED'::character varying, 'CONDITIONAL'::character varying])::"text"[])))
);


ALTER TABLE "public"."admission_decisions" OWNER TO "postgres";


COMMENT ON TABLE "public"."admission_decisions" IS 'Formal academic/admission selection decisions.';



CREATE TABLE IF NOT EXISTS "public"."admission_offers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "application_id" "uuid" NOT NULL,
    "programme_id" "uuid" NOT NULL,
    "decision_id" "uuid",
    "offer_number" character varying(60) NOT NULL,
    "offer_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "expiry_date" "date",
    "offer_status" character varying(30) DEFAULT 'ISSUED'::character varying NOT NULL,
    "admission_conditions" "text",
    "admission_letter_url" "text",
    "joining_instructions_url" "text",
    "issued_by" "uuid",
    "issued_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "admission_offers_date_check" CHECK ((("expiry_date" IS NULL) OR ("expiry_date" >= "offer_date"))),
    CONSTRAINT "admission_offers_status_check" CHECK ((("offer_status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'ISSUED'::character varying, 'ACCEPTED'::character varying, 'DECLINED'::character varying, 'EXPIRED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."admission_offers" OWNER TO "postgres";


COMMENT ON TABLE "public"."admission_offers" IS 'Admission offers issued to successful applicants.';



CREATE TABLE IF NOT EXISTS "public"."alumni_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "graduation_candidate_id" "uuid",
    "graduation_award_id" "uuid",
    "alumni_number" character varying(100) NOT NULL,
    "graduation_year" integer NOT NULL,
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "current_employer" character varying(200),
    "current_position" character varying(200),
    "phone" character varying(50),
    "email" character varying(255),
    "address" "text",
    "linkedin_url" "text",
    "website_url" "text",
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "alumni_records_graduation_year_valid" CHECK ((("graduation_year" >= 2000) AND ("graduation_year" <= ((EXTRACT(year FROM CURRENT_DATE))::integer + 1)))),
    CONSTRAINT "alumni_records_number_not_blank" CHECK (("length"(TRIM(BOTH FROM "alumni_number")) > 0)),
    CONSTRAINT "alumni_records_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'DECEASED'::character varying, 'UNSUBSCRIBED'::character varying])::"text"[]))),
    CONSTRAINT "alumni_records_status_chk" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'DECEASED'::character varying, 'UNSUBSCRIBED'::character varying])::"text"[])))
);


ALTER TABLE "public"."alumni_records" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."applicants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "applicant_number" character varying(50) NOT NULL,
    "first_name" character varying(100) NOT NULL,
    "middle_name" character varying(100),
    "last_name" character varying(100) NOT NULL,
    "gender" character varying(30),
    "date_of_birth" "date",
    "nationality" character varying(100),
    "national_id_number" character varying(100),
    "passport_number" character varying(100),
    "email" character varying(255) NOT NULL,
    "phone" character varying(50),
    "address_line_1" character varying(255),
    "address_line_2" character varying(255),
    "city" character varying(100),
    "district" character varying(100),
    "region" character varying(100),
    "country" character varying(100) DEFAULT 'Tanzania'::character varying,
    "disability_status" boolean DEFAULT false NOT NULL,
    "disability_details" "text",
    "applicant_type" character varying(50) DEFAULT 'NEW'::character varying NOT NULL,
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "auth_user_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "applicants_gender_check" CHECK ((("gender" IS NULL) OR (("gender")::"text" = ANY ((ARRAY['MALE'::character varying, 'FEMALE'::character varying, 'OTHER'::character varying, 'PREFER_NOT_TO_SAY'::character varying])::"text"[])))),
    CONSTRAINT "applicants_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'BLACKLISTED'::character varying, 'CONVERTED'::character varying, 'ARCHIVED'::character varying])::"text"[]))),
    CONSTRAINT "applicants_type_check" CHECK ((("applicant_type")::"text" = ANY ((ARRAY['NEW'::character varying, 'TRANSFER'::character varying, 'CONTINUING'::character varying, 'INTERNATIONAL'::character varying, 'OTHER'::character varying])::"text"[])))
);


ALTER TABLE "public"."applicants" OWNER TO "postgres";


COMMENT ON TABLE "public"."applicants" IS 'Applicant master records for the IDMC admissions process.';



CREATE TABLE IF NOT EXISTS "public"."application_choices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "application_id" "uuid" NOT NULL,
    "programme_id" "uuid" NOT NULL,
    "choice_number" integer NOT NULL,
    "preference_type" character varying(30) DEFAULT 'PREFERRED'::character varying NOT NULL,
    "status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "decision_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "application_choices_number_check" CHECK (("choice_number" > 0)),
    CONSTRAINT "application_choices_preference_check" CHECK ((("preference_type")::"text" = ANY ((ARRAY['PREFERRED'::character varying, 'ALTERNATIVE'::character varying])::"text"[]))),
    CONSTRAINT "application_choices_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'ELIGIBLE'::character varying, 'INELIGIBLE'::character varying, 'SELECTED'::character varying, 'WAITLISTED'::character varying, 'REJECTED'::character varying, 'WITHDRAWN'::character varying])::"text"[])))
);


ALTER TABLE "public"."application_choices" OWNER TO "postgres";


COMMENT ON TABLE "public"."application_choices" IS 'Programme choices submitted by an applicant within an application.';



CREATE TABLE IF NOT EXISTS "public"."application_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "application_id" "uuid" NOT NULL,
    "document_type" character varying(80) NOT NULL,
    "document_name" character varying(255) NOT NULL,
    "file_url" "text" NOT NULL,
    "file_size" bigint,
    "mime_type" character varying(100),
    "document_number" character varying(100),
    "issue_date" "date",
    "expiry_date" "date",
    "verification_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "verified_by" "uuid",
    "verified_at" timestamp with time zone,
    "rejection_reason" "text",
    "uploaded_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "application_documents_date_check" CHECK ((("expiry_date" IS NULL) OR ("issue_date" IS NULL) OR ("expiry_date" >= "issue_date"))),
    CONSTRAINT "application_documents_file_size_check" CHECK ((("file_size" IS NULL) OR ("file_size" >= 0))),
    CONSTRAINT "application_documents_status_check" CHECK ((("verification_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'UNDER_REVIEW'::character varying, 'VERIFIED'::character varying, 'REJECTED'::character varying, 'EXPIRED'::character varying, 'CORRECTION_REQUIRED'::character varying])::"text"[])))
);


ALTER TABLE "public"."application_documents" OWNER TO "postgres";


COMMENT ON TABLE "public"."application_documents" IS 'Documents uploaded as part of an application and their verification status.';



CREATE TABLE IF NOT EXISTS "public"."applications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "applicant_id" "uuid" NOT NULL,
    "academic_year_id" "uuid" NOT NULL,
    "application_number" character varying(50) NOT NULL,
    "application_type" character varying(50) DEFAULT 'NEW'::character varying NOT NULL,
    "application_round" character varying(50),
    "submitted_at" timestamp with time zone,
    "status" character varying(40) DEFAULT 'DRAFT'::character varying NOT NULL,
    "payment_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "verification_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "eligibility_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "selection_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "completion_percentage" numeric(5,2) DEFAULT 0 NOT NULL,
    "correction_count" integer DEFAULT 0 NOT NULL,
    "correction_deadline" timestamp with time zone,
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "review_comments" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "applications_completion_check" CHECK ((("completion_percentage" >= (0)::numeric) AND ("completion_percentage" <= (100)::numeric))),
    CONSTRAINT "applications_correction_count_check" CHECK (("correction_count" >= 0)),
    CONSTRAINT "applications_eligibility_status_check" CHECK ((("eligibility_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'ELIGIBLE'::character varying, 'INELIGIBLE'::character varying, 'CONDITIONAL'::character varying])::"text"[]))),
    CONSTRAINT "applications_payment_status_check" CHECK ((("payment_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'UNPAID'::character varying, 'PAID'::character varying, 'FAILED'::character varying, 'WAIVED'::character varying, 'REFUNDED'::character varying])::"text"[]))),
    CONSTRAINT "applications_selection_status_check" CHECK ((("selection_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'SELECTED'::character varying, 'WAITLISTED'::character varying, 'NOT_SELECTED'::character varying])::"text"[]))),
    CONSTRAINT "applications_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'SUBMITTED'::character varying, 'PAYMENT_PENDING'::character varying, 'PAYMENT_CONFIRMED'::character varying, 'UNDER_REVIEW'::character varying, 'CORRECTION_REQUIRED'::character varying, 'VERIFIED'::character varying, 'ELIGIBLE'::character varying, 'INELIGIBLE'::character varying, 'SELECTED'::character varying, 'WAITLISTED'::character varying, 'ADMISSION_OFFERED'::character varying, 'ACCEPTED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying, 'CONVERTED_TO_STUDENT'::character varying])::"text"[]))),
    CONSTRAINT "applications_type_check" CHECK ((("application_type")::"text" = ANY ((ARRAY['NEW'::character varying, 'TRANSFER'::character varying, 'POSTGRADUATE'::character varying, 'SHORT_COURSE'::character varying, 'INTERNATIONAL'::character varying, 'OTHER'::character varying])::"text"[]))),
    CONSTRAINT "applications_verification_status_check" CHECK ((("verification_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'IN_PROGRESS'::character varying, 'VERIFIED'::character varying, 'REJECTED'::character varying, 'CORRECTION_REQUIRED'::character varying])::"text"[])))
);


ALTER TABLE "public"."applications" OWNER TO "postgres";


COMMENT ON TABLE "public"."applications" IS 'Online admission applications and their complete lifecycle.';



CREATE TABLE IF NOT EXISTS "public"."assessment_mark_corrections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "assessment_mark_id" "uuid" NOT NULL,
    "requested_by" "uuid" NOT NULL,
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "old_marks" numeric(8,2),
    "new_marks" numeric(8,2),
    "old_grade" character varying(20),
    "new_grade" character varying(20),
    "reason" "text" NOT NULL,
    "evidence_file_id" "uuid",
    "status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "review_comment" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "assessment_mark_correction_reason_chk" CHECK (("length"(TRIM(BOTH FROM "reason")) >= 5)),
    CONSTRAINT "assessment_mark_correction_review_chk" CHECK (((("status")::"text" = 'PENDING'::"text") OR (("status")::"text" = 'CANCELLED'::"text") OR ((("status")::"text" = ANY ((ARRAY['APPROVED'::character varying, 'REJECTED'::character varying])::"text"[])) AND ("reviewed_by" IS NOT NULL) AND ("reviewed_at" IS NOT NULL)))),
    CONSTRAINT "assessment_mark_corrections_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."assessment_mark_corrections" OWNER TO "postgres";


COMMENT ON TABLE "public"."assessment_mark_corrections" IS 'Formal audited workflow for correcting approved or locked assessment marks.';



COMMENT ON COLUMN "public"."assessment_mark_corrections"."reason" IS 'Mandatory business reason for requesting a mark correction.';



COMMENT ON COLUMN "public"."assessment_mark_corrections"."evidence_file_id" IS 'Optional supporting evidence reference.';



COMMENT ON COLUMN "public"."assessment_mark_corrections"."status" IS 'Correction workflow status: PENDING, APPROVED, REJECTED or CANCELLED.';



CREATE TABLE IF NOT EXISTS "public"."assessment_marks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "assessment_id" "uuid" NOT NULL,
    "student_id" "uuid" NOT NULL,
    "course_registration_id" "uuid" NOT NULL,
    "marks" numeric(8,2) DEFAULT 0 NOT NULL,
    "percentage" numeric(8,4),
    "grade" character varying(10),
    "remarks" "text",
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "entered_by" "uuid",
    "entered_at" timestamp with time zone,
    "submitted_by" "uuid",
    "submitted_at" timestamp with time zone,
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "assessment_marks_marks_check" CHECK (("marks" >= (0)::numeric)),
    CONSTRAINT "assessment_marks_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'SUBMITTED'::character varying, 'APPROVED'::character varying, 'LOCKED'::character varying, 'CORRECTION_PENDING'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."assessment_marks" OWNER TO "postgres";


COMMENT ON TABLE "public"."assessment_marks" IS 'Student-level assessment marks with controlled approval and locking.';



CREATE TABLE IF NOT EXISTS "public"."assessment_submissions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "assessment_id" "uuid" NOT NULL,
    "student_id" "uuid" NOT NULL,
    "submitted_at" timestamp with time zone,
    "submission_status" character varying(30) DEFAULT 'NOT_SUBMITTED'::character varying NOT NULL,
    "file_id" "uuid",
    "submission_reference" character varying(100),
    "remarks" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "assessment_submissions_submission_status_check" CHECK ((("submission_status")::"text" = ANY ((ARRAY['NOT_SUBMITTED'::character varying, 'SUBMITTED'::character varying, 'LATE'::character varying, 'ACCEPTED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."assessment_submissions" OWNER TO "postgres";


COMMENT ON TABLE "public"."assessment_submissions" IS 'Student assessment submission records and associated submission metadata.';



CREATE TABLE IF NOT EXISTS "public"."assessments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_offering_id" "uuid" NOT NULL,
    "assessment_code" character varying(50) NOT NULL,
    "assessment_name" character varying(255) NOT NULL,
    "assessment_type" character varying(30) NOT NULL,
    "assessment_number" integer,
    "maximum_marks" numeric(6,2) NOT NULL,
    "weight_percentage" numeric(6,2) NOT NULL,
    "due_date" "date",
    "due_time" time without time zone,
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "instructions" "text",
    "created_by" "uuid",
    "updated_by" "uuid",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "locked_by" "uuid",
    "locked_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "assessments_assessment_type_check" CHECK ((("assessment_type")::"text" = ANY ((ARRAY['ASSIGNMENT'::character varying, 'QUIZ'::character varying, 'TEST'::character varying, 'PRACTICAL'::character varying, 'PRESENTATION'::character varying, 'PROJECT'::character varying, 'CONTINUOUS_ASSESSMENT'::character varying, 'OTHER'::character varying])::"text"[]))),
    CONSTRAINT "assessments_maximum_marks_check" CHECK (("maximum_marks" > (0)::numeric)),
    CONSTRAINT "assessments_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'OPEN'::character varying, 'SUBMITTED'::character varying, 'UNDER_REVIEW'::character varying, 'APPROVED'::character varying, 'LOCKED'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "assessments_weight_percentage_check" CHECK ((("weight_percentage" > (0)::numeric) AND ("weight_percentage" <= (100)::numeric)))
);


ALTER TABLE "public"."assessments" OWNER TO "postgres";


COMMENT ON TABLE "public"."assessments" IS 'Course assessment definitions including coursework, tests, practicals and projects.';



CREATE TABLE IF NOT EXISTS "public"."asset_assignments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "staff_id" "uuid",
    "department_id" "uuid",
    "assigned_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "returned_date" "date",
    "assignment_status" character varying(20) DEFAULT 'ASSIGNED'::character varying NOT NULL,
    "assigned_by" "uuid",
    "received_by" "uuid",
    "return_condition" character varying(30),
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "asset_assignments_assignment_status_check" CHECK ((("assignment_status")::"text" = ANY ((ARRAY['ASSIGNED'::character varying, 'RETURNED'::character varying, 'TRANSFERRED'::character varying, 'LOST'::character varying])::"text"[]))),
    CONSTRAINT "asset_assignments_return_condition_check" CHECK ((("return_condition" IS NULL) OR (("return_condition")::"text" = ANY ((ARRAY['NEW'::character varying, 'GOOD'::character varying, 'FAIR'::character varying, 'POOR'::character varying, 'DAMAGED'::character varying])::"text"[])))),
    CONSTRAINT "chk_asset_assignment_dates" CHECK ((("returned_date" IS NULL) OR ("returned_date" >= "assigned_date"))),
    CONSTRAINT "chk_asset_assignment_owner" CHECK ((("staff_id" IS NOT NULL) OR ("department_id" IS NOT NULL)))
);


ALTER TABLE "public"."asset_assignments" OWNER TO "postgres";


COMMENT ON TABLE "public"."asset_assignments" IS 'Assignment and custody records for institutional assets.';



CREATE TABLE IF NOT EXISTS "public"."asset_categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "category_code" character varying(60) NOT NULL,
    "category_name" character varying(150) NOT NULL,
    "depreciation_method" character varying(40),
    "default_useful_life_years" integer,
    "description" "text",
    "status" character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "asset_categories_default_useful_life_years_check" CHECK ((("default_useful_life_years" IS NULL) OR ("default_useful_life_years" > 0))),
    CONSTRAINT "asset_categories_depreciation_method_check" CHECK ((("depreciation_method" IS NULL) OR (("depreciation_method")::"text" = ANY ((ARRAY['STRAIGHT_LINE'::character varying, 'DECLINING_BALANCE'::character varying, 'NONE'::character varying])::"text"[])))),
    CONSTRAINT "asset_categories_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying])::"text"[])))
);


ALTER TABLE "public"."asset_categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."asset_maintenance" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "maintenance_type" character varying(30) NOT NULL,
    "maintenance_date" "date" NOT NULL,
    "service_provider" character varying(255),
    "description" "text" NOT NULL,
    "cost" numeric(14,2) DEFAULT 0 NOT NULL,
    "next_maintenance_date" "date",
    "maintenance_status" character varying(20) DEFAULT 'COMPLETED'::character varying NOT NULL,
    "performed_by" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "asset_maintenance_cost_check" CHECK (("cost" >= (0)::numeric)),
    CONSTRAINT "asset_maintenance_maintenance_status_check" CHECK ((("maintenance_status")::"text" = ANY ((ARRAY['SCHEDULED'::character varying, 'IN_PROGRESS'::character varying, 'COMPLETED'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "asset_maintenance_maintenance_type_check" CHECK ((("maintenance_type")::"text" = ANY ((ARRAY['PREVENTIVE'::character varying, 'CORRECTIVE'::character varying, 'INSPECTION'::character varying, 'CALIBRATION'::character varying, 'OTHER'::character varying])::"text"[]))),
    CONSTRAINT "chk_asset_maintenance_dates" CHECK ((("next_maintenance_date" IS NULL) OR ("next_maintenance_date" >= "maintenance_date")))
);


ALTER TABLE "public"."asset_maintenance" OWNER TO "postgres";


COMMENT ON TABLE "public"."asset_maintenance" IS 'Maintenance and service history for institutional assets.';



CREATE TABLE IF NOT EXISTS "public"."assets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "category_id" "uuid",
    "department_id" "uuid",
    "asset_tag" character varying(80) NOT NULL,
    "asset_name" character varying(255) NOT NULL,
    "description" "text",
    "serial_number" character varying(150),
    "manufacturer" character varying(150),
    "model" character varying(150),
    "acquisition_date" "date",
    "acquisition_cost" numeric(14,2) DEFAULT 0 NOT NULL,
    "current_value" numeric(14,2),
    "useful_life_years" integer,
    "location" character varying(255),
    "condition_status" character varying(30) DEFAULT 'GOOD'::character varying NOT NULL,
    "asset_status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "warranty_expiry_date" "date",
    "notes" "text",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "assets_acquisition_cost_check" CHECK (("acquisition_cost" >= (0)::numeric)),
    CONSTRAINT "assets_asset_status_check" CHECK ((("asset_status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'UNDER_REPAIR'::character varying, 'LOST'::character varying, 'DISPOSED'::character varying, 'TRANSFERRED'::character varying, 'INACTIVE'::character varying])::"text"[]))),
    CONSTRAINT "assets_condition_status_check" CHECK ((("condition_status")::"text" = ANY ((ARRAY['NEW'::character varying, 'GOOD'::character varying, 'FAIR'::character varying, 'POOR'::character varying, 'DAMAGED'::character varying, 'DISPOSED'::character varying])::"text"[]))),
    CONSTRAINT "assets_current_value_check" CHECK ((("current_value" IS NULL) OR ("current_value" >= (0)::numeric))),
    CONSTRAINT "assets_useful_life_years_check" CHECK ((("useful_life_years" IS NULL) OR ("useful_life_years" > 0)))
);


ALTER TABLE "public"."assets" OWNER TO "postgres";


COMMENT ON TABLE "public"."assets" IS 'Institutional fixed assets and equipment.';



CREATE OR REPLACE VIEW "public"."asset_summary" AS
 SELECT "id",
    "asset_tag",
    "asset_name",
    "institution_id",
    "category_id",
    "department_id",
    "serial_number",
    "manufacturer",
    "model",
    "acquisition_date",
    "acquisition_cost",
    "current_value",
    "location",
    "condition_status",
    "asset_status",
    "warranty_expiry_date",
    "created_at",
    "updated_at"
   FROM "public"."assets" "a";


ALTER VIEW "public"."asset_summary" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attendance_corrections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "attendance_record_id" "uuid" NOT NULL,
    "requested_by" "uuid" NOT NULL,
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "old_status" character varying(20),
    "new_status" character varying(20),
    "old_check_in_time" timestamp with time zone,
    "new_check_in_time" timestamp with time zone,
    "reason" "text" NOT NULL,
    "evidence_file_id" "uuid",
    "status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "review_comment" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attendance_corrections_reason_required" CHECK (("length"(TRIM(BOTH FROM "reason")) >= 5)),
    CONSTRAINT "attendance_corrections_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."attendance_corrections" OWNER TO "postgres";


COMMENT ON TABLE "public"."attendance_corrections" IS 'Controlled workflow for correcting attendance after submission or locking.';



CREATE TABLE IF NOT EXISTS "public"."attendance_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "attendance_session_id" "uuid" NOT NULL,
    "student_id" "uuid" NOT NULL,
    "course_registration_id" "uuid",
    "attendance_status" character varying(20) DEFAULT 'ABSENT'::character varying NOT NULL,
    "check_in_time" timestamp with time zone,
    "minutes_late" integer DEFAULT 0 NOT NULL,
    "remarks" "text",
    "marked_by" "uuid",
    "marked_at" timestamp with time zone,
    "correction_required" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attendance_records_attendance_status_check" CHECK ((("attendance_status")::"text" = ANY ((ARRAY['PRESENT'::character varying, 'ABSENT'::character varying, 'LATE'::character varying, 'EXCUSED'::character varying])::"text"[]))),
    CONSTRAINT "attendance_records_minutes_late_check" CHECK (("minutes_late" >= 0))
);


ALTER TABLE "public"."attendance_records" OWNER TO "postgres";


COMMENT ON TABLE "public"."attendance_records" IS 'Student-level attendance records for each attendance session.';



CREATE TABLE IF NOT EXISTS "public"."attendance_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "class_id" "uuid" NOT NULL,
    "course_offering_id" "uuid" NOT NULL,
    "timetable_entry_id" "uuid",
    "session_date" "date" NOT NULL,
    "start_time" time without time zone NOT NULL,
    "end_time" time without time zone NOT NULL,
    "session_type" character varying(30) DEFAULT 'LECTURE'::character varying NOT NULL,
    "topic" character varying(255),
    "venue_room_id" "uuid",
    "conducted_by" "uuid",
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "opened_at" timestamp with time zone,
    "submitted_at" timestamp with time zone,
    "locked_at" timestamp with time zone,
    "locked_by" "uuid",
    "notes" "text",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attendance_sessions_date_valid" CHECK (("session_date" IS NOT NULL)),
    CONSTRAINT "attendance_sessions_session_type_check" CHECK ((("session_type")::"text" = ANY ((ARRAY['LECTURE'::character varying, 'PRACTICAL'::character varying, 'TUTORIAL'::character varying, 'SEMINAR'::character varying, 'CLINICAL'::character varying, 'FIELD'::character varying, 'EXAM'::character varying, 'OTHER'::character varying])::"text"[]))),
    CONSTRAINT "attendance_sessions_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'OPEN'::character varying, 'SUBMITTED'::character varying, 'LOCKED'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "attendance_sessions_time_valid" CHECK (("end_time" > "start_time"))
);


ALTER TABLE "public"."attendance_sessions" OWNER TO "postgres";


COMMENT ON TABLE "public"."attendance_sessions" IS 'Attendance session master records for scheduled academic teaching activities.';



CREATE TABLE IF NOT EXISTS "public"."audit_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "action_code" character varying(100) NOT NULL,
    "module_code" character varying(100) NOT NULL,
    "entity_type" character varying(100),
    "entity_id" "uuid",
    "old_values" "jsonb",
    "new_values" "jsonb",
    "description" "text",
    "ip_address" "inet",
    "user_agent" "text",
    "request_id" character varying(100),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."audit_logs" OWNER TO "postgres";


COMMENT ON TABLE "public"."audit_logs" IS 'Central audit trail for important system operations.';



CREATE TABLE IF NOT EXISTS "public"."campuses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "campus_code" character varying(30) NOT NULL,
    "campus_name" character varying(255) NOT NULL,
    "campus_type" character varying(50),
    "physical_address" "text",
    "city" character varying(100),
    "region" character varying(100),
    "phone" character varying(50),
    "email" character varying(255),
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."campuses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."certificate_verifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "certificate_id" "uuid" NOT NULL,
    "verification_code" character varying(100) NOT NULL,
    "verified_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "verification_result" character varying(30) NOT NULL,
    "ip_address" "inet",
    "user_agent" "text",
    CONSTRAINT "certificate_verifications_result_chk" CHECK ((("verification_result")::"text" = ANY ((ARRAY['VALID'::character varying, 'INVALID'::character varying, 'REVOKED'::character varying, 'REPLACED'::character varying])::"text"[])))
);


ALTER TABLE "public"."certificate_verifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."certificates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "graduation_award_id" "uuid" NOT NULL,
    "student_id" "uuid" NOT NULL,
    "certificate_number" character varying(100) NOT NULL,
    "certificate_type" character varying(50) DEFAULT 'ACADEMIC'::character varying NOT NULL,
    "award_name" character varying(200) NOT NULL,
    "programme_id" "uuid",
    "programme_version_id" "uuid",
    "issue_date" "date",
    "verification_code" character varying(100) NOT NULL,
    "document_file_id" "uuid",
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "issued_by" "uuid",
    "issued_at" timestamp with time zone,
    "revoked_by" "uuid",
    "revoked_at" timestamp with time zone,
    "revocation_reason" "text",
    "replacement_of" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "certificates_status_chk" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'APPROVED'::character varying, 'ISSUED'::character varying, 'REVOKED'::character varying, 'REPLACED'::character varying])::"text"[])))
);


ALTER TABLE "public"."certificates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."class_students" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "class_id" "uuid" NOT NULL,
    "student_id" "uuid" NOT NULL,
    "course_registration_id" "uuid",
    "enrollment_status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "enrolled_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "withdrawn_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_class_student_status" CHECK ((("enrollment_status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'WITHDRAWN'::character varying, 'COMPLETED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."class_students" OWNER TO "postgres";


COMMENT ON TABLE "public"."class_students" IS 'Students enrolled into teaching classes.';



CREATE TABLE IF NOT EXISTS "public"."classes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_offering_id" "uuid" NOT NULL,
    "class_code" character varying(80) NOT NULL,
    "class_name" character varying(150) NOT NULL,
    "class_type" character varying(30) DEFAULT 'LECTURE'::character varying NOT NULL,
    "capacity" integer DEFAULT 0 NOT NULL,
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_class_capacity" CHECK (("capacity" >= 0)),
    CONSTRAINT "chk_class_status" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'CANCELLED'::character varying, 'COMPLETED'::character varying])::"text"[]))),
    CONSTRAINT "chk_class_type" CHECK ((("class_type")::"text" = ANY ((ARRAY['LECTURE'::character varying, 'TUTORIAL'::character varying, 'PRACTICAL'::character varying, 'LAB'::character varying, 'SEMINAR'::character varying, 'CLINICAL'::character varying, 'FIELD'::character varying])::"text"[]))),
    CONSTRAINT "classes_capacity_positive" CHECK ((("capacity" IS NULL) OR ("capacity" > 0)))
);


ALTER TABLE "public"."classes" OWNER TO "postgres";


COMMENT ON TABLE "public"."classes" IS 'Teaching classes linked to course offerings.';



CREATE TABLE IF NOT EXISTS "public"."course_add_drop_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_registration_id" "uuid" NOT NULL,
    "student_id" "uuid" NOT NULL,
    "course_id" "uuid" NOT NULL,
    "course_offering_id" "uuid",
    "request_type" character varying(20) NOT NULL,
    "request_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "reason" "text",
    "decision_reason" "text",
    "requested_by" "uuid",
    "reviewed_by" "uuid",
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reviewed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_add_drop_status" CHECK ((("request_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "chk_add_drop_type" CHECK ((("request_type")::"text" = ANY ((ARRAY['ADD'::character varying, 'DROP'::character varying])::"text"[])))
);


ALTER TABLE "public"."course_add_drop_requests" OWNER TO "postgres";


COMMENT ON TABLE "public"."course_add_drop_requests" IS 'Formal requests by students to add or drop courses.';



CREATE TABLE IF NOT EXISTS "public"."course_offerings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "academic_year_id" "uuid" NOT NULL,
    "semester_id" "uuid" NOT NULL,
    "programme_id" "uuid" NOT NULL,
    "programme_version_id" "uuid",
    "course_id" "uuid" NOT NULL,
    "offering_code" character varying(80) NOT NULL,
    "section_name" character varying(100),
    "capacity" integer DEFAULT 0 NOT NULL,
    "minimum_students" integer DEFAULT 0 NOT NULL,
    "delivery_mode" character varying(30) DEFAULT 'ON_CAMPUS'::character varying NOT NULL,
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "registration_open_at" timestamp with time zone,
    "registration_close_at" timestamp with time zone,
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_course_offering_capacity" CHECK (("capacity" >= 0)),
    CONSTRAINT "chk_course_offering_dates" CHECK ((("registration_close_at" IS NULL) OR ("registration_open_at" IS NULL) OR ("registration_close_at" >= "registration_open_at"))),
    CONSTRAINT "chk_course_offering_delivery_mode" CHECK ((("delivery_mode")::"text" = ANY ((ARRAY['ON_CAMPUS'::character varying, 'ONLINE'::character varying, 'HYBRID'::character varying, 'DISTANCE'::character varying, 'FIELD'::character varying, 'CLINICAL'::character varying])::"text"[]))),
    CONSTRAINT "chk_course_offering_minimum_students" CHECK (("minimum_students" >= 0)),
    CONSTRAINT "chk_course_offering_status" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'OPEN'::character varying, 'CLOSED'::character varying, 'SUSPENDED'::character varying, 'COMPLETED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."course_offerings" OWNER TO "postgres";


COMMENT ON TABLE "public"."course_offerings" IS 'Courses officially offered to programmes during an academic semester.';



CREATE TABLE IF NOT EXISTS "public"."course_prerequisites" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_id" "uuid" NOT NULL,
    "prerequisite_course_id" "uuid" NOT NULL,
    "minimum_grade" character varying(20),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "course_prerequisite_self_check" CHECK (("course_id" <> "prerequisite_course_id"))
);


ALTER TABLE "public"."course_prerequisites" OWNER TO "postgres";


COMMENT ON TABLE "public"."course_prerequisites" IS 'Prerequisite relationships between courses.';



CREATE TABLE IF NOT EXISTS "public"."course_registrations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_registration_id" "uuid" NOT NULL,
    "student_id" "uuid" NOT NULL,
    "course_id" "uuid" NOT NULL,
    "course_offering_id" "uuid",
    "registration_type" character varying(30) DEFAULT 'NORMAL'::character varying NOT NULL,
    "registration_status" character varying(30) DEFAULT 'SELECTED'::character varying NOT NULL,
    "credits" numeric(8,2) NOT NULL,
    "attempt_number" integer DEFAULT 1 NOT NULL,
    "is_core" boolean DEFAULT false NOT NULL,
    "is_elective" boolean DEFAULT false NOT NULL,
    "prerequisite_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "eligibility_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "selected_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "approved_at" timestamp with time zone,
    "approved_by" "uuid",
    "dropped_at" timestamp with time zone,
    "drop_reason" "text",
    "notes" "text",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_attempt_number" CHECK (("attempt_number" >= 1)),
    CONSTRAINT "chk_course_eligibility" CHECK ((("eligibility_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'ELIGIBLE'::character varying, 'NOT_ELIGIBLE'::character varying, 'OVERRIDE'::character varying])::"text"[]))),
    CONSTRAINT "chk_course_registration_credits" CHECK (("credits" > (0)::numeric)),
    CONSTRAINT "chk_course_registration_status" CHECK ((("registration_status")::"text" = ANY ((ARRAY['SELECTED'::character varying, 'PENDING_APPROVAL'::character varying, 'APPROVED'::character varying, 'REGISTERED'::character varying, 'DROPPED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "chk_course_registration_type" CHECK ((("registration_type")::"text" = ANY ((ARRAY['NORMAL'::character varying, 'RETAKE'::character varying, 'REPEAT'::character varying, 'AUDIT'::character varying, 'CARRY_FORWARD'::character varying, 'SPECIAL'::character varying])::"text"[]))),
    CONSTRAINT "chk_prerequisite_status" CHECK ((("prerequisite_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'PASSED'::character varying, 'FAILED'::character varying, 'NOT_REQUIRED'::character varying, 'OVERRIDE'::character varying])::"text"[])))
);


ALTER TABLE "public"."course_registrations" OWNER TO "postgres";


COMMENT ON TABLE "public"."course_registrations" IS 'Individual course selections belonging to a student registration.';



CREATE TABLE IF NOT EXISTS "public"."course_result_corrections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_result_id" "uuid" NOT NULL,
    "requested_by" "uuid",
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "old_coursework_mark" numeric(8,2),
    "new_coursework_mark" numeric(8,2),
    "old_examination_mark" numeric(8,2),
    "new_examination_mark" numeric(8,2),
    "old_total_mark" numeric(8,2),
    "new_total_mark" numeric(8,2),
    "old_grade_code" character varying(10),
    "new_grade_code" character varying(10),
    "old_grade_point" numeric(5,2),
    "new_grade_point" numeric(5,2),
    "reason" "text" NOT NULL,
    "evidence_file_id" "uuid",
    "status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "review_comment" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "course_result_corrections_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."course_result_corrections" OWNER TO "postgres";


COMMENT ON TABLE "public"."course_result_corrections" IS 'Formal correction workflow for approved, published or locked course results.';



CREATE TABLE IF NOT EXISTS "public"."course_result_policies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_offering_id" "uuid" NOT NULL,
    "grade_scale_id" "uuid" NOT NULL,
    "coursework_weight" numeric(5,2) DEFAULT 40.00 NOT NULL,
    "examination_weight" numeric(5,2) DEFAULT 60.00 NOT NULL,
    "minimum_coursework_required" numeric(5,2),
    "minimum_exam_required" numeric(5,2),
    "minimum_pass_mark" numeric(5,2) DEFAULT 40.00 NOT NULL,
    "status" character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_by" "uuid",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "course_result_policies_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'ACTIVE'::character varying, 'LOCKED'::character varying, 'ARCHIVED'::character varying])::"text"[]))),
    CONSTRAINT "result_policy_pass_mark_valid" CHECK ((("minimum_pass_mark" >= (0)::numeric) AND ("minimum_pass_mark" <= (100)::numeric))),
    CONSTRAINT "result_policy_weight_valid" CHECK ((("coursework_weight" >= (0)::numeric) AND ("examination_weight" >= (0)::numeric) AND (("coursework_weight" + "examination_weight") = (100)::numeric)))
);


ALTER TABLE "public"."course_result_policies" OWNER TO "postgres";


COMMENT ON TABLE "public"."course_result_policies" IS 'Defines coursework and examination weighting for each course offering.';



CREATE TABLE IF NOT EXISTS "public"."courses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "department_id" "uuid",
    "course_code" character varying(50) NOT NULL,
    "course_name" character varying(200) NOT NULL,
    "course_short_name" character varying(100),
    "credit_units" numeric(6,2) DEFAULT 0 NOT NULL,
    "contact_hours" numeric(6,2),
    "course_type" character varying(50) DEFAULT 'CORE'::character varying NOT NULL,
    "level" character varying(50),
    "description" "text",
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "courses_contact_hours_check" CHECK ((("contact_hours" IS NULL) OR ("contact_hours" >= (0)::numeric))),
    CONSTRAINT "courses_credit_check" CHECK (("credit_units" >= (0)::numeric)),
    CONSTRAINT "courses_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'RETIRED'::character varying, 'ARCHIVED'::character varying])::"text"[]))),
    CONSTRAINT "courses_type_check" CHECK ((("course_type")::"text" = ANY ((ARRAY['CORE'::character varying, 'ELECTIVE'::character varying, 'OPTIONAL'::character varying, 'GENERAL'::character varying, 'PRACTICAL'::character varying, 'FIELD'::character varying, 'CLINICAL'::character varying, 'PROJECT'::character varying, 'OTHER'::character varying])::"text"[])))
);


ALTER TABLE "public"."courses" OWNER TO "postgres";


COMMENT ON TABLE "public"."courses" IS 'Institutional course catalogue.';



CREATE TABLE IF NOT EXISTS "public"."curricula" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "programme_version_id" "uuid" NOT NULL,
    "curriculum_code" character varying(50) NOT NULL,
    "curriculum_name" character varying(200) NOT NULL,
    "effective_from" "date" NOT NULL,
    "effective_to" "date",
    "total_credits" numeric(8,2),
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "curricula_credits_check" CHECK ((("total_credits" IS NULL) OR ("total_credits" >= (0)::numeric))),
    CONSTRAINT "curricula_date_check" CHECK ((("effective_to" IS NULL) OR ("effective_to" >= "effective_from"))),
    CONSTRAINT "curricula_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'ACTIVE'::character varying, 'RETIRED'::character varying, 'ARCHIVED'::character varying])::"text"[])))
);


ALTER TABLE "public"."curricula" OWNER TO "postgres";


COMMENT ON TABLE "public"."curricula" IS 'Curriculum definitions attached to programme versions.';



CREATE TABLE IF NOT EXISTS "public"."curriculum_courses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "curriculum_id" "uuid" NOT NULL,
    "course_id" "uuid" NOT NULL,
    "semester_number" integer NOT NULL,
    "year_number" integer,
    "course_category" character varying(50) DEFAULT 'CORE'::character varying NOT NULL,
    "is_compulsory" boolean DEFAULT true NOT NULL,
    "credit_units" numeric(6,2),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "curriculum_courses_category_check" CHECK ((("course_category")::"text" = ANY ((ARRAY['CORE'::character varying, 'ELECTIVE'::character varying, 'OPTIONAL'::character varying, 'GENERAL'::character varying, 'PRACTICAL'::character varying, 'FIELD'::character varying, 'CLINICAL'::character varying, 'PROJECT'::character varying, 'OTHER'::character varying])::"text"[]))),
    CONSTRAINT "curriculum_courses_credit_check" CHECK ((("credit_units" IS NULL) OR ("credit_units" >= (0)::numeric))),
    CONSTRAINT "curriculum_courses_semester_check" CHECK (("semester_number" > 0)),
    CONSTRAINT "curriculum_courses_year_check" CHECK ((("year_number" IS NULL) OR ("year_number" > 0)))
);


ALTER TABLE "public"."curriculum_courses" OWNER TO "postgres";


COMMENT ON TABLE "public"."curriculum_courses" IS 'Courses and their placement within a curriculum.';



CREATE TABLE IF NOT EXISTS "public"."departments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "school_id" "uuid" NOT NULL,
    "department_code" character varying(30) NOT NULL,
    "department_name" character varying(255) NOT NULL,
    "head_title" character varying(100) DEFAULT 'Head of Department'::character varying,
    "email" character varying(255),
    "phone" character varying(50),
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."departments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."emergency_contacts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "full_name" character varying(200) NOT NULL,
    "relationship" character varying(100) NOT NULL,
    "phone" character varying(50) NOT NULL,
    "alternate_phone" character varying(50),
    "email" character varying(255),
    "address_line_1" character varying(255),
    "city" character varying(100),
    "district" character varying(100),
    "region" character varying(100),
    "country" character varying(100) DEFAULT 'Tanzania'::character varying,
    "is_primary" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."emergency_contacts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."examination_attendance" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "examination_session_id" "uuid" NOT NULL,
    "examination_candidate_id" "uuid" NOT NULL,
    "attendance_status" character varying(30) DEFAULT 'PRESENT'::character varying NOT NULL,
    "check_in_time" timestamp with time zone,
    "seat_number" character varying(30),
    "identity_verified" boolean DEFAULT false NOT NULL,
    "remarks" "text",
    "marked_by" "uuid",
    "marked_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "examination_attendance_attendance_status_check" CHECK ((("attendance_status")::"text" = ANY ((ARRAY['PRESENT'::character varying, 'ABSENT'::character varying, 'LATE'::character varying, 'EXCUSED'::character varying])::"text"[])))
);


ALTER TABLE "public"."examination_attendance" OWNER TO "postgres";


COMMENT ON TABLE "public"."examination_attendance" IS 'Stores candidate attendance during examination sessions.';



CREATE TABLE IF NOT EXISTS "public"."examination_candidate_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "examination_session_id" "uuid" NOT NULL,
    "examination_candidate_id" "uuid" NOT NULL,
    "seat_number" character varying(50),
    "assignment_status" character varying(30) DEFAULT 'ASSIGNED'::character varying NOT NULL,
    "assigned_by" "uuid",
    "assigned_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "examination_candidate_sessions_assignment_status_check" CHECK ((("assignment_status")::"text" = ANY ((ARRAY['ASSIGNED'::character varying, 'CONFIRMED'::character varying, 'MOVED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."examination_candidate_sessions" OWNER TO "postgres";


COMMENT ON TABLE "public"."examination_candidate_sessions" IS 'Controls examination room/session assignment and seating for each candidate.';



CREATE TABLE IF NOT EXISTS "public"."examination_candidates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "examination_paper_id" "uuid" NOT NULL,
    "student_id" "uuid" NOT NULL,
    "course_registration_id" "uuid" NOT NULL,
    "candidate_number" character varying(80),
    "eligibility_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "eligibility_reason" "text",
    "attendance_status" character varying(30) DEFAULT 'NOT_MARKED'::character varying NOT NULL,
    "candidate_status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "examination_candidates_attendance_status_check" CHECK ((("attendance_status")::"text" = ANY ((ARRAY['NOT_MARKED'::character varying, 'PRESENT'::character varying, 'ABSENT'::character varying, 'LATE'::character varying, 'EXCUSED'::character varying])::"text"[]))),
    CONSTRAINT "examination_candidates_candidate_status_check" CHECK ((("candidate_status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'WITHDRAWN'::character varying, 'DEFERRED'::character varying, 'DISQUALIFIED'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "examination_candidates_eligibility_status_check" CHECK ((("eligibility_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'ELIGIBLE'::character varying, 'INELIGIBLE'::character varying, 'WITHHELD'::character varying])::"text"[])))
);


ALTER TABLE "public"."examination_candidates" OWNER TO "postgres";


COMMENT ON TABLE "public"."examination_candidates" IS 'Stores students eligible to sit specific examination papers.';



CREATE TABLE IF NOT EXISTS "public"."examination_invigilators" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "examination_session_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "assignment_role" character varying(30) DEFAULT 'INVIGILATOR'::character varying NOT NULL,
    "status" character varying(30) DEFAULT 'ASSIGNED'::character varying NOT NULL,
    "assigned_by" "uuid",
    "assigned_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "confirmed_at" timestamp with time zone,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "examination_invigilators_assignment_role_check" CHECK ((("assignment_role")::"text" = ANY ((ARRAY['CHIEF_INVIGILATOR'::character varying, 'INVIGILATOR'::character varying, 'RELIEF_INVIGILATOR'::character varying, 'SUPERVISOR'::character varying])::"text"[]))),
    CONSTRAINT "examination_invigilators_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ASSIGNED'::character varying, 'CONFIRMED'::character varying, 'DECLINED'::character varying, 'COMPLETED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."examination_invigilators" OWNER TO "postgres";


COMMENT ON TABLE "public"."examination_invigilators" IS 'Stores invigilator assignments for examination sessions.';



CREATE TABLE IF NOT EXISTS "public"."examination_mark_corrections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "examination_mark_id" "uuid" NOT NULL,
    "requested_by" "uuid",
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "old_marks" numeric(8,2) NOT NULL,
    "new_marks" numeric(8,2) NOT NULL,
    "old_grade" character varying(10),
    "new_grade" character varying(10),
    "reason" "text" NOT NULL,
    "evidence_file_id" "uuid",
    "status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "review_comment" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "examination_mark_corrections_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."examination_mark_corrections" OWNER TO "postgres";


COMMENT ON TABLE "public"."examination_mark_corrections" IS 'Formal approval workflow for correcting examination marks after submission/approval/locking.';



CREATE TABLE IF NOT EXISTS "public"."examination_marks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "examination_paper_id" "uuid" NOT NULL,
    "examination_candidate_id" "uuid" NOT NULL,
    "student_id" "uuid" NOT NULL,
    "course_registration_id" "uuid" NOT NULL,
    "marks" numeric(8,2),
    "percentage" numeric(8,4),
    "grade" character varying(20),
    "remarks" "text",
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "entered_by" "uuid",
    "entered_at" timestamp with time zone,
    "submitted_by" "uuid",
    "submitted_at" timestamp with time zone,
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "locked_by" "uuid",
    "locked_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "examination_marks_marks_check" CHECK (("marks" >= (0)::numeric)),
    CONSTRAINT "examination_marks_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'SUBMITTED'::character varying, 'UNDER_REVIEW'::character varying, 'APPROVED'::character varying, 'LOCKED'::character varying, 'CORRECTION_PENDING'::character varying])::"text"[])))
);


ALTER TABLE "public"."examination_marks" OWNER TO "postgres";


COMMENT ON TABLE "public"."examination_marks" IS 'Stores examination marks prior to integration into the Results Engine.';



CREATE TABLE IF NOT EXISTS "public"."examination_papers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "examination_period_id" "uuid" NOT NULL,
    "course_offering_id" "uuid" NOT NULL,
    "paper_code" character varying(80) NOT NULL,
    "paper_title" character varying(200) NOT NULL,
    "examination_type" character varying(30) DEFAULT 'FINAL'::character varying NOT NULL,
    "maximum_marks" numeric(8,2) DEFAULT 100 NOT NULL,
    "duration_minutes" integer NOT NULL,
    "instructions" "text",
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "locked_by" "uuid",
    "locked_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "examination_papers_duration_minutes_check" CHECK (("duration_minutes" > 0)),
    CONSTRAINT "examination_papers_examination_type_check" CHECK ((("examination_type")::"text" = ANY ((ARRAY['FINAL'::character varying, 'SUPPLEMENTARY'::character varying, 'SPECIAL'::character varying, 'RESIT'::character varying, 'MAKEUP'::character varying])::"text"[]))),
    CONSTRAINT "examination_papers_maximum_marks_check" CHECK (("maximum_marks" > (0)::numeric)),
    CONSTRAINT "examination_papers_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'SCHEDULED'::character varying, 'APPROVED'::character varying, 'PUBLISHED'::character varying, 'COMPLETED'::character varying, 'LOCKED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."examination_papers" OWNER TO "postgres";


COMMENT ON TABLE "public"."examination_papers" IS 'Defines examination papers linked to course offerings.';



CREATE TABLE IF NOT EXISTS "public"."examination_periods" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "academic_year_id" "uuid" NOT NULL,
    "semester_id" "uuid" NOT NULL,
    "period_code" character varying(50) NOT NULL,
    "period_name" character varying(150) NOT NULL,
    "examination_type" character varying(30) DEFAULT 'END_OF_SEMESTER'::character varying NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date" NOT NULL,
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "published_by" "uuid",
    "published_at" timestamp with time zone,
    "locked_by" "uuid",
    "locked_at" timestamp with time zone,
    "notes" "text",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "examination_period_dates_chk" CHECK (("end_date" >= "start_date")),
    CONSTRAINT "examination_periods_examination_type_check" CHECK ((("examination_type")::"text" = ANY ((ARRAY['END_OF_SEMESTER'::character varying, 'MID_SEMESTER'::character varying, 'SUPPLEMENTARY'::character varying, 'SPECIAL'::character varying, 'RESIT'::character varying, 'MAKEUP'::character varying, 'OTHER'::character varying])::"text"[]))),
    CONSTRAINT "examination_periods_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'PLANNING'::character varying, 'APPROVED'::character varying, 'PUBLISHED'::character varying, 'ONGOING'::character varying, 'COMPLETED'::character varying, 'LOCKED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."examination_periods" OWNER TO "postgres";


COMMENT ON TABLE "public"."examination_periods" IS 'Controls examination periods for academic semesters and examination cycles.';



CREATE TABLE IF NOT EXISTS "public"."examination_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "examination_paper_id" "uuid" NOT NULL,
    "campus_id" "uuid" NOT NULL,
    "room_id" "uuid" NOT NULL,
    "examination_date" "date" NOT NULL,
    "start_time" time without time zone NOT NULL,
    "end_time" time without time zone NOT NULL,
    "session_code" character varying(80) NOT NULL,
    "capacity" integer NOT NULL,
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "locked_by" "uuid",
    "locked_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "examination_session_time_chk" CHECK (("end_time" > "start_time")),
    CONSTRAINT "examination_sessions_capacity_check" CHECK (("capacity" > 0)),
    CONSTRAINT "examination_sessions_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'SCHEDULED'::character varying, 'APPROVED'::character varying, 'PUBLISHED'::character varying, 'ONGOING'::character varying, 'COMPLETED'::character varying, 'LOCKED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."examination_sessions" OWNER TO "postgres";


COMMENT ON TABLE "public"."examination_sessions" IS 'Stores examination timetable sessions, rooms, dates and times.';



CREATE TABLE IF NOT EXISTS "public"."fee_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fee_structure_id" "uuid" NOT NULL,
    "fee_item_code" character varying(100) NOT NULL,
    "fee_item_name" character varying(200) NOT NULL,
    "category" character varying(50) DEFAULT 'OTHER'::character varying NOT NULL,
    "description" "text",
    "amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "is_mandatory" boolean DEFAULT true NOT NULL,
    "is_refundable" boolean DEFAULT false NOT NULL,
    "display_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "fee_items_amount_check" CHECK (("amount" >= (0)::numeric)),
    CONSTRAINT "fee_items_category_check" CHECK ((("category")::"text" = ANY ((ARRAY['TUITION'::character varying, 'REGISTRATION'::character varying, 'EXAMINATION'::character varying, 'LIBRARY'::character varying, 'HOSTEL'::character varying, 'MEDICAL'::character varying, 'STUDENT_ID'::character varying, 'ICT'::character varying, 'FIELD_PRACTICAL'::character varying, 'CLINICAL'::character varying, 'GRADUATION'::character varying, 'CERTIFICATION'::character varying, 'LATE_FEE'::character varying, 'OTHER'::character varying])::"text"[])))
);


ALTER TABLE "public"."fee_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fee_structures" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fee_structure_code" character varying(100) NOT NULL,
    "fee_structure_name" character varying(200) NOT NULL,
    "academic_year" character varying(20),
    "semester" character varying(50),
    "description" "text",
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "currency_code" character varying(10) DEFAULT 'TZS'::character varying NOT NULL,
    "effective_from" "date",
    "effective_to" "date",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_fee_structure_dates" CHECK ((("effective_to" IS NULL) OR ("effective_from" IS NULL) OR ("effective_to" >= "effective_from"))),
    CONSTRAINT "fee_structures_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'ACTIVE'::character varying, 'INACTIVE'::character varying, 'ARCHIVED'::character varying])::"text"[])))
);


ALTER TABLE "public"."fee_structures" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."financial_transactions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "transaction_number" character varying(100) NOT NULL,
    "student_id" "uuid",
    "payment_id" "uuid",
    "invoice_id" "uuid",
    "charge_id" "uuid",
    "refund_id" "uuid",
    "transaction_type" character varying(50) NOT NULL,
    "debit_amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "credit_amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "transaction_date" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reference_number" character varying(150),
    "description" "text" NOT NULL,
    "status" character varying(30) DEFAULT 'POSTED'::character varying NOT NULL,
    "reversal_of" "uuid",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_financial_transaction_amount" CHECK ((("debit_amount" > (0)::numeric) OR ("credit_amount" > (0)::numeric))),
    CONSTRAINT "chk_financial_transaction_direction" CHECK ((NOT (("debit_amount" > (0)::numeric) AND ("credit_amount" > (0)::numeric)))),
    CONSTRAINT "financial_transactions_credit_amount_check" CHECK (("credit_amount" >= (0)::numeric)),
    CONSTRAINT "financial_transactions_debit_amount_check" CHECK (("debit_amount" >= (0)::numeric)),
    CONSTRAINT "financial_transactions_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'POSTED'::character varying, 'REVERSED'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "financial_transactions_transaction_type_check" CHECK ((("transaction_type")::"text" = ANY ((ARRAY['CHARGE'::character varying, 'PAYMENT'::character varying, 'PAYMENT_REVERSAL'::character varying, 'REFUND'::character varying, 'SCHOLARSHIP'::character varying, 'WAIVER'::character varying, 'DISCOUNT'::character varying, 'ADJUSTMENT_DEBIT'::character varying, 'ADJUSTMENT_CREDIT'::character varying, 'OPENING_BALANCE'::character varying, 'WRITE_OFF'::character varying])::"text"[])))
);


ALTER TABLE "public"."financial_transactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."grade_scale_details" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "grade_scale_id" "uuid" NOT NULL,
    "grade_code" character varying(10) NOT NULL,
    "grade_name" character varying(100),
    "minimum_mark" numeric(5,2) NOT NULL,
    "maximum_mark" numeric(5,2) NOT NULL,
    "grade_point" numeric(5,2) NOT NULL,
    "pass_status" character varying(20) DEFAULT 'PASS'::character varying NOT NULL,
    "result_classification" character varying(100),
    "status" character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "grade_point_valid" CHECK (("grade_point" >= (0)::numeric)),
    CONSTRAINT "grade_range_order_valid" CHECK (("maximum_mark" >= "minimum_mark")),
    CONSTRAINT "grade_range_valid" CHECK ((("minimum_mark" >= (0)::numeric) AND ("maximum_mark" <= (100)::numeric))),
    CONSTRAINT "grade_scale_details_pass_status_check" CHECK ((("pass_status")::"text" = ANY ((ARRAY['PASS'::character varying, 'FAIL'::character varying, 'SUPPLEMENTARY'::character varying, 'INCOMPLETE'::character varying, 'WITHHELD'::character varying])::"text"[]))),
    CONSTRAINT "grade_scale_details_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'ARCHIVED'::character varying])::"text"[])))
);


ALTER TABLE "public"."grade_scale_details" OWNER TO "postgres";


COMMENT ON TABLE "public"."grade_scale_details" IS 'Individual grade bands and grade points.';



CREATE TABLE IF NOT EXISTS "public"."grade_scales" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "scale_code" character varying(50) NOT NULL,
    "scale_name" character varying(150) NOT NULL,
    "description" "text",
    "minimum_total" numeric(5,2) DEFAULT 0 NOT NULL,
    "maximum_total" numeric(5,2) DEFAULT 100 NOT NULL,
    "status" character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "is_default" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "grade_scales_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'ARCHIVED'::character varying])::"text"[])))
);


ALTER TABLE "public"."grade_scales" OWNER TO "postgres";


COMMENT ON TABLE "public"."grade_scales" IS 'Institutional grading scale definitions.';



CREATE TABLE IF NOT EXISTS "public"."graduation_approvals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "graduation_candidate_id" "uuid" NOT NULL,
    "approval_stage" character varying(40) NOT NULL,
    "decision" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "comments" "text",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "graduation_approvals_decision_chk" CHECK ((("decision")::"text" = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'RETURNED'::character varying])::"text"[]))),
    CONSTRAINT "graduation_approvals_stage_chk" CHECK ((("approval_stage")::"text" = ANY ((ARRAY['DEPARTMENT'::character varying, 'HOD'::character varying, 'ACADEMIC'::character varying, 'EXAMINATION'::character varying, 'MANAGEMENT'::character varying])::"text"[])))
);


ALTER TABLE "public"."graduation_approvals" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."graduation_awards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "graduation_candidate_id" "uuid" NOT NULL,
    "award_name" character varying(200) NOT NULL,
    "award_classification" character varying(100),
    "final_cgpa" numeric(5,2),
    "graduation_date" "date" NOT NULL,
    "certificate_number" character varying(100),
    "transcript_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "graduation_awards_cgpa_chk" CHECK ((("final_cgpa" IS NULL) OR (("final_cgpa" >= (0)::numeric) AND ("final_cgpa" <= (5)::numeric))))
);


ALTER TABLE "public"."graduation_awards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."graduation_candidates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "graduation_period_id" "uuid" NOT NULL,
    "student_id" "uuid" NOT NULL,
    "programme_id" "uuid" NOT NULL,
    "programme_version_id" "uuid",
    "eligibility_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "academic_completion_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "final_cgpa" numeric(5,2),
    "award_classification" character varying(100),
    "candidate_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "eligible_at" timestamp with time zone,
    "approved_at" timestamp with time zone,
    "approved_by" "uuid",
    "remarks" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "graduation_candidates_academic_chk" CHECK ((("academic_completion_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'COMPLETE'::character varying, 'INCOMPLETE'::character varying])::"text"[]))),
    CONSTRAINT "graduation_candidates_cgpa_chk" CHECK ((("final_cgpa" IS NULL) OR (("final_cgpa" >= (0)::numeric) AND ("final_cgpa" <= (5)::numeric)))),
    CONSTRAINT "graduation_candidates_eligibility_chk" CHECK ((("eligibility_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'ELIGIBLE'::character varying, 'INELIGIBLE'::character varying, 'REVIEW'::character varying])::"text"[]))),
    CONSTRAINT "graduation_candidates_status_chk" CHECK ((("candidate_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'CLEARED'::character varying, 'APPROVED'::character varying, 'GRADUATED'::character varying, 'WITHDRAWN'::character varying, 'REJECTED'::character varying])::"text"[])))
);


ALTER TABLE "public"."graduation_candidates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."graduation_clearance_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "graduation_clearance_id" "uuid" NOT NULL,
    "item_code" character varying(50),
    "item_name" character varying(200) NOT NULL,
    "status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "amount_due" numeric(14,2) DEFAULT 0 NOT NULL,
    "amount_cleared" numeric(14,2) DEFAULT 0 NOT NULL,
    "remarks" "text",
    "resolved_by" "uuid",
    "resolved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "graduation_clearance_items_amount_chk" CHECK ((("amount_due" >= (0)::numeric) AND ("amount_cleared" >= (0)::numeric))),
    CONSTRAINT "graduation_clearance_items_status_chk" CHECK ((("status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'CLEARED'::character varying, 'NOT_CLEARED'::character varying, 'WAIVED'::character varying])::"text"[])))
);


ALTER TABLE "public"."graduation_clearance_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."graduation_clearances" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "graduation_candidate_id" "uuid" NOT NULL,
    "clearance_type" character varying(30) NOT NULL,
    "status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "amount_due" numeric(14,2) DEFAULT 0 NOT NULL,
    "amount_cleared" numeric(14,2) DEFAULT 0 NOT NULL,
    "remarks" "text",
    "cleared_by" "uuid",
    "cleared_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "graduation_clearances_amount_chk" CHECK ((("amount_due" >= (0)::numeric) AND ("amount_cleared" >= (0)::numeric))),
    CONSTRAINT "graduation_clearances_status_chk" CHECK ((("status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'CLEARED'::character varying, 'NOT_CLEARED'::character varying, 'WAIVED'::character varying])::"text"[]))),
    CONSTRAINT "graduation_clearances_type_chk" CHECK ((("clearance_type")::"text" = ANY ((ARRAY['ACADEMIC'::character varying, 'FINANCE'::character varying, 'LIBRARY'::character varying, 'HOSTEL'::character varying, 'DEPARTMENT'::character varying, 'DISCIPLINE'::character varying, 'DOCUMENTS'::character varying])::"text"[])))
);


ALTER TABLE "public"."graduation_clearances" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."graduation_periods" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "academic_year_id" "uuid" NOT NULL,
    "graduation_number" character varying(50) NOT NULL,
    "graduation_name" character varying(200) NOT NULL,
    "graduation_date" "date" NOT NULL,
    "application_open_at" timestamp with time zone,
    "application_close_at" timestamp with time zone,
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "remarks" "text",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "graduation_periods_dates_chk" CHECK ((("application_close_at" IS NULL) OR ("application_open_at" IS NULL) OR ("application_close_at" >= "application_open_at"))),
    CONSTRAINT "graduation_periods_status_chk" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'OPEN'::character varying, 'CLOSED'::character varying, 'APPROVED'::character varying, 'COMPLETED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."graduation_periods" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."guardians" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "full_name" character varying(200) NOT NULL,
    "relationship" character varying(100) NOT NULL,
    "phone" character varying(50),
    "alternate_phone" character varying(50),
    "email" character varying(255),
    "occupation" character varying(150),
    "organisation" character varying(200),
    "address_line_1" character varying(255),
    "address_line_2" character varying(255),
    "city" character varying(100),
    "district" character varying(100),
    "region" character varying(100),
    "country" character varying(100) DEFAULT 'Tanzania'::character varying,
    "is_primary" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."guardians" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."hostel_allocations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "hostel_id" "uuid" NOT NULL,
    "room_id" "uuid" NOT NULL,
    "bed_id" "uuid",
    "academic_year" character varying(20) NOT NULL,
    "allocation_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "move_in_date" "date",
    "move_out_date" "date",
    "allocation_status" character varying(30) DEFAULT 'ALLOCATED'::character varying NOT NULL,
    "remarks" "text",
    "allocated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_hostel_allocation_dates" CHECK ((("move_out_date" IS NULL) OR ("move_in_date" IS NULL) OR ("move_out_date" >= "move_in_date"))),
    CONSTRAINT "hostel_allocations_allocation_status_check" CHECK ((("allocation_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'ALLOCATED'::character varying, 'ACTIVE'::character varying, 'CANCELLED'::character varying, 'VACATED'::character varying])::"text"[])))
);


ALTER TABLE "public"."hostel_allocations" OWNER TO "postgres";


COMMENT ON TABLE "public"."hostel_allocations" IS 'Student hostel accommodation allocations.';



CREATE TABLE IF NOT EXISTS "public"."hostel_beds" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "room_id" "uuid" NOT NULL,
    "bed_number" character varying(50) NOT NULL,
    "bed_status" character varying(20) DEFAULT 'AVAILABLE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "hostel_beds_bed_status_check" CHECK ((("bed_status")::"text" = ANY ((ARRAY['AVAILABLE'::character varying, 'OCCUPIED'::character varying, 'RESERVED'::character varying, 'MAINTENANCE'::character varying, 'INACTIVE'::character varying])::"text"[])))
);


ALTER TABLE "public"."hostel_beds" OWNER TO "postgres";


COMMENT ON TABLE "public"."hostel_beds" IS 'Beds available for hostel allocation.';



CREATE TABLE IF NOT EXISTS "public"."hostel_fees" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "hostel_id" "uuid",
    "academic_year" character varying(20) NOT NULL,
    "fee_name" character varying(150) NOT NULL,
    "amount" numeric(14,2) NOT NULL,
    "currency" character varying(10) DEFAULT 'TZS'::character varying NOT NULL,
    "status" character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "hostel_fees_amount_check" CHECK (("amount" >= (0)::numeric)),
    CONSTRAINT "hostel_fees_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying])::"text"[])))
);


ALTER TABLE "public"."hostel_fees" OWNER TO "postgres";


COMMENT ON TABLE "public"."hostel_fees" IS 'Hostel accommodation fee configurations.';



CREATE TABLE IF NOT EXISTS "public"."hostel_rooms" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "hostel_id" "uuid" NOT NULL,
    "room_number" character varying(50) NOT NULL,
    "floor_number" integer,
    "room_type" character varying(30) DEFAULT 'STANDARD'::character varying NOT NULL,
    "capacity" integer DEFAULT 1 NOT NULL,
    "status" character varying(20) DEFAULT 'AVAILABLE'::character varying NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "hostel_rooms_capacity_check" CHECK (("capacity" > 0)),
    CONSTRAINT "hostel_rooms_room_type_check" CHECK ((("room_type")::"text" = ANY ((ARRAY['STANDARD'::character varying, 'SINGLE'::character varying, 'DOUBLE'::character varying, 'TRIPLE'::character varying, 'DORMITORY'::character varying, 'OTHER'::character varying])::"text"[]))),
    CONSTRAINT "hostel_rooms_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['AVAILABLE'::character varying, 'FULL'::character varying, 'MAINTENANCE'::character varying, 'BLOCKED'::character varying, 'INACTIVE'::character varying])::"text"[])))
);


ALTER TABLE "public"."hostel_rooms" OWNER TO "postgres";


COMMENT ON TABLE "public"."hostel_rooms" IS 'Rooms within institutional hostels.';



CREATE TABLE IF NOT EXISTS "public"."hostels" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "hostel_code" character varying(60) NOT NULL,
    "hostel_name" character varying(150) NOT NULL,
    "hostel_type" character varying(30) DEFAULT 'GENERAL'::character varying NOT NULL,
    "capacity" integer DEFAULT 0 NOT NULL,
    "location" character varying(255),
    "warden_user_id" "uuid",
    "status" character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "description" "text",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "hostels_capacity_check" CHECK (("capacity" >= 0)),
    CONSTRAINT "hostels_hostel_type_check" CHECK ((("hostel_type")::"text" = ANY ((ARRAY['MALE'::character varying, 'FEMALE'::character varying, 'MIXED'::character varying, 'GENERAL'::character varying])::"text"[]))),
    CONSTRAINT "hostels_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'CLOSED'::character varying])::"text"[])))
);


ALTER TABLE "public"."hostels" OWNER TO "postgres";


COMMENT ON TABLE "public"."hostels" IS 'Institutional hostel/accommodation facilities.';



CREATE OR REPLACE VIEW "public"."hostel_occupancy_summary" AS
 SELECT "h"."id" AS "hostel_id",
    "h"."institution_id",
    "h"."hostel_code",
    "h"."hostel_name",
    "h"."capacity",
    "count"(DISTINCT "hr"."id") AS "total_rooms",
    "count"(DISTINCT "hb"."id") AS "total_beds",
    "count"(DISTINCT
        CASE
            WHEN (("hb"."bed_status")::"text" = 'OCCUPIED'::"text") THEN "hb"."id"
            ELSE NULL::"uuid"
        END) AS "occupied_beds",
    "count"(DISTINCT
        CASE
            WHEN (("hb"."bed_status")::"text" = 'AVAILABLE'::"text") THEN "hb"."id"
            ELSE NULL::"uuid"
        END) AS "available_beds"
   FROM (("public"."hostels" "h"
     LEFT JOIN "public"."hostel_rooms" "hr" ON (("hr"."hostel_id" = "h"."id")))
     LEFT JOIN "public"."hostel_beds" "hb" ON (("hb"."room_id" = "hr"."id")))
  GROUP BY "h"."id", "h"."institution_id", "h"."hostel_code", "h"."hostel_name", "h"."capacity";


ALTER VIEW "public"."hostel_occupancy_summary" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."institutions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_code" character varying(30) NOT NULL,
    "institution_name" character varying(255) NOT NULL,
    "short_name" character varying(100),
    "registration_number" character varying(100),
    "accreditation_number" character varying(100),
    "institution_type" character varying(50),
    "ownership_type" character varying(50),
    "email" character varying(255),
    "phone" character varying(50),
    "website" character varying(255),
    "physical_address" "text",
    "postal_address" "text",
    "city" character varying(100),
    "region" character varying(100),
    "country" character varying(100) DEFAULT 'Tanzania'::character varying,
    "logo_url" "text",
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."institutions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory_categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "category_code" character varying(60) NOT NULL,
    "category_name" character varying(150) NOT NULL,
    "description" "text",
    "status" character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inventory_categories_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying])::"text"[])))
);


ALTER TABLE "public"."inventory_categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "category_id" "uuid",
    "item_code" character varying(80) NOT NULL,
    "item_name" character varying(255) NOT NULL,
    "description" "text",
    "unit_of_measure" character varying(50) DEFAULT 'UNIT'::character varying NOT NULL,
    "minimum_stock_level" numeric(14,2) DEFAULT 0 NOT NULL,
    "maximum_stock_level" numeric(14,2),
    "reorder_level" numeric(14,2) DEFAULT 0 NOT NULL,
    "current_quantity" numeric(14,2) DEFAULT 0 NOT NULL,
    "unit_cost" numeric(14,2) DEFAULT 0 NOT NULL,
    "storage_location" character varying(255),
    "status" character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inventory_items_check" CHECK ((("maximum_stock_level" IS NULL) OR ("maximum_stock_level" >= "minimum_stock_level"))),
    CONSTRAINT "inventory_items_current_quantity_check" CHECK (("current_quantity" >= (0)::numeric)),
    CONSTRAINT "inventory_items_minimum_stock_level_check" CHECK (("minimum_stock_level" >= (0)::numeric)),
    CONSTRAINT "inventory_items_reorder_level_check" CHECK (("reorder_level" >= (0)::numeric)),
    CONSTRAINT "inventory_items_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'DISCONTINUED'::character varying])::"text"[]))),
    CONSTRAINT "inventory_items_unit_cost_check" CHECK (("unit_cost" >= (0)::numeric))
);


ALTER TABLE "public"."inventory_items" OWNER TO "postgres";


COMMENT ON TABLE "public"."inventory_items" IS 'Consumable and stock-controlled institutional items.';



CREATE OR REPLACE VIEW "public"."inventory_stock_summary" AS
 SELECT "id",
    "institution_id",
    "category_id",
    "item_code",
    "item_name",
    "unit_of_measure",
    "minimum_stock_level",
    "maximum_stock_level",
    "reorder_level",
    "current_quantity",
    "unit_cost",
        CASE
            WHEN ("current_quantity" <= "reorder_level") THEN true
            ELSE false
        END AS "reorder_required",
    "storage_location",
    "status",
    "created_at",
    "updated_at"
   FROM "public"."inventory_items" "ii";


ALTER VIEW "public"."inventory_stock_summary" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory_transactions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "inventory_item_id" "uuid" NOT NULL,
    "transaction_type" character varying(30) NOT NULL,
    "transaction_number" character varying(80) NOT NULL,
    "quantity" numeric(14,2) NOT NULL,
    "unit_cost" numeric(14,2) DEFAULT 0 NOT NULL,
    "reference_type" character varying(50),
    "reference_id" "uuid",
    "transaction_date" timestamp with time zone DEFAULT "now"() NOT NULL,
    "balance_before" numeric(14,2) DEFAULT 0 NOT NULL,
    "balance_after" numeric(14,2) DEFAULT 0 NOT NULL,
    "performed_by" "uuid",
    "remarks" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inventory_transactions_balance_after_check" CHECK (("balance_after" >= (0)::numeric)),
    CONSTRAINT "inventory_transactions_balance_before_check" CHECK (("balance_before" >= (0)::numeric)),
    CONSTRAINT "inventory_transactions_quantity_check" CHECK (("quantity" > (0)::numeric)),
    CONSTRAINT "inventory_transactions_transaction_type_check" CHECK ((("transaction_type")::"text" = ANY ((ARRAY['RECEIPT'::character varying, 'ISSUE'::character varying, 'RETURN'::character varying, 'ADJUSTMENT_IN'::character varying, 'ADJUSTMENT_OUT'::character varying, 'TRANSFER'::character varying])::"text"[]))),
    CONSTRAINT "inventory_transactions_unit_cost_check" CHECK (("unit_cost" >= (0)::numeric))
);


ALTER TABLE "public"."inventory_transactions" OWNER TO "postgres";


COMMENT ON TABLE "public"."inventory_transactions" IS 'Inventory receipt, issue, return and adjustment transactions.';



CREATE TABLE IF NOT EXISTS "public"."invoice_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "invoice_id" "uuid" NOT NULL,
    "student_charge_id" "uuid",
    "description" character varying(255) NOT NULL,
    "quantity" numeric(12,2) DEFAULT 1 NOT NULL,
    "unit_amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "discount_amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "line_total" numeric(18,2) GENERATED ALWAYS AS ((("quantity" * "unit_amount") - "discount_amount")) STORED,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_invoice_item_discount" CHECK (("discount_amount" <= ("quantity" * "unit_amount"))),
    CONSTRAINT "invoice_items_discount_amount_check" CHECK (("discount_amount" >= (0)::numeric)),
    CONSTRAINT "invoice_items_quantity_check" CHECK (("quantity" > (0)::numeric)),
    CONSTRAINT "invoice_items_unit_amount_check" CHECK (("unit_amount" >= (0)::numeric))
);


ALTER TABLE "public"."invoice_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."invoices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "invoice_number" character varying(100) NOT NULL,
    "invoice_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "due_date" "date",
    "academic_year" character varying(20),
    "semester" character varying(50),
    "subtotal" numeric(18,2) DEFAULT 0 NOT NULL,
    "discount_amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "scholarship_amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "adjustment_amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "total_amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "amount_paid" numeric(18,2) DEFAULT 0 NOT NULL,
    "balance_amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "currency_code" character varying(10) DEFAULT 'TZS'::character varying NOT NULL,
    "notes" "text",
    "issued_by" "uuid",
    "issued_at" timestamp with time zone,
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_invoice_balance" CHECK (("balance_amount" = ("total_amount" - "amount_paid"))),
    CONSTRAINT "chk_invoice_dates" CHECK ((("due_date" IS NULL) OR ("due_date" >= "invoice_date"))),
    CONSTRAINT "chk_invoice_paid_not_exceed_total" CHECK (("amount_paid" <= "total_amount")),
    CONSTRAINT "invoices_amount_paid_check" CHECK (("amount_paid" >= (0)::numeric)),
    CONSTRAINT "invoices_balance_amount_check" CHECK (("balance_amount" >= (0)::numeric)),
    CONSTRAINT "invoices_discount_amount_check" CHECK (("discount_amount" >= (0)::numeric)),
    CONSTRAINT "invoices_scholarship_amount_check" CHECK (("scholarship_amount" >= (0)::numeric)),
    CONSTRAINT "invoices_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'ISSUED'::character varying, 'PARTIALLY_PAID'::character varying, 'PAID'::character varying, 'OVERDUE'::character varying, 'CANCELLED'::character varying, 'VOID'::character varying])::"text"[]))),
    CONSTRAINT "invoices_subtotal_check" CHECK (("subtotal" >= (0)::numeric)),
    CONSTRAINT "invoices_total_amount_check" CHECK (("total_amount" >= (0)::numeric))
);


ALTER TABLE "public"."invoices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."joining_instructions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "academic_year_id" "uuid" NOT NULL,
    "programme_id" "uuid",
    "title" character varying(255) NOT NULL,
    "description" "text",
    "document_url" "text",
    "version_number" integer DEFAULT 1 NOT NULL,
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "published_at" timestamp with time zone,
    "published_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "joining_instructions_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'PUBLISHED'::character varying, 'ARCHIVED'::character varying])::"text"[]))),
    CONSTRAINT "joining_instructions_version_check" CHECK (("version_number" > 0))
);


ALTER TABLE "public"."joining_instructions" OWNER TO "postgres";


COMMENT ON TABLE "public"."joining_instructions" IS 'Published joining instructions by academic year and programme.';



CREATE TABLE IF NOT EXISTS "public"."lecturer_assignments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_offering_id" "uuid" NOT NULL,
    "class_id" "uuid",
    "lecturer_user_id" "uuid" NOT NULL,
    "assignment_role" character varying(40) DEFAULT 'LECTURER'::character varying NOT NULL,
    "workload_hours" numeric(8,2) DEFAULT 0 NOT NULL,
    "assignment_status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "assigned_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "assigned_by" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_lecturer_assignment_role" CHECK ((("assignment_role")::"text" = ANY ((ARRAY['LECTURER'::character varying, 'CO_LECTURER'::character varying, 'TUTOR'::character varying, 'LAB_INSTRUCTOR'::character varying, 'CLINICAL_SUPERVISOR'::character varying])::"text"[]))),
    CONSTRAINT "chk_lecturer_assignment_status" CHECK ((("assignment_status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'COMPLETED'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "chk_lecturer_workload" CHECK (("workload_hours" >= (0)::numeric))
);


ALTER TABLE "public"."lecturer_assignments" OWNER TO "postgres";


COMMENT ON TABLE "public"."lecturer_assignments" IS 'Lecturer and teaching staff assignments to course offerings/classes.';



CREATE TABLE IF NOT EXISTS "public"."library_fines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "loan_id" "uuid" NOT NULL,
    "member_id" "uuid" NOT NULL,
    "fine_type" character varying(30) NOT NULL,
    "amount" numeric(14,2) NOT NULL,
    "amount_paid" numeric(14,2) DEFAULT 0 NOT NULL,
    "currency" character varying(10) DEFAULT 'TZS'::character varying NOT NULL,
    "fine_status" character varying(20) DEFAULT 'OUTSTANDING'::character varying NOT NULL,
    "reason" "text",
    "waived_by" "uuid",
    "waived_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "library_fines_amount_check" CHECK (("amount" >= (0)::numeric)),
    CONSTRAINT "library_fines_check" CHECK ((("amount_paid" >= (0)::numeric) AND ("amount_paid" <= "amount"))),
    CONSTRAINT "library_fines_fine_status_check" CHECK ((("fine_status")::"text" = ANY ((ARRAY['OUTSTANDING'::character varying, 'PARTIALLY_PAID'::character varying, 'PAID'::character varying, 'WAIVED'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "library_fines_fine_type_check" CHECK ((("fine_type")::"text" = ANY ((ARRAY['OVERDUE'::character varying, 'LOST_ITEM'::character varying, 'DAMAGED_ITEM'::character varying, 'OTHER'::character varying])::"text"[])))
);


ALTER TABLE "public"."library_fines" OWNER TO "postgres";


COMMENT ON TABLE "public"."library_fines" IS 'Library overdue, lost and damaged item fines.';



CREATE TABLE IF NOT EXISTS "public"."library_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "accession_number" character varying(80) NOT NULL,
    "title" character varying(500) NOT NULL,
    "subtitle" character varying(500),
    "item_type" character varying(40) DEFAULT 'BOOK'::character varying NOT NULL,
    "isbn" character varying(50),
    "author" character varying(500),
    "publisher" character varying(255),
    "publication_year" integer,
    "edition" character varying(100),
    "subject" character varying(255),
    "call_number" character varying(100),
    "language" character varying(100) DEFAULT 'English'::character varying,
    "total_copies" integer DEFAULT 1 NOT NULL,
    "available_copies" integer DEFAULT 1 NOT NULL,
    "location" character varying(255),
    "item_status" character varying(30) DEFAULT 'AVAILABLE'::character varying NOT NULL,
    "description" "text",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "library_items_check" CHECK ((("available_copies" >= 0) AND ("available_copies" <= "total_copies"))),
    CONSTRAINT "library_items_item_status_check" CHECK ((("item_status")::"text" = ANY ((ARRAY['AVAILABLE'::character varying, 'PARTIALLY_AVAILABLE'::character varying, 'OUT_OF_STOCK'::character varying, 'LOST'::character varying, 'DAMAGED'::character varying, 'ARCHIVED'::character varying, 'INACTIVE'::character varying])::"text"[]))),
    CONSTRAINT "library_items_item_type_check" CHECK ((("item_type")::"text" = ANY ((ARRAY['BOOK'::character varying, 'JOURNAL'::character varying, 'REFERENCE'::character varying, 'THESIS'::character varying, 'DISSERTATION'::character varying, 'REPORT'::character varying, 'E_RESOURCE'::character varying, 'OTHER'::character varying])::"text"[]))),
    CONSTRAINT "library_items_total_copies_check" CHECK (("total_copies" >= 0))
);


ALTER TABLE "public"."library_items" OWNER TO "postgres";


COMMENT ON TABLE "public"."library_items" IS 'Library books, journals, references and other resources.';



CREATE OR REPLACE VIEW "public"."library_inventory_summary" AS
 SELECT "id",
    "institution_id",
    "accession_number",
    "title",
    "item_type",
    "isbn",
    "author",
    "publisher",
    "publication_year",
    "subject",
    "call_number",
    "total_copies",
    "available_copies",
    ("total_copies" - "available_copies") AS "issued_copies",
    "item_status",
    "created_at",
    "updated_at"
   FROM "public"."library_items" "li";


ALTER VIEW "public"."library_inventory_summary" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."library_loan_number_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."library_loan_number_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."library_loans" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "library_member_id" "uuid" NOT NULL,
    "library_item_id" "uuid" NOT NULL,
    "loan_number" character varying(80) NOT NULL,
    "loan_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "due_date" "date" NOT NULL,
    "return_date" "date",
    "quantity" integer DEFAULT 1 NOT NULL,
    "loan_status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "issued_by" "uuid",
    "returned_to" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_library_loan_dates" CHECK (("due_date" >= "loan_date")),
    CONSTRAINT "chk_library_return_date" CHECK ((("return_date" IS NULL) OR ("return_date" >= "loan_date"))),
    CONSTRAINT "library_loans_loan_status_check" CHECK ((("loan_status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'RETURNED'::character varying, 'OVERDUE'::character varying, 'LOST'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "library_loans_quantity_check" CHECK (("quantity" > 0))
);


ALTER TABLE "public"."library_loans" OWNER TO "postgres";


COMMENT ON TABLE "public"."library_loans" IS 'Library borrowing and return transactions.';



CREATE TABLE IF NOT EXISTS "public"."library_members" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "student_id" "uuid",
    "staff_id" "uuid",
    "membership_number" character varying(80) NOT NULL,
    "membership_type" character varying(30) NOT NULL,
    "membership_status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "registration_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "expiry_date" "date",
    "max_active_loans" integer DEFAULT 3 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_library_member_expiry" CHECK ((("expiry_date" IS NULL) OR ("expiry_date" >= "registration_date"))),
    CONSTRAINT "chk_library_member_owner" CHECK ((("student_id" IS NOT NULL) OR ("staff_id" IS NOT NULL))),
    CONSTRAINT "library_members_max_active_loans_check" CHECK (("max_active_loans" > 0)),
    CONSTRAINT "library_members_membership_status_check" CHECK ((("membership_status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'SUSPENDED'::character varying, 'EXPIRED'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "library_members_membership_type_check" CHECK ((("membership_type")::"text" = ANY ((ARRAY['STUDENT'::character varying, 'STAFF'::character varying, 'OTHER'::character varying])::"text"[])))
);


ALTER TABLE "public"."library_members" OWNER TO "postgres";


COMMENT ON TABLE "public"."library_members" IS 'Institutional library membership records.';



CREATE TABLE IF NOT EXISTS "public"."library_reservations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "library_member_id" "uuid" NOT NULL,
    "library_item_id" "uuid" NOT NULL,
    "reservation_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "expiry_date" "date",
    "reservation_status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "fulfilled_at" timestamp with time zone,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_library_reservation_dates" CHECK ((("expiry_date" IS NULL) OR ("expiry_date" >= "reservation_date"))),
    CONSTRAINT "library_reservations_reservation_status_check" CHECK ((("reservation_status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'FULFILLED'::character varying, 'EXPIRED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."library_reservations" OWNER TO "postgres";


COMMENT ON TABLE "public"."library_reservations" IS 'Library material reservation records.';



CREATE TABLE IF NOT EXISTS "public"."notification_deliveries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "notification_id" "uuid" NOT NULL,
    "channel" character varying(30) NOT NULL,
    "provider" character varying(100),
    "provider_message_id" character varying(255),
    "destination_masked" character varying(255),
    "status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "attempt_count" integer DEFAULT 0 NOT NULL,
    "last_attempt_at" timestamp with time zone,
    "delivered_at" timestamp with time zone,
    "failed_at" timestamp with time zone,
    "error_code" character varying(100),
    "error_message" "text",
    "provider_response" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notification_deliveries_attempt_check" CHECK (("attempt_count" >= 0)),
    CONSTRAINT "notification_deliveries_channel_check" CHECK ((("channel")::"text" = ANY ((ARRAY['IN_APP'::character varying, 'EMAIL'::character varying, 'SMS'::character varying, 'PUSH'::character varying])::"text"[]))),
    CONSTRAINT "notification_deliveries_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'QUEUED'::character varying, 'SENDING'::character varying, 'SENT'::character varying, 'DELIVERED'::character varying, 'FAILED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."notification_deliveries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notification_queue" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "notification_id" "uuid" NOT NULL,
    "delivery_id" "uuid",
    "available_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "locked_at" timestamp with time zone,
    "locked_by" character varying(255),
    "attempt_count" integer DEFAULT 0 NOT NULL,
    "max_attempts" integer DEFAULT 5 NOT NULL,
    "status" character varying(30) DEFAULT 'QUEUED'::character varying NOT NULL,
    "last_error" "text",
    "completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notification_queue_attempt_check" CHECK (("attempt_count" >= 0)),
    CONSTRAINT "notification_queue_attempt_limit_check" CHECK (("attempt_count" <= "max_attempts")),
    CONSTRAINT "notification_queue_max_attempts_check" CHECK (("max_attempts" > 0)),
    CONSTRAINT "notification_queue_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['QUEUED'::character varying, 'PROCESSING'::character varying, 'COMPLETED'::character varying, 'FAILED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."notification_queue" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notification_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "template_code" character varying(100) NOT NULL,
    "template_name" character varying(200) NOT NULL,
    "channel" character varying(30) NOT NULL,
    "subject_template" "text",
    "body_template" "text" NOT NULL,
    "description" "text",
    "language_code" character varying(20) DEFAULT 'en'::character varying NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "version" integer DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notification_templates_channel_check" CHECK ((("channel")::"text" = ANY ((ARRAY['IN_APP'::character varying, 'EMAIL'::character varying, 'SMS'::character varying, 'PUSH'::character varying])::"text"[]))),
    CONSTRAINT "notification_templates_code_check" CHECK (("length"(TRIM(BOTH FROM "template_code")) > 0)),
    CONSTRAINT "notification_templates_language_check" CHECK (("length"(TRIM(BOTH FROM "language_code")) > 0)),
    CONSTRAINT "notification_templates_name_check" CHECK (("length"(TRIM(BOTH FROM "template_name")) > 0)),
    CONSTRAINT "notification_templates_version_check" CHECK (("version" > 0))
);


ALTER TABLE "public"."notification_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "notification_number" character varying(100) NOT NULL,
    "recipient_user_id" "uuid",
    "recipient_student_id" "uuid",
    "template_id" "uuid",
    "notification_type" character varying(50) NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "priority" character varying(20) DEFAULT 'NORMAL'::character varying NOT NULL,
    "status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "scheduled_at" timestamp with time zone,
    "sent_at" timestamp with time zone,
    "read_at" timestamp with time zone,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notifications_priority_check" CHECK ((("priority")::"text" = ANY ((ARRAY['LOW'::character varying, 'NORMAL'::character varying, 'HIGH'::character varying, 'URGENT'::character varying])::"text"[]))),
    CONSTRAINT "notifications_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'QUEUED'::character varying, 'PROCESSING'::character varying, 'SENT'::character varying, 'DELIVERED'::character varying, 'READ'::character varying, 'FAILED'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "notifications_title_check" CHECK (("length"(TRIM(BOTH FROM "title")) > 0)),
    CONSTRAINT "notifications_type_check" CHECK (("length"(TRIM(BOTH FROM "notification_type")) > 0))
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payment_allocations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "payment_id" "uuid" NOT NULL,
    "invoice_id" "uuid",
    "student_charge_id" "uuid",
    "allocated_amount" numeric(18,2) NOT NULL,
    "allocation_date" timestamp with time zone DEFAULT "now"() NOT NULL,
    "allocation_reference" character varying(100),
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_payment_allocation_target" CHECK ((("invoice_id" IS NOT NULL) OR ("student_charge_id" IS NOT NULL))),
    CONSTRAINT "payment_allocations_allocated_amount_check" CHECK (("allocated_amount" > (0)::numeric)),
    CONSTRAINT "payment_allocations_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'REVERSED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."payment_allocations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "payment_number" character varying(100) NOT NULL,
    "external_reference" character varying(150),
    "control_number" character varying(100),
    "payment_method" character varying(50) NOT NULL,
    "provider" character varying(100),
    "amount" numeric(18,2) NOT NULL,
    "currency_code" character varying(10) DEFAULT 'TZS'::character varying NOT NULL,
    "payment_date" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "payer_name" character varying(200),
    "payer_phone" character varying(50),
    "payer_email" character varying(255),
    "provider_transaction_id" character varying(200),
    "receipt_number" character varying(100),
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "confirmed_by" "uuid",
    "confirmed_at" timestamp with time zone,
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "payments_amount_check" CHECK (("amount" > (0)::numeric)),
    CONSTRAINT "payments_payment_method_check" CHECK ((("payment_method")::"text" = ANY ((ARRAY['CASH'::character varying, 'BANK'::character varying, 'MOBILE_MONEY'::character varying, 'CARD'::character varying, 'CONTROL_NUMBER'::character varying, 'ONLINE'::character varying, 'SCHOLARSHIP'::character varying, 'WAIVER'::character varying, 'ADJUSTMENT'::character varying, 'OTHER'::character varying])::"text"[]))),
    CONSTRAINT "payments_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'CONFIRMED'::character varying, 'FAILED'::character varying, 'REVERSED'::character varying, 'REFUNDED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."payments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."permissions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "permission_code" character varying(150) NOT NULL,
    "permission_name" character varying(200) NOT NULL,
    "module_code" character varying(100) NOT NULL,
    "action_code" character varying(50) NOT NULL,
    "description" "text",
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "permissions_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying])::"text"[])))
);


ALTER TABLE "public"."permissions" OWNER TO "postgres";


COMMENT ON TABLE "public"."permissions" IS 'Fine-grained permissions for IDMC iMIS modules and actions, including Finance.';



CREATE TABLE IF NOT EXISTS "public"."procurement_request_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "procurement_request_id" "uuid" NOT NULL,
    "item_description" "text" NOT NULL,
    "quantity" numeric(12,2) NOT NULL,
    "unit_of_measure" character varying(50) DEFAULT 'UNIT'::character varying NOT NULL,
    "estimated_unit_price" numeric(14,2) DEFAULT 0 NOT NULL,
    "estimated_total" numeric(14,2) GENERATED ALWAYS AS (("quantity" * "estimated_unit_price")) STORED,
    "specifications" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "procurement_request_items_estimated_unit_price_check" CHECK (("estimated_unit_price" >= (0)::numeric)),
    CONSTRAINT "procurement_request_items_quantity_check" CHECK (("quantity" > (0)::numeric))
);


ALTER TABLE "public"."procurement_request_items" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."procurement_request_number_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."procurement_request_number_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."procurement_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "request_number" character varying(60) NOT NULL,
    "requested_by" "uuid",
    "department_id" "uuid",
    "request_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "required_date" "date",
    "priority" character varying(20) DEFAULT 'NORMAL'::character varying NOT NULL,
    "request_status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "purpose" "text" NOT NULL,
    "estimated_total" numeric(14,2) DEFAULT 0 NOT NULL,
    "justification" "text",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "rejection_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_procurement_request_dates" CHECK ((("required_date" IS NULL) OR ("required_date" >= "request_date"))),
    CONSTRAINT "procurement_requests_estimated_total_check" CHECK (("estimated_total" >= (0)::numeric)),
    CONSTRAINT "procurement_requests_priority_check" CHECK ((("priority")::"text" = ANY ((ARRAY['LOW'::character varying, 'NORMAL'::character varying, 'HIGH'::character varying, 'URGENT'::character varying])::"text"[]))),
    CONSTRAINT "procurement_requests_request_status_check" CHECK ((("request_status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'SUBMITTED'::character varying, 'UNDER_REVIEW'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying, 'FULFILLED'::character varying, 'CLOSED'::character varying])::"text"[])))
);


ALTER TABLE "public"."procurement_requests" OWNER TO "postgres";


COMMENT ON TABLE "public"."procurement_requests" IS 'Internal procurement requests raised by institutional users.';



CREATE OR REPLACE VIEW "public"."procurement_request_summary" AS
 SELECT "id",
    "request_number",
    "institution_id",
    "department_id",
    "requested_by",
    "request_date",
    "required_date",
    "priority",
    "request_status",
    "purpose",
    "estimated_total",
    "approved_by",
    "approved_at",
    "created_at",
    "updated_at"
   FROM "public"."procurement_requests" "pr";


ALTER VIEW "public"."procurement_request_summary" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."programme_versions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "programme_id" "uuid" NOT NULL,
    "version_code" character varying(50) NOT NULL,
    "version_name" character varying(150),
    "effective_from" "date" NOT NULL,
    "effective_to" "date",
    "total_credits" numeric(8,2),
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "programme_versions_credits_check" CHECK ((("total_credits" IS NULL) OR ("total_credits" >= (0)::numeric))),
    CONSTRAINT "programme_versions_date_check" CHECK ((("effective_to" IS NULL) OR ("effective_to" >= "effective_from"))),
    CONSTRAINT "programme_versions_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'ACTIVE'::character varying, 'RETIRED'::character varying, 'ARCHIVED'::character varying])::"text"[])))
);


ALTER TABLE "public"."programme_versions" OWNER TO "postgres";


COMMENT ON TABLE "public"."programme_versions" IS 'Versioned academic programme definitions.';



CREATE TABLE IF NOT EXISTS "public"."programmes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "school_id" "uuid",
    "department_id" "uuid",
    "programme_code" character varying(50) NOT NULL,
    "programme_name" character varying(200) NOT NULL,
    "programme_type" character varying(50) DEFAULT 'ACADEMIC'::character varying NOT NULL,
    "award_level" character varying(50) NOT NULL,
    "duration_years" numeric(4,2),
    "mode_of_study" character varying(50) DEFAULT 'FULL_TIME'::character varying NOT NULL,
    "description" "text",
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "programmes_mode_check" CHECK ((("mode_of_study")::"text" = ANY ((ARRAY['FULL_TIME'::character varying, 'PART_TIME'::character varying, 'EVENING'::character varying, 'WEEKEND'::character varying, 'DISTANCE'::character varying, 'ONLINE'::character varying, 'BLENDED'::character varying])::"text"[]))),
    CONSTRAINT "programmes_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'SUSPENDED'::character varying, 'ARCHIVED'::character varying])::"text"[]))),
    CONSTRAINT "programmes_type_check" CHECK ((("programme_type")::"text" = ANY ((ARRAY['ACADEMIC'::character varying, 'PROFESSIONAL'::character varying, 'SHORT_COURSE'::character varying, 'CERTIFICATE'::character varying, 'OTHER'::character varying])::"text"[])))
);


ALTER TABLE "public"."programmes" OWNER TO "postgres";


COMMENT ON TABLE "public"."programmes" IS 'Academic programmes offered by the institution.';



CREATE TABLE IF NOT EXISTS "public"."purchase_order_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "purchase_order_id" "uuid" NOT NULL,
    "item_description" "text" NOT NULL,
    "quantity" numeric(12,2) NOT NULL,
    "unit_of_measure" character varying(50) DEFAULT 'UNIT'::character varying NOT NULL,
    "unit_price" numeric(14,2) DEFAULT 0 NOT NULL,
    "tax_amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "discount_amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "line_total" numeric(14,2) GENERATED ALWAYS AS (((("quantity" * "unit_price") + "tax_amount") - "discount_amount")) STORED,
    "specifications" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "purchase_order_items_discount_amount_check" CHECK (("discount_amount" >= (0)::numeric)),
    CONSTRAINT "purchase_order_items_quantity_check" CHECK (("quantity" > (0)::numeric)),
    CONSTRAINT "purchase_order_items_tax_amount_check" CHECK (("tax_amount" >= (0)::numeric)),
    CONSTRAINT "purchase_order_items_unit_price_check" CHECK (("unit_price" >= (0)::numeric))
);


ALTER TABLE "public"."purchase_order_items" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."purchase_order_number_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."purchase_order_number_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."purchase_orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "procurement_request_id" "uuid",
    "supplier_id" "uuid" NOT NULL,
    "purchase_order_number" character varying(60) NOT NULL,
    "order_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "expected_delivery_date" "date",
    "currency" character varying(10) DEFAULT 'TZS'::character varying NOT NULL,
    "subtotal" numeric(14,2) DEFAULT 0 NOT NULL,
    "tax_amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "discount_amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "total_amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "order_status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "created_by" "uuid",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_purchase_order_dates" CHECK ((("expected_delivery_date" IS NULL) OR ("expected_delivery_date" >= "order_date"))),
    CONSTRAINT "purchase_orders_discount_amount_check" CHECK (("discount_amount" >= (0)::numeric)),
    CONSTRAINT "purchase_orders_order_status_check" CHECK ((("order_status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'PENDING_APPROVAL'::character varying, 'APPROVED'::character varying, 'SENT'::character varying, 'PARTIALLY_RECEIVED'::character varying, 'RECEIVED'::character varying, 'CANCELLED'::character varying, 'CLOSED'::character varying])::"text"[]))),
    CONSTRAINT "purchase_orders_subtotal_check" CHECK (("subtotal" >= (0)::numeric)),
    CONSTRAINT "purchase_orders_tax_amount_check" CHECK (("tax_amount" >= (0)::numeric)),
    CONSTRAINT "purchase_orders_total_amount_check" CHECK (("total_amount" >= (0)::numeric))
);


ALTER TABLE "public"."purchase_orders" OWNER TO "postgres";


COMMENT ON TABLE "public"."purchase_orders" IS 'Purchase orders issued to approved suppliers.';



CREATE TABLE IF NOT EXISTS "public"."refunds" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "payment_id" "uuid" NOT NULL,
    "student_id" "uuid" NOT NULL,
    "refund_number" character varying(100) NOT NULL,
    "amount" numeric(18,2) NOT NULL,
    "reason" "text" NOT NULL,
    "refund_method" character varying(50),
    "status" character varying(30) DEFAULT 'REQUESTED'::character varying NOT NULL,
    "requested_by" "uuid",
    "approved_by" "uuid",
    "processed_by" "uuid",
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "approved_at" timestamp with time zone,
    "processed_at" timestamp with time zone,
    "external_reference" character varying(150),
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "refunds_amount_check" CHECK (("amount" > (0)::numeric)),
    CONSTRAINT "refunds_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['REQUESTED'::character varying, 'APPROVED'::character varying, 'PROCESSING'::character varying, 'PAID'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."refunds" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."registration_approvals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_registration_id" "uuid" NOT NULL,
    "approval_level" integer NOT NULL,
    "approval_role" character varying(80) NOT NULL,
    "approval_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "comments" "text",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "rejected_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_approval_level" CHECK (("approval_level" > 0)),
    CONSTRAINT "chk_registration_approval_status" CHECK ((("approval_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'SKIPPED'::character varying])::"text"[])))
);


ALTER TABLE "public"."registration_approvals" OWNER TO "postgres";


COMMENT ON TABLE "public"."registration_approvals" IS 'Approval workflow for student academic registration.';



CREATE TABLE IF NOT EXISTS "public"."role_permissions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "role_id" "uuid" NOT NULL,
    "permission_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."role_permissions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."roles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "role_code" character varying(80) NOT NULL,
    "role_name" character varying(150) NOT NULL,
    "description" "text",
    "is_system_role" boolean DEFAULT false NOT NULL,
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "roles_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying])::"text"[])))
);


ALTER TABLE "public"."roles" OWNER TO "postgres";


COMMENT ON TABLE "public"."roles" IS 'System roles used by the IDMC iMIS RBAC framework.';



CREATE TABLE IF NOT EXISTS "public"."rooms" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campus_id" "uuid" NOT NULL,
    "room_code" character varying(50) NOT NULL,
    "room_name" character varying(150) NOT NULL,
    "room_type" character varying(40) DEFAULT 'LECTURE_ROOM'::character varying NOT NULL,
    "capacity" integer DEFAULT 0 NOT NULL,
    "building_name" character varying(150),
    "floor_number" character varying(30),
    "location_description" "text",
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_room_capacity" CHECK (("capacity" >= 0)),
    CONSTRAINT "chk_room_status" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'MAINTENANCE'::character varying, 'CLOSED'::character varying])::"text"[]))),
    CONSTRAINT "chk_room_type" CHECK ((("room_type")::"text" = ANY ((ARRAY['LECTURE_ROOM'::character varying, 'LABORATORY'::character varying, 'COMPUTER_LAB'::character varying, 'SEMINAR_ROOM'::character varying, 'HALL'::character varying, 'OFFICE'::character varying, 'CLINICAL_ROOM'::character varying, 'OTHER'::character varying])::"text"[]))),
    CONSTRAINT "rooms_capacity_positive" CHECK ((("capacity" IS NULL) OR ("capacity" > 0)))
);


ALTER TABLE "public"."rooms" OWNER TO "postgres";


COMMENT ON TABLE "public"."rooms" IS 'Academic and operational rooms available for teaching and timetable allocation.';



CREATE TABLE IF NOT EXISTS "public"."schools" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "campus_id" "uuid",
    "school_code" character varying(30) NOT NULL,
    "school_name" character varying(255) NOT NULL,
    "dean_title" character varying(100) DEFAULT 'Dean'::character varying,
    "email" character varying(255),
    "phone" character varying(50),
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."schools" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."security_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "event_code" character varying(100) NOT NULL,
    "success" boolean DEFAULT true NOT NULL,
    "ip_address" "inet",
    "user_agent" "text",
    "details" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."security_logs" OWNER TO "postgres";


COMMENT ON TABLE "public"."security_logs" IS 'Security and authentication event history.';



CREATE TABLE IF NOT EXISTS "public"."semesters" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "academic_year_id" "uuid" NOT NULL,
    "semester_code" character varying(30) NOT NULL,
    "semester_name" character varying(100) NOT NULL,
    "semester_number" integer NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date" NOT NULL,
    "status" character varying(30) DEFAULT 'PLANNED'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "semesters_date_check" CHECK (("end_date" > "start_date")),
    CONSTRAINT "semesters_number_check" CHECK (("semester_number" > 0)),
    CONSTRAINT "semesters_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['PLANNED'::character varying, 'ACTIVE'::character varying, 'CLOSED'::character varying, 'ARCHIVED'::character varying])::"text"[])))
);


ALTER TABLE "public"."semesters" OWNER TO "postgres";


COMMENT ON TABLE "public"."semesters" IS 'Academic periods belonging to an academic year.';



CREATE TABLE IF NOT EXISTS "public"."staff" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "department_id" "uuid",
    "employee_number" character varying(50) NOT NULL,
    "staff_category" character varying(40) DEFAULT 'ADMINISTRATIVE'::character varying NOT NULL,
    "employment_type" character varying(40) DEFAULT 'FULL_TIME'::character varying NOT NULL,
    "employment_status" character varying(40) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "first_name" character varying(100) NOT NULL,
    "middle_name" character varying(100),
    "last_name" character varying(100) NOT NULL,
    "gender" character varying(20),
    "date_of_birth" "date",
    "nationality" character varying(100) DEFAULT 'Tanzanian'::character varying,
    "national_id" character varying(100),
    "passport_number" character varying(100),
    "marital_status" character varying(30),
    "phone" character varying(50),
    "email" character varying(255),
    "physical_address" "text",
    "postal_address" "text",
    "job_title" character varying(150),
    "appointment_date" "date",
    "confirmation_date" "date",
    "contract_start_date" "date",
    "contract_end_date" "date",
    "highest_qualification" character varying(255),
    "professional_registration_number" character varying(150),
    "emergency_contact_name" character varying(200),
    "emergency_contact_phone" character varying(50),
    "emergency_contact_relationship" character varying(100),
    "profile_photo_url" "text",
    "notes" "text",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "staff_employment_status_check" CHECK ((("employment_status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'ON_LEAVE'::character varying, 'SUSPENDED'::character varying, 'RESIGNED'::character varying, 'TERMINATED'::character varying, 'RETIRED'::character varying, 'INACTIVE'::character varying])::"text"[]))),
    CONSTRAINT "staff_employment_type_check" CHECK ((("employment_type")::"text" = ANY ((ARRAY['FULL_TIME'::character varying, 'PART_TIME'::character varying, 'CONTRACT'::character varying, 'TEMPORARY'::character varying, 'VOLUNTEER'::character varying, 'INTERNSHIP'::character varying, 'OTHER'::character varying])::"text"[]))),
    CONSTRAINT "staff_gender_check" CHECK ((("gender" IS NULL) OR (("gender")::"text" = ANY ((ARRAY['MALE'::character varying, 'FEMALE'::character varying, 'OTHER'::character varying])::"text"[])))),
    CONSTRAINT "staff_marital_status_check" CHECK ((("marital_status" IS NULL) OR (("marital_status")::"text" = ANY ((ARRAY['SINGLE'::character varying, 'MARRIED'::character varying, 'DIVORCED'::character varying, 'WIDOWED'::character varying, 'OTHER'::character varying])::"text"[])))),
    CONSTRAINT "staff_staff_category_check" CHECK ((("staff_category")::"text" = ANY ((ARRAY['ACADEMIC'::character varying, 'ADMINISTRATIVE'::character varying, 'CLINICAL'::character varying, 'TECHNICAL'::character varying, 'SUPPORT'::character varying, 'MANAGEMENT'::character varying, 'OTHER'::character varying])::"text"[])))
);


ALTER TABLE "public"."staff" OWNER TO "postgres";


COMMENT ON TABLE "public"."staff" IS 'Core institutional staff records.';



CREATE TABLE IF NOT EXISTS "public"."staff_attendance" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "staff_id" "uuid" NOT NULL,
    "attendance_date" "date" NOT NULL,
    "attendance_status" character varying(30) DEFAULT 'PRESENT'::character varying NOT NULL,
    "check_in" time without time zone,
    "check_out" time without time zone,
    "late_minutes" integer DEFAULT 0 NOT NULL,
    "worked_minutes" integer,
    "source" character varying(30) DEFAULT 'MANUAL'::character varying NOT NULL,
    "location" character varying(255),
    "remarks" "text",
    "marked_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_staff_attendance_time" CHECK ((("check_out" IS NULL) OR ("check_in" IS NULL) OR ("check_out" >= "check_in"))),
    CONSTRAINT "staff_attendance_attendance_status_check" CHECK ((("attendance_status")::"text" = ANY ((ARRAY['PRESENT'::character varying, 'ABSENT'::character varying, 'LATE'::character varying, 'HALF_DAY'::character varying, 'REMOTE'::character varying, 'ON_LEAVE'::character varying, 'OFF_DUTY'::character varying])::"text"[]))),
    CONSTRAINT "staff_attendance_late_minutes_check" CHECK (("late_minutes" >= 0)),
    CONSTRAINT "staff_attendance_source_check" CHECK ((("source")::"text" = ANY ((ARRAY['MANUAL'::character varying, 'DEVICE'::character varying, 'IMPORT'::character varying, 'SYSTEM'::character varying])::"text"[]))),
    CONSTRAINT "staff_attendance_worked_minutes_check" CHECK ((("worked_minutes" IS NULL) OR ("worked_minutes" >= 0)))
);


ALTER TABLE "public"."staff_attendance" OWNER TO "postgres";


COMMENT ON TABLE "public"."staff_attendance" IS 'Daily attendance records for institutional staff.';



CREATE TABLE IF NOT EXISTS "public"."staff_attendance_adjustments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "attendance_id" "uuid" NOT NULL,
    "requested_by" "uuid",
    "reviewed_by" "uuid",
    "old_status" character varying(30),
    "new_status" character varying(30),
    "old_check_in" time without time zone,
    "new_check_in" time without time zone,
    "old_check_out" time without time zone,
    "new_check_out" time without time zone,
    "adjustment_reason" "text" NOT NULL,
    "adjustment_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "reviewed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "staff_attendance_adjustments_adjustment_status_check" CHECK ((("adjustment_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."staff_attendance_adjustments" OWNER TO "postgres";


COMMENT ON TABLE "public"."staff_attendance_adjustments" IS 'Controlled corrections to staff attendance records.';



CREATE OR REPLACE VIEW "public"."staff_attendance_summary" AS
 SELECT "sa"."id",
    "sa"."staff_id",
    "s"."employee_number",
    TRIM(BOTH FROM "concat_ws"(' '::"text", "s"."first_name", "s"."middle_name", "s"."last_name")) AS "staff_name",
    "s"."department_id",
    "sa"."attendance_date",
    "sa"."attendance_status",
    "sa"."check_in",
    "sa"."check_out",
    "sa"."late_minutes",
    "sa"."worked_minutes",
    "sa"."source",
    "sa"."location",
    "sa"."remarks",
    "sa"."created_at",
    "sa"."updated_at"
   FROM ("public"."staff_attendance" "sa"
     JOIN "public"."staff" "s" ON (("s"."id" = "sa"."staff_id")));


ALTER VIEW "public"."staff_attendance_summary" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."staff_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "staff_id" "uuid" NOT NULL,
    "document_type" character varying(100) NOT NULL,
    "document_name" character varying(255) NOT NULL,
    "document_url" "text",
    "storage_path" "text",
    "document_number" character varying(150),
    "issue_date" "date",
    "expiry_date" "date",
    "verification_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "verification_notes" "text",
    "verified_by" "uuid",
    "verified_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "staff_documents_verification_status_check" CHECK ((("verification_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'VERIFIED'::character varying, 'REJECTED'::character varying, 'EXPIRED'::character varying])::"text"[])))
);


ALTER TABLE "public"."staff_documents" OWNER TO "postgres";


COMMENT ON TABLE "public"."staff_documents" IS 'Documents associated with staff records.';



CREATE SEQUENCE IF NOT EXISTS "public"."staff_employee_number_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."staff_employee_number_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."staff_employment_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "staff_id" "uuid" NOT NULL,
    "department_id" "uuid",
    "job_title" character varying(150),
    "employment_type" character varying(40) DEFAULT 'FULL_TIME'::character varying NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date",
    "reason_for_change" character varying(255),
    "notes" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "staff_employment_history_employment_type_check" CHECK ((("employment_type")::"text" = ANY ((ARRAY['FULL_TIME'::character varying, 'PART_TIME'::character varying, 'CONTRACT'::character varying, 'TEMPORARY'::character varying, 'VOLUNTEER'::character varying, 'INTERNSHIP'::character varying, 'OTHER'::character varying])::"text"[])))
);


ALTER TABLE "public"."staff_employment_history" OWNER TO "postgres";


COMMENT ON TABLE "public"."staff_employment_history" IS 'Historical staff employment and assignment records.';



CREATE TABLE IF NOT EXISTS "public"."staff_leave_approvals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "leave_request_id" "uuid" NOT NULL,
    "approval_level" integer NOT NULL,
    "approver_user_id" "uuid",
    "decision" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "approved_days" numeric(6,2),
    "comments" "text",
    "actioned_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "staff_leave_approvals_approval_level_check" CHECK (("approval_level" > 0)),
    CONSTRAINT "staff_leave_approvals_decision_check" CHECK ((("decision")::"text" = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'RETURNED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."staff_leave_approvals" OWNER TO "postgres";


COMMENT ON TABLE "public"."staff_leave_approvals" IS 'Approval workflow for staff leave requests.';



CREATE TABLE IF NOT EXISTS "public"."staff_leave_balances" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "staff_id" "uuid" NOT NULL,
    "leave_type_id" "uuid" NOT NULL,
    "leave_year" integer NOT NULL,
    "opening_balance" numeric(6,2) DEFAULT 0 NOT NULL,
    "accrued_days" numeric(6,2) DEFAULT 0 NOT NULL,
    "carried_forward_days" numeric(6,2) DEFAULT 0 NOT NULL,
    "used_days" numeric(6,2) DEFAULT 0 NOT NULL,
    "pending_days" numeric(6,2) DEFAULT 0 NOT NULL,
    "closing_adjustment" numeric(6,2) DEFAULT 0 NOT NULL,
    "available_balance" numeric(6,2) GENERATED ALWAYS AS (((((("opening_balance" + "accrued_days") + "carried_forward_days") + "closing_adjustment") - "used_days") - "pending_days")) STORED,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "staff_leave_balances_accrued_days_check" CHECK (("accrued_days" >= (0)::numeric)),
    CONSTRAINT "staff_leave_balances_carried_forward_days_check" CHECK (("carried_forward_days" >= (0)::numeric)),
    CONSTRAINT "staff_leave_balances_opening_balance_check" CHECK (("opening_balance" >= (0)::numeric)),
    CONSTRAINT "staff_leave_balances_pending_days_check" CHECK (("pending_days" >= (0)::numeric)),
    CONSTRAINT "staff_leave_balances_used_days_check" CHECK (("used_days" >= (0)::numeric))
);


ALTER TABLE "public"."staff_leave_balances" OWNER TO "postgres";


COMMENT ON TABLE "public"."staff_leave_balances" IS 'Annual staff leave balances by leave type.';



CREATE SEQUENCE IF NOT EXISTS "public"."staff_leave_request_number_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."staff_leave_request_number_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."staff_leave_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "staff_id" "uuid" NOT NULL,
    "leave_type_id" "uuid" NOT NULL,
    "leave_year" integer NOT NULL,
    "request_number" character varying(60) NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date" NOT NULL,
    "days_requested" numeric(6,2) NOT NULL,
    "reason" "text" NOT NULL,
    "attachment_url" "text",
    "request_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "submitted_at" timestamp with time zone,
    "approved_days" numeric(6,2) DEFAULT 0 NOT NULL,
    "rejection_reason" "text",
    "current_approver_user_id" "uuid",
    "final_approved_by" "uuid",
    "final_approved_at" timestamp with time zone,
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_leave_approved_days" CHECK (("approved_days" <= "days_requested")),
    CONSTRAINT "chk_leave_request_dates" CHECK (("end_date" >= "start_date")),
    CONSTRAINT "staff_leave_requests_approved_days_check" CHECK (("approved_days" >= (0)::numeric)),
    CONSTRAINT "staff_leave_requests_days_requested_check" CHECK (("days_requested" > (0)::numeric)),
    CONSTRAINT "staff_leave_requests_request_status_check" CHECK ((("request_status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'PENDING'::character varying, 'APPROVED'::character varying, 'PARTIALLY_APPROVED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying, 'WITHDRAWN'::character varying])::"text"[])))
);


ALTER TABLE "public"."staff_leave_requests" OWNER TO "postgres";


COMMENT ON TABLE "public"."staff_leave_requests" IS 'Staff leave requests and approval state.';



CREATE TABLE IF NOT EXISTS "public"."staff_leave_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "leave_code" character varying(50) NOT NULL,
    "leave_name" character varying(150) NOT NULL,
    "annual_entitlement" numeric(6,2) DEFAULT 0 NOT NULL,
    "requires_document" boolean DEFAULT false NOT NULL,
    "requires_approval" boolean DEFAULT true NOT NULL,
    "paid_leave" boolean DEFAULT true NOT NULL,
    "carry_forward_allowed" boolean DEFAULT false NOT NULL,
    "max_carry_forward_days" numeric(6,2) DEFAULT 0 NOT NULL,
    "status" character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "description" "text",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "staff_leave_types_annual_entitlement_check" CHECK (("annual_entitlement" >= (0)::numeric)),
    CONSTRAINT "staff_leave_types_max_carry_forward_days_check" CHECK (("max_carry_forward_days" >= (0)::numeric)),
    CONSTRAINT "staff_leave_types_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying])::"text"[])))
);


ALTER TABLE "public"."staff_leave_types" OWNER TO "postgres";


COMMENT ON TABLE "public"."staff_leave_types" IS 'Institutional staff leave categories and entitlement rules.';



CREATE OR REPLACE VIEW "public"."staff_leave_summary" AS
 SELECT "lr"."id",
    "lr"."request_number",
    "lr"."staff_id",
    TRIM(BOTH FROM "concat_ws"(' '::"text", "s"."first_name", "s"."middle_name", "s"."last_name")) AS "staff_name",
    "s"."employee_number",
    "lr"."leave_type_id",
    "lt"."leave_code",
    "lt"."leave_name",
    "lr"."leave_year",
    "lr"."start_date",
    "lr"."end_date",
    "lr"."days_requested",
    "lr"."approved_days",
    "lr"."request_status",
    "lr"."submitted_at",
    "lr"."final_approved_at",
    "lr"."created_at",
    "lr"."updated_at"
   FROM (("public"."staff_leave_requests" "lr"
     JOIN "public"."staff" "s" ON (("s"."id" = "lr"."staff_id")))
     JOIN "public"."staff_leave_types" "lt" ON (("lt"."id" = "lr"."leave_type_id")));


ALTER VIEW "public"."staff_leave_summary" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."staff_lifecycle_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "staff_id" "uuid" NOT NULL,
    "event_type" character varying(50) NOT NULL,
    "effective_date" "date" NOT NULL,
    "previous_status" character varying(40),
    "new_status" character varying(40),
    "previous_department_id" "uuid",
    "new_department_id" "uuid",
    "previous_job_title" character varying(150),
    "new_job_title" character varying(150),
    "reason" "text",
    "reference_number" character varying(100),
    "notes" "text",
    "recorded_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "staff_lifecycle_events_event_type_check" CHECK ((("event_type")::"text" = ANY ((ARRAY['HIRED'::character varying, 'APPOINTED'::character varying, 'CONFIRMED'::character varying, 'PROMOTED'::character varying, 'TRANSFERRED'::character varying, 'DEPARTMENT_CHANGED'::character varying, 'ROLE_CHANGED'::character varying, 'CONTRACT_STARTED'::character varying, 'CONTRACT_RENEWED'::character varying, 'CONTRACT_ENDED'::character varying, 'SUSPENDED'::character varying, 'RETURNED_FROM_SUSPENSION'::character varying, 'RESIGNED'::character varying, 'TERMINATED'::character varying, 'RETIRED'::character varying, 'RETURNED_FROM_LEAVE'::character varying, 'REACTIVATED'::character varying, 'STATUS_CHANGED'::character varying, 'OTHER'::character varying])::"text"[])))
);


ALTER TABLE "public"."staff_lifecycle_events" OWNER TO "postgres";


COMMENT ON TABLE "public"."staff_lifecycle_events" IS 'Chronological employment lifecycle events for staff.';



CREATE TABLE IF NOT EXISTS "public"."staff_qualifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "staff_id" "uuid" NOT NULL,
    "qualification_level" character varying(100) NOT NULL,
    "qualification_name" character varying(255) NOT NULL,
    "institution_name" character varying(255),
    "field_of_study" character varying(255),
    "start_year" integer,
    "completion_year" integer,
    "certificate_number" character varying(150),
    "verification_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "verification_notes" "text",
    "verified_by" "uuid",
    "verified_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "staff_qualifications_verification_status_check" CHECK ((("verification_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'VERIFIED'::character varying, 'REJECTED'::character varying])::"text"[])))
);


ALTER TABLE "public"."staff_qualifications" OWNER TO "postgres";


COMMENT ON TABLE "public"."staff_qualifications" IS 'Professional and academic qualifications of staff.';



CREATE OR REPLACE VIEW "public"."staff_summary" AS
 SELECT "s"."id",
    "s"."employee_number",
    "s"."institution_id",
    "s"."user_id",
    "s"."department_id",
    TRIM(BOTH FROM "concat_ws"(' '::"text", "s"."first_name", "s"."middle_name", "s"."last_name")) AS "staff_name",
    "s"."staff_category",
    "s"."employment_type",
    "s"."employment_status",
    "s"."gender",
    "s"."phone",
    "s"."email",
    "s"."job_title",
    "s"."appointment_date",
    "s"."confirmation_date",
    "d"."department_name",
    "s"."created_at",
    "s"."updated_at"
   FROM ("public"."staff" "s"
     LEFT JOIN "public"."departments" "d" ON (("d"."id" = "s"."department_id")));


ALTER VIEW "public"."staff_summary" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."student_academic_deficiencies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "course_id" "uuid",
    "course_offering_id" "uuid",
    "course_result_id" "uuid",
    "deficiency_type" character varying(40) NOT NULL,
    "deficiency_status" character varying(30) DEFAULT 'OPEN'::character varying NOT NULL,
    "first_recorded_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone,
    "resolution_course_result_id" "uuid",
    "remarks" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "student_academic_deficiencies_deficiency_status_check" CHECK ((("deficiency_status")::"text" = ANY ((ARRAY['OPEN'::character varying, 'IN_PROGRESS'::character varying, 'RESOLVED'::character varying, 'WAIVED'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "student_academic_deficiencies_deficiency_type_check" CHECK ((("deficiency_type")::"text" = ANY ((ARRAY['FAILED'::character varying, 'SUPPLEMENTARY_REQUIRED'::character varying, 'RETAKE_REQUIRED'::character varying, 'REPEAT_REQUIRED'::character varying, 'CARRY_FORWARD'::character varying, 'INCOMPLETE'::character varying, 'WITHHELD'::character varying])::"text"[])))
);


ALTER TABLE "public"."student_academic_deficiencies" OWNER TO "postgres";


COMMENT ON TABLE "public"."student_academic_deficiencies" IS 'Tracks failed, supplementary, repeat, carry-forward, incomplete and withheld academic obligations.';



CREATE TABLE IF NOT EXISTS "public"."student_cgpa_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "academic_year_id" "uuid",
    "semester_id" "uuid",
    "cumulative_credits" numeric(10,2) DEFAULT 0 NOT NULL,
    "cumulative_earned_credits" numeric(10,2) DEFAULT 0 NOT NULL,
    "cumulative_quality_points" numeric(12,3) DEFAULT 0 NOT NULL,
    "cgpa" numeric(6,3) DEFAULT 0 NOT NULL,
    "calculation_version" character varying(30) DEFAULT '1.0'::character varying NOT NULL,
    "calculated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "student_cgpa_range" CHECK ((("cgpa" >= (0)::numeric) AND ("cgpa" <= (5)::numeric)))
);


ALTER TABLE "public"."student_cgpa_records" OWNER TO "postgres";


COMMENT ON TABLE "public"."student_cgpa_records" IS 'Cumulative GPA snapshots used for transcripts and graduation.';



CREATE TABLE IF NOT EXISTS "public"."student_charges" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "fee_structure_id" "uuid",
    "fee_item_id" "uuid",
    "charge_number" character varying(100) NOT NULL,
    "description" character varying(255) NOT NULL,
    "academic_year" character varying(20),
    "semester" character varying(50),
    "original_amount" numeric(18,2) NOT NULL,
    "scholarship_amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "waiver_amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "adjustment_amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "net_amount" numeric(18,2) GENERATED ALWAYS AS (((("original_amount" - "scholarship_amount") - "waiver_amount") + "adjustment_amount")) STORED,
    "status" character varying(30) DEFAULT 'POSTED'::character varying NOT NULL,
    "charge_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "due_date" "date",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_student_charge_discount" CHECK ((("scholarship_amount" + "waiver_amount") <= "original_amount")),
    CONSTRAINT "chk_student_charge_due_date" CHECK ((("due_date" IS NULL) OR ("due_date" >= "charge_date"))),
    CONSTRAINT "chk_student_charge_net" CHECK (("net_amount" >= (0)::numeric)),
    CONSTRAINT "student_charges_original_amount_check" CHECK (("original_amount" >= (0)::numeric)),
    CONSTRAINT "student_charges_scholarship_amount_check" CHECK (("scholarship_amount" >= (0)::numeric)),
    CONSTRAINT "student_charges_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'POSTED'::character varying, 'PARTIALLY_PAID'::character varying, 'PAID'::character varying, 'WAIVED'::character varying, 'CANCELLED'::character varying, 'REVERSED'::character varying])::"text"[]))),
    CONSTRAINT "student_charges_waiver_amount_check" CHECK (("waiver_amount" >= (0)::numeric))
);


ALTER TABLE "public"."student_charges" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."student_course_attempts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "course_id" "uuid",
    "course_offering_id" "uuid",
    "course_registration_id" "uuid",
    "course_result_id" "uuid",
    "academic_year_id" "uuid" NOT NULL,
    "semester_id" "uuid" NOT NULL,
    "attempt_number" integer DEFAULT 1 NOT NULL,
    "attempt_type" character varying(30) DEFAULT 'NORMAL'::character varying NOT NULL,
    "attempt_status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "total_mark" numeric(8,2),
    "grade_code" character varying(10),
    "grade_point" numeric(5,2),
    "credits" numeric(6,2),
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "remarks" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "course_attempt_grade_point_valid" CHECK ((("grade_point" IS NULL) OR ("grade_point" >= (0)::numeric))),
    CONSTRAINT "course_attempt_mark_valid" CHECK ((("total_mark" IS NULL) OR (("total_mark" >= (0)::numeric) AND ("total_mark" <= (100)::numeric)))),
    CONSTRAINT "course_attempt_number_valid" CHECK (("attempt_number" > 0)),
    CONSTRAINT "student_course_attempts_attempt_status_check" CHECK ((("attempt_status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'PASSED'::character varying, 'FAILED'::character varying, 'REPLACED'::character varying, 'WITHDRAWN'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "student_course_attempts_attempt_type_check" CHECK ((("attempt_type")::"text" = ANY ((ARRAY['NORMAL'::character varying, 'SUPPLEMENTARY'::character varying, 'SPECIAL'::character varying, 'RESIT'::character varying, 'RETAKE'::character varying, 'REPEAT'::character varying, 'CARRY_FORWARD'::character varying, 'MAKEUP'::character varying])::"text"[])))
);


ALTER TABLE "public"."student_course_attempts" OWNER TO "postgres";


COMMENT ON TABLE "public"."student_course_attempts" IS 'Historical record of every academic attempt made by a student for a course.';



CREATE TABLE IF NOT EXISTS "public"."student_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "document_type" character varying(100) NOT NULL,
    "document_number" character varying(150),
    "file_url" "text",
    "file_name" character varying(255),
    "mime_type" character varying(100),
    "verification_status" character varying(40) DEFAULT 'PENDING'::character varying NOT NULL,
    "verified_by" "uuid",
    "verified_at" timestamp with time zone,
    "verification_notes" "text",
    "uploaded_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_student_document_verification" CHECK ((("verification_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'VERIFIED'::character varying, 'REJECTED'::character varying, 'EXPIRED'::character varying])::"text"[])))
);


ALTER TABLE "public"."student_documents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."student_fee_adjustments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "student_charge_id" "uuid",
    "adjustment_number" character varying(100) NOT NULL,
    "adjustment_type" character varying(30) NOT NULL,
    "amount" numeric(18,2) NOT NULL,
    "reason" "text" NOT NULL,
    "status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "requested_by" "uuid",
    "approved_by" "uuid",
    "posted_by" "uuid",
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "approved_at" timestamp with time zone,
    "posted_at" timestamp with time zone,
    "reference_number" character varying(100),
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "student_fee_adjustments_adjustment_type_check" CHECK ((("adjustment_type")::"text" = ANY ((ARRAY['DISCOUNT'::character varying, 'WAIVER'::character varying, 'SURCHARGE'::character varying, 'CORRECTION'::character varying, 'CREDIT'::character varying, 'DEBIT'::character varying])::"text"[]))),
    CONSTRAINT "student_fee_adjustments_amount_check" CHECK (("amount" > (0)::numeric)),
    CONSTRAINT "student_fee_adjustments_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'POSTED'::character varying, 'REJECTED'::character varying, 'REVERSED'::character varying])::"text"[])))
);


ALTER TABLE "public"."student_fee_adjustments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."student_financial_accounts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "total_charged" numeric(14,2) DEFAULT 0 NOT NULL,
    "total_paid" numeric(14,2) DEFAULT 0 NOT NULL,
    "total_refunded" numeric(14,2) DEFAULT 0 NOT NULL,
    "total_scholarship" numeric(14,2) DEFAULT 0 NOT NULL,
    "total_waiver" numeric(14,2) DEFAULT 0 NOT NULL,
    "total_adjustments" numeric(14,2) DEFAULT 0 NOT NULL,
    "account_status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "last_calculated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "current_balance" numeric GENERATED ALWAYS AS ((("total_charged" - "total_paid") + "total_refunded")) STORED,
    CONSTRAINT "chk_financial_totals_nonnegative" CHECK ((("total_charged" >= (0)::numeric) AND ("total_paid" >= (0)::numeric) AND ("total_refunded" >= (0)::numeric) AND ("total_scholarship" >= (0)::numeric) AND ("total_waiver" >= (0)::numeric))),
    CONSTRAINT "chk_student_financial_account_amounts" CHECK ((("total_charged" >= (0)::numeric) AND ("total_paid" >= (0)::numeric) AND ("total_refunded" >= (0)::numeric) AND ("total_scholarship" >= (0)::numeric) AND ("total_waiver" >= (0)::numeric))),
    CONSTRAINT "student_financial_accounts_account_status_check" CHECK ((("account_status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'SUSPENDED'::character varying, 'CLOSED'::character varying])::"text"[])))
);


ALTER TABLE "public"."student_financial_accounts" OWNER TO "postgres";


COMMENT ON COLUMN "public"."student_financial_accounts"."total_charged" IS 'Authoritative net student charges based on student_charges.net_amount.';



COMMENT ON COLUMN "public"."student_financial_accounts"."total_scholarship" IS 'Informational aggregate of scholarships already reflected in net charges.';



COMMENT ON COLUMN "public"."student_financial_accounts"."total_waiver" IS 'Informational aggregate of waivers already reflected in net charges.';



COMMENT ON COLUMN "public"."student_financial_accounts"."total_adjustments" IS 'Informational aggregate of adjustments already reflected in net charges.';



COMMENT ON COLUMN "public"."student_financial_accounts"."current_balance" IS 'Authoritative student balance: total_charged - total_paid + total_refunded.';



CREATE TABLE IF NOT EXISTS "public"."student_gpa_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "academic_year_id" "uuid" NOT NULL,
    "semester_id" "uuid" NOT NULL,
    "semester_result_id" "uuid",
    "gpa" numeric(6,3) DEFAULT 0 NOT NULL,
    "total_credits" numeric(8,2) DEFAULT 0 NOT NULL,
    "total_quality_points" numeric(10,3) DEFAULT 0 NOT NULL,
    "calculation_version" character varying(30) DEFAULT '1.0'::character varying NOT NULL,
    "calculated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "student_gpa_range" CHECK ((("gpa" >= (0)::numeric) AND ("gpa" <= (5)::numeric)))
);


ALTER TABLE "public"."student_gpa_records" OWNER TO "postgres";


COMMENT ON TABLE "public"."student_gpa_records" IS 'Calculated semester GPA snapshots.';



CREATE TABLE IF NOT EXISTS "public"."student_profiles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "first_name" character varying(100),
    "middle_name" character varying(100),
    "last_name" character varying(100),
    "preferred_name" character varying(150),
    "date_of_birth" "date",
    "gender" character varying(30),
    "nationality" character varying(100),
    "national_id_number" character varying(100),
    "passport_number" character varying(100),
    "phone" character varying(50),
    "alternate_phone" character varying(50),
    "email" character varying(255),
    "profile_photo_url" "text",
    "disability_status" character varying(100),
    "blood_group" character varying(20),
    "marital_status" character varying(30),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_student_profiles_gender" CHECK ((("gender" IS NULL) OR (("gender")::"text" = ANY ((ARRAY['MALE'::character varying, 'FEMALE'::character varying, 'OTHER'::character varying, 'PREFER_NOT_TO_SAY'::character varying])::"text"[])))),
    CONSTRAINT "chk_student_profiles_marital_status" CHECK ((("marital_status" IS NULL) OR (("marital_status")::"text" = ANY ((ARRAY['SINGLE'::character varying, 'MARRIED'::character varying, 'DIVORCED'::character varying, 'WIDOWED'::character varying, 'SEPARATED'::character varying, 'PREFER_NOT_TO_SAY'::character varying])::"text"[]))))
);


ALTER TABLE "public"."student_profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."student_programme_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "programme_id" "uuid" NOT NULL,
    "programme_version_id" "uuid",
    "change_type" character varying(40) DEFAULT 'INITIAL'::character varying NOT NULL,
    "effective_from" "date" DEFAULT CURRENT_DATE NOT NULL,
    "effective_to" "date",
    "reason" "text",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_student_programme_change_type" CHECK ((("change_type")::"text" = ANY ((ARRAY['INITIAL'::character varying, 'TRANSFER'::character varying, 'PROGRAMME_CHANGE'::character varying, 'RE_ADMISSION'::character varying, 'READMISSION'::character varying])::"text"[]))),
    CONSTRAINT "chk_student_programme_dates" CHECK ((("effective_to" IS NULL) OR ("effective_to" >= "effective_from")))
);


ALTER TABLE "public"."student_programme_history" OWNER TO "postgres";


COMMENT ON TABLE "public"."student_programme_history" IS 'Historical record of programme assignments and programme changes.';



CREATE TABLE IF NOT EXISTS "public"."student_registrations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "academic_year_id" "uuid" NOT NULL,
    "semester_id" "uuid" NOT NULL,
    "programme_id" "uuid" NOT NULL,
    "programme_version_id" "uuid",
    "registration_number" character varying(80) NOT NULL,
    "registration_status" character varying(40) DEFAULT 'DRAFT'::character varying NOT NULL,
    "academic_eligibility_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "finance_eligibility_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "document_eligibility_status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "total_registered_credits" numeric(8,2) DEFAULT 0 NOT NULL,
    "minimum_credits" numeric(8,2) DEFAULT 0 NOT NULL,
    "maximum_credits" numeric(8,2) DEFAULT 30 NOT NULL,
    "submitted_at" timestamp with time zone,
    "approved_at" timestamp with time zone,
    "approved_by" "uuid",
    "locked_at" timestamp with time zone,
    "locked_by" "uuid",
    "rejection_reason" "text",
    "notes" "text",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_academic_eligibility" CHECK ((("academic_eligibility_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'ELIGIBLE'::character varying, 'NOT_ELIGIBLE'::character varying, 'OVERRIDE'::character varying])::"text"[]))),
    CONSTRAINT "chk_document_eligibility" CHECK ((("document_eligibility_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'CLEARED'::character varying, 'INCOMPLETE'::character varying, 'OVERRIDE'::character varying])::"text"[]))),
    CONSTRAINT "chk_finance_eligibility" CHECK ((("finance_eligibility_status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'CLEARED'::character varying, 'BLOCKED'::character varying, 'OVERRIDE'::character varying])::"text"[]))),
    CONSTRAINT "chk_registration_credits" CHECK ((("minimum_credits" >= (0)::numeric) AND ("maximum_credits" >= "minimum_credits") AND ("total_registered_credits" >= (0)::numeric))),
    CONSTRAINT "chk_registration_status" CHECK ((("registration_status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'ELIGIBILITY_PENDING'::character varying, 'ELIGIBLE'::character varying, 'SUBMITTED'::character varying, 'PENDING_APPROVAL'::character varying, 'APPROVED'::character varying, 'REGISTERED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying, 'LOCKED'::character varying])::"text"[])))
);


ALTER TABLE "public"."student_registrations" OWNER TO "postgres";


COMMENT ON TABLE "public"."student_registrations" IS 'Main semester registration record for a student.';



CREATE TABLE IF NOT EXISTS "public"."student_scholarships" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "scholarship_code" character varying(100) NOT NULL,
    "scholarship_name" character varying(200) NOT NULL,
    "sponsor_name" character varying(200),
    "scholarship_type" character varying(50) DEFAULT 'PARTIAL'::character varying NOT NULL,
    "amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "percentage" numeric(7,4),
    "academic_year" character varying(20),
    "semester" character varying(50),
    "start_date" "date",
    "end_date" "date",
    "status" character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    "approval_reference" character varying(100),
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "notes" "text",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_scholarship_dates" CHECK ((("end_date" IS NULL) OR ("start_date" IS NULL) OR ("end_date" >= "start_date"))),
    CONSTRAINT "student_scholarships_amount_check" CHECK (("amount" >= (0)::numeric)),
    CONSTRAINT "student_scholarships_percentage_check" CHECK ((("percentage" IS NULL) OR (("percentage" >= (0)::numeric) AND ("percentage" <= (100)::numeric)))),
    CONSTRAINT "student_scholarships_scholarship_type_check" CHECK ((("scholarship_type")::"text" = ANY ((ARRAY['FULL'::character varying, 'PARTIAL'::character varying, 'FIXED_AMOUNT'::character varying, 'PERCENTAGE'::character varying])::"text"[]))),
    CONSTRAINT "student_scholarships_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'ACTIVE'::character varying, 'SUSPENDED'::character varying, 'EXPIRED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."student_scholarships" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."student_status_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_id" "uuid" NOT NULL,
    "old_status" character varying(40),
    "new_status" character varying(40) NOT NULL,
    "reason" "text",
    "changed_by" "uuid",
    "changed_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."student_status_history" OWNER TO "postgres";


COMMENT ON TABLE "public"."student_status_history" IS 'Immutable-style lifecycle history of student status changes.';



CREATE TABLE IF NOT EXISTS "public"."student_transcript_courses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "transcript_id" "uuid" NOT NULL,
    "transcript_semester_id" "uuid",
    "course_result_id" "uuid",
    "course_registration_id" "uuid",
    "course_id" "uuid",
    "course_code" character varying(50),
    "course_name" character varying(255),
    "credits" numeric(6,2),
    "coursework_mark" numeric(8,2),
    "examination_mark" numeric(8,2),
    "total_mark" numeric(8,2),
    "grade_code" character varying(10),
    "grade_point" numeric(5,2),
    "result_type" character varying(30),
    "attempt_number" integer,
    "pass_status" character varying(30),
    "display_sequence" integer DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "student_transcript_courses_credits_valid" CHECK ((("credits" IS NULL) OR ("credits" > (0)::numeric))),
    CONSTRAINT "student_transcript_courses_grade_point_valid" CHECK ((("grade_point" IS NULL) OR (("grade_point" >= (0)::numeric) AND ("grade_point" <= (5)::numeric)))),
    CONSTRAINT "student_transcript_courses_marks_valid" CHECK ((("total_mark" IS NULL) OR (("total_mark" >= (0)::numeric) AND ("total_mark" <= (100)::numeric))))
);


ALTER TABLE "public"."student_transcript_courses" OWNER TO "postgres";


COMMENT ON TABLE "public"."student_transcript_courses" IS 'Course-level transcript records.';



CREATE TABLE IF NOT EXISTS "public"."student_transcript_semesters" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "transcript_id" "uuid" NOT NULL,
    "academic_year_id" "uuid" NOT NULL,
    "semester_id" "uuid" NOT NULL,
    "semester_result_id" "uuid",
    "gpa" numeric(6,3),
    "registered_credits" numeric(8,2) DEFAULT 0 NOT NULL,
    "attempted_credits" numeric(8,2) DEFAULT 0 NOT NULL,
    "earned_credits" numeric(8,2) DEFAULT 0 NOT NULL,
    "quality_points" numeric(10,3) DEFAULT 0 NOT NULL,
    "academic_standing" character varying(100),
    "sequence_no" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "student_transcript_semesters_attempted_credits_valid" CHECK (("attempted_credits" >= (0)::numeric)),
    CONSTRAINT "student_transcript_semesters_earned_credits_valid" CHECK (("earned_credits" >= (0)::numeric)),
    CONSTRAINT "student_transcript_semesters_gpa_valid" CHECK ((("gpa" IS NULL) OR (("gpa" >= (0)::numeric) AND ("gpa" <= (5)::numeric)))),
    CONSTRAINT "student_transcript_semesters_registered_credits_valid" CHECK (("registered_credits" >= (0)::numeric)),
    CONSTRAINT "student_transcript_semesters_sequence_positive" CHECK (("sequence_no" > 0))
);


ALTER TABLE "public"."student_transcript_semesters" OWNER TO "postgres";


COMMENT ON TABLE "public"."student_transcript_semesters" IS 'Semester summaries included in a transcript.';



CREATE TABLE IF NOT EXISTS "public"."student_transcripts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "transcript_number" character varying(80) NOT NULL,
    "student_id" "uuid" NOT NULL,
    "programme_version_id" "uuid",
    "transcript_type" character varying(30) DEFAULT 'OFFICIAL'::character varying NOT NULL,
    "issue_reason" character varying(100),
    "cumulative_credits" numeric(10,2) DEFAULT 0 NOT NULL,
    "cumulative_earned_credits" numeric(10,2) DEFAULT 0 NOT NULL,
    "cumulative_quality_points" numeric(12,3) DEFAULT 0 NOT NULL,
    "cgpa" numeric(6,3),
    "final_academic_standing" character varying(100),
    "transcript_status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "generated_at" timestamp with time zone,
    "generated_by" "uuid",
    "approved_at" timestamp with time zone,
    "approved_by" "uuid",
    "issued_at" timestamp with time zone,
    "issued_by" "uuid",
    "revoked_at" timestamp with time zone,
    "revoked_by" "uuid",
    "replacement_of" "uuid",
    "document_file_id" "uuid",
    "verification_code" character varying(120),
    "remarks" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "student_transcripts_transcript_status_check" CHECK ((("transcript_status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'GENERATED'::character varying, 'REVIEW'::character varying, 'APPROVED'::character varying, 'ISSUED'::character varying, 'REVOKED'::character varying, 'SUPERSEDED'::character varying])::"text"[]))),
    CONSTRAINT "student_transcripts_transcript_type_check" CHECK ((("transcript_type")::"text" = ANY ((ARRAY['OFFICIAL'::character varying, 'UNOFFICIAL'::character varying, 'PROVISIONAL'::character varying, 'REPLACEMENT'::character varying, 'FINAL'::character varying])::"text"[])))
);


ALTER TABLE "public"."student_transcripts" OWNER TO "postgres";


COMMENT ON TABLE "public"."student_transcripts" IS 'Official and controlled student transcript records.';



CREATE TABLE IF NOT EXISTS "public"."students" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "student_number" character varying(50) NOT NULL,
    "applicant_id" "uuid" NOT NULL,
    "source_application_id" "uuid" NOT NULL,
    "admission_offer_id" "uuid" NOT NULL,
    "programme_id" "uuid" NOT NULL,
    "programme_version_id" "uuid",
    "student_status" character varying(40) DEFAULT 'PENDING_ACTIVATION'::character varying NOT NULL,
    "admission_date" "date",
    "enrollment_date" "date",
    "expected_completion_date" "date",
    "actual_completion_date" "date",
    "activated_at" timestamp with time zone,
    "suspended_at" timestamp with time zone,
    "withdrawn_at" timestamp with time zone,
    "graduated_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "institution_id" "uuid",
    "user_id" "uuid",
    "first_name" character varying(100),
    "middle_name" character varying(100),
    "last_name" character varying(100),
    "gender" character varying(30),
    "date_of_birth" "date",
    "nationality" character varying(100),
    "national_id" character varying(100),
    "passport_number" character varying(100),
    "phone" character varying(50),
    "email" character varying(255),
    "physical_address" "text",
    "postal_address" "text",
    "emergency_contact_name" character varying(200),
    "emergency_contact_phone" character varying(50),
    "admission_year" integer,
    "entry_type" character varying(50),
    "profile_photo_url" "text",
    "notes" "text",
    CONSTRAINT "chk_students_status" CHECK ((("student_status")::"text" = ANY ((ARRAY['PENDING_ACTIVATION'::character varying, 'ACTIVE'::character varying, 'DEFERRED'::character varying, 'SUSPENDED'::character varying, 'WITHDRAWN'::character varying, 'COMPLETED'::character varying, 'GRADUATED'::character varying, 'EXPELLED'::character varying, 'DECEASED'::character varying, 'INACTIVE'::character varying])::"text"[])))
);


ALTER TABLE "public"."students" OWNER TO "postgres";


COMMENT ON TABLE "public"."students" IS 'Core student master record created only after successful admission conversion.';



COMMENT ON COLUMN "public"."students"."source_application_id" IS 'Original admission application. UNIQUE prevents duplicate applicant-to-student conversion.';



COMMENT ON COLUMN "public"."students"."student_status" IS 'Student lifecycle state: PENDING_ACTIVATION, ACTIVE, DEFERRED, SUSPENDED, WITHDRAWN, COMPLETED, GRADUATED, EXPELLED, DECEASED or INACTIVE.';



CREATE TABLE IF NOT EXISTS "public"."suppliers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "institution_id" "uuid" NOT NULL,
    "supplier_code" character varying(60) NOT NULL,
    "supplier_name" character varying(255) NOT NULL,
    "supplier_type" character varying(40) DEFAULT 'COMPANY'::character varying NOT NULL,
    "registration_number" character varying(100),
    "tax_identification_number" character varying(100),
    "contact_person" character varying(200),
    "phone" character varying(50),
    "email" character varying(255),
    "physical_address" "text",
    "postal_address" "text",
    "bank_name" character varying(255),
    "bank_account_name" character varying(255),
    "bank_account_number" character varying(100),
    "status" character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "notes" "text",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "suppliers_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'SUSPENDED'::character varying])::"text"[]))),
    CONSTRAINT "suppliers_supplier_type_check" CHECK ((("supplier_type")::"text" = ANY ((ARRAY['COMPANY'::character varying, 'INDIVIDUAL'::character varying, 'GOVERNMENT'::character varying, 'NGO'::character varying, 'OTHER'::character varying])::"text"[])))
);


ALTER TABLE "public"."suppliers" OWNER TO "postgres";


COMMENT ON TABLE "public"."suppliers" IS 'Approved suppliers and vendors used by the institution.';



CREATE TABLE IF NOT EXISTS "public"."timetable_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "timetable_id" "uuid" NOT NULL,
    "class_id" "uuid" NOT NULL,
    "course_offering_id" "uuid" NOT NULL,
    "lecturer_assignment_id" "uuid",
    "room_id" "uuid" NOT NULL,
    "timetable_slot_id" "uuid" NOT NULL,
    "entry_date" "date",
    "entry_type" character varying(30) DEFAULT 'REGULAR'::character varying NOT NULL,
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "notes" "text",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_timetable_entry_status" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'CONFIRMED'::character varying, 'CANCELLED'::character varying])::"text"[]))),
    CONSTRAINT "chk_timetable_entry_type" CHECK ((("entry_type")::"text" = ANY ((ARRAY['REGULAR'::character varying, 'MAKE_UP'::character varying, 'SPECIAL'::character varying, 'EXAM'::character varying, 'PRACTICAL'::character varying, 'CLINICAL'::character varying])::"text"[])))
);


ALTER TABLE "public"."timetable_entries" OWNER TO "postgres";


COMMENT ON TABLE "public"."timetable_entries" IS 'Individual class timetable entries with room, lecturer and time allocation.';



CREATE TABLE IF NOT EXISTS "public"."timetable_slots" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slot_code" character varying(50) NOT NULL,
    "day_of_week" integer NOT NULL,
    "start_time" time without time zone NOT NULL,
    "end_time" time without time zone NOT NULL,
    "duration_minutes" integer NOT NULL,
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_day_of_week" CHECK ((("day_of_week" >= 1) AND ("day_of_week" <= 7))),
    CONSTRAINT "chk_slot_duration" CHECK (("duration_minutes" > 0)),
    CONSTRAINT "chk_slot_status" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying])::"text"[]))),
    CONSTRAINT "chk_slot_time" CHECK (("end_time" > "start_time"))
);


ALTER TABLE "public"."timetable_slots" OWNER TO "postgres";


COMMENT ON TABLE "public"."timetable_slots" IS 'Reusable weekly timetable time slots.';



CREATE TABLE IF NOT EXISTS "public"."timetables" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "academic_year_id" "uuid" NOT NULL,
    "semester_id" "uuid" NOT NULL,
    "campus_id" "uuid" NOT NULL,
    "timetable_code" character varying(80) NOT NULL,
    "timetable_name" character varying(150) NOT NULL,
    "status" character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    "published_at" timestamp with time zone,
    "published_by" "uuid",
    "locked_at" timestamp with time zone,
    "locked_by" "uuid",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_timetable_status" CHECK ((("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'UNDER_REVIEW'::character varying, 'APPROVED'::character varying, 'PUBLISHED'::character varying, 'LOCKED'::character varying, 'CANCELLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."timetables" OWNER TO "postgres";


COMMENT ON TABLE "public"."timetables" IS 'Academic timetable master records per academic year, semester and campus.';



CREATE TABLE IF NOT EXISTS "public"."user_addresses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "address_type" character varying(30) DEFAULT 'PRIMARY'::character varying NOT NULL,
    "address_line_1" character varying(250),
    "address_line_2" character varying(250),
    "city" character varying(100),
    "district" character varying(100),
    "region" character varying(100),
    "country" character varying(100) DEFAULT 'Tanzania'::character varying NOT NULL,
    "postal_code" character varying(30),
    "is_primary" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_addresses_type_check" CHECK ((("address_type")::"text" = ANY ((ARRAY['PRIMARY'::character varying, 'PERMANENT'::character varying, 'RESIDENTIAL'::character varying, 'POSTAL'::character varying, 'WORK'::character varying, 'OTHER'::character varying])::"text"[])))
);


ALTER TABLE "public"."user_addresses" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_addresses" IS 'Multiple physical or postal addresses associated with an iMIS user.';



CREATE TABLE IF NOT EXISTS "public"."user_preferences" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "timezone" character varying(100) DEFAULT 'Africa/Dar_es_Salaam'::character varying NOT NULL,
    "date_format" character varying(30) DEFAULT 'DD/MM/YYYY'::character varying NOT NULL,
    "time_format" character varying(10) DEFAULT '24H'::character varying NOT NULL,
    "email_notifications" boolean DEFAULT true NOT NULL,
    "sms_notifications" boolean DEFAULT true NOT NULL,
    "push_notifications" boolean DEFAULT true NOT NULL,
    "in_app_notifications" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_preferences_time_format_check" CHECK ((("time_format")::"text" = ANY ((ARRAY['12H'::character varying, '24H'::character varying])::"text"[])))
);


ALTER TABLE "public"."user_preferences" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_preferences" IS 'Application-level preferences for an IDMC iMIS user.';



CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" character varying(30),
    "date_of_birth" "date",
    "gender" character varying(30),
    "nationality" character varying(100),
    "national_id_number" character varying(100),
    "passport_number" character varying(100),
    "marital_status" character varying(30),
    "occupation" character varying(150),
    "organisation" character varying(200),
    "biography" "text",
    "preferred_language" character varying(20) DEFAULT 'en'::character varying NOT NULL,
    "profile_completed" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_profiles_gender_check" CHECK ((("gender" IS NULL) OR (("gender")::"text" = ANY ((ARRAY['MALE'::character varying, 'FEMALE'::character varying, 'OTHER'::character varying, 'PREFER_NOT_TO_SAY'::character varying])::"text"[])))),
    CONSTRAINT "user_profiles_marital_status_check" CHECK ((("marital_status" IS NULL) OR (("marital_status")::"text" = ANY ((ARRAY['SINGLE'::character varying, 'MARRIED'::character varying, 'DIVORCED'::character varying, 'WIDOWED'::character varying, 'SEPARATED'::character varying, 'PREFER_NOT_TO_SAY'::character varying])::"text"[])))),
    CONSTRAINT "user_profiles_preferred_language_check" CHECK ((("preferred_language")::"text" = ANY ((ARRAY['en'::character varying, 'sw'::character varying])::"text"[])))
);


ALTER TABLE "public"."user_profiles" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_profiles" IS 'General personal profile information for an IDMC iMIS user.';



COMMENT ON COLUMN "public"."user_profiles"."national_id_number" IS 'National identification number where applicable.';



COMMENT ON COLUMN "public"."user_profiles"."passport_number" IS 'Passport number where applicable.';



COMMENT ON COLUMN "public"."user_profiles"."profile_completed" IS 'Indicates whether the required profile information has been completed.';



CREATE TABLE IF NOT EXISTS "public"."user_roles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role_id" "uuid" NOT NULL,
    "assigned_by" "uuid",
    "assigned_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone,
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    CONSTRAINT "user_roles_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'EXPIRED'::character varying])::"text"[])))
);


ALTER TABLE "public"."user_roles" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_roles" IS 'Many-to-many relationship between users and roles.';



CREATE TABLE IF NOT EXISTS "public"."user_scopes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "institution_id" "uuid",
    "campus_id" "uuid",
    "school_id" "uuid",
    "department_id" "uuid",
    "scope_type" character varying(50) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_user_scope_reference" CHECK ((((("scope_type")::"text" = 'GLOBAL'::"text") AND ("institution_id" IS NULL) AND ("campus_id" IS NULL) AND ("school_id" IS NULL) AND ("department_id" IS NULL)) OR ((("scope_type")::"text" = 'INSTITUTION'::"text") AND ("institution_id" IS NOT NULL)) OR ((("scope_type")::"text" = 'CAMPUS'::"text") AND ("campus_id" IS NOT NULL)) OR ((("scope_type")::"text" = 'SCHOOL'::"text") AND ("school_id" IS NOT NULL)) OR ((("scope_type")::"text" = 'DEPARTMENT'::"text") AND ("department_id" IS NOT NULL)))),
    CONSTRAINT "user_scopes_scope_type_check" CHECK ((("scope_type")::"text" = ANY ((ARRAY['GLOBAL'::character varying, 'INSTITUTION'::character varying, 'CAMPUS'::character varying, 'SCHOOL'::character varying, 'DEPARTMENT'::character varying])::"text"[])))
);


ALTER TABLE "public"."user_scopes" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_scopes" IS 'Defines institutional access scope for users.';



CREATE TABLE IF NOT EXISTS "public"."user_status_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "old_status" character varying(30),
    "new_status" character varying(30) NOT NULL,
    "reason" "text",
    "changed_by" "uuid",
    "changed_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_status_history" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_status_history" IS 'Historical record of IDMC iMIS account status changes.';



CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "auth_user_id" "uuid" NOT NULL,
    "user_number" character varying(50) NOT NULL,
    "username" character varying(100),
    "first_name" character varying(100) NOT NULL,
    "middle_name" character varying(100),
    "last_name" character varying(100) NOT NULL,
    "display_name" character varying(255),
    "email" character varying(255) NOT NULL,
    "phone" character varying(50),
    "profile_photo_url" "text",
    "status" character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    "last_login_at" timestamp with time zone,
    "password_changed_at" timestamp with time zone,
    "failed_login_attempts" integer DEFAULT 0 NOT NULL,
    "locked_until" timestamp with time zone,
    "email_verified_at" timestamp with time zone,
    "phone_verified_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "users_failed_login_attempts_check" CHECK (("failed_login_attempts" >= 0)),
    CONSTRAINT "users_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['PENDING'::character varying, 'ACTIVE'::character varying, 'SUSPENDED'::character varying, 'LOCKED'::character varying, 'INACTIVE'::character varying, 'DISABLED'::character varying])::"text"[])))
);


ALTER TABLE "public"."users" OWNER TO "postgres";


COMMENT ON TABLE "public"."users" IS 'Application users linked to Supabase Auth identities.';



CREATE OR REPLACE VIEW "public"."v_invoice_financial_summary" WITH ("security_invoker"='true') AS
 SELECT "id",
    "invoice_number",
    "student_id",
    "academic_year",
    "semester",
    "status",
    "total_amount",
    "amount_paid",
    "balance_amount",
    "due_date",
        CASE
            WHEN ("balance_amount" <= (0)::numeric) THEN 'CLEARED'::"text"
            WHEN (("due_date" IS NOT NULL) AND ("due_date" < CURRENT_DATE)) THEN 'OVERDUE'::"text"
            WHEN ("amount_paid" > (0)::numeric) THEN 'PARTIAL'::"text"
            ELSE 'UNPAID'::"text"
        END AS "payment_position"
   FROM "public"."invoices" "i";


ALTER VIEW "public"."v_invoice_financial_summary" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_student_financial_summary" WITH ("security_invoker"='true') AS
 SELECT "student_id",
    "total_charged",
    "total_paid",
    "total_refunded",
    "total_scholarship",
    "total_waiver",
    "total_adjustments",
    "current_balance",
    "account_status",
    "last_calculated_at"
   FROM "public"."student_financial_accounts";


ALTER VIEW "public"."v_student_financial_summary" OWNER TO "postgres";


ALTER TABLE ONLY "public"."academic_qualifications"
    ADD CONSTRAINT "academic_qualifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."academic_standing_rules"
    ADD CONSTRAINT "academic_standing_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."academic_standing_rules"
    ADD CONSTRAINT "academic_standing_rules_rule_code_key" UNIQUE ("rule_code");



ALTER TABLE ONLY "public"."academic_years"
    ADD CONSTRAINT "academic_years_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."academic_years"
    ADD CONSTRAINT "academic_years_year_code_key" UNIQUE ("year_code");



ALTER TABLE ONLY "public"."admission_acceptances"
    ADD CONSTRAINT "admission_acceptances_admission_offer_id_key" UNIQUE ("admission_offer_id");



ALTER TABLE ONLY "public"."admission_acceptances"
    ADD CONSTRAINT "admission_acceptances_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admission_decisions"
    ADD CONSTRAINT "admission_decisions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admission_offers"
    ADD CONSTRAINT "admission_offers_offer_number_key" UNIQUE ("offer_number");



ALTER TABLE ONLY "public"."admission_offers"
    ADD CONSTRAINT "admission_offers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."alumni_records"
    ADD CONSTRAINT "alumni_records_alumni_number_key" UNIQUE ("alumni_number");



ALTER TABLE ONLY "public"."alumni_records"
    ADD CONSTRAINT "alumni_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."alumni_records"
    ADD CONSTRAINT "alumni_records_student_id_key" UNIQUE ("student_id");



ALTER TABLE ONLY "public"."applicants"
    ADD CONSTRAINT "applicants_applicant_number_key" UNIQUE ("applicant_number");



ALTER TABLE ONLY "public"."applicants"
    ADD CONSTRAINT "applicants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."application_choices"
    ADD CONSTRAINT "application_choices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."application_documents"
    ADD CONSTRAINT "application_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."applications"
    ADD CONSTRAINT "applications_application_number_key" UNIQUE ("application_number");



ALTER TABLE ONLY "public"."applications"
    ADD CONSTRAINT "applications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."assessment_mark_corrections"
    ADD CONSTRAINT "assessment_mark_corrections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."assessment_marks"
    ADD CONSTRAINT "assessment_marks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."assessment_marks"
    ADD CONSTRAINT "assessment_marks_unique_student" UNIQUE ("assessment_id", "student_id");



ALTER TABLE ONLY "public"."assessment_submissions"
    ADD CONSTRAINT "assessment_submissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."assessment_submissions"
    ADD CONSTRAINT "assessment_submissions_unique_student" UNIQUE ("assessment_id", "student_id");



ALTER TABLE ONLY "public"."assessments"
    ADD CONSTRAINT "assessments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."assessments"
    ADD CONSTRAINT "assessments_unique_code" UNIQUE ("course_offering_id", "assessment_code");



ALTER TABLE ONLY "public"."asset_assignments"
    ADD CONSTRAINT "asset_assignments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."asset_categories"
    ADD CONSTRAINT "asset_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."asset_maintenance"
    ADD CONSTRAINT "asset_maintenance_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_asset_tag_key" UNIQUE ("asset_tag");



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance_corrections"
    ADD CONSTRAINT "attendance_corrections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_unique_student_session" UNIQUE ("attendance_session_id", "student_id");



ALTER TABLE ONLY "public"."attendance_sessions"
    ADD CONSTRAINT "attendance_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."audit_logs"
    ADD CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campuses"
    ADD CONSTRAINT "campuses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."certificate_verifications"
    ADD CONSTRAINT "certificate_verifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."certificates"
    ADD CONSTRAINT "certificates_certificate_number_key" UNIQUE ("certificate_number");



ALTER TABLE ONLY "public"."certificates"
    ADD CONSTRAINT "certificates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."certificates"
    ADD CONSTRAINT "certificates_verification_code_key" UNIQUE ("verification_code");



ALTER TABLE ONLY "public"."class_students"
    ADD CONSTRAINT "class_students_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."classes"
    ADD CONSTRAINT "classes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."course_add_drop_requests"
    ADD CONSTRAINT "course_add_drop_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."course_offerings"
    ADD CONSTRAINT "course_offerings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."course_prerequisites"
    ADD CONSTRAINT "course_prerequisites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."course_registrations"
    ADD CONSTRAINT "course_registrations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."course_result_corrections"
    ADD CONSTRAINT "course_result_corrections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."course_result_policies"
    ADD CONSTRAINT "course_result_policies_course_offering_id_key" UNIQUE ("course_offering_id");



ALTER TABLE ONLY "public"."course_result_policies"
    ADD CONSTRAINT "course_result_policies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."course_results"
    ADD CONSTRAINT "course_results_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."course_results"
    ADD CONSTRAINT "course_results_student_id_course_offering_id_course_registr_key" UNIQUE ("student_id", "course_offering_id", "course_registration_id");



ALTER TABLE ONLY "public"."courses"
    ADD CONSTRAINT "courses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."curricula"
    ADD CONSTRAINT "curricula_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."curriculum_courses"
    ADD CONSTRAINT "curriculum_courses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."departments"
    ADD CONSTRAINT "departments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."emergency_contacts"
    ADD CONSTRAINT "emergency_contacts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."examination_attendance"
    ADD CONSTRAINT "examination_attendance_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."examination_attendance"
    ADD CONSTRAINT "examination_attendance_uq" UNIQUE ("examination_session_id", "examination_candidate_id");



ALTER TABLE ONLY "public"."examination_candidate_sessions"
    ADD CONSTRAINT "examination_candidate_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."examination_candidates"
    ADD CONSTRAINT "examination_candidate_uq" UNIQUE ("examination_paper_id", "student_id");



ALTER TABLE ONLY "public"."examination_candidates"
    ADD CONSTRAINT "examination_candidates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."examination_invigilators"
    ADD CONSTRAINT "examination_invigilator_uq" UNIQUE ("examination_session_id", "user_id");



ALTER TABLE ONLY "public"."examination_invigilators"
    ADD CONSTRAINT "examination_invigilators_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."examination_mark_corrections"
    ADD CONSTRAINT "examination_mark_corrections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."examination_marks"
    ADD CONSTRAINT "examination_mark_uq" UNIQUE ("examination_paper_id", "examination_candidate_id");



ALTER TABLE ONLY "public"."examination_marks"
    ADD CONSTRAINT "examination_marks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."examination_papers"
    ADD CONSTRAINT "examination_paper_code_uq" UNIQUE ("examination_period_id", "paper_code");



ALTER TABLE ONLY "public"."examination_papers"
    ADD CONSTRAINT "examination_papers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."examination_periods"
    ADD CONSTRAINT "examination_period_code_uq" UNIQUE ("period_code");



ALTER TABLE ONLY "public"."examination_periods"
    ADD CONSTRAINT "examination_periods_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."examination_sessions"
    ADD CONSTRAINT "examination_session_code_uq" UNIQUE ("session_code");



ALTER TABLE ONLY "public"."examination_sessions"
    ADD CONSTRAINT "examination_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fee_items"
    ADD CONSTRAINT "fee_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fee_structures"
    ADD CONSTRAINT "fee_structures_fee_structure_code_key" UNIQUE ("fee_structure_code");



ALTER TABLE ONLY "public"."fee_structures"
    ADD CONSTRAINT "fee_structures_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."financial_transactions"
    ADD CONSTRAINT "financial_transactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."financial_transactions"
    ADD CONSTRAINT "financial_transactions_transaction_number_key" UNIQUE ("transaction_number");



ALTER TABLE ONLY "public"."grade_scale_details"
    ADD CONSTRAINT "grade_scale_details_grade_scale_id_grade_code_key" UNIQUE ("grade_scale_id", "grade_code");



ALTER TABLE ONLY "public"."grade_scale_details"
    ADD CONSTRAINT "grade_scale_details_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grade_scales"
    ADD CONSTRAINT "grade_scales_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grade_scales"
    ADD CONSTRAINT "grade_scales_scale_code_key" UNIQUE ("scale_code");



ALTER TABLE ONLY "public"."graduation_approvals"
    ADD CONSTRAINT "graduation_approvals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."graduation_approvals"
    ADD CONSTRAINT "graduation_approvals_unique_stage" UNIQUE ("graduation_candidate_id", "approval_stage");



ALTER TABLE ONLY "public"."graduation_awards"
    ADD CONSTRAINT "graduation_awards_certificate_number_key" UNIQUE ("certificate_number");



ALTER TABLE ONLY "public"."graduation_awards"
    ADD CONSTRAINT "graduation_awards_graduation_candidate_id_key" UNIQUE ("graduation_candidate_id");



ALTER TABLE ONLY "public"."graduation_awards"
    ADD CONSTRAINT "graduation_awards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."graduation_candidates"
    ADD CONSTRAINT "graduation_candidates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."graduation_candidates"
    ADD CONSTRAINT "graduation_candidates_unique_student" UNIQUE ("graduation_period_id", "student_id");



ALTER TABLE ONLY "public"."graduation_clearance_items"
    ADD CONSTRAINT "graduation_clearance_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."graduation_clearances"
    ADD CONSTRAINT "graduation_clearances_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."graduation_clearances"
    ADD CONSTRAINT "graduation_clearances_unique_type" UNIQUE ("graduation_candidate_id", "clearance_type");



ALTER TABLE ONLY "public"."graduation_periods"
    ADD CONSTRAINT "graduation_periods_graduation_number_key" UNIQUE ("graduation_number");



ALTER TABLE ONLY "public"."graduation_periods"
    ADD CONSTRAINT "graduation_periods_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."guardians"
    ADD CONSTRAINT "guardians_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hostel_allocations"
    ADD CONSTRAINT "hostel_allocations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hostel_beds"
    ADD CONSTRAINT "hostel_beds_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hostel_fees"
    ADD CONSTRAINT "hostel_fees_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hostel_rooms"
    ADD CONSTRAINT "hostel_rooms_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hostels"
    ADD CONSTRAINT "hostels_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."institutions"
    ADD CONSTRAINT "institutions_institution_code_key" UNIQUE ("institution_code");



ALTER TABLE ONLY "public"."institutions"
    ADD CONSTRAINT "institutions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_categories"
    ADD CONSTRAINT "inventory_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_transactions"
    ADD CONSTRAINT "inventory_transactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_transactions"
    ADD CONSTRAINT "inventory_transactions_transaction_number_key" UNIQUE ("transaction_number");



ALTER TABLE ONLY "public"."invoice_items"
    ADD CONSTRAINT "invoice_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_invoice_number_key" UNIQUE ("invoice_number");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."joining_instructions"
    ADD CONSTRAINT "joining_instructions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lecturer_assignments"
    ADD CONSTRAINT "lecturer_assignments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."library_fines"
    ADD CONSTRAINT "library_fines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."library_items"
    ADD CONSTRAINT "library_items_accession_number_key" UNIQUE ("accession_number");



ALTER TABLE ONLY "public"."library_items"
    ADD CONSTRAINT "library_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."library_loans"
    ADD CONSTRAINT "library_loans_loan_number_key" UNIQUE ("loan_number");



ALTER TABLE ONLY "public"."library_loans"
    ADD CONSTRAINT "library_loans_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."library_members"
    ADD CONSTRAINT "library_members_membership_number_key" UNIQUE ("membership_number");



ALTER TABLE ONLY "public"."library_members"
    ADD CONSTRAINT "library_members_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."library_reservations"
    ADD CONSTRAINT "library_reservations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_deliveries"
    ADD CONSTRAINT "notification_deliveries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_queue"
    ADD CONSTRAINT "notification_queue_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_templates"
    ADD CONSTRAINT "notification_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_templates"
    ADD CONSTRAINT "notification_templates_template_code_key" UNIQUE ("template_code");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_notification_number_key" UNIQUE ("notification_number");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payment_allocations"
    ADD CONSTRAINT "payment_allocations_allocation_reference_key" UNIQUE ("allocation_reference");



ALTER TABLE ONLY "public"."payment_allocations"
    ADD CONSTRAINT "payment_allocations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_payment_number_key" UNIQUE ("payment_number");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_receipt_number_key" UNIQUE ("receipt_number");



ALTER TABLE ONLY "public"."permissions"
    ADD CONSTRAINT "permissions_permission_code_key" UNIQUE ("permission_code");



ALTER TABLE ONLY "public"."permissions"
    ADD CONSTRAINT "permissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."procurement_request_items"
    ADD CONSTRAINT "procurement_request_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."procurement_requests"
    ADD CONSTRAINT "procurement_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."procurement_requests"
    ADD CONSTRAINT "procurement_requests_request_number_key" UNIQUE ("request_number");



ALTER TABLE ONLY "public"."programme_versions"
    ADD CONSTRAINT "programme_versions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."programmes"
    ADD CONSTRAINT "programmes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."purchase_order_items"
    ADD CONSTRAINT "purchase_order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_purchase_order_number_key" UNIQUE ("purchase_order_number");



ALTER TABLE ONLY "public"."refunds"
    ADD CONSTRAINT "refunds_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."refunds"
    ADD CONSTRAINT "refunds_refund_number_key" UNIQUE ("refund_number");



ALTER TABLE ONLY "public"."registration_approvals"
    ADD CONSTRAINT "registration_approvals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."role_permissions"
    ADD CONSTRAINT "role_permissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."roles"
    ADD CONSTRAINT "roles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."roles"
    ADD CONSTRAINT "roles_role_code_key" UNIQUE ("role_code");



ALTER TABLE ONLY "public"."rooms"
    ADD CONSTRAINT "rooms_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."schools"
    ADD CONSTRAINT "schools_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."security_logs"
    ADD CONSTRAINT "security_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."semesters"
    ADD CONSTRAINT "semesters_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."staff_attendance_adjustments"
    ADD CONSTRAINT "staff_attendance_adjustments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."staff_attendance"
    ADD CONSTRAINT "staff_attendance_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."staff_documents"
    ADD CONSTRAINT "staff_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "staff_employee_number_key" UNIQUE ("employee_number");



ALTER TABLE ONLY "public"."staff_employment_history"
    ADD CONSTRAINT "staff_employment_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."staff_leave_approvals"
    ADD CONSTRAINT "staff_leave_approvals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."staff_leave_balances"
    ADD CONSTRAINT "staff_leave_balances_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."staff_leave_requests"
    ADD CONSTRAINT "staff_leave_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."staff_leave_requests"
    ADD CONSTRAINT "staff_leave_requests_request_number_key" UNIQUE ("request_number");



ALTER TABLE ONLY "public"."staff_leave_types"
    ADD CONSTRAINT "staff_leave_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."staff_lifecycle_events"
    ADD CONSTRAINT "staff_lifecycle_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "staff_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."staff_qualifications"
    ADD CONSTRAINT "staff_qualifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_academic_deficiencies"
    ADD CONSTRAINT "student_academic_deficiencies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_academic_standings"
    ADD CONSTRAINT "student_academic_standings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_academic_standings"
    ADD CONSTRAINT "student_academic_standings_student_id_academic_year_id_seme_key" UNIQUE ("student_id", "academic_year_id", "semester_id");



ALTER TABLE ONLY "public"."student_cgpa_records"
    ADD CONSTRAINT "student_cgpa_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_cgpa_records"
    ADD CONSTRAINT "student_cgpa_records_student_id_academic_year_id_semester_i_key" UNIQUE ("student_id", "academic_year_id", "semester_id");



ALTER TABLE ONLY "public"."student_charges"
    ADD CONSTRAINT "student_charges_charge_number_key" UNIQUE ("charge_number");



ALTER TABLE ONLY "public"."student_charges"
    ADD CONSTRAINT "student_charges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_course_attempts"
    ADD CONSTRAINT "student_course_attempts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_documents"
    ADD CONSTRAINT "student_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_fee_adjustments"
    ADD CONSTRAINT "student_fee_adjustments_adjustment_number_key" UNIQUE ("adjustment_number");



ALTER TABLE ONLY "public"."student_fee_adjustments"
    ADD CONSTRAINT "student_fee_adjustments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_financial_accounts"
    ADD CONSTRAINT "student_financial_accounts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_gpa_records"
    ADD CONSTRAINT "student_gpa_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_gpa_records"
    ADD CONSTRAINT "student_gpa_records_student_id_academic_year_id_semester_id_key" UNIQUE ("student_id", "academic_year_id", "semester_id");



ALTER TABLE ONLY "public"."student_profiles"
    ADD CONSTRAINT "student_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_programme_history"
    ADD CONSTRAINT "student_programme_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_registrations"
    ADD CONSTRAINT "student_registrations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_scholarships"
    ADD CONSTRAINT "student_scholarships_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_semester_results"
    ADD CONSTRAINT "student_semester_results_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_semester_results"
    ADD CONSTRAINT "student_semester_results_student_id_academic_year_id_semest_key" UNIQUE ("student_id", "academic_year_id", "semester_id");



ALTER TABLE ONLY "public"."student_status_history"
    ADD CONSTRAINT "student_status_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_transcript_courses"
    ADD CONSTRAINT "student_transcript_courses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_transcript_semesters"
    ADD CONSTRAINT "student_transcript_semesters_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_transcript_semesters"
    ADD CONSTRAINT "student_transcript_semesters_transcript_id_academic_year_id_key" UNIQUE ("transcript_id", "academic_year_id", "semester_id");



ALTER TABLE ONLY "public"."student_transcript_semesters"
    ADD CONSTRAINT "student_transcript_semesters_transcript_id_sequence_no_key" UNIQUE ("transcript_id", "sequence_no");



ALTER TABLE ONLY "public"."student_transcripts"
    ADD CONSTRAINT "student_transcripts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."student_transcripts"
    ADD CONSTRAINT "student_transcripts_transcript_number_key" UNIQUE ("transcript_number");



ALTER TABLE ONLY "public"."student_transcripts"
    ADD CONSTRAINT "student_transcripts_verification_code_key" UNIQUE ("verification_code");



ALTER TABLE ONLY "public"."students"
    ADD CONSTRAINT "students_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."timetable_entries"
    ADD CONSTRAINT "timetable_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."timetable_slots"
    ADD CONSTRAINT "timetable_slots_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."timetable_slots"
    ADD CONSTRAINT "timetable_slots_slot_code_key" UNIQUE ("slot_code");



ALTER TABLE ONLY "public"."timetables"
    ADD CONSTRAINT "timetables_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."timetables"
    ADD CONSTRAINT "timetables_timetable_code_key" UNIQUE ("timetable_code");



ALTER TABLE ONLY "public"."application_choices"
    ADD CONSTRAINT "uq_application_choice_number" UNIQUE ("application_id", "choice_number");



ALTER TABLE ONLY "public"."application_choices"
    ADD CONSTRAINT "uq_application_programme" UNIQUE ("application_id", "programme_id");



ALTER TABLE ONLY "public"."asset_categories"
    ADD CONSTRAINT "uq_asset_category" UNIQUE ("institution_id", "category_code");



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "uq_asset_serial" UNIQUE ("serial_number");



ALTER TABLE ONLY "public"."campuses"
    ADD CONSTRAINT "uq_campus_code_per_institution" UNIQUE ("institution_id", "campus_code");



ALTER TABLE ONLY "public"."classes"
    ADD CONSTRAINT "uq_class_code" UNIQUE ("class_code");



ALTER TABLE ONLY "public"."class_students"
    ADD CONSTRAINT "uq_class_student" UNIQUE ("class_id", "student_id");



ALTER TABLE ONLY "public"."courses"
    ADD CONSTRAINT "uq_course_institution_code" UNIQUE ("institution_id", "course_code");



ALTER TABLE ONLY "public"."course_offerings"
    ADD CONSTRAINT "uq_course_offering_code" UNIQUE ("offering_code");



ALTER TABLE ONLY "public"."course_prerequisites"
    ADD CONSTRAINT "uq_course_prerequisite" UNIQUE ("course_id", "prerequisite_course_id");



ALTER TABLE ONLY "public"."curriculum_courses"
    ADD CONSTRAINT "uq_curriculum_course" UNIQUE ("curriculum_id", "course_id");



ALTER TABLE ONLY "public"."curricula"
    ADD CONSTRAINT "uq_curriculum_programme_code" UNIQUE ("programme_version_id", "curriculum_code");



ALTER TABLE ONLY "public"."departments"
    ADD CONSTRAINT "uq_department_code_per_school" UNIQUE ("school_id", "department_code");



ALTER TABLE ONLY "public"."fee_items"
    ADD CONSTRAINT "uq_fee_item_structure_code" UNIQUE ("fee_structure_id", "fee_item_code");



ALTER TABLE ONLY "public"."hostel_beds"
    ADD CONSTRAINT "uq_hostel_bed" UNIQUE ("room_id", "bed_number");



ALTER TABLE ONLY "public"."hostels"
    ADD CONSTRAINT "uq_hostel_code" UNIQUE ("institution_id", "hostel_code");



ALTER TABLE ONLY "public"."hostel_rooms"
    ADD CONSTRAINT "uq_hostel_room" UNIQUE ("hostel_id", "room_number");



ALTER TABLE ONLY "public"."inventory_categories"
    ADD CONSTRAINT "uq_inventory_category" UNIQUE ("institution_id", "category_code");



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "uq_inventory_item" UNIQUE ("institution_id", "item_code");



ALTER TABLE ONLY "public"."staff_leave_approvals"
    ADD CONSTRAINT "uq_leave_approval_level" UNIQUE ("leave_request_id", "approval_level");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "uq_payment_external_reference" UNIQUE ("provider", "external_reference");



ALTER TABLE ONLY "public"."permissions"
    ADD CONSTRAINT "uq_permission_module_action" UNIQUE ("module_code", "action_code");



ALTER TABLE ONLY "public"."programmes"
    ADD CONSTRAINT "uq_programme_institution_code" UNIQUE ("institution_id", "programme_code");



ALTER TABLE ONLY "public"."programme_versions"
    ADD CONSTRAINT "uq_programme_version" UNIQUE ("programme_id", "version_code");



ALTER TABLE ONLY "public"."registration_approvals"
    ADD CONSTRAINT "uq_registration_approval_level" UNIQUE ("student_registration_id", "approval_level");



ALTER TABLE ONLY "public"."role_permissions"
    ADD CONSTRAINT "uq_role_permission" UNIQUE ("role_id", "permission_id");



ALTER TABLE ONLY "public"."rooms"
    ADD CONSTRAINT "uq_room_code" UNIQUE ("campus_id", "room_code");



ALTER TABLE ONLY "public"."schools"
    ADD CONSTRAINT "uq_school_code_per_institution" UNIQUE ("institution_id", "school_code");



ALTER TABLE ONLY "public"."semesters"
    ADD CONSTRAINT "uq_semester_year_code" UNIQUE ("academic_year_id", "semester_code");



ALTER TABLE ONLY "public"."semesters"
    ADD CONSTRAINT "uq_semester_year_number" UNIQUE ("academic_year_id", "semester_number");



ALTER TABLE ONLY "public"."staff_attendance"
    ADD CONSTRAINT "uq_staff_attendance_day" UNIQUE ("staff_id", "attendance_date");



ALTER TABLE ONLY "public"."staff_leave_balances"
    ADD CONSTRAINT "uq_staff_leave_balance" UNIQUE ("staff_id", "leave_type_id", "leave_year");



ALTER TABLE ONLY "public"."staff_leave_types"
    ADD CONSTRAINT "uq_staff_leave_type" UNIQUE ("institution_id", "leave_code");



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "uq_staff_national_id" UNIQUE ("national_id");



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "uq_staff_passport" UNIQUE ("passport_number");



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "uq_staff_user" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."student_financial_accounts"
    ADD CONSTRAINT "uq_student_financial_account" UNIQUE ("student_id");



ALTER TABLE ONLY "public"."student_profiles"
    ADD CONSTRAINT "uq_student_profiles_student" UNIQUE ("student_id");



ALTER TABLE ONLY "public"."student_registrations"
    ADD CONSTRAINT "uq_student_registration_number" UNIQUE ("registration_number");



ALTER TABLE ONLY "public"."student_registrations"
    ADD CONSTRAINT "uq_student_year_semester" UNIQUE ("student_id", "academic_year_id", "semester_id");



ALTER TABLE ONLY "public"."students"
    ADD CONSTRAINT "uq_students_admission_offer" UNIQUE ("admission_offer_id");



ALTER TABLE ONLY "public"."students"
    ADD CONSTRAINT "uq_students_source_application" UNIQUE ("source_application_id");



ALTER TABLE ONLY "public"."students"
    ADD CONSTRAINT "uq_students_student_number" UNIQUE ("student_number");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "uq_supplier_code" UNIQUE ("institution_id", "supplier_code");



ALTER TABLE ONLY "public"."user_preferences"
    ADD CONSTRAINT "uq_user_preferences_user" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "uq_user_profiles_user" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "uq_user_role" UNIQUE ("user_id", "role_id");



ALTER TABLE ONLY "public"."user_addresses"
    ADD CONSTRAINT "user_addresses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_preferences"
    ADD CONSTRAINT "user_preferences_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_scopes"
    ADD CONSTRAINT "user_scopes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_status_history"
    ADD CONSTRAINT "user_status_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_auth_user_id_key" UNIQUE ("auth_user_id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_user_number_key" UNIQUE ("user_number");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_username_key" UNIQUE ("username");



CREATE INDEX "idx_academic_qualifications_applicant" ON "public"."academic_qualifications" USING "btree" ("applicant_id");



CREATE INDEX "idx_academic_qualifications_type" ON "public"."academic_qualifications" USING "btree" ("qualification_type");



CREATE INDEX "idx_academic_qualifications_verification" ON "public"."academic_qualifications" USING "btree" ("verification_status");



CREATE INDEX "idx_academic_standings_status" ON "public"."student_academic_standings" USING "btree" ("status");



CREATE INDEX "idx_academic_standings_student" ON "public"."student_academic_standings" USING "btree" ("student_id");



CREATE INDEX "idx_academic_years_dates" ON "public"."academic_years" USING "btree" ("start_date", "end_date");



CREATE INDEX "idx_academic_years_status" ON "public"."academic_years" USING "btree" ("status");



CREATE INDEX "idx_add_drop_course" ON "public"."course_add_drop_requests" USING "btree" ("course_id");



CREATE INDEX "idx_add_drop_status" ON "public"."course_add_drop_requests" USING "btree" ("request_status");



CREATE INDEX "idx_add_drop_student" ON "public"."course_add_drop_requests" USING "btree" ("student_id");



CREATE INDEX "idx_add_drop_student_registration" ON "public"."course_add_drop_requests" USING "btree" ("student_registration_id");



CREATE INDEX "idx_admission_acceptances_status" ON "public"."admission_acceptances" USING "btree" ("acceptance_status");



CREATE INDEX "idx_admission_decisions_application" ON "public"."admission_decisions" USING "btree" ("application_id");



CREATE INDEX "idx_admission_decisions_choice" ON "public"."admission_decisions" USING "btree" ("application_choice_id");



CREATE INDEX "idx_admission_decisions_status" ON "public"."admission_decisions" USING "btree" ("decision_status");



CREATE INDEX "idx_admission_offers_application" ON "public"."admission_offers" USING "btree" ("application_id");



CREATE INDEX "idx_admission_offers_programme" ON "public"."admission_offers" USING "btree" ("programme_id");



CREATE INDEX "idx_admission_offers_status" ON "public"."admission_offers" USING "btree" ("offer_status");



CREATE INDEX "idx_alumni_graduation_year" ON "public"."alumni_records" USING "btree" ("graduation_year");



CREATE INDEX "idx_alumni_records_current_employer" ON "public"."alumni_records" USING "btree" ("current_employer");



CREATE INDEX "idx_alumni_records_email" ON "public"."alumni_records" USING "btree" ("email");



CREATE INDEX "idx_alumni_records_graduation_award" ON "public"."alumni_records" USING "btree" ("graduation_award_id");



CREATE INDEX "idx_alumni_records_graduation_candidate" ON "public"."alumni_records" USING "btree" ("graduation_candidate_id");



CREATE INDEX "idx_alumni_records_graduation_year" ON "public"."alumni_records" USING "btree" ("graduation_year");



CREATE INDEX "idx_alumni_records_status" ON "public"."alumni_records" USING "btree" ("status");



CREATE INDEX "idx_alumni_records_student" ON "public"."alumni_records" USING "btree" ("student_id");



CREATE INDEX "idx_alumni_student_integrity" ON "public"."alumni_records" USING "btree" ("student_id");



CREATE INDEX "idx_applicants_auth_user" ON "public"."applicants" USING "btree" ("auth_user_id");



CREATE INDEX "idx_applicants_email" ON "public"."applicants" USING "btree" ("email");



CREATE INDEX "idx_applicants_national_id" ON "public"."applicants" USING "btree" ("national_id_number");



CREATE INDEX "idx_applicants_passport" ON "public"."applicants" USING "btree" ("passport_number");



CREATE INDEX "idx_applicants_phone" ON "public"."applicants" USING "btree" ("phone");



CREATE INDEX "idx_applicants_status" ON "public"."applicants" USING "btree" ("status");



CREATE INDEX "idx_application_choices_application" ON "public"."application_choices" USING "btree" ("application_id");



CREATE INDEX "idx_application_choices_programme" ON "public"."application_choices" USING "btree" ("programme_id");



CREATE INDEX "idx_application_choices_status" ON "public"."application_choices" USING "btree" ("status");



CREATE INDEX "idx_application_documents_application" ON "public"."application_documents" USING "btree" ("application_id");



CREATE INDEX "idx_application_documents_status" ON "public"."application_documents" USING "btree" ("verification_status");



CREATE INDEX "idx_application_documents_type" ON "public"."application_documents" USING "btree" ("document_type");



CREATE INDEX "idx_applications_academic_year" ON "public"."applications" USING "btree" ("academic_year_id");



CREATE INDEX "idx_applications_applicant" ON "public"."applications" USING "btree" ("applicant_id");



CREATE INDEX "idx_applications_payment_status" ON "public"."applications" USING "btree" ("payment_status");



CREATE INDEX "idx_applications_selection_status" ON "public"."applications" USING "btree" ("selection_status");



CREATE INDEX "idx_applications_status" ON "public"."applications" USING "btree" ("status");



CREATE INDEX "idx_applications_verification_status" ON "public"."applications" USING "btree" ("verification_status");



CREATE INDEX "idx_assessment_mark_corrections_mark" ON "public"."assessment_mark_corrections" USING "btree" ("assessment_mark_id");



CREATE INDEX "idx_assessment_mark_corrections_requested_by" ON "public"."assessment_mark_corrections" USING "btree" ("requested_by");



CREATE INDEX "idx_assessment_mark_corrections_reviewed_by" ON "public"."assessment_mark_corrections" USING "btree" ("reviewed_by");



CREATE INDEX "idx_assessment_mark_corrections_status" ON "public"."assessment_mark_corrections" USING "btree" ("status");



CREATE INDEX "idx_assessment_marks_assessment" ON "public"."assessment_marks" USING "btree" ("assessment_id");



CREATE INDEX "idx_assessment_marks_status" ON "public"."assessment_marks" USING "btree" ("status");



CREATE INDEX "idx_assessment_marks_student" ON "public"."assessment_marks" USING "btree" ("student_id");



CREATE INDEX "idx_assessment_submissions_assessment" ON "public"."assessment_submissions" USING "btree" ("assessment_id");



CREATE INDEX "idx_assessment_submissions_student" ON "public"."assessment_submissions" USING "btree" ("student_id");



CREATE INDEX "idx_assessments_course_offering" ON "public"."assessments" USING "btree" ("course_offering_id");



CREATE INDEX "idx_assessments_status" ON "public"."assessments" USING "btree" ("status");



CREATE INDEX "idx_asset_assignments_asset" ON "public"."asset_assignments" USING "btree" ("asset_id");



CREATE INDEX "idx_asset_assignments_department" ON "public"."asset_assignments" USING "btree" ("department_id");



CREATE INDEX "idx_asset_assignments_staff" ON "public"."asset_assignments" USING "btree" ("staff_id");



CREATE INDEX "idx_asset_categories_institution" ON "public"."asset_categories" USING "btree" ("institution_id");



CREATE INDEX "idx_asset_maintenance_asset" ON "public"."asset_maintenance" USING "btree" ("asset_id");



CREATE INDEX "idx_asset_maintenance_date" ON "public"."asset_maintenance" USING "btree" ("maintenance_date");



CREATE INDEX "idx_assets_category" ON "public"."assets" USING "btree" ("category_id");



CREATE INDEX "idx_assets_department" ON "public"."assets" USING "btree" ("department_id");



CREATE INDEX "idx_assets_status" ON "public"."assets" USING "btree" ("asset_status");



CREATE INDEX "idx_attendance_corrections_record" ON "public"."attendance_corrections" USING "btree" ("attendance_record_id");



CREATE INDEX "idx_attendance_corrections_status" ON "public"."attendance_corrections" USING "btree" ("status");



CREATE INDEX "idx_attendance_records_session" ON "public"."attendance_records" USING "btree" ("attendance_session_id");



CREATE INDEX "idx_attendance_records_student" ON "public"."attendance_records" USING "btree" ("student_id");



CREATE INDEX "idx_attendance_records_student_status" ON "public"."attendance_records" USING "btree" ("student_id", "attendance_status");



CREATE INDEX "idx_attendance_sessions_class_date" ON "public"."attendance_sessions" USING "btree" ("class_id", "session_date");



CREATE INDEX "idx_attendance_sessions_course_date" ON "public"."attendance_sessions" USING "btree" ("course_offering_id", "session_date");



CREATE INDEX "idx_attendance_sessions_status" ON "public"."attendance_sessions" USING "btree" ("status");



CREATE INDEX "idx_audit_logs_action" ON "public"."audit_logs" USING "btree" ("action_code");



CREATE INDEX "idx_audit_logs_created_at" ON "public"."audit_logs" USING "btree" ("created_at");



CREATE INDEX "idx_audit_logs_entity" ON "public"."audit_logs" USING "btree" ("entity_type", "entity_id");



CREATE INDEX "idx_audit_logs_module" ON "public"."audit_logs" USING "btree" ("module_code");



CREATE INDEX "idx_audit_logs_request_id" ON "public"."audit_logs" USING "btree" ("request_id");



CREATE INDEX "idx_audit_logs_user" ON "public"."audit_logs" USING "btree" ("user_id");



CREATE INDEX "idx_campuses_institution" ON "public"."campuses" USING "btree" ("institution_id");



CREATE INDEX "idx_certificate_verifications_certificate_integrity" ON "public"."certificate_verifications" USING "btree" ("certificate_id");



CREATE INDEX "idx_certificate_verifications_code" ON "public"."certificate_verifications" USING "btree" ("verification_code");



CREATE INDEX "idx_certificates_student" ON "public"."certificates" USING "btree" ("student_id");



CREATE INDEX "idx_certificates_student_integrity" ON "public"."certificates" USING "btree" ("student_id");



CREATE INDEX "idx_certificates_verification" ON "public"."certificates" USING "btree" ("verification_code");



CREATE INDEX "idx_cgpa_records_student" ON "public"."student_cgpa_records" USING "btree" ("student_id");



CREATE INDEX "idx_class_students_class" ON "public"."class_students" USING "btree" ("class_id");



CREATE INDEX "idx_class_students_class_status" ON "public"."class_students" USING "btree" ("class_id", "enrollment_status");



CREATE INDEX "idx_class_students_course_registration" ON "public"."class_students" USING "btree" ("course_registration_id");



CREATE INDEX "idx_class_students_student" ON "public"."class_students" USING "btree" ("student_id");



CREATE INDEX "idx_classes_offering" ON "public"."classes" USING "btree" ("course_offering_id");



CREATE INDEX "idx_classes_status" ON "public"."classes" USING "btree" ("status");



CREATE INDEX "idx_course_attempts_course" ON "public"."student_course_attempts" USING "btree" ("course_id");



CREATE INDEX "idx_course_attempts_result" ON "public"."student_course_attempts" USING "btree" ("course_result_id");



CREATE INDEX "idx_course_attempts_student" ON "public"."student_course_attempts" USING "btree" ("student_id");



CREATE INDEX "idx_course_offerings_course" ON "public"."course_offerings" USING "btree" ("course_id");



CREATE INDEX "idx_course_offerings_programme" ON "public"."course_offerings" USING "btree" ("programme_id");



CREATE INDEX "idx_course_offerings_programme_version" ON "public"."course_offerings" USING "btree" ("programme_version_id");



CREATE INDEX "idx_course_offerings_semester" ON "public"."course_offerings" USING "btree" ("semester_id");



CREATE INDEX "idx_course_offerings_status" ON "public"."course_offerings" USING "btree" ("status");



CREATE INDEX "idx_course_offerings_year" ON "public"."course_offerings" USING "btree" ("academic_year_id");



CREATE INDEX "idx_course_prerequisites_course" ON "public"."course_prerequisites" USING "btree" ("course_id");



CREATE INDEX "idx_course_prerequisites_prerequisite" ON "public"."course_prerequisites" USING "btree" ("prerequisite_course_id");



CREATE INDEX "idx_course_reg_course" ON "public"."course_registrations" USING "btree" ("course_id");



CREATE INDEX "idx_course_reg_offering" ON "public"."course_registrations" USING "btree" ("course_offering_id");



CREATE INDEX "idx_course_reg_status" ON "public"."course_registrations" USING "btree" ("registration_status");



CREATE INDEX "idx_course_reg_student" ON "public"."course_registrations" USING "btree" ("student_id");



CREATE INDEX "idx_course_reg_student_registration" ON "public"."course_registrations" USING "btree" ("student_registration_id");



CREATE INDEX "idx_course_result_policies_offering" ON "public"."course_result_policies" USING "btree" ("course_offering_id");



CREATE INDEX "idx_course_results_offering" ON "public"."course_results" USING "btree" ("course_offering_id");



CREATE INDEX "idx_course_results_registration" ON "public"."course_results" USING "btree" ("course_registration_id");



CREATE INDEX "idx_course_results_status" ON "public"."course_results" USING "btree" ("result_status");



CREATE INDEX "idx_course_results_student" ON "public"."course_results" USING "btree" ("student_id");



CREATE INDEX "idx_courses_department" ON "public"."courses" USING "btree" ("department_id");



CREATE INDEX "idx_courses_institution" ON "public"."courses" USING "btree" ("institution_id");



CREATE INDEX "idx_courses_status" ON "public"."courses" USING "btree" ("status");



CREATE INDEX "idx_curricula_programme_version" ON "public"."curricula" USING "btree" ("programme_version_id");



CREATE INDEX "idx_curricula_status" ON "public"."curricula" USING "btree" ("status");



CREATE INDEX "idx_curriculum_courses_course" ON "public"."curriculum_courses" USING "btree" ("course_id");



CREATE INDEX "idx_curriculum_courses_curriculum" ON "public"."curriculum_courses" USING "btree" ("curriculum_id");



CREATE INDEX "idx_curriculum_courses_semester" ON "public"."curriculum_courses" USING "btree" ("semester_number");



CREATE INDEX "idx_deficiencies_status" ON "public"."student_academic_deficiencies" USING "btree" ("deficiency_status");



CREATE INDEX "idx_deficiencies_student" ON "public"."student_academic_deficiencies" USING "btree" ("student_id");



CREATE INDEX "idx_departments_institution" ON "public"."departments" USING "btree" ("institution_id");



CREATE INDEX "idx_departments_school" ON "public"."departments" USING "btree" ("school_id");



CREATE INDEX "idx_emergency_contacts_primary" ON "public"."emergency_contacts" USING "btree" ("student_id", "is_primary");



CREATE INDEX "idx_emergency_contacts_student" ON "public"."emergency_contacts" USING "btree" ("student_id");



CREATE INDEX "idx_exam_attendance_session_candidate" ON "public"."examination_attendance" USING "btree" ("examination_session_id", "examination_candidate_id");



CREATE INDEX "idx_exam_candidate_sessions_candidate" ON "public"."examination_candidate_sessions" USING "btree" ("examination_candidate_id");



CREATE INDEX "idx_exam_candidate_sessions_session" ON "public"."examination_candidate_sessions" USING "btree" ("examination_session_id");



CREATE INDEX "idx_exam_invigilators_user" ON "public"."examination_invigilators" USING "btree" ("user_id");



CREATE INDEX "idx_exam_mark_corrections_mark" ON "public"."examination_mark_corrections" USING "btree" ("examination_mark_id");



CREATE INDEX "idx_exam_marks_paper" ON "public"."examination_marks" USING "btree" ("examination_paper_id");



CREATE INDEX "idx_exam_marks_student" ON "public"."examination_marks" USING "btree" ("student_id");



CREATE INDEX "idx_examination_attendance_candidate" ON "public"."examination_attendance" USING "btree" ("examination_candidate_id");



CREATE INDEX "idx_examination_attendance_session" ON "public"."examination_attendance" USING "btree" ("examination_session_id");



CREATE INDEX "idx_examination_candidates_paper" ON "public"."examination_candidates" USING "btree" ("examination_paper_id");



CREATE INDEX "idx_examination_candidates_registration" ON "public"."examination_candidates" USING "btree" ("course_registration_id");



CREATE INDEX "idx_examination_candidates_status" ON "public"."examination_candidates" USING "btree" ("eligibility_status");



CREATE INDEX "idx_examination_candidates_student" ON "public"."examination_candidates" USING "btree" ("student_id");



CREATE INDEX "idx_examination_invigilators_session" ON "public"."examination_invigilators" USING "btree" ("examination_session_id");



CREATE INDEX "idx_examination_invigilators_user" ON "public"."examination_invigilators" USING "btree" ("user_id");



CREATE INDEX "idx_examination_marks_candidate" ON "public"."examination_marks" USING "btree" ("examination_candidate_id");



CREATE INDEX "idx_examination_marks_paper" ON "public"."examination_marks" USING "btree" ("examination_paper_id");



CREATE INDEX "idx_examination_marks_registration" ON "public"."examination_marks" USING "btree" ("course_registration_id");



CREATE INDEX "idx_examination_marks_status" ON "public"."examination_marks" USING "btree" ("status");



CREATE INDEX "idx_examination_marks_student" ON "public"."examination_marks" USING "btree" ("student_id");



CREATE INDEX "idx_examination_papers_offering" ON "public"."examination_papers" USING "btree" ("course_offering_id");



CREATE INDEX "idx_examination_papers_period" ON "public"."examination_papers" USING "btree" ("examination_period_id");



CREATE INDEX "idx_examination_papers_status" ON "public"."examination_papers" USING "btree" ("status");



CREATE INDEX "idx_examination_periods_academic_year" ON "public"."examination_periods" USING "btree" ("academic_year_id");



CREATE INDEX "idx_examination_periods_semester" ON "public"."examination_periods" USING "btree" ("semester_id");



CREATE INDEX "idx_examination_periods_status" ON "public"."examination_periods" USING "btree" ("status");



CREATE INDEX "idx_examination_sessions_date" ON "public"."examination_sessions" USING "btree" ("examination_date");



CREATE INDEX "idx_examination_sessions_paper" ON "public"."examination_sessions" USING "btree" ("examination_paper_id");



CREATE INDEX "idx_examination_sessions_room" ON "public"."examination_sessions" USING "btree" ("room_id");



CREATE INDEX "idx_fee_adjustments_charge" ON "public"."student_fee_adjustments" USING "btree" ("student_charge_id");



CREATE INDEX "idx_fee_adjustments_student" ON "public"."student_fee_adjustments" USING "btree" ("student_id");



CREATE INDEX "idx_fee_items_category" ON "public"."fee_items" USING "btree" ("category");



CREATE INDEX "idx_fee_items_structure" ON "public"."fee_items" USING "btree" ("fee_structure_id");



CREATE INDEX "idx_fee_structures_status" ON "public"."fee_structures" USING "btree" ("status");



CREATE INDEX "idx_financial_transactions_date" ON "public"."financial_transactions" USING "btree" ("transaction_date");



CREATE INDEX "idx_financial_transactions_invoice" ON "public"."financial_transactions" USING "btree" ("invoice_id");



CREATE INDEX "idx_financial_transactions_payment" ON "public"."financial_transactions" USING "btree" ("payment_id");



CREATE INDEX "idx_financial_transactions_student" ON "public"."financial_transactions" USING "btree" ("student_id");



CREATE INDEX "idx_financial_transactions_type" ON "public"."financial_transactions" USING "btree" ("transaction_type");



CREATE INDEX "idx_gpa_records_student" ON "public"."student_gpa_records" USING "btree" ("student_id");



CREATE INDEX "idx_grade_scale_details_scale" ON "public"."grade_scale_details" USING "btree" ("grade_scale_id");



CREATE INDEX "idx_graduation_approvals_candidate" ON "public"."graduation_approvals" USING "btree" ("graduation_candidate_id");



CREATE INDEX "idx_graduation_approvals_candidate_integrity" ON "public"."graduation_approvals" USING "btree" ("graduation_candidate_id");



CREATE INDEX "idx_graduation_awards_candidate_integrity" ON "public"."graduation_awards" USING "btree" ("graduation_candidate_id");



CREATE INDEX "idx_graduation_candidates_eligibility" ON "public"."graduation_candidates" USING "btree" ("eligibility_status");



CREATE INDEX "idx_graduation_candidates_period" ON "public"."graduation_candidates" USING "btree" ("graduation_period_id");



CREATE INDEX "idx_graduation_candidates_status" ON "public"."graduation_candidates" USING "btree" ("candidate_status");



CREATE INDEX "idx_graduation_candidates_student" ON "public"."graduation_candidates" USING "btree" ("student_id");



CREATE INDEX "idx_graduation_clearances_candidate" ON "public"."graduation_clearances" USING "btree" ("graduation_candidate_id");



CREATE INDEX "idx_graduation_clearances_candidate_integrity" ON "public"."graduation_clearances" USING "btree" ("graduation_candidate_id");



CREATE INDEX "idx_graduation_clearances_status" ON "public"."graduation_clearances" USING "btree" ("status");



CREATE INDEX "idx_guardians_primary" ON "public"."guardians" USING "btree" ("student_id", "is_primary");



CREATE INDEX "idx_guardians_student" ON "public"."guardians" USING "btree" ("student_id");



CREATE INDEX "idx_hostel_allocations_hostel" ON "public"."hostel_allocations" USING "btree" ("hostel_id");



CREATE INDEX "idx_hostel_allocations_room" ON "public"."hostel_allocations" USING "btree" ("room_id");



CREATE INDEX "idx_hostel_allocations_status" ON "public"."hostel_allocations" USING "btree" ("allocation_status");



CREATE INDEX "idx_hostel_allocations_student" ON "public"."hostel_allocations" USING "btree" ("student_id");



CREATE INDEX "idx_hostel_allocations_year" ON "public"."hostel_allocations" USING "btree" ("academic_year");



CREATE INDEX "idx_hostel_beds_room" ON "public"."hostel_beds" USING "btree" ("room_id");



CREATE INDEX "idx_hostel_beds_status" ON "public"."hostel_beds" USING "btree" ("bed_status");



CREATE INDEX "idx_hostel_rooms_hostel" ON "public"."hostel_rooms" USING "btree" ("hostel_id");



CREATE INDEX "idx_hostel_rooms_status" ON "public"."hostel_rooms" USING "btree" ("status");



CREATE INDEX "idx_hostels_institution" ON "public"."hostels" USING "btree" ("institution_id");



CREATE INDEX "idx_hostels_status" ON "public"."hostels" USING "btree" ("status");



CREATE INDEX "idx_inventory_categories_institution" ON "public"."inventory_categories" USING "btree" ("institution_id");



CREATE INDEX "idx_inventory_items_category" ON "public"."inventory_items" USING "btree" ("category_id");



CREATE INDEX "idx_inventory_items_status" ON "public"."inventory_items" USING "btree" ("status");



CREATE INDEX "idx_inventory_transactions_date" ON "public"."inventory_transactions" USING "btree" ("transaction_date");



CREATE INDEX "idx_inventory_transactions_item" ON "public"."inventory_transactions" USING "btree" ("inventory_item_id");



CREATE INDEX "idx_invoice_items_invoice" ON "public"."invoice_items" USING "btree" ("invoice_id");



CREATE INDEX "idx_invoices_due_date" ON "public"."invoices" USING "btree" ("due_date");



CREATE INDEX "idx_invoices_status" ON "public"."invoices" USING "btree" ("status");



CREATE INDEX "idx_invoices_student" ON "public"."invoices" USING "btree" ("student_id");



CREATE INDEX "idx_joining_instructions_programme" ON "public"."joining_instructions" USING "btree" ("programme_id");



CREATE INDEX "idx_joining_instructions_status" ON "public"."joining_instructions" USING "btree" ("status");



CREATE INDEX "idx_joining_instructions_year" ON "public"."joining_instructions" USING "btree" ("academic_year_id");



CREATE INDEX "idx_lecturer_assignments_class" ON "public"."lecturer_assignments" USING "btree" ("class_id");



CREATE INDEX "idx_lecturer_assignments_lecturer" ON "public"."lecturer_assignments" USING "btree" ("lecturer_user_id");



CREATE INDEX "idx_lecturer_assignments_offering" ON "public"."lecturer_assignments" USING "btree" ("course_offering_id");



CREATE INDEX "idx_lecturer_assignments_offering_class" ON "public"."lecturer_assignments" USING "btree" ("course_offering_id", "class_id", "lecturer_user_id");



CREATE INDEX "idx_library_fines_member" ON "public"."library_fines" USING "btree" ("member_id");



CREATE INDEX "idx_library_fines_status" ON "public"."library_fines" USING "btree" ("fine_status");



CREATE INDEX "idx_library_items_author" ON "public"."library_items" USING "btree" ("author");



CREATE INDEX "idx_library_items_institution" ON "public"."library_items" USING "btree" ("institution_id");



CREATE INDEX "idx_library_items_status" ON "public"."library_items" USING "btree" ("item_status");



CREATE INDEX "idx_library_items_title" ON "public"."library_items" USING "btree" ("title");



CREATE INDEX "idx_library_loans_due_date" ON "public"."library_loans" USING "btree" ("due_date");



CREATE INDEX "idx_library_loans_item" ON "public"."library_loans" USING "btree" ("library_item_id");



CREATE INDEX "idx_library_loans_member" ON "public"."library_loans" USING "btree" ("library_member_id");



CREATE INDEX "idx_library_loans_status" ON "public"."library_loans" USING "btree" ("loan_status");



CREATE INDEX "idx_library_members_staff" ON "public"."library_members" USING "btree" ("staff_id");



CREATE INDEX "idx_library_members_status" ON "public"."library_members" USING "btree" ("membership_status");



CREATE INDEX "idx_library_members_student" ON "public"."library_members" USING "btree" ("student_id");



CREATE INDEX "idx_library_reservations_item" ON "public"."library_reservations" USING "btree" ("library_item_id");



CREATE INDEX "idx_library_reservations_member" ON "public"."library_reservations" USING "btree" ("library_member_id");



CREATE INDEX "idx_library_reservations_status" ON "public"."library_reservations" USING "btree" ("reservation_status");



CREATE INDEX "idx_notification_deliveries_notification" ON "public"."notification_deliveries" USING "btree" ("notification_id");



CREATE INDEX "idx_notification_deliveries_provider_message" ON "public"."notification_deliveries" USING "btree" ("provider_message_id");



CREATE INDEX "idx_notification_deliveries_status" ON "public"."notification_deliveries" USING "btree" ("status");



CREATE INDEX "idx_notification_queue_available" ON "public"."notification_queue" USING "btree" ("available_at");



CREATE INDEX "idx_notification_queue_processing" ON "public"."notification_queue" USING "btree" ("status", "available_at");



CREATE INDEX "idx_notification_queue_status" ON "public"."notification_queue" USING "btree" ("status");



CREATE INDEX "idx_notification_templates_active" ON "public"."notification_templates" USING "btree" ("is_active");



CREATE INDEX "idx_notification_templates_channel" ON "public"."notification_templates" USING "btree" ("channel");



CREATE INDEX "idx_notifications_created_at" ON "public"."notifications" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_notifications_recipient_student" ON "public"."notifications" USING "btree" ("recipient_student_id");



CREATE INDEX "idx_notifications_recipient_user" ON "public"."notifications" USING "btree" ("recipient_user_id");



CREATE INDEX "idx_notifications_scheduled_at" ON "public"."notifications" USING "btree" ("scheduled_at");



CREATE INDEX "idx_notifications_status" ON "public"."notifications" USING "btree" ("status");



CREATE INDEX "idx_notifications_type" ON "public"."notifications" USING "btree" ("notification_type");



CREATE INDEX "idx_payment_allocations_charge" ON "public"."payment_allocations" USING "btree" ("student_charge_id");



CREATE INDEX "idx_payment_allocations_invoice" ON "public"."payment_allocations" USING "btree" ("invoice_id");



CREATE INDEX "idx_payment_allocations_payment" ON "public"."payment_allocations" USING "btree" ("payment_id");



CREATE INDEX "idx_payments_control_number" ON "public"."payments" USING "btree" ("control_number");



CREATE INDEX "idx_payments_date" ON "public"."payments" USING "btree" ("payment_date");



CREATE INDEX "idx_payments_status" ON "public"."payments" USING "btree" ("status");



CREATE INDEX "idx_payments_student" ON "public"."payments" USING "btree" ("student_id");



CREATE INDEX "idx_permissions_action" ON "public"."permissions" USING "btree" ("action_code");



CREATE INDEX "idx_permissions_module" ON "public"."permissions" USING "btree" ("module_code");



CREATE INDEX "idx_procurement_request_items_request" ON "public"."procurement_request_items" USING "btree" ("procurement_request_id");



CREATE INDEX "idx_procurement_requests_department" ON "public"."procurement_requests" USING "btree" ("department_id");



CREATE INDEX "idx_procurement_requests_institution" ON "public"."procurement_requests" USING "btree" ("institution_id");



CREATE INDEX "idx_procurement_requests_status" ON "public"."procurement_requests" USING "btree" ("request_status");



CREATE INDEX "idx_programme_versions_programme" ON "public"."programme_versions" USING "btree" ("programme_id");



CREATE INDEX "idx_programme_versions_status" ON "public"."programme_versions" USING "btree" ("status");



CREATE INDEX "idx_programmes_department" ON "public"."programmes" USING "btree" ("department_id");



CREATE INDEX "idx_programmes_institution" ON "public"."programmes" USING "btree" ("institution_id");



CREATE INDEX "idx_programmes_school" ON "public"."programmes" USING "btree" ("school_id");



CREATE INDEX "idx_programmes_status" ON "public"."programmes" USING "btree" ("status");



CREATE INDEX "idx_purchase_order_items_order" ON "public"."purchase_order_items" USING "btree" ("purchase_order_id");



CREATE INDEX "idx_purchase_orders_status" ON "public"."purchase_orders" USING "btree" ("order_status");



CREATE INDEX "idx_purchase_orders_supplier" ON "public"."purchase_orders" USING "btree" ("supplier_id");



CREATE INDEX "idx_refunds_payment" ON "public"."refunds" USING "btree" ("payment_id");



CREATE INDEX "idx_refunds_status" ON "public"."refunds" USING "btree" ("status");



CREATE INDEX "idx_refunds_student" ON "public"."refunds" USING "btree" ("student_id");



CREATE INDEX "idx_registration_approvals_registration" ON "public"."registration_approvals" USING "btree" ("student_registration_id");



CREATE INDEX "idx_registration_approvals_status" ON "public"."registration_approvals" USING "btree" ("approval_status");



CREATE INDEX "idx_result_corrections_result" ON "public"."course_result_corrections" USING "btree" ("course_result_id");



CREATE INDEX "idx_role_permissions_permission" ON "public"."role_permissions" USING "btree" ("permission_id");



CREATE INDEX "idx_role_permissions_role" ON "public"."role_permissions" USING "btree" ("role_id");



CREATE INDEX "idx_rooms_campus" ON "public"."rooms" USING "btree" ("campus_id");



CREATE INDEX "idx_rooms_status" ON "public"."rooms" USING "btree" ("status");



CREATE INDEX "idx_rooms_type" ON "public"."rooms" USING "btree" ("room_type");



CREATE INDEX "idx_schools_campus" ON "public"."schools" USING "btree" ("campus_id");



CREATE INDEX "idx_schools_institution" ON "public"."schools" USING "btree" ("institution_id");



CREATE INDEX "idx_security_logs_created_at" ON "public"."security_logs" USING "btree" ("created_at");



CREATE INDEX "idx_security_logs_event" ON "public"."security_logs" USING "btree" ("event_code");



CREATE INDEX "idx_security_logs_user" ON "public"."security_logs" USING "btree" ("user_id");



CREATE INDEX "idx_semester_results_student" ON "public"."student_semester_results" USING "btree" ("student_id");



CREATE INDEX "idx_semesters_academic_year" ON "public"."semesters" USING "btree" ("academic_year_id");



CREATE INDEX "idx_semesters_status" ON "public"."semesters" USING "btree" ("status");



CREATE INDEX "idx_staff_attendance_adjustments_attendance" ON "public"."staff_attendance_adjustments" USING "btree" ("attendance_id");



CREATE INDEX "idx_staff_attendance_adjustments_status" ON "public"."staff_attendance_adjustments" USING "btree" ("adjustment_status");



CREATE INDEX "idx_staff_attendance_date" ON "public"."staff_attendance" USING "btree" ("attendance_date");



CREATE INDEX "idx_staff_attendance_staff" ON "public"."staff_attendance" USING "btree" ("staff_id");



CREATE INDEX "idx_staff_attendance_status" ON "public"."staff_attendance" USING "btree" ("attendance_status");



CREATE INDEX "idx_staff_category" ON "public"."staff" USING "btree" ("staff_category");



CREATE INDEX "idx_staff_department" ON "public"."staff" USING "btree" ("department_id");



CREATE INDEX "idx_staff_documents_expiry" ON "public"."staff_documents" USING "btree" ("expiry_date");



CREATE INDEX "idx_staff_documents_staff" ON "public"."staff_documents" USING "btree" ("staff_id");



CREATE INDEX "idx_staff_documents_status" ON "public"."staff_documents" USING "btree" ("verification_status");



CREATE INDEX "idx_staff_employment_history_staff" ON "public"."staff_employment_history" USING "btree" ("staff_id");



CREATE INDEX "idx_staff_employment_type" ON "public"."staff" USING "btree" ("employment_type");



CREATE INDEX "idx_staff_institution" ON "public"."staff" USING "btree" ("institution_id");



CREATE INDEX "idx_staff_last_name" ON "public"."staff" USING "btree" ("last_name");



CREATE INDEX "idx_staff_leave_approvals_approver" ON "public"."staff_leave_approvals" USING "btree" ("approver_user_id");



CREATE INDEX "idx_staff_leave_approvals_request" ON "public"."staff_leave_approvals" USING "btree" ("leave_request_id");



CREATE INDEX "idx_staff_leave_balances_staff" ON "public"."staff_leave_balances" USING "btree" ("staff_id");



CREATE INDEX "idx_staff_leave_balances_year" ON "public"."staff_leave_balances" USING "btree" ("leave_year");



CREATE INDEX "idx_staff_leave_requests_dates" ON "public"."staff_leave_requests" USING "btree" ("start_date", "end_date");



CREATE INDEX "idx_staff_leave_requests_staff" ON "public"."staff_leave_requests" USING "btree" ("staff_id");



CREATE INDEX "idx_staff_leave_requests_status" ON "public"."staff_leave_requests" USING "btree" ("request_status");



CREATE INDEX "idx_staff_leave_types_institution" ON "public"."staff_leave_types" USING "btree" ("institution_id");



CREATE INDEX "idx_staff_leave_types_status" ON "public"."staff_leave_types" USING "btree" ("status");



CREATE INDEX "idx_staff_lifecycle_events_date" ON "public"."staff_lifecycle_events" USING "btree" ("effective_date");



CREATE INDEX "idx_staff_lifecycle_events_staff" ON "public"."staff_lifecycle_events" USING "btree" ("staff_id");



CREATE INDEX "idx_staff_lifecycle_events_type" ON "public"."staff_lifecycle_events" USING "btree" ("event_type");



CREATE INDEX "idx_staff_qualification_staff" ON "public"."staff_qualifications" USING "btree" ("staff_id");



CREATE INDEX "idx_staff_qualification_status" ON "public"."staff_qualifications" USING "btree" ("verification_status");



CREATE INDEX "idx_staff_status" ON "public"."staff" USING "btree" ("employment_status");



CREATE INDEX "idx_staff_user" ON "public"."staff" USING "btree" ("user_id");



CREATE INDEX "idx_student_charges_due_date" ON "public"."student_charges" USING "btree" ("due_date");



CREATE INDEX "idx_student_charges_status" ON "public"."student_charges" USING "btree" ("status");



CREATE INDEX "idx_student_charges_student" ON "public"."student_charges" USING "btree" ("student_id");



CREATE INDEX "idx_student_documents_status" ON "public"."student_documents" USING "btree" ("verification_status");



CREATE INDEX "idx_student_documents_student" ON "public"."student_documents" USING "btree" ("student_id");



CREATE INDEX "idx_student_financial_accounts_status" ON "public"."student_financial_accounts" USING "btree" ("account_status");



CREATE INDEX "idx_student_financial_accounts_student" ON "public"."student_financial_accounts" USING "btree" ("student_id");



CREATE INDEX "idx_student_profiles_email" ON "public"."student_profiles" USING "btree" ("email");



CREATE INDEX "idx_student_profiles_national_id" ON "public"."student_profiles" USING "btree" ("national_id_number");



CREATE INDEX "idx_student_profiles_phone" ON "public"."student_profiles" USING "btree" ("phone");



CREATE INDEX "idx_student_programme_history_dates" ON "public"."student_programme_history" USING "btree" ("effective_from", "effective_to");



CREATE INDEX "idx_student_programme_history_programme" ON "public"."student_programme_history" USING "btree" ("programme_id");



CREATE INDEX "idx_student_programme_history_student" ON "public"."student_programme_history" USING "btree" ("student_id");



CREATE INDEX "idx_student_registrations_programme" ON "public"."student_registrations" USING "btree" ("programme_id");



CREATE INDEX "idx_student_registrations_semester" ON "public"."student_registrations" USING "btree" ("semester_id");



CREATE INDEX "idx_student_registrations_status" ON "public"."student_registrations" USING "btree" ("registration_status");



CREATE INDEX "idx_student_registrations_student" ON "public"."student_registrations" USING "btree" ("student_id");



CREATE INDEX "idx_student_registrations_year" ON "public"."student_registrations" USING "btree" ("academic_year_id");



CREATE INDEX "idx_student_scholarships_status" ON "public"."student_scholarships" USING "btree" ("status");



CREATE INDEX "idx_student_scholarships_student" ON "public"."student_scholarships" USING "btree" ("student_id");



CREATE INDEX "idx_student_status_history_changed_at" ON "public"."student_status_history" USING "btree" ("changed_at");



CREATE INDEX "idx_student_status_history_student" ON "public"."student_status_history" USING "btree" ("student_id");



CREATE INDEX "idx_student_transcript_courses_transcript" ON "public"."student_transcript_courses" USING "btree" ("transcript_id");



CREATE INDEX "idx_student_transcript_semesters_transcript" ON "public"."student_transcript_semesters" USING "btree" ("transcript_id");



CREATE INDEX "idx_student_transcripts_student_status" ON "public"."student_transcripts" USING "btree" ("student_id", "transcript_status");



CREATE INDEX "idx_student_transcripts_verification" ON "public"."student_transcripts" USING "btree" ("verification_code") WHERE ("verification_code" IS NOT NULL);



CREATE INDEX "idx_students_applicant" ON "public"."students" USING "btree" ("applicant_id");



CREATE INDEX "idx_students_application" ON "public"."students" USING "btree" ("source_application_id");



CREATE INDEX "idx_students_email" ON "public"."students" USING "btree" ("email");



CREATE INDEX "idx_students_institution_id" ON "public"."students" USING "btree" ("institution_id");



CREATE INDEX "idx_students_names" ON "public"."students" USING "btree" ("last_name", "first_name");



CREATE INDEX "idx_students_offer" ON "public"."students" USING "btree" ("admission_offer_id");



CREATE INDEX "idx_students_programme" ON "public"."students" USING "btree" ("programme_id");



CREATE INDEX "idx_students_programme_version" ON "public"."students" USING "btree" ("programme_version_id");



CREATE INDEX "idx_students_status" ON "public"."students" USING "btree" ("student_status");



CREATE INDEX "idx_students_status_programme" ON "public"."students" USING "btree" ("student_status", "programme_id");



CREATE INDEX "idx_students_student_number" ON "public"."students" USING "btree" ("student_number");



CREATE INDEX "idx_students_user_id" ON "public"."students" USING "btree" ("user_id");



CREATE INDEX "idx_suppliers_institution" ON "public"."suppliers" USING "btree" ("institution_id");



CREATE INDEX "idx_suppliers_status" ON "public"."suppliers" USING "btree" ("status");



CREATE INDEX "idx_timetable_entries_class" ON "public"."timetable_entries" USING "btree" ("class_id");



CREATE INDEX "idx_timetable_entries_course_offering" ON "public"."timetable_entries" USING "btree" ("course_offering_id");



CREATE INDEX "idx_timetable_entries_lecturer" ON "public"."timetable_entries" USING "btree" ("lecturer_assignment_id");



CREATE INDEX "idx_timetable_entries_room" ON "public"."timetable_entries" USING "btree" ("room_id");



CREATE INDEX "idx_timetable_entries_slot" ON "public"."timetable_entries" USING "btree" ("timetable_slot_id");



CREATE INDEX "idx_timetable_entries_timetable" ON "public"."timetable_entries" USING "btree" ("timetable_id");



CREATE INDEX "idx_timetable_entries_timetable_class" ON "public"."timetable_entries" USING "btree" ("timetable_id", "class_id", "timetable_slot_id");



CREATE INDEX "idx_timetable_entries_timetable_room" ON "public"."timetable_entries" USING "btree" ("timetable_id", "room_id", "timetable_slot_id");



CREATE INDEX "idx_timetable_slots_day" ON "public"."timetable_slots" USING "btree" ("day_of_week");



CREATE INDEX "idx_timetable_slots_time" ON "public"."timetable_slots" USING "btree" ("start_time", "end_time");



CREATE INDEX "idx_timetables_campus" ON "public"."timetables" USING "btree" ("campus_id");



CREATE INDEX "idx_timetables_semester" ON "public"."timetables" USING "btree" ("semester_id");



CREATE INDEX "idx_timetables_status" ON "public"."timetables" USING "btree" ("status");



CREATE INDEX "idx_timetables_year" ON "public"."timetables" USING "btree" ("academic_year_id");



CREATE INDEX "idx_transcript_courses_result" ON "public"."student_transcript_courses" USING "btree" ("course_result_id");



CREATE INDEX "idx_transcript_courses_transcript" ON "public"."student_transcript_courses" USING "btree" ("transcript_id");



CREATE INDEX "idx_transcript_semesters_transcript" ON "public"."student_transcript_semesters" USING "btree" ("transcript_id");



CREATE INDEX "idx_transcripts_status" ON "public"."student_transcripts" USING "btree" ("transcript_status");



CREATE INDEX "idx_transcripts_student" ON "public"."student_transcripts" USING "btree" ("student_id");



CREATE INDEX "idx_transcripts_verification" ON "public"."student_transcripts" USING "btree" ("verification_code");



CREATE INDEX "idx_user_addresses_primary" ON "public"."user_addresses" USING "btree" ("user_id", "is_primary");



CREATE INDEX "idx_user_addresses_type" ON "public"."user_addresses" USING "btree" ("address_type");



CREATE INDEX "idx_user_addresses_user" ON "public"."user_addresses" USING "btree" ("user_id");



CREATE INDEX "idx_user_preferences_user" ON "public"."user_preferences" USING "btree" ("user_id");



CREATE INDEX "idx_user_profiles_gender" ON "public"."user_profiles" USING "btree" ("gender");



CREATE INDEX "idx_user_profiles_national_id" ON "public"."user_profiles" USING "btree" ("national_id_number");



CREATE INDEX "idx_user_profiles_nationality" ON "public"."user_profiles" USING "btree" ("nationality");



CREATE INDEX "idx_user_profiles_passport" ON "public"."user_profiles" USING "btree" ("passport_number");



CREATE INDEX "idx_user_profiles_user" ON "public"."user_profiles" USING "btree" ("user_id");



CREATE INDEX "idx_user_roles_role" ON "public"."user_roles" USING "btree" ("role_id");



CREATE INDEX "idx_user_roles_user" ON "public"."user_roles" USING "btree" ("user_id");



CREATE INDEX "idx_user_scopes_campus" ON "public"."user_scopes" USING "btree" ("campus_id");



CREATE INDEX "idx_user_scopes_department" ON "public"."user_scopes" USING "btree" ("department_id");



CREATE INDEX "idx_user_scopes_institution" ON "public"."user_scopes" USING "btree" ("institution_id");



CREATE INDEX "idx_user_scopes_school" ON "public"."user_scopes" USING "btree" ("school_id");



CREATE INDEX "idx_user_scopes_user" ON "public"."user_scopes" USING "btree" ("user_id");



CREATE INDEX "idx_user_status_history_changed_at" ON "public"."user_status_history" USING "btree" ("changed_at");



CREATE INDEX "idx_user_status_history_new_status" ON "public"."user_status_history" USING "btree" ("new_status");



CREATE INDEX "idx_user_status_history_user" ON "public"."user_status_history" USING "btree" ("user_id");



CREATE INDEX "idx_users_auth_user_id" ON "public"."users" USING "btree" ("auth_user_id");



CREATE INDEX "idx_users_email" ON "public"."users" USING "btree" ("email");



CREATE INDEX "idx_users_status" ON "public"."users" USING "btree" ("status");



CREATE UNIQUE INDEX "uq_accepted_admission_offer" ON "public"."admission_acceptances" USING "btree" ("admission_offer_id") WHERE (("acceptance_status")::"text" = 'ACCEPTED'::"text");



COMMENT ON INDEX "public"."uq_accepted_admission_offer" IS 'Prevents multiple accepted admission acceptance records for one offer.';



CREATE UNIQUE INDEX "uq_active_admission_offer_application" ON "public"."admission_offers" USING "btree" ("application_id") WHERE (("offer_status")::"text" = ANY ((ARRAY['ISSUED'::character varying, 'ACCEPTED'::character varying])::"text"[]));



COMMENT ON INDEX "public"."uq_active_admission_offer_application" IS 'Prevents more than one active admission offer per application.';



CREATE UNIQUE INDEX "uq_active_assessment_mark_correction" ON "public"."assessment_mark_corrections" USING "btree" ("assessment_mark_id") WHERE (("status")::"text" = 'PENDING'::"text");



CREATE UNIQUE INDEX "uq_active_course_registration" ON "public"."course_registrations" USING "btree" ("student_registration_id", "course_id") WHERE (("registration_status")::"text" <> ALL ((ARRAY['DROPPED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying])::"text"[]));



CREATE UNIQUE INDEX "uq_active_lecturer_offering" ON "public"."lecturer_assignments" USING "btree" ("course_offering_id", "lecturer_user_id", COALESCE("class_id", '00000000-0000-0000-0000-000000000000'::"uuid")) WHERE (("assignment_status")::"text" = 'ACTIVE'::"text");



CREATE UNIQUE INDEX "uq_active_student_registration" ON "public"."student_registrations" USING "btree" ("student_id", "academic_year_id", "semester_id") WHERE (("registration_status")::"text" <> 'CANCELLED'::"text");



CREATE UNIQUE INDEX "uq_alumni_records_graduation_award" ON "public"."alumni_records" USING "btree" ("graduation_award_id") WHERE ("graduation_award_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_alumni_records_graduation_candidate" ON "public"."alumni_records" USING "btree" ("graduation_candidate_id") WHERE ("graduation_candidate_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_alumni_records_student" ON "public"."alumni_records" USING "btree" ("student_id");



CREATE UNIQUE INDEX "uq_approved_admission_decision_application" ON "public"."admission_decisions" USING "btree" ("application_id") WHERE (("decision_status")::"text" = 'APPROVED'::"text");



COMMENT ON INDEX "public"."uq_approved_admission_decision_application" IS 'Prevents more than one approved admission decision per application.';



CREATE UNIQUE INDEX "uq_course_offering_course_semester" ON "public"."course_offerings" USING "btree" ("academic_year_id", "semester_id", "programme_id", "course_id", COALESCE("section_name", ''::character varying));



CREATE UNIQUE INDEX "uq_course_result_active_attempt" ON "public"."course_results" USING "btree" ("student_id", "course_offering_id") WHERE (("result_status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'CALCULATED'::character varying, 'SUBMITTED'::character varying, 'UNDER_REVIEW'::character varying, 'APPROVED'::character varying, 'PUBLISHED'::character varying, 'LOCKED'::character varying, 'WITHHELD'::character varying, 'INCOMPLETE'::character varying])::"text"[]));



CREATE UNIQUE INDEX "uq_exam_candidate_one_session" ON "public"."examination_candidate_sessions" USING "btree" ("examination_candidate_id") WHERE (("assignment_status")::"text" = ANY ((ARRAY['ASSIGNED'::character varying, 'CONFIRMED'::character varying, 'MOVED'::character varying])::"text"[]));



CREATE UNIQUE INDEX "uq_exam_session_candidate" ON "public"."examination_candidate_sessions" USING "btree" ("examination_session_id", "examination_candidate_id");



CREATE UNIQUE INDEX "uq_exam_session_seat" ON "public"."examination_candidate_sessions" USING "btree" ("examination_session_id", "seat_number") WHERE (("seat_number" IS NOT NULL) AND (("assignment_status")::"text" = ANY ((ARRAY['ASSIGNED'::character varying, 'CONFIRMED'::character varying, 'MOVED'::character varying])::"text"[])));



CREATE UNIQUE INDEX "uq_pending_course_result_correction" ON "public"."course_result_corrections" USING "btree" ("course_result_id") WHERE (("status")::"text" = 'PENDING'::"text");



CREATE UNIQUE INDEX "uq_pending_examination_mark_correction" ON "public"."examination_mark_corrections" USING "btree" ("examination_mark_id") WHERE (("status")::"text" = 'PENDING'::"text");



CREATE UNIQUE INDEX "uq_primary_emergency_contact_per_student" ON "public"."emergency_contacts" USING "btree" ("student_id") WHERE ("is_primary" = true);



CREATE UNIQUE INDEX "uq_primary_guardian_per_student" ON "public"."guardians" USING "btree" ("student_id") WHERE ("is_primary" = true);



CREATE UNIQUE INDEX "uq_student_active_programme" ON "public"."student_programme_history" USING "btree" ("student_id") WHERE ("effective_to" IS NULL);



CREATE UNIQUE INDEX "uq_student_active_transcript_workflow" ON "public"."student_transcripts" USING "btree" ("student_id", "transcript_type") WHERE (("transcript_status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'GENERATED'::character varying, 'REVIEW'::character varying, 'APPROVED'::character varying])::"text"[]));



CREATE UNIQUE INDEX "uq_student_course_open_deficiency" ON "public"."student_academic_deficiencies" USING "btree" ("student_id", "course_id", "deficiency_type") WHERE ((("deficiency_status")::"text" = ANY ((ARRAY['OPEN'::character varying, 'IN_PROGRESS'::character varying])::"text"[])) AND ("course_id" IS NOT NULL));



CREATE UNIQUE INDEX "uq_timetables_active_context" ON "public"."timetables" USING "btree" ("academic_year_id", "semester_id", "campus_id") WHERE (("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'REVIEW'::character varying, 'APPROVED'::character varying, 'PUBLISHED'::character varying, 'LOCKED'::character varying])::"text"[]));



CREATE UNIQUE INDEX "uq_transcript_course_result" ON "public"."student_transcript_courses" USING "btree" ("transcript_id", "course_result_id") WHERE ("course_result_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_transcript_semester_context" ON "public"."student_transcript_semesters" USING "btree" ("transcript_id", "academic_year_id", "semester_id");



CREATE UNIQUE INDEX "ux_alumni_graduation_candidate" ON "public"."alumni_records" USING "btree" ("graduation_candidate_id") WHERE ("graduation_candidate_id" IS NOT NULL);



CREATE UNIQUE INDEX "ux_certificates_active_award" ON "public"."certificates" USING "btree" ("graduation_award_id") WHERE (("status")::"text" = ANY ((ARRAY['DRAFT'::character varying, 'APPROVED'::character varying, 'ISSUED'::character varying])::"text"[]));



CREATE UNIQUE INDEX "ux_graduation_period_open_year" ON "public"."graduation_periods" USING "btree" ("academic_year_id") WHERE (("status")::"text" = 'OPEN'::"text");



CREATE OR REPLACE TRIGGER "trg_academic_qualifications_updated_at" BEFORE UPDATE ON "public"."academic_qualifications" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_academic_standing_rules_updated_at" BEFORE UPDATE ON "public"."academic_standing_rules" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_academic_years_updated_at" BEFORE UPDATE ON "public"."academic_years" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_admission_acceptances_updated_at" BEFORE UPDATE ON "public"."admission_acceptances" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_admission_decisions_updated_at" BEFORE UPDATE ON "public"."admission_decisions" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_admission_offers_updated_at" BEFORE UPDATE ON "public"."admission_offers" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_alumni_records_updated_at" BEFORE UPDATE ON "public"."alumni_records" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_applicants_updated_at" BEFORE UPDATE ON "public"."applicants" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_application_choices_updated_at" BEFORE UPDATE ON "public"."application_choices" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_application_documents_updated_at" BEFORE UPDATE ON "public"."application_documents" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_applications_updated_at" BEFORE UPDATE ON "public"."applications" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_assessment_mark_corrections_updated_at" BEFORE UPDATE ON "public"."assessment_mark_corrections" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_assessment_marks_updated_at" BEFORE UPDATE ON "public"."assessment_marks" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_assessment_submissions_updated_at" BEFORE UPDATE ON "public"."assessment_submissions" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_assessments_updated_at" BEFORE UPDATE ON "public"."assessments" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_asset_categories_updated_at" BEFORE UPDATE ON "public"."asset_categories" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_assets_updated_at" BEFORE UPDATE ON "public"."assets" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_attendance_corrections_updated_at" BEFORE UPDATE ON "public"."attendance_corrections" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_attendance_records_updated_at" BEFORE UPDATE ON "public"."attendance_records" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_attendance_sessions_updated_at" BEFORE UPDATE ON "public"."attendance_sessions" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_campuses_updated_at" BEFORE UPDATE ON "public"."campuses" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_certificates_updated_at" BEFORE UPDATE ON "public"."certificates" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_class_students_updated_at" BEFORE UPDATE ON "public"."class_students" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_classes_updated_at" BEFORE UPDATE ON "public"."classes" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_course_add_drop_updated_at" BEFORE UPDATE ON "public"."course_add_drop_requests" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_course_offerings_updated_at" BEFORE UPDATE ON "public"."course_offerings" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_course_registrations_updated_at" BEFORE UPDATE ON "public"."course_registrations" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_course_result_corrections_updated_at" BEFORE UPDATE ON "public"."course_result_corrections" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_course_result_policies_updated_at" BEFORE UPDATE ON "public"."course_result_policies" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_course_results_updated_at" BEFORE UPDATE ON "public"."course_results" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_courses_updated_at" BEFORE UPDATE ON "public"."courses" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_create_result_deficiency" AFTER INSERT OR UPDATE ON "public"."course_results" FOR EACH ROW EXECUTE FUNCTION "public"."create_result_deficiency"();



CREATE OR REPLACE TRIGGER "trg_curricula_updated_at" BEFORE UPDATE ON "public"."curricula" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_curriculum_courses_updated_at" BEFORE UPDATE ON "public"."curriculum_courses" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_departments_updated_at" BEFORE UPDATE ON "public"."departments" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_emergency_contacts_updated_at" BEFORE UPDATE ON "public"."emergency_contacts" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_examination_attendance_updated_at" BEFORE UPDATE ON "public"."examination_attendance" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_examination_candidate_sessions_updated_at" BEFORE UPDATE ON "public"."examination_candidate_sessions" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_examination_candidates_updated_at" BEFORE UPDATE ON "public"."examination_candidates" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_examination_invigilators_updated_at" BEFORE UPDATE ON "public"."examination_invigilators" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_examination_mark_corrections_updated_at" BEFORE UPDATE ON "public"."examination_mark_corrections" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_examination_marks_updated_at" BEFORE UPDATE ON "public"."examination_marks" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_examination_papers_updated_at" BEFORE UPDATE ON "public"."examination_papers" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_examination_periods_updated_at" BEFORE UPDATE ON "public"."examination_periods" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_examination_sessions_updated_at" BEFORE UPDATE ON "public"."examination_sessions" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_fee_items_updated_at" BEFORE UPDATE ON "public"."fee_items" FOR EACH ROW EXECUTE FUNCTION "public"."touch_finance_updated_at"();



CREATE OR REPLACE TRIGGER "trg_fee_structures_updated_at" BEFORE UPDATE ON "public"."fee_structures" FOR EACH ROW EXECUTE FUNCTION "public"."touch_finance_updated_at"();



CREATE OR REPLACE TRIGGER "trg_generate_graduation_clearances" AFTER INSERT ON "public"."graduation_candidates" FOR EACH ROW EXECUTE FUNCTION "public"."trg_generate_graduation_clearances"();



CREATE OR REPLACE TRIGGER "trg_generate_library_loan_number" BEFORE INSERT ON "public"."library_loans" FOR EACH ROW EXECUTE FUNCTION "public"."generate_library_loan_number"();



CREATE OR REPLACE TRIGGER "trg_generate_procurement_request_number" BEFORE INSERT ON "public"."procurement_requests" FOR EACH ROW EXECUTE FUNCTION "public"."generate_procurement_request_number"();



CREATE OR REPLACE TRIGGER "trg_generate_purchase_order_number" BEFORE INSERT ON "public"."purchase_orders" FOR EACH ROW EXECUTE FUNCTION "public"."generate_purchase_order_number"();



CREATE OR REPLACE TRIGGER "trg_generate_staff_employee_number" BEFORE INSERT ON "public"."staff" FOR EACH ROW EXECUTE FUNCTION "public"."generate_staff_employee_number"();



CREATE OR REPLACE TRIGGER "trg_generate_staff_leave_request_number" BEFORE INSERT ON "public"."staff_leave_requests" FOR EACH ROW EXECUTE FUNCTION "public"."generate_staff_leave_request_number"();



CREATE OR REPLACE TRIGGER "trg_grade_scale_details_updated_at" BEFORE UPDATE ON "public"."grade_scale_details" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_grade_scales_updated_at" BEFORE UPDATE ON "public"."grade_scales" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_graduation_candidate_transition" BEFORE UPDATE ON "public"."graduation_candidates" FOR EACH ROW EXECUTE FUNCTION "public"."validate_graduation_candidate_transition"();



CREATE OR REPLACE TRIGGER "trg_graduation_candidates_updated_at" BEFORE UPDATE ON "public"."graduation_candidates" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_graduation_clearance_items_updated_at" BEFORE UPDATE ON "public"."graduation_clearance_items" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_graduation_clearances_updated_at" BEFORE UPDATE ON "public"."graduation_clearances" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_graduation_periods_updated_at" BEFORE UPDATE ON "public"."graduation_periods" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_guardians_updated_at" BEFORE UPDATE ON "public"."guardians" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_hostel_allocations_updated_at" BEFORE UPDATE ON "public"."hostel_allocations" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_hostel_beds_updated_at" BEFORE UPDATE ON "public"."hostel_beds" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_hostel_fees_updated_at" BEFORE UPDATE ON "public"."hostel_fees" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_hostel_rooms_updated_at" BEFORE UPDATE ON "public"."hostel_rooms" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_hostels_updated_at" BEFORE UPDATE ON "public"."hostels" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_institutions_updated_at" BEFORE UPDATE ON "public"."institutions" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_inventory_categories_updated_at" BEFORE UPDATE ON "public"."inventory_categories" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_inventory_items_updated_at" BEFORE UPDATE ON "public"."inventory_items" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_invoice_item_refresh" AFTER INSERT OR DELETE OR UPDATE ON "public"."invoice_items" FOR EACH ROW EXECUTE FUNCTION "public"."trg_refresh_invoice_after_item"();



CREATE OR REPLACE TRIGGER "trg_invoices_updated_at" BEFORE UPDATE ON "public"."invoices" FOR EACH ROW EXECUTE FUNCTION "public"."touch_finance_updated_at"();



CREATE OR REPLACE TRIGGER "trg_joining_instructions_updated_at" BEFORE UPDATE ON "public"."joining_instructions" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_lecturer_assignments_updated_at" BEFORE UPDATE ON "public"."lecturer_assignments" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_library_fines_updated_at" BEFORE UPDATE ON "public"."library_fines" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_library_items_updated_at" BEFORE UPDATE ON "public"."library_items" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_library_loans_updated_at" BEFORE UPDATE ON "public"."library_loans" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_library_members_updated_at" BEFORE UPDATE ON "public"."library_members" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_library_reservations_updated_at" BEFORE UPDATE ON "public"."library_reservations" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_payment_allocation_refresh_financials" AFTER INSERT OR DELETE OR UPDATE ON "public"."payment_allocations" FOR EACH ROW EXECUTE FUNCTION "public"."trg_refresh_financials_after_allocation"();



CREATE OR REPLACE TRIGGER "trg_payment_allocations_updated_at" BEFORE UPDATE ON "public"."payment_allocations" FOR EACH ROW EXECUTE FUNCTION "public"."touch_finance_updated_at"();



CREATE OR REPLACE TRIGGER "trg_payment_refresh_student_account" AFTER INSERT OR UPDATE OF "status", "amount" ON "public"."payments" FOR EACH ROW EXECUTE FUNCTION "public"."trg_refresh_after_payment_status"();



CREATE OR REPLACE TRIGGER "trg_payments_updated_at" BEFORE UPDATE ON "public"."payments" FOR EACH ROW EXECUTE FUNCTION "public"."touch_finance_updated_at"();



CREATE OR REPLACE TRIGGER "trg_prepare_student_transcript" BEFORE INSERT ON "public"."student_transcripts" FOR EACH ROW EXECUTE FUNCTION "public"."prepare_student_transcript"();



CREATE OR REPLACE TRIGGER "trg_prevent_add_drop_after_lock" BEFORE INSERT OR DELETE OR UPDATE ON "public"."course_add_drop_requests" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_add_drop_after_lock"();



CREATE OR REPLACE TRIGGER "trg_prevent_alumni_hard_delete" BEFORE DELETE ON "public"."alumni_records" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_alumni_hard_delete"();



CREATE OR REPLACE TRIGGER "trg_prevent_assessment_mark_delete" BEFORE DELETE ON "public"."assessment_marks" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_assessment_mark_delete"();



CREATE OR REPLACE TRIGGER "trg_prevent_course_result_delete" BEFORE DELETE ON "public"."course_results" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_course_result_delete"();



CREATE OR REPLACE TRIGGER "trg_prevent_delivery_delete" BEFORE DELETE ON "public"."notification_deliveries" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_notification_history_delete"();



CREATE OR REPLACE TRIGGER "trg_prevent_examination_mark_delete" BEFORE DELETE ON "public"."examination_marks" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_examination_mark_delete"();



CREATE OR REPLACE TRIGGER "trg_prevent_financial_account_delete" BEFORE DELETE ON "public"."student_financial_accounts" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_financial_account_delete"();



CREATE OR REPLACE TRIGGER "trg_prevent_financial_transaction_delete" BEFORE DELETE ON "public"."financial_transactions" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_financial_transaction_delete"();



CREATE OR REPLACE TRIGGER "trg_prevent_invalid_offer_status_change" BEFORE UPDATE OF "offer_status" ON "public"."admission_offers" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_invalid_offer_status_change"();



CREATE OR REPLACE TRIGGER "trg_prevent_issued_certificate_change" BEFORE UPDATE ON "public"."certificates" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_issued_certificate_change"();



CREATE OR REPLACE TRIGGER "trg_prevent_issued_transcript_change" BEFORE UPDATE ON "public"."student_transcripts" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_issued_transcript_change"();



CREATE OR REPLACE TRIGGER "trg_prevent_locked_assessment_mark_change" BEFORE UPDATE ON "public"."assessment_marks" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_locked_assessment_mark_change"();



CREATE OR REPLACE TRIGGER "trg_prevent_locked_attendance_change" BEFORE INSERT OR DELETE OR UPDATE ON "public"."attendance_records" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_locked_attendance_change"();



CREATE OR REPLACE TRIGGER "trg_prevent_locked_course_registration" BEFORE INSERT OR DELETE OR UPDATE ON "public"."course_registrations" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_locked_course_registration_change"();



CREATE OR REPLACE TRIGGER "trg_prevent_locked_course_result_change" BEFORE UPDATE ON "public"."course_results" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_locked_course_result_change"();



CREATE OR REPLACE TRIGGER "trg_prevent_locked_examination_mark_change" BEFORE UPDATE ON "public"."examination_marks" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_locked_examination_mark_change"();



CREATE OR REPLACE TRIGGER "trg_prevent_locked_examination_paper_change" BEFORE UPDATE ON "public"."examination_papers" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_locked_examination_paper_change"();



CREATE OR REPLACE TRIGGER "trg_prevent_locked_examination_session_change" BEFORE UPDATE ON "public"."examination_sessions" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_locked_examination_session_change"();



CREATE OR REPLACE TRIGGER "trg_prevent_locked_semester_result_change" BEFORE UPDATE ON "public"."student_semester_results" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_locked_semester_result_change"();



CREATE OR REPLACE TRIGGER "trg_prevent_locked_timetable_change" BEFORE INSERT OR DELETE OR UPDATE ON "public"."timetable_entries" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_locked_timetable_change"();



CREATE OR REPLACE TRIGGER "trg_prevent_notification_delete" BEFORE DELETE ON "public"."notifications" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_notification_history_delete"();



CREATE OR REPLACE TRIGGER "trg_prevent_payment_delete" BEFORE DELETE ON "public"."payments" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_financial_history_delete"();



CREATE OR REPLACE TRIGGER "trg_prevent_refund_delete" BEFORE DELETE ON "public"."refunds" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_financial_history_delete"();



CREATE OR REPLACE TRIGGER "trg_prevent_reviewed_assessment_correction_change" BEFORE UPDATE ON "public"."assessment_mark_corrections" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_reviewed_assessment_correction_change"();



CREATE OR REPLACE TRIGGER "trg_prevent_reviewed_course_result_correction_change" BEFORE UPDATE ON "public"."course_result_corrections" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_reviewed_course_result_correction_change"();



CREATE OR REPLACE TRIGGER "trg_prevent_reviewed_examination_correction_change" BEFORE UPDATE ON "public"."examination_mark_corrections" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_reviewed_examination_correction_change"();



CREATE OR REPLACE TRIGGER "trg_procurement_requests_updated_at" BEFORE UPDATE ON "public"."procurement_requests" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_programme_versions_updated_at" BEFORE UPDATE ON "public"."programme_versions" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_programmes_updated_at" BEFORE UPDATE ON "public"."programmes" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_protect_alumni_identity" BEFORE UPDATE ON "public"."alumni_records" FOR EACH ROW EXECUTE FUNCTION "public"."protect_alumni_identity"();



CREATE OR REPLACE TRIGGER "trg_protect_posted_financial_transaction" BEFORE UPDATE ON "public"."financial_transactions" FOR EACH ROW EXECUTE FUNCTION "public"."protect_posted_financial_transaction"();



CREATE OR REPLACE TRIGGER "trg_purchase_orders_updated_at" BEFORE UPDATE ON "public"."purchase_orders" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_record_student_status_history" AFTER INSERT OR UPDATE OF "student_status" ON "public"."students" FOR EACH ROW EXECUTE FUNCTION "public"."record_student_status_history"();



CREATE OR REPLACE TRIGGER "trg_refresh_registration_credits" AFTER INSERT OR DELETE OR UPDATE ON "public"."course_registrations" FOR EACH ROW EXECUTE FUNCTION "public"."refresh_registration_credits"();



CREATE OR REPLACE TRIGGER "trg_refund_refresh_student_account" AFTER INSERT OR UPDATE OF "status", "amount" ON "public"."refunds" FOR EACH ROW EXECUTE FUNCTION "public"."trg_refresh_after_refund"();



CREATE OR REPLACE TRIGGER "trg_refunds_updated_at" BEFORE UPDATE ON "public"."refunds" FOR EACH ROW EXECUTE FUNCTION "public"."touch_finance_updated_at"();



CREATE OR REPLACE TRIGGER "trg_registration_approvals_updated_at" BEFORE UPDATE ON "public"."registration_approvals" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_rooms_updated_at" BEFORE UPDATE ON "public"."rooms" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_schools_updated_at" BEFORE UPDATE ON "public"."schools" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_semesters_updated_at" BEFORE UPDATE ON "public"."semesters" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_staff_attendance_updated_at" BEFORE UPDATE ON "public"."staff_attendance" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_staff_documents_updated_at" BEFORE UPDATE ON "public"."staff_documents" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_staff_leave_balances_updated_at" BEFORE UPDATE ON "public"."staff_leave_balances" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_staff_leave_requests_updated_at" BEFORE UPDATE ON "public"."staff_leave_requests" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_staff_leave_types_updated_at" BEFORE UPDATE ON "public"."staff_leave_types" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_staff_qualifications_updated_at" BEFORE UPDATE ON "public"."staff_qualifications" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_staff_updated_at" BEFORE UPDATE ON "public"."staff" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_student_academic_deficiencies_updated_at" BEFORE UPDATE ON "public"."student_academic_deficiencies" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_student_academic_standings_updated_at" BEFORE UPDATE ON "public"."student_academic_standings" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_student_charge_refresh_account" AFTER INSERT OR DELETE OR UPDATE ON "public"."student_charges" FOR EACH ROW EXECUTE FUNCTION "public"."trg_refresh_student_financial_account"();



CREATE OR REPLACE TRIGGER "trg_student_charges_updated_at" BEFORE UPDATE ON "public"."student_charges" FOR EACH ROW EXECUTE FUNCTION "public"."touch_finance_updated_at"();



CREATE OR REPLACE TRIGGER "trg_student_course_attempts_updated_at" BEFORE UPDATE ON "public"."student_course_attempts" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_student_documents_updated_at" BEFORE UPDATE ON "public"."student_documents" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_student_fee_adjustments_updated_at" BEFORE UPDATE ON "public"."student_fee_adjustments" FOR EACH ROW EXECUTE FUNCTION "public"."touch_finance_updated_at"();



CREATE OR REPLACE TRIGGER "trg_student_financial_accounts_updated_at" BEFORE UPDATE ON "public"."student_financial_accounts" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_student_profiles_updated_at" BEFORE UPDATE ON "public"."student_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_student_programme_history_updated_at" BEFORE UPDATE ON "public"."student_programme_history" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_student_registrations_updated_at" BEFORE UPDATE ON "public"."student_registrations" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_student_scholarships_updated_at" BEFORE UPDATE ON "public"."student_scholarships" FOR EACH ROW EXECUTE FUNCTION "public"."touch_finance_updated_at"();



CREATE OR REPLACE TRIGGER "trg_student_semester_results_updated_at" BEFORE UPDATE ON "public"."student_semester_results" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_student_transcripts_updated_at" BEFORE UPDATE ON "public"."student_transcripts" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_students_updated_at" BEFORE UPDATE ON "public"."students" FOR EACH ROW EXECUTE FUNCTION "public"."set_students_updated_at"();



CREATE OR REPLACE TRIGGER "trg_suppliers_updated_at" BEFORE UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_sync_admission_offer_after_acceptance" AFTER INSERT OR UPDATE ON "public"."admission_acceptances" FOR EACH ROW EXECUTE FUNCTION "public"."sync_admission_offer_after_acceptance"();



CREATE OR REPLACE TRIGGER "trg_sync_application_after_admission_acceptance" AFTER INSERT OR UPDATE ON "public"."admission_acceptances" FOR EACH ROW EXECUTE FUNCTION "public"."sync_application_after_admission_acceptance"();



CREATE OR REPLACE TRIGGER "trg_sync_attendance_session_timestamps" BEFORE UPDATE OF "status" ON "public"."attendance_sessions" FOR EACH ROW EXECUTE FUNCTION "public"."sync_attendance_session_timestamps"();



CREATE OR REPLACE TRIGGER "trg_timetable_entries_updated_at" BEFORE UPDATE ON "public"."timetable_entries" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_timetable_slots_updated_at" BEFORE UPDATE ON "public"."timetable_slots" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_timetables_updated_at" BEFORE UPDATE ON "public"."timetables" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_touch_alumni_updated_at" BEFORE UPDATE ON "public"."alumni_records" FOR EACH ROW EXECUTE FUNCTION "public"."touch_alumni_updated_at"();



CREATE OR REPLACE TRIGGER "trg_touch_notification_deliveries_updated_at" BEFORE UPDATE ON "public"."notification_deliveries" FOR EACH ROW EXECUTE FUNCTION "public"."touch_notification_updated_at"();



CREATE OR REPLACE TRIGGER "trg_touch_notification_queue_updated_at" BEFORE UPDATE ON "public"."notification_queue" FOR EACH ROW EXECUTE FUNCTION "public"."touch_notification_updated_at"();



CREATE OR REPLACE TRIGGER "trg_touch_notification_templates_updated_at" BEFORE UPDATE ON "public"."notification_templates" FOR EACH ROW EXECUTE FUNCTION "public"."touch_notification_updated_at"();



CREATE OR REPLACE TRIGGER "trg_touch_notifications_updated_at" BEFORE UPDATE ON "public"."notifications" FOR EACH ROW EXECUTE FUNCTION "public"."touch_notification_updated_at"();



CREATE OR REPLACE TRIGGER "trg_update_library_loan_status" BEFORE INSERT OR UPDATE ON "public"."library_loans" FOR EACH ROW EXECUTE FUNCTION "public"."update_library_loan_status"();



CREATE OR REPLACE TRIGGER "trg_user_addresses_updated_at" BEFORE UPDATE ON "public"."user_addresses" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_user_preferences_updated_at" BEFORE UPDATE ON "public"."user_preferences" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_user_profiles_updated_at" BEFORE UPDATE ON "public"."user_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_validate_admission_acceptance" BEFORE INSERT OR UPDATE ON "public"."admission_acceptances" FOR EACH ROW EXECUTE FUNCTION "public"."validate_admission_acceptance"();



CREATE OR REPLACE TRIGGER "trg_validate_admission_decision_application" BEFORE INSERT OR UPDATE ON "public"."admission_decisions" FOR EACH ROW EXECUTE FUNCTION "public"."validate_admission_decision_application"();



CREATE OR REPLACE TRIGGER "trg_validate_admission_offer" BEFORE INSERT OR UPDATE ON "public"."admission_offers" FOR EACH ROW EXECUTE FUNCTION "public"."validate_admission_offer"();



CREATE OR REPLACE TRIGGER "trg_validate_alumni_integrity" BEFORE INSERT OR UPDATE ON "public"."alumni_records" FOR EACH ROW EXECUTE FUNCTION "public"."validate_alumni_integrity"();



CREATE OR REPLACE TRIGGER "trg_validate_alumni_record" BEFORE INSERT OR UPDATE ON "public"."alumni_records" FOR EACH ROW EXECUTE FUNCTION "public"."validate_alumni_record"();



CREATE OR REPLACE TRIGGER "trg_validate_alumni_record_integrity" BEFORE INSERT OR UPDATE ON "public"."alumni_records" FOR EACH ROW EXECUTE FUNCTION "public"."validate_alumni_record_integrity"();



CREATE OR REPLACE TRIGGER "trg_validate_assessment_correction_status" BEFORE UPDATE ON "public"."assessment_mark_corrections" FOR EACH ROW EXECUTE FUNCTION "public"."validate_assessment_correction_status"();



CREATE OR REPLACE TRIGGER "trg_validate_assessment_course_offering" BEFORE INSERT OR UPDATE OF "course_offering_id" ON "public"."assessments" FOR EACH ROW EXECUTE FUNCTION "public"."validate_assessment_course_offering"();



CREATE OR REPLACE TRIGGER "trg_validate_assessment_mark" BEFORE INSERT OR UPDATE OF "assessment_id", "student_id", "course_registration_id", "marks" ON "public"."assessment_marks" FOR EACH ROW EXECUTE FUNCTION "public"."validate_assessment_mark"();



CREATE OR REPLACE TRIGGER "trg_validate_assessment_mark_correction" BEFORE INSERT OR UPDATE ON "public"."assessment_mark_corrections" FOR EACH ROW EXECUTE FUNCTION "public"."validate_assessment_mark_correction"();



CREATE OR REPLACE TRIGGER "trg_validate_assessment_mark_registration" BEFORE INSERT OR UPDATE ON "public"."assessment_marks" FOR EACH ROW EXECUTE FUNCTION "public"."validate_assessment_mark_registration"();



CREATE OR REPLACE TRIGGER "trg_validate_assessment_mark_status" BEFORE UPDATE OF "status" ON "public"."assessment_marks" FOR EACH ROW EXECUTE FUNCTION "public"."validate_assessment_mark_status"();



CREATE OR REPLACE TRIGGER "trg_validate_assessment_status_transition" BEFORE UPDATE OF "status" ON "public"."assessments" FOR EACH ROW EXECUTE FUNCTION "public"."validate_assessment_status_transition"();



CREATE OR REPLACE TRIGGER "trg_validate_assessment_weight" BEFORE INSERT OR UPDATE OF "course_offering_id", "weight_percentage", "status" ON "public"."assessments" FOR EACH ROW EXECUTE FUNCTION "public"."validate_assessment_weight"();



CREATE OR REPLACE TRIGGER "trg_validate_attendance_record_status" BEFORE INSERT OR UPDATE OF "attendance_status", "check_in_time", "minutes_late" ON "public"."attendance_records" FOR EACH ROW EXECUTE FUNCTION "public"."validate_attendance_record_status"();



CREATE OR REPLACE TRIGGER "trg_validate_attendance_record_student" BEFORE INSERT OR UPDATE OF "attendance_session_id", "student_id", "course_registration_id" ON "public"."attendance_records" FOR EACH ROW EXECUTE FUNCTION "public"."validate_attendance_record_student"();



CREATE OR REPLACE TRIGGER "trg_validate_attendance_session_consistency" BEFORE INSERT OR UPDATE OF "class_id", "course_offering_id" ON "public"."attendance_sessions" FOR EACH ROW EXECUTE FUNCTION "public"."validate_attendance_session_consistency"();



CREATE OR REPLACE TRIGGER "trg_validate_attendance_status_transition" BEFORE UPDATE OF "status" ON "public"."attendance_sessions" FOR EACH ROW EXECUTE FUNCTION "public"."validate_attendance_status_transition"();



CREATE OR REPLACE TRIGGER "trg_validate_attendance_timetable_entry" BEFORE INSERT OR UPDATE OF "timetable_entry_id", "class_id", "course_offering_id" ON "public"."attendance_sessions" FOR EACH ROW EXECUTE FUNCTION "public"."validate_attendance_timetable_entry"();



CREATE OR REPLACE TRIGGER "trg_validate_certificate" BEFORE INSERT OR UPDATE ON "public"."certificates" FOR EACH ROW EXECUTE FUNCTION "public"."validate_certificate"();



CREATE OR REPLACE TRIGGER "trg_validate_certificate_integrity" BEFORE INSERT OR UPDATE ON "public"."certificates" FOR EACH ROW EXECUTE FUNCTION "public"."validate_certificate_integrity"();



CREATE OR REPLACE TRIGGER "trg_validate_certificate_replacement" BEFORE INSERT OR UPDATE ON "public"."certificates" FOR EACH ROW EXECUTE FUNCTION "public"."validate_certificate_replacement"();



CREATE OR REPLACE TRIGGER "trg_validate_certificate_verification_integrity" BEFORE INSERT OR UPDATE ON "public"."certificate_verifications" FOR EACH ROW EXECUTE FUNCTION "public"."validate_certificate_verification_integrity"();



CREATE OR REPLACE TRIGGER "trg_validate_class_capacity_against_offering" BEFORE INSERT OR UPDATE OF "capacity", "course_offering_id" ON "public"."classes" FOR EACH ROW EXECUTE FUNCTION "public"."validate_class_capacity_against_offering"();



CREATE OR REPLACE TRIGGER "trg_validate_class_course_offering_consistency" BEFORE INSERT OR UPDATE OF "class_id", "course_offering_id" ON "public"."timetable_entries" FOR EACH ROW EXECUTE FUNCTION "public"."validate_class_course_offering_consistency"();



CREATE OR REPLACE TRIGGER "trg_validate_class_student_capacity" BEFORE INSERT ON "public"."class_students" FOR EACH ROW EXECUTE FUNCTION "public"."validate_class_student_capacity"();



CREATE OR REPLACE TRIGGER "trg_validate_class_student_registration" BEFORE INSERT OR UPDATE OF "class_id", "student_id", "course_registration_id" ON "public"."class_students" FOR EACH ROW EXECUTE FUNCTION "public"."validate_class_student_registration"();



CREATE OR REPLACE TRIGGER "trg_validate_course_registration" BEFORE INSERT OR UPDATE ON "public"."course_registrations" FOR EACH ROW EXECUTE FUNCTION "public"."validate_course_registration"();



CREATE OR REPLACE TRIGGER "trg_validate_course_result_approval" BEFORE INSERT OR UPDATE ON "public"."course_results" FOR EACH ROW EXECUTE FUNCTION "public"."validate_course_result_approval"();



CREATE OR REPLACE TRIGGER "trg_validate_course_result_context" BEFORE INSERT OR UPDATE ON "public"."course_results" FOR EACH ROW EXECUTE FUNCTION "public"."validate_course_result_context"();



CREATE OR REPLACE TRIGGER "trg_validate_course_result_correction" BEFORE INSERT OR UPDATE ON "public"."course_result_corrections" FOR EACH ROW EXECUTE FUNCTION "public"."validate_course_result_correction"();



CREATE OR REPLACE TRIGGER "trg_validate_course_result_lock" BEFORE UPDATE ON "public"."course_results" FOR EACH ROW EXECUTE FUNCTION "public"."validate_course_result_lock"();



CREATE OR REPLACE TRIGGER "trg_validate_course_result_publication" BEFORE UPDATE ON "public"."course_results" FOR EACH ROW EXECUTE FUNCTION "public"."validate_course_result_publication"();



CREATE OR REPLACE TRIGGER "trg_validate_course_result_status_transition" BEFORE UPDATE ON "public"."course_results" FOR EACH ROW EXECUTE FUNCTION "public"."validate_course_result_status_transition"();



CREATE OR REPLACE TRIGGER "trg_validate_course_result_submission" BEFORE INSERT OR UPDATE ON "public"."course_results" FOR EACH ROW EXECUTE FUNCTION "public"."validate_course_result_submission"();



CREATE OR REPLACE TRIGGER "trg_validate_examination_attendance" BEFORE INSERT OR UPDATE ON "public"."examination_attendance" FOR EACH ROW EXECUTE FUNCTION "public"."validate_examination_attendance"();



CREATE OR REPLACE TRIGGER "trg_validate_examination_candidate" BEFORE INSERT OR UPDATE ON "public"."examination_candidates" FOR EACH ROW EXECUTE FUNCTION "public"."validate_examination_candidate"();



CREATE OR REPLACE TRIGGER "trg_validate_examination_candidate_number" BEFORE INSERT OR UPDATE ON "public"."examination_candidates" FOR EACH ROW EXECUTE FUNCTION "public"."validate_examination_candidate_number"();



CREATE OR REPLACE TRIGGER "trg_validate_examination_candidate_registration" BEFORE INSERT OR UPDATE ON "public"."examination_candidates" FOR EACH ROW EXECUTE FUNCTION "public"."validate_examination_candidate_registration"();



CREATE OR REPLACE TRIGGER "trg_validate_examination_candidate_session" BEFORE INSERT OR UPDATE ON "public"."examination_candidate_sessions" FOR EACH ROW EXECUTE FUNCTION "public"."validate_examination_candidate_session"();



CREATE OR REPLACE TRIGGER "trg_validate_examination_invigilator_conflict" BEFORE INSERT OR UPDATE ON "public"."examination_invigilators" FOR EACH ROW EXECUTE FUNCTION "public"."validate_examination_invigilator_conflict"();



CREATE OR REPLACE TRIGGER "trg_validate_examination_mark" BEFORE INSERT OR UPDATE ON "public"."examination_marks" FOR EACH ROW EXECUTE FUNCTION "public"."validate_examination_mark"();



CREATE OR REPLACE TRIGGER "trg_validate_examination_mark_correction" BEFORE INSERT OR UPDATE ON "public"."examination_mark_corrections" FOR EACH ROW EXECUTE FUNCTION "public"."validate_examination_mark_correction"();



CREATE OR REPLACE TRIGGER "trg_validate_examination_paper_context" BEFORE INSERT OR UPDATE ON "public"."examination_papers" FOR EACH ROW EXECUTE FUNCTION "public"."validate_examination_paper_context"();



CREATE OR REPLACE TRIGGER "trg_validate_examination_room_conflict" BEFORE INSERT OR UPDATE ON "public"."examination_sessions" FOR EACH ROW EXECUTE FUNCTION "public"."validate_examination_room_conflict"();



CREATE OR REPLACE TRIGGER "trg_validate_examination_session" BEFORE INSERT OR UPDATE ON "public"."examination_sessions" FOR EACH ROW EXECUTE FUNCTION "public"."validate_examination_session"();



CREATE OR REPLACE TRIGGER "trg_validate_examination_session_capacity" BEFORE INSERT OR UPDATE ON "public"."examination_sessions" FOR EACH ROW EXECUTE FUNCTION "public"."validate_examination_session_capacity"();



CREATE OR REPLACE TRIGGER "trg_validate_financial_transaction" BEFORE INSERT OR UPDATE ON "public"."financial_transactions" FOR EACH ROW EXECUTE FUNCTION "public"."validate_financial_transaction_row"();



CREATE OR REPLACE TRIGGER "trg_validate_gpa_record" BEFORE INSERT OR UPDATE ON "public"."student_gpa_records" FOR EACH ROW EXECUTE FUNCTION "public"."validate_gpa_record"();



CREATE OR REPLACE TRIGGER "trg_validate_graduation_academic_integrity" BEFORE INSERT OR UPDATE ON "public"."graduation_candidates" FOR EACH ROW EXECUTE FUNCTION "public"."validate_graduation_academic_integrity"();



CREATE OR REPLACE TRIGGER "trg_validate_graduation_approval" BEFORE INSERT OR UPDATE ON "public"."graduation_approvals" FOR EACH ROW EXECUTE FUNCTION "public"."validate_graduation_approval"();



CREATE OR REPLACE TRIGGER "trg_validate_graduation_approval_completeness" BEFORE UPDATE ON "public"."graduation_candidates" FOR EACH ROW EXECUTE FUNCTION "public"."validate_graduation_approval_completeness"();



CREATE OR REPLACE TRIGGER "trg_validate_graduation_approval_integrity" BEFORE INSERT OR UPDATE ON "public"."graduation_approvals" FOR EACH ROW EXECUTE FUNCTION "public"."validate_graduation_approval_integrity"();



CREATE OR REPLACE TRIGGER "trg_validate_graduation_award" BEFORE INSERT OR UPDATE ON "public"."graduation_awards" FOR EACH ROW EXECUTE FUNCTION "public"."validate_graduation_award"();



CREATE OR REPLACE TRIGGER "trg_validate_graduation_award_integrity" BEFORE INSERT OR UPDATE ON "public"."graduation_awards" FOR EACH ROW EXECUTE FUNCTION "public"."validate_graduation_award_integrity"();



CREATE OR REPLACE TRIGGER "trg_validate_graduation_candidate" BEFORE INSERT OR UPDATE ON "public"."graduation_candidates" FOR EACH ROW EXECUTE FUNCTION "public"."validate_graduation_candidate"();



CREATE OR REPLACE TRIGGER "trg_validate_graduation_candidate_clearance_completeness" BEFORE UPDATE ON "public"."graduation_candidates" FOR EACH ROW EXECUTE FUNCTION "public"."validate_graduation_candidate_clearance_completeness"();



CREATE OR REPLACE TRIGGER "trg_validate_graduation_clearance" BEFORE INSERT OR UPDATE ON "public"."graduation_clearances" FOR EACH ROW EXECUTE FUNCTION "public"."validate_graduation_clearance"();



CREATE OR REPLACE TRIGGER "trg_validate_graduation_clearance_integrity" BEFORE INSERT OR UPDATE ON "public"."graduation_clearances" FOR EACH ROW EXECUTE FUNCTION "public"."validate_graduation_clearance_integrity"();



CREATE OR REPLACE TRIGGER "trg_validate_lecturer_assignment_consistency" BEFORE INSERT OR UPDATE OF "lecturer_assignment_id", "class_id", "course_offering_id" ON "public"."timetable_entries" FOR EACH ROW EXECUTE FUNCTION "public"."validate_lecturer_assignment_consistency"();



CREATE OR REPLACE TRIGGER "trg_validate_notification_delivery" BEFORE INSERT OR UPDATE ON "public"."notification_deliveries" FOR EACH ROW EXECUTE FUNCTION "public"."validate_notification_delivery"();



CREATE OR REPLACE TRIGGER "trg_validate_notification_number" BEFORE INSERT OR UPDATE ON "public"."notifications" FOR EACH ROW EXECUTE FUNCTION "public"."validate_notification_number"();



CREATE OR REPLACE TRIGGER "trg_validate_notification_queue" BEFORE INSERT OR UPDATE ON "public"."notification_queue" FOR EACH ROW EXECUTE FUNCTION "public"."validate_notification_queue"();



CREATE OR REPLACE TRIGGER "trg_validate_payment_allocation" BEFORE INSERT OR UPDATE ON "public"."payment_allocations" FOR EACH ROW EXECUTE FUNCTION "public"."validate_payment_allocation_integrity"();



CREATE OR REPLACE TRIGGER "trg_validate_payment_integrity" BEFORE INSERT OR UPDATE ON "public"."payments" FOR EACH ROW EXECUTE FUNCTION "public"."validate_payment_integrity"();



CREATE OR REPLACE TRIGGER "trg_validate_refund_integrity" BEFORE INSERT OR UPDATE ON "public"."refunds" FOR EACH ROW EXECUTE FUNCTION "public"."validate_refund_integrity"();



CREATE OR REPLACE TRIGGER "trg_validate_registration_credit_limit" BEFORE INSERT OR UPDATE OF "credits", "registration_status" ON "public"."course_registrations" FOR EACH ROW WHEN ((("new"."registration_status")::"text" <> ALL ((ARRAY['DROPPED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying])::"text"[]))) EXECUTE FUNCTION "public"."validate_registration_credit_limit"();



CREATE OR REPLACE TRIGGER "trg_validate_registration_status" BEFORE INSERT OR UPDATE OF "registration_status" ON "public"."student_registrations" FOR EACH ROW EXECUTE FUNCTION "public"."validate_registration_status_transition"();



CREATE OR REPLACE TRIGGER "trg_validate_semester_result_status_transition" BEFORE UPDATE ON "public"."student_semester_results" FOR EACH ROW EXECUTE FUNCTION "public"."validate_semester_result_status_transition"();



CREATE OR REPLACE TRIGGER "trg_validate_staff_leave_request" BEFORE INSERT OR UPDATE ON "public"."staff_leave_requests" FOR EACH ROW EXECUTE FUNCTION "public"."validate_staff_leave_request"();



CREATE OR REPLACE TRIGGER "trg_validate_student_registration" BEFORE INSERT OR UPDATE ON "public"."student_registrations" FOR EACH ROW EXECUTE FUNCTION "public"."validate_student_registration"();



CREATE OR REPLACE TRIGGER "trg_validate_student_status" BEFORE INSERT OR UPDATE OF "student_status" ON "public"."students" FOR EACH ROW EXECUTE FUNCTION "public"."validate_student_status_transition"();



CREATE OR REPLACE TRIGGER "trg_validate_timetable_class_conflict" BEFORE INSERT OR UPDATE ON "public"."timetable_entries" FOR EACH ROW EXECUTE FUNCTION "public"."validate_timetable_class_conflict"();



CREATE OR REPLACE TRIGGER "trg_validate_timetable_course_offering_status" BEFORE INSERT OR UPDATE OF "course_offering_id" ON "public"."timetable_entries" FOR EACH ROW EXECUTE FUNCTION "public"."validate_timetable_course_offering_status"();



CREATE OR REPLACE TRIGGER "trg_validate_timetable_lecturer_conflict" BEFORE INSERT OR UPDATE ON "public"."timetable_entries" FOR EACH ROW EXECUTE FUNCTION "public"."validate_timetable_lecturer_conflict"();



CREATE OR REPLACE TRIGGER "trg_validate_timetable_room_capacity" BEFORE INSERT OR UPDATE OF "room_id", "class_id" ON "public"."timetable_entries" FOR EACH ROW EXECUTE FUNCTION "public"."validate_timetable_room_capacity"();



CREATE OR REPLACE TRIGGER "trg_validate_timetable_room_conflict" BEFORE INSERT OR UPDATE ON "public"."timetable_entries" FOR EACH ROW EXECUTE FUNCTION "public"."validate_timetable_room_conflict"();



CREATE OR REPLACE TRIGGER "trg_validate_timetable_room_status" BEFORE INSERT OR UPDATE OF "room_id" ON "public"."timetable_entries" FOR EACH ROW EXECUTE FUNCTION "public"."validate_timetable_room_status"();



CREATE OR REPLACE TRIGGER "trg_validate_timetable_status" BEFORE INSERT OR UPDATE OF "status" ON "public"."timetables" FOR EACH ROW EXECUTE FUNCTION "public"."validate_timetable_status_transition"();



CREATE OR REPLACE TRIGGER "trg_validate_transcript_insert_status" BEFORE INSERT ON "public"."student_transcripts" FOR EACH ROW EXECUTE FUNCTION "public"."validate_transcript_insert_status"();



CREATE OR REPLACE TRIGGER "trg_validate_transcript_issue" BEFORE UPDATE ON "public"."student_transcripts" FOR EACH ROW EXECUTE FUNCTION "public"."validate_transcript_issue"();



CREATE OR REPLACE TRIGGER "trg_validate_transcript_replacement" BEFORE INSERT OR UPDATE ON "public"."student_transcripts" FOR EACH ROW EXECUTE FUNCTION "public"."validate_transcript_replacement"();



CREATE OR REPLACE TRIGGER "trg_validate_transcript_replacement_cycle" BEFORE INSERT OR UPDATE ON "public"."student_transcripts" FOR EACH ROW EXECUTE FUNCTION "public"."validate_transcript_replacement_cycle"();



CREATE OR REPLACE TRIGGER "trg_validate_transcript_status_transition" BEFORE UPDATE ON "public"."student_transcripts" FOR EACH ROW EXECUTE FUNCTION "public"."validate_transcript_status_transition"();



ALTER TABLE ONLY "public"."academic_qualifications"
    ADD CONSTRAINT "academic_qualifications_applicant_id_fkey" FOREIGN KEY ("applicant_id") REFERENCES "public"."applicants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."academic_qualifications"
    ADD CONSTRAINT "academic_qualifications_verified_by_fkey" FOREIGN KEY ("verified_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admission_acceptances"
    ADD CONSTRAINT "admission_acceptances_accepted_by_fkey" FOREIGN KEY ("accepted_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admission_acceptances"
    ADD CONSTRAINT "admission_acceptances_admission_offer_id_fkey" FOREIGN KEY ("admission_offer_id") REFERENCES "public"."admission_offers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."admission_decisions"
    ADD CONSTRAINT "admission_decisions_application_choice_id_fkey" FOREIGN KEY ("application_choice_id") REFERENCES "public"."application_choices"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."admission_decisions"
    ADD CONSTRAINT "admission_decisions_application_id_fkey" FOREIGN KEY ("application_id") REFERENCES "public"."applications"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."admission_decisions"
    ADD CONSTRAINT "admission_decisions_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admission_offers"
    ADD CONSTRAINT "admission_offers_application_id_fkey" FOREIGN KEY ("application_id") REFERENCES "public"."applications"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."admission_offers"
    ADD CONSTRAINT "admission_offers_decision_id_fkey" FOREIGN KEY ("decision_id") REFERENCES "public"."admission_decisions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admission_offers"
    ADD CONSTRAINT "admission_offers_issued_by_fkey" FOREIGN KEY ("issued_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admission_offers"
    ADD CONSTRAINT "admission_offers_programme_id_fkey" FOREIGN KEY ("programme_id") REFERENCES "public"."programmes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."alumni_records"
    ADD CONSTRAINT "alumni_records_graduation_award_id_fkey" FOREIGN KEY ("graduation_award_id") REFERENCES "public"."graduation_awards"("id");



ALTER TABLE ONLY "public"."alumni_records"
    ADD CONSTRAINT "alumni_records_graduation_candidate_id_fkey" FOREIGN KEY ("graduation_candidate_id") REFERENCES "public"."graduation_candidates"("id");



ALTER TABLE ONLY "public"."alumni_records"
    ADD CONSTRAINT "alumni_records_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id");



ALTER TABLE ONLY "public"."applicants"
    ADD CONSTRAINT "applicants_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."application_choices"
    ADD CONSTRAINT "application_choices_application_id_fkey" FOREIGN KEY ("application_id") REFERENCES "public"."applications"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."application_choices"
    ADD CONSTRAINT "application_choices_programme_id_fkey" FOREIGN KEY ("programme_id") REFERENCES "public"."programmes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."application_documents"
    ADD CONSTRAINT "application_documents_application_id_fkey" FOREIGN KEY ("application_id") REFERENCES "public"."applications"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."application_documents"
    ADD CONSTRAINT "application_documents_verified_by_fkey" FOREIGN KEY ("verified_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."applications"
    ADD CONSTRAINT "applications_academic_year_id_fkey" FOREIGN KEY ("academic_year_id") REFERENCES "public"."academic_years"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."applications"
    ADD CONSTRAINT "applications_applicant_id_fkey" FOREIGN KEY ("applicant_id") REFERENCES "public"."applicants"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."applications"
    ADD CONSTRAINT "applications_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."assessment_mark_corrections"
    ADD CONSTRAINT "assessment_mark_corrections_assessment_mark_id_fkey" FOREIGN KEY ("assessment_mark_id") REFERENCES "public"."assessment_marks"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."assessment_mark_corrections"
    ADD CONSTRAINT "assessment_mark_corrections_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."assessment_mark_corrections"
    ADD CONSTRAINT "assessment_mark_corrections_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."assessment_marks"
    ADD CONSTRAINT "assessment_marks_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."assessment_marks"
    ADD CONSTRAINT "assessment_marks_assessment_id_fkey" FOREIGN KEY ("assessment_id") REFERENCES "public"."assessments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."assessment_marks"
    ADD CONSTRAINT "assessment_marks_course_registration_id_fkey" FOREIGN KEY ("course_registration_id") REFERENCES "public"."course_registrations"("id");



ALTER TABLE ONLY "public"."assessment_marks"
    ADD CONSTRAINT "assessment_marks_entered_by_fkey" FOREIGN KEY ("entered_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."assessment_marks"
    ADD CONSTRAINT "assessment_marks_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id");



ALTER TABLE ONLY "public"."assessment_marks"
    ADD CONSTRAINT "assessment_marks_submitted_by_fkey" FOREIGN KEY ("submitted_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."assessment_submissions"
    ADD CONSTRAINT "assessment_submissions_assessment_id_fkey" FOREIGN KEY ("assessment_id") REFERENCES "public"."assessments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."assessment_submissions"
    ADD CONSTRAINT "assessment_submissions_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id");



ALTER TABLE ONLY "public"."assessments"
    ADD CONSTRAINT "assessments_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."assessments"
    ADD CONSTRAINT "assessments_course_offering_id_fkey" FOREIGN KEY ("course_offering_id") REFERENCES "public"."course_offerings"("id");



ALTER TABLE ONLY "public"."assessments"
    ADD CONSTRAINT "assessments_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."assessments"
    ADD CONSTRAINT "assessments_locked_by_fkey" FOREIGN KEY ("locked_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."assessments"
    ADD CONSTRAINT "assessments_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."asset_assignments"
    ADD CONSTRAINT "asset_assignments_asset_id_fkey" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."asset_assignments"
    ADD CONSTRAINT "asset_assignments_assigned_by_fkey" FOREIGN KEY ("assigned_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."asset_assignments"
    ADD CONSTRAINT "asset_assignments_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."asset_assignments"
    ADD CONSTRAINT "asset_assignments_received_by_fkey" FOREIGN KEY ("received_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."asset_assignments"
    ADD CONSTRAINT "asset_assignments_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."staff"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."asset_categories"
    ADD CONSTRAINT "asset_categories_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."asset_maintenance"
    ADD CONSTRAINT "asset_maintenance_asset_id_fkey" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."asset_maintenance"
    ADD CONSTRAINT "asset_maintenance_performed_by_fkey" FOREIGN KEY ("performed_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."asset_categories"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."attendance_corrections"
    ADD CONSTRAINT "attendance_corrections_attendance_record_id_fkey" FOREIGN KEY ("attendance_record_id") REFERENCES "public"."attendance_records"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_corrections"
    ADD CONSTRAINT "attendance_corrections_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."attendance_corrections"
    ADD CONSTRAINT "attendance_corrections_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_attendance_session_id_fkey" FOREIGN KEY ("attendance_session_id") REFERENCES "public"."attendance_sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_course_registration_id_fkey" FOREIGN KEY ("course_registration_id") REFERENCES "public"."course_registrations"("id");



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_marked_by_fkey" FOREIGN KEY ("marked_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id");



ALTER TABLE ONLY "public"."attendance_sessions"
    ADD CONSTRAINT "attendance_sessions_class_id_fkey" FOREIGN KEY ("class_id") REFERENCES "public"."classes"("id");



ALTER TABLE ONLY "public"."attendance_sessions"
    ADD CONSTRAINT "attendance_sessions_conducted_by_fkey" FOREIGN KEY ("conducted_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."attendance_sessions"
    ADD CONSTRAINT "attendance_sessions_course_offering_id_fkey" FOREIGN KEY ("course_offering_id") REFERENCES "public"."course_offerings"("id");



ALTER TABLE ONLY "public"."attendance_sessions"
    ADD CONSTRAINT "attendance_sessions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."attendance_sessions"
    ADD CONSTRAINT "attendance_sessions_locked_by_fkey" FOREIGN KEY ("locked_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."attendance_sessions"
    ADD CONSTRAINT "attendance_sessions_timetable_entry_id_fkey" FOREIGN KEY ("timetable_entry_id") REFERENCES "public"."timetable_entries"("id");



ALTER TABLE ONLY "public"."attendance_sessions"
    ADD CONSTRAINT "attendance_sessions_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."attendance_sessions"
    ADD CONSTRAINT "attendance_sessions_venue_room_id_fkey" FOREIGN KEY ("venue_room_id") REFERENCES "public"."rooms"("id");



ALTER TABLE ONLY "public"."audit_logs"
    ADD CONSTRAINT "audit_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campuses"
    ADD CONSTRAINT "campuses_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."certificate_verifications"
    ADD CONSTRAINT "certificate_verifications_certificate_id_fkey" FOREIGN KEY ("certificate_id") REFERENCES "public"."certificates"("id");



ALTER TABLE ONLY "public"."certificates"
    ADD CONSTRAINT "certificates_graduation_award_id_fkey" FOREIGN KEY ("graduation_award_id") REFERENCES "public"."graduation_awards"("id");



ALTER TABLE ONLY "public"."certificates"
    ADD CONSTRAINT "certificates_programme_id_fkey" FOREIGN KEY ("programme_id") REFERENCES "public"."programmes"("id");



ALTER TABLE ONLY "public"."certificates"
    ADD CONSTRAINT "certificates_programme_version_id_fkey" FOREIGN KEY ("programme_version_id") REFERENCES "public"."programme_versions"("id");



ALTER TABLE ONLY "public"."certificates"
    ADD CONSTRAINT "certificates_replacement_of_fkey" FOREIGN KEY ("replacement_of") REFERENCES "public"."certificates"("id");



ALTER TABLE ONLY "public"."certificates"
    ADD CONSTRAINT "certificates_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id");



ALTER TABLE ONLY "public"."class_students"
    ADD CONSTRAINT "class_students_class_id_fkey" FOREIGN KEY ("class_id") REFERENCES "public"."classes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."class_students"
    ADD CONSTRAINT "class_students_course_registration_id_fkey" FOREIGN KEY ("course_registration_id") REFERENCES "public"."course_registrations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."class_students"
    ADD CONSTRAINT "class_students_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."classes"
    ADD CONSTRAINT "classes_course_offering_id_fkey" FOREIGN KEY ("course_offering_id") REFERENCES "public"."course_offerings"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."classes"
    ADD CONSTRAINT "classes_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."classes"
    ADD CONSTRAINT "classes_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."course_add_drop_requests"
    ADD CONSTRAINT "course_add_drop_requests_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_add_drop_requests"
    ADD CONSTRAINT "course_add_drop_requests_course_offering_id_fkey" FOREIGN KEY ("course_offering_id") REFERENCES "public"."course_offerings"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_add_drop_requests"
    ADD CONSTRAINT "course_add_drop_requests_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."course_add_drop_requests"
    ADD CONSTRAINT "course_add_drop_requests_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."course_add_drop_requests"
    ADD CONSTRAINT "course_add_drop_requests_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_add_drop_requests"
    ADD CONSTRAINT "course_add_drop_requests_student_registration_id_fkey" FOREIGN KEY ("student_registration_id") REFERENCES "public"."student_registrations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_offerings"
    ADD CONSTRAINT "course_offerings_academic_year_id_fkey" FOREIGN KEY ("academic_year_id") REFERENCES "public"."academic_years"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_offerings"
    ADD CONSTRAINT "course_offerings_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_offerings"
    ADD CONSTRAINT "course_offerings_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."course_offerings"
    ADD CONSTRAINT "course_offerings_programme_id_fkey" FOREIGN KEY ("programme_id") REFERENCES "public"."programmes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_offerings"
    ADD CONSTRAINT "course_offerings_programme_version_id_fkey" FOREIGN KEY ("programme_version_id") REFERENCES "public"."programme_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_offerings"
    ADD CONSTRAINT "course_offerings_semester_id_fkey" FOREIGN KEY ("semester_id") REFERENCES "public"."semesters"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_offerings"
    ADD CONSTRAINT "course_offerings_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."course_prerequisites"
    ADD CONSTRAINT "course_prerequisites_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."course_prerequisites"
    ADD CONSTRAINT "course_prerequisites_prerequisite_course_id_fkey" FOREIGN KEY ("prerequisite_course_id") REFERENCES "public"."courses"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_registrations"
    ADD CONSTRAINT "course_registrations_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."course_registrations"
    ADD CONSTRAINT "course_registrations_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_registrations"
    ADD CONSTRAINT "course_registrations_course_offering_id_fkey" FOREIGN KEY ("course_offering_id") REFERENCES "public"."course_offerings"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_registrations"
    ADD CONSTRAINT "course_registrations_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."course_registrations"
    ADD CONSTRAINT "course_registrations_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_registrations"
    ADD CONSTRAINT "course_registrations_student_registration_id_fkey" FOREIGN KEY ("student_registration_id") REFERENCES "public"."student_registrations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."course_registrations"
    ADD CONSTRAINT "course_registrations_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."course_result_corrections"
    ADD CONSTRAINT "course_result_corrections_course_result_id_fkey" FOREIGN KEY ("course_result_id") REFERENCES "public"."course_results"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_result_corrections"
    ADD CONSTRAINT "course_result_corrections_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."course_result_corrections"
    ADD CONSTRAINT "course_result_corrections_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."course_result_policies"
    ADD CONSTRAINT "course_result_policies_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."course_result_policies"
    ADD CONSTRAINT "course_result_policies_course_offering_id_fkey" FOREIGN KEY ("course_offering_id") REFERENCES "public"."course_offerings"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_result_policies"
    ADD CONSTRAINT "course_result_policies_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."course_result_policies"
    ADD CONSTRAINT "course_result_policies_grade_scale_id_fkey" FOREIGN KEY ("grade_scale_id") REFERENCES "public"."grade_scales"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_results"
    ADD CONSTRAINT "course_results_academic_year_id_fkey" FOREIGN KEY ("academic_year_id") REFERENCES "public"."academic_years"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_results"
    ADD CONSTRAINT "course_results_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."course_results"
    ADD CONSTRAINT "course_results_course_offering_id_fkey" FOREIGN KEY ("course_offering_id") REFERENCES "public"."course_offerings"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_results"
    ADD CONSTRAINT "course_results_course_registration_id_fkey" FOREIGN KEY ("course_registration_id") REFERENCES "public"."course_registrations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_results"
    ADD CONSTRAINT "course_results_locked_by_fkey" FOREIGN KEY ("locked_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."course_results"
    ADD CONSTRAINT "course_results_published_by_fkey" FOREIGN KEY ("published_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."course_results"
    ADD CONSTRAINT "course_results_semester_id_fkey" FOREIGN KEY ("semester_id") REFERENCES "public"."semesters"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_results"
    ADD CONSTRAINT "course_results_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."course_results"
    ADD CONSTRAINT "course_results_submitted_by_fkey" FOREIGN KEY ("submitted_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."courses"
    ADD CONSTRAINT "courses_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."courses"
    ADD CONSTRAINT "courses_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."curricula"
    ADD CONSTRAINT "curricula_programme_version_id_fkey" FOREIGN KEY ("programme_version_id") REFERENCES "public"."programme_versions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."curriculum_courses"
    ADD CONSTRAINT "curriculum_courses_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."curriculum_courses"
    ADD CONSTRAINT "curriculum_courses_curriculum_id_fkey" FOREIGN KEY ("curriculum_id") REFERENCES "public"."curricula"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."departments"
    ADD CONSTRAINT "departments_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."departments"
    ADD CONSTRAINT "departments_school_id_fkey" FOREIGN KEY ("school_id") REFERENCES "public"."schools"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_attendance"
    ADD CONSTRAINT "examination_attendance_examination_candidate_id_fkey" FOREIGN KEY ("examination_candidate_id") REFERENCES "public"."examination_candidates"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_attendance"
    ADD CONSTRAINT "examination_attendance_examination_session_id_fkey" FOREIGN KEY ("examination_session_id") REFERENCES "public"."examination_sessions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_attendance"
    ADD CONSTRAINT "examination_attendance_marked_by_fkey" FOREIGN KEY ("marked_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_candidate_sessions"
    ADD CONSTRAINT "examination_candidate_sessions_assigned_by_fkey" FOREIGN KEY ("assigned_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."examination_candidate_sessions"
    ADD CONSTRAINT "examination_candidate_sessions_examination_candidate_id_fkey" FOREIGN KEY ("examination_candidate_id") REFERENCES "public"."examination_candidates"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_candidate_sessions"
    ADD CONSTRAINT "examination_candidate_sessions_examination_session_id_fkey" FOREIGN KEY ("examination_session_id") REFERENCES "public"."examination_sessions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_candidates"
    ADD CONSTRAINT "examination_candidates_course_registration_id_fkey" FOREIGN KEY ("course_registration_id") REFERENCES "public"."course_registrations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_candidates"
    ADD CONSTRAINT "examination_candidates_examination_paper_id_fkey" FOREIGN KEY ("examination_paper_id") REFERENCES "public"."examination_papers"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_candidates"
    ADD CONSTRAINT "examination_candidates_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_invigilators"
    ADD CONSTRAINT "examination_invigilators_assigned_by_fkey" FOREIGN KEY ("assigned_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_invigilators"
    ADD CONSTRAINT "examination_invigilators_examination_session_id_fkey" FOREIGN KEY ("examination_session_id") REFERENCES "public"."examination_sessions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_invigilators"
    ADD CONSTRAINT "examination_invigilators_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_mark_corrections"
    ADD CONSTRAINT "examination_mark_corrections_examination_mark_id_fkey" FOREIGN KEY ("examination_mark_id") REFERENCES "public"."examination_marks"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_mark_corrections"
    ADD CONSTRAINT "examination_mark_corrections_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."examination_mark_corrections"
    ADD CONSTRAINT "examination_mark_corrections_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."examination_marks"
    ADD CONSTRAINT "examination_marks_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_marks"
    ADD CONSTRAINT "examination_marks_course_registration_id_fkey" FOREIGN KEY ("course_registration_id") REFERENCES "public"."course_registrations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_marks"
    ADD CONSTRAINT "examination_marks_entered_by_fkey" FOREIGN KEY ("entered_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_marks"
    ADD CONSTRAINT "examination_marks_examination_candidate_id_fkey" FOREIGN KEY ("examination_candidate_id") REFERENCES "public"."examination_candidates"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_marks"
    ADD CONSTRAINT "examination_marks_examination_paper_id_fkey" FOREIGN KEY ("examination_paper_id") REFERENCES "public"."examination_papers"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_marks"
    ADD CONSTRAINT "examination_marks_locked_by_fkey" FOREIGN KEY ("locked_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_marks"
    ADD CONSTRAINT "examination_marks_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_marks"
    ADD CONSTRAINT "examination_marks_submitted_by_fkey" FOREIGN KEY ("submitted_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_papers"
    ADD CONSTRAINT "examination_papers_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_papers"
    ADD CONSTRAINT "examination_papers_course_offering_id_fkey" FOREIGN KEY ("course_offering_id") REFERENCES "public"."course_offerings"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_papers"
    ADD CONSTRAINT "examination_papers_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_papers"
    ADD CONSTRAINT "examination_papers_examination_period_id_fkey" FOREIGN KEY ("examination_period_id") REFERENCES "public"."examination_periods"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_papers"
    ADD CONSTRAINT "examination_papers_locked_by_fkey" FOREIGN KEY ("locked_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_papers"
    ADD CONSTRAINT "examination_papers_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_periods"
    ADD CONSTRAINT "examination_periods_academic_year_id_fkey" FOREIGN KEY ("academic_year_id") REFERENCES "public"."academic_years"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_periods"
    ADD CONSTRAINT "examination_periods_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_periods"
    ADD CONSTRAINT "examination_periods_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_periods"
    ADD CONSTRAINT "examination_periods_locked_by_fkey" FOREIGN KEY ("locked_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_periods"
    ADD CONSTRAINT "examination_periods_published_by_fkey" FOREIGN KEY ("published_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_periods"
    ADD CONSTRAINT "examination_periods_semester_id_fkey" FOREIGN KEY ("semester_id") REFERENCES "public"."semesters"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_periods"
    ADD CONSTRAINT "examination_periods_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_sessions"
    ADD CONSTRAINT "examination_sessions_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_sessions"
    ADD CONSTRAINT "examination_sessions_campus_id_fkey" FOREIGN KEY ("campus_id") REFERENCES "public"."campuses"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_sessions"
    ADD CONSTRAINT "examination_sessions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_sessions"
    ADD CONSTRAINT "examination_sessions_examination_paper_id_fkey" FOREIGN KEY ("examination_paper_id") REFERENCES "public"."examination_papers"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_sessions"
    ADD CONSTRAINT "examination_sessions_locked_by_fkey" FOREIGN KEY ("locked_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_sessions"
    ADD CONSTRAINT "examination_sessions_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "public"."rooms"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."examination_sessions"
    ADD CONSTRAINT "examination_sessions_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."fee_items"
    ADD CONSTRAINT "fee_items_fee_structure_id_fkey" FOREIGN KEY ("fee_structure_id") REFERENCES "public"."fee_structures"("id");



ALTER TABLE ONLY "public"."financial_transactions"
    ADD CONSTRAINT "financial_transactions_charge_id_fkey" FOREIGN KEY ("charge_id") REFERENCES "public"."student_charges"("id");



ALTER TABLE ONLY "public"."financial_transactions"
    ADD CONSTRAINT "financial_transactions_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "public"."invoices"("id");



ALTER TABLE ONLY "public"."financial_transactions"
    ADD CONSTRAINT "financial_transactions_payment_id_fkey" FOREIGN KEY ("payment_id") REFERENCES "public"."payments"("id");



ALTER TABLE ONLY "public"."financial_transactions"
    ADD CONSTRAINT "financial_transactions_refund_id_fkey" FOREIGN KEY ("refund_id") REFERENCES "public"."refunds"("id");



ALTER TABLE ONLY "public"."financial_transactions"
    ADD CONSTRAINT "financial_transactions_reversal_of_fkey" FOREIGN KEY ("reversal_of") REFERENCES "public"."financial_transactions"("id");



ALTER TABLE ONLY "public"."financial_transactions"
    ADD CONSTRAINT "financial_transactions_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id");



ALTER TABLE ONLY "public"."emergency_contacts"
    ADD CONSTRAINT "fk_emergency_contacts_student" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."guardians"
    ADD CONSTRAINT "fk_guardians_student" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."student_documents"
    ADD CONSTRAINT "fk_student_documents_student" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."student_documents"
    ADD CONSTRAINT "fk_student_documents_verified_by" FOREIGN KEY ("verified_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_profiles"
    ADD CONSTRAINT "fk_student_profiles_student" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."student_programme_history"
    ADD CONSTRAINT "fk_student_programme_history_approved_by" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_programme_history"
    ADD CONSTRAINT "fk_student_programme_history_programme" FOREIGN KEY ("programme_id") REFERENCES "public"."programmes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_programme_history"
    ADD CONSTRAINT "fk_student_programme_history_programme_version" FOREIGN KEY ("programme_version_id") REFERENCES "public"."programme_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_programme_history"
    ADD CONSTRAINT "fk_student_programme_history_student" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."student_status_history"
    ADD CONSTRAINT "fk_student_status_history_changed_by" FOREIGN KEY ("changed_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_status_history"
    ADD CONSTRAINT "fk_student_status_history_student" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."students"
    ADD CONSTRAINT "fk_students_admission_offer" FOREIGN KEY ("admission_offer_id") REFERENCES "public"."admission_offers"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."students"
    ADD CONSTRAINT "fk_students_applicant" FOREIGN KEY ("applicant_id") REFERENCES "public"."applicants"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."students"
    ADD CONSTRAINT "fk_students_application" FOREIGN KEY ("source_application_id") REFERENCES "public"."applications"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."students"
    ADD CONSTRAINT "fk_students_institution" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON UPDATE CASCADE ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."students"
    ADD CONSTRAINT "fk_students_programme" FOREIGN KEY ("programme_id") REFERENCES "public"."programmes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."students"
    ADD CONSTRAINT "fk_students_programme_version" FOREIGN KEY ("programme_version_id") REFERENCES "public"."programme_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."students"
    ADD CONSTRAINT "fk_students_user" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."grade_scale_details"
    ADD CONSTRAINT "grade_scale_details_grade_scale_id_fkey" FOREIGN KEY ("grade_scale_id") REFERENCES "public"."grade_scales"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."graduation_approvals"
    ADD CONSTRAINT "graduation_approvals_graduation_candidate_id_fkey" FOREIGN KEY ("graduation_candidate_id") REFERENCES "public"."graduation_candidates"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."graduation_awards"
    ADD CONSTRAINT "graduation_awards_graduation_candidate_id_fkey" FOREIGN KEY ("graduation_candidate_id") REFERENCES "public"."graduation_candidates"("id");



ALTER TABLE ONLY "public"."graduation_awards"
    ADD CONSTRAINT "graduation_awards_transcript_id_fkey" FOREIGN KEY ("transcript_id") REFERENCES "public"."student_transcripts"("id");



ALTER TABLE ONLY "public"."graduation_candidates"
    ADD CONSTRAINT "graduation_candidates_graduation_period_id_fkey" FOREIGN KEY ("graduation_period_id") REFERENCES "public"."graduation_periods"("id");



ALTER TABLE ONLY "public"."graduation_candidates"
    ADD CONSTRAINT "graduation_candidates_programme_id_fkey" FOREIGN KEY ("programme_id") REFERENCES "public"."programmes"("id");



ALTER TABLE ONLY "public"."graduation_candidates"
    ADD CONSTRAINT "graduation_candidates_programme_version_id_fkey" FOREIGN KEY ("programme_version_id") REFERENCES "public"."programme_versions"("id");



ALTER TABLE ONLY "public"."graduation_candidates"
    ADD CONSTRAINT "graduation_candidates_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id");



ALTER TABLE ONLY "public"."graduation_clearance_items"
    ADD CONSTRAINT "graduation_clearance_items_graduation_clearance_id_fkey" FOREIGN KEY ("graduation_clearance_id") REFERENCES "public"."graduation_clearances"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."graduation_clearances"
    ADD CONSTRAINT "graduation_clearances_graduation_candidate_id_fkey" FOREIGN KEY ("graduation_candidate_id") REFERENCES "public"."graduation_candidates"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."graduation_periods"
    ADD CONSTRAINT "graduation_periods_academic_year_id_fkey" FOREIGN KEY ("academic_year_id") REFERENCES "public"."academic_years"("id");



ALTER TABLE ONLY "public"."hostel_allocations"
    ADD CONSTRAINT "hostel_allocations_allocated_by_fkey" FOREIGN KEY ("allocated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."hostel_allocations"
    ADD CONSTRAINT "hostel_allocations_bed_id_fkey" FOREIGN KEY ("bed_id") REFERENCES "public"."hostel_beds"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."hostel_allocations"
    ADD CONSTRAINT "hostel_allocations_hostel_id_fkey" FOREIGN KEY ("hostel_id") REFERENCES "public"."hostels"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."hostel_allocations"
    ADD CONSTRAINT "hostel_allocations_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "public"."hostel_rooms"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."hostel_allocations"
    ADD CONSTRAINT "hostel_allocations_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."hostel_beds"
    ADD CONSTRAINT "hostel_beds_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "public"."hostel_rooms"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hostel_fees"
    ADD CONSTRAINT "hostel_fees_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."hostel_fees"
    ADD CONSTRAINT "hostel_fees_hostel_id_fkey" FOREIGN KEY ("hostel_id") REFERENCES "public"."hostels"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."hostel_fees"
    ADD CONSTRAINT "hostel_fees_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."hostel_rooms"
    ADD CONSTRAINT "hostel_rooms_hostel_id_fkey" FOREIGN KEY ("hostel_id") REFERENCES "public"."hostels"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hostels"
    ADD CONSTRAINT "hostels_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."hostels"
    ADD CONSTRAINT "hostels_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."hostels"
    ADD CONSTRAINT "hostels_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."hostels"
    ADD CONSTRAINT "hostels_warden_user_id_fkey" FOREIGN KEY ("warden_user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory_categories"
    ADD CONSTRAINT "inventory_categories_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."inventory_categories"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory_transactions"
    ADD CONSTRAINT "inventory_transactions_inventory_item_id_fkey" FOREIGN KEY ("inventory_item_id") REFERENCES "public"."inventory_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_transactions"
    ADD CONSTRAINT "inventory_transactions_performed_by_fkey" FOREIGN KEY ("performed_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."invoice_items"
    ADD CONSTRAINT "invoice_items_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "public"."invoices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."invoice_items"
    ADD CONSTRAINT "invoice_items_student_charge_id_fkey" FOREIGN KEY ("student_charge_id") REFERENCES "public"."student_charges"("id");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id");



ALTER TABLE ONLY "public"."joining_instructions"
    ADD CONSTRAINT "joining_instructions_academic_year_id_fkey" FOREIGN KEY ("academic_year_id") REFERENCES "public"."academic_years"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."joining_instructions"
    ADD CONSTRAINT "joining_instructions_programme_id_fkey" FOREIGN KEY ("programme_id") REFERENCES "public"."programmes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."joining_instructions"
    ADD CONSTRAINT "joining_instructions_published_by_fkey" FOREIGN KEY ("published_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."lecturer_assignments"
    ADD CONSTRAINT "lecturer_assignments_assigned_by_fkey" FOREIGN KEY ("assigned_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."lecturer_assignments"
    ADD CONSTRAINT "lecturer_assignments_class_id_fkey" FOREIGN KEY ("class_id") REFERENCES "public"."classes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."lecturer_assignments"
    ADD CONSTRAINT "lecturer_assignments_course_offering_id_fkey" FOREIGN KEY ("course_offering_id") REFERENCES "public"."course_offerings"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."lecturer_assignments"
    ADD CONSTRAINT "lecturer_assignments_lecturer_user_id_fkey" FOREIGN KEY ("lecturer_user_id") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."library_fines"
    ADD CONSTRAINT "library_fines_loan_id_fkey" FOREIGN KEY ("loan_id") REFERENCES "public"."library_loans"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."library_fines"
    ADD CONSTRAINT "library_fines_member_id_fkey" FOREIGN KEY ("member_id") REFERENCES "public"."library_members"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."library_fines"
    ADD CONSTRAINT "library_fines_waived_by_fkey" FOREIGN KEY ("waived_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."library_items"
    ADD CONSTRAINT "library_items_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."library_items"
    ADD CONSTRAINT "library_items_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."library_items"
    ADD CONSTRAINT "library_items_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."library_loans"
    ADD CONSTRAINT "library_loans_issued_by_fkey" FOREIGN KEY ("issued_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."library_loans"
    ADD CONSTRAINT "library_loans_library_item_id_fkey" FOREIGN KEY ("library_item_id") REFERENCES "public"."library_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."library_loans"
    ADD CONSTRAINT "library_loans_library_member_id_fkey" FOREIGN KEY ("library_member_id") REFERENCES "public"."library_members"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."library_loans"
    ADD CONSTRAINT "library_loans_returned_to_fkey" FOREIGN KEY ("returned_to") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."library_members"
    ADD CONSTRAINT "library_members_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."library_members"
    ADD CONSTRAINT "library_members_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."staff"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."library_members"
    ADD CONSTRAINT "library_members_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."library_reservations"
    ADD CONSTRAINT "library_reservations_library_item_id_fkey" FOREIGN KEY ("library_item_id") REFERENCES "public"."library_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."library_reservations"
    ADD CONSTRAINT "library_reservations_library_member_id_fkey" FOREIGN KEY ("library_member_id") REFERENCES "public"."library_members"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."notification_deliveries"
    ADD CONSTRAINT "notification_deliveries_notification_id_fkey" FOREIGN KEY ("notification_id") REFERENCES "public"."notifications"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_queue"
    ADD CONSTRAINT "notification_queue_delivery_id_fkey" FOREIGN KEY ("delivery_id") REFERENCES "public"."notification_deliveries"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_queue"
    ADD CONSTRAINT "notification_queue_notification_id_fkey" FOREIGN KEY ("notification_id") REFERENCES "public"."notifications"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_recipient_student_id_fkey" FOREIGN KEY ("recipient_student_id") REFERENCES "public"."students"("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "public"."notification_templates"("id");



ALTER TABLE ONLY "public"."payment_allocations"
    ADD CONSTRAINT "payment_allocations_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "public"."invoices"("id");



ALTER TABLE ONLY "public"."payment_allocations"
    ADD CONSTRAINT "payment_allocations_payment_id_fkey" FOREIGN KEY ("payment_id") REFERENCES "public"."payments"("id");



ALTER TABLE ONLY "public"."payment_allocations"
    ADD CONSTRAINT "payment_allocations_student_charge_id_fkey" FOREIGN KEY ("student_charge_id") REFERENCES "public"."student_charges"("id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id");



ALTER TABLE ONLY "public"."procurement_request_items"
    ADD CONSTRAINT "procurement_request_items_procurement_request_id_fkey" FOREIGN KEY ("procurement_request_id") REFERENCES "public"."procurement_requests"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."procurement_requests"
    ADD CONSTRAINT "procurement_requests_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."procurement_requests"
    ADD CONSTRAINT "procurement_requests_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."procurement_requests"
    ADD CONSTRAINT "procurement_requests_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."procurement_requests"
    ADD CONSTRAINT "procurement_requests_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."programme_versions"
    ADD CONSTRAINT "programme_versions_programme_id_fkey" FOREIGN KEY ("programme_id") REFERENCES "public"."programmes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."programmes"
    ADD CONSTRAINT "programmes_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."programmes"
    ADD CONSTRAINT "programmes_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."programmes"
    ADD CONSTRAINT "programmes_school_id_fkey" FOREIGN KEY ("school_id") REFERENCES "public"."schools"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."purchase_order_items"
    ADD CONSTRAINT "purchase_order_items_purchase_order_id_fkey" FOREIGN KEY ("purchase_order_id") REFERENCES "public"."purchase_orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_procurement_request_id_fkey" FOREIGN KEY ("procurement_request_id") REFERENCES "public"."procurement_requests"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."refunds"
    ADD CONSTRAINT "refunds_payment_id_fkey" FOREIGN KEY ("payment_id") REFERENCES "public"."payments"("id");



ALTER TABLE ONLY "public"."refunds"
    ADD CONSTRAINT "refunds_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id");



ALTER TABLE ONLY "public"."registration_approvals"
    ADD CONSTRAINT "registration_approvals_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."registration_approvals"
    ADD CONSTRAINT "registration_approvals_student_registration_id_fkey" FOREIGN KEY ("student_registration_id") REFERENCES "public"."student_registrations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."role_permissions"
    ADD CONSTRAINT "role_permissions_permission_id_fkey" FOREIGN KEY ("permission_id") REFERENCES "public"."permissions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."role_permissions"
    ADD CONSTRAINT "role_permissions_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "public"."roles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."rooms"
    ADD CONSTRAINT "rooms_campus_id_fkey" FOREIGN KEY ("campus_id") REFERENCES "public"."campuses"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."schools"
    ADD CONSTRAINT "schools_campus_id_fkey" FOREIGN KEY ("campus_id") REFERENCES "public"."campuses"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."schools"
    ADD CONSTRAINT "schools_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."security_logs"
    ADD CONSTRAINT "security_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."semesters"
    ADD CONSTRAINT "semesters_academic_year_id_fkey" FOREIGN KEY ("academic_year_id") REFERENCES "public"."academic_years"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."staff_attendance_adjustments"
    ADD CONSTRAINT "staff_attendance_adjustments_attendance_id_fkey" FOREIGN KEY ("attendance_id") REFERENCES "public"."staff_attendance"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."staff_attendance_adjustments"
    ADD CONSTRAINT "staff_attendance_adjustments_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_attendance_adjustments"
    ADD CONSTRAINT "staff_attendance_adjustments_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_attendance"
    ADD CONSTRAINT "staff_attendance_marked_by_fkey" FOREIGN KEY ("marked_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_attendance"
    ADD CONSTRAINT "staff_attendance_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."staff"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "staff_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "staff_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_documents"
    ADD CONSTRAINT "staff_documents_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."staff"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."staff_documents"
    ADD CONSTRAINT "staff_documents_verified_by_fkey" FOREIGN KEY ("verified_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_employment_history"
    ADD CONSTRAINT "staff_employment_history_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_employment_history"
    ADD CONSTRAINT "staff_employment_history_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_employment_history"
    ADD CONSTRAINT "staff_employment_history_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."staff"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "staff_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."staff_leave_approvals"
    ADD CONSTRAINT "staff_leave_approvals_approver_user_id_fkey" FOREIGN KEY ("approver_user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_leave_approvals"
    ADD CONSTRAINT "staff_leave_approvals_leave_request_id_fkey" FOREIGN KEY ("leave_request_id") REFERENCES "public"."staff_leave_requests"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."staff_leave_balances"
    ADD CONSTRAINT "staff_leave_balances_leave_type_id_fkey" FOREIGN KEY ("leave_type_id") REFERENCES "public"."staff_leave_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."staff_leave_balances"
    ADD CONSTRAINT "staff_leave_balances_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."staff"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."staff_leave_requests"
    ADD CONSTRAINT "staff_leave_requests_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_leave_requests"
    ADD CONSTRAINT "staff_leave_requests_current_approver_user_id_fkey" FOREIGN KEY ("current_approver_user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_leave_requests"
    ADD CONSTRAINT "staff_leave_requests_final_approved_by_fkey" FOREIGN KEY ("final_approved_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_leave_requests"
    ADD CONSTRAINT "staff_leave_requests_leave_type_id_fkey" FOREIGN KEY ("leave_type_id") REFERENCES "public"."staff_leave_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."staff_leave_requests"
    ADD CONSTRAINT "staff_leave_requests_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."staff"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."staff_leave_requests"
    ADD CONSTRAINT "staff_leave_requests_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_leave_types"
    ADD CONSTRAINT "staff_leave_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_leave_types"
    ADD CONSTRAINT "staff_leave_types_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."staff_leave_types"
    ADD CONSTRAINT "staff_leave_types_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_lifecycle_events"
    ADD CONSTRAINT "staff_lifecycle_events_new_department_id_fkey" FOREIGN KEY ("new_department_id") REFERENCES "public"."departments"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_lifecycle_events"
    ADD CONSTRAINT "staff_lifecycle_events_previous_department_id_fkey" FOREIGN KEY ("previous_department_id") REFERENCES "public"."departments"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_lifecycle_events"
    ADD CONSTRAINT "staff_lifecycle_events_recorded_by_fkey" FOREIGN KEY ("recorded_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff_lifecycle_events"
    ADD CONSTRAINT "staff_lifecycle_events_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."staff"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."staff_qualifications"
    ADD CONSTRAINT "staff_qualifications_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."staff"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."staff_qualifications"
    ADD CONSTRAINT "staff_qualifications_verified_by_fkey" FOREIGN KEY ("verified_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "staff_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "staff_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_academic_deficiencies"
    ADD CONSTRAINT "student_academic_deficiencies_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_academic_deficiencies"
    ADD CONSTRAINT "student_academic_deficiencies_course_offering_id_fkey" FOREIGN KEY ("course_offering_id") REFERENCES "public"."course_offerings"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_academic_deficiencies"
    ADD CONSTRAINT "student_academic_deficiencies_course_result_id_fkey" FOREIGN KEY ("course_result_id") REFERENCES "public"."course_results"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_academic_deficiencies"
    ADD CONSTRAINT "student_academic_deficiencies_resolution_course_result_id_fkey" FOREIGN KEY ("resolution_course_result_id") REFERENCES "public"."course_results"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_academic_deficiencies"
    ADD CONSTRAINT "student_academic_deficiencies_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_academic_standings"
    ADD CONSTRAINT "student_academic_standings_academic_year_id_fkey" FOREIGN KEY ("academic_year_id") REFERENCES "public"."academic_years"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_academic_standings"
    ADD CONSTRAINT "student_academic_standings_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_academic_standings"
    ADD CONSTRAINT "student_academic_standings_semester_id_fkey" FOREIGN KEY ("semester_id") REFERENCES "public"."semesters"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_academic_standings"
    ADD CONSTRAINT "student_academic_standings_semester_result_id_fkey" FOREIGN KEY ("semester_result_id") REFERENCES "public"."student_semester_results"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_academic_standings"
    ADD CONSTRAINT "student_academic_standings_standing_rule_id_fkey" FOREIGN KEY ("standing_rule_id") REFERENCES "public"."academic_standing_rules"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_academic_standings"
    ADD CONSTRAINT "student_academic_standings_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_cgpa_records"
    ADD CONSTRAINT "student_cgpa_records_academic_year_id_fkey" FOREIGN KEY ("academic_year_id") REFERENCES "public"."academic_years"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_cgpa_records"
    ADD CONSTRAINT "student_cgpa_records_semester_id_fkey" FOREIGN KEY ("semester_id") REFERENCES "public"."semesters"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_cgpa_records"
    ADD CONSTRAINT "student_cgpa_records_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_charges"
    ADD CONSTRAINT "student_charges_fee_item_id_fkey" FOREIGN KEY ("fee_item_id") REFERENCES "public"."fee_items"("id");



ALTER TABLE ONLY "public"."student_charges"
    ADD CONSTRAINT "student_charges_fee_structure_id_fkey" FOREIGN KEY ("fee_structure_id") REFERENCES "public"."fee_structures"("id");



ALTER TABLE ONLY "public"."student_charges"
    ADD CONSTRAINT "student_charges_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id");



ALTER TABLE ONLY "public"."student_course_attempts"
    ADD CONSTRAINT "student_course_attempts_academic_year_id_fkey" FOREIGN KEY ("academic_year_id") REFERENCES "public"."academic_years"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_course_attempts"
    ADD CONSTRAINT "student_course_attempts_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_course_attempts"
    ADD CONSTRAINT "student_course_attempts_course_offering_id_fkey" FOREIGN KEY ("course_offering_id") REFERENCES "public"."course_offerings"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_course_attempts"
    ADD CONSTRAINT "student_course_attempts_course_registration_id_fkey" FOREIGN KEY ("course_registration_id") REFERENCES "public"."course_registrations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_course_attempts"
    ADD CONSTRAINT "student_course_attempts_course_result_id_fkey" FOREIGN KEY ("course_result_id") REFERENCES "public"."course_results"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_course_attempts"
    ADD CONSTRAINT "student_course_attempts_semester_id_fkey" FOREIGN KEY ("semester_id") REFERENCES "public"."semesters"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_course_attempts"
    ADD CONSTRAINT "student_course_attempts_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_fee_adjustments"
    ADD CONSTRAINT "student_fee_adjustments_student_charge_id_fkey" FOREIGN KEY ("student_charge_id") REFERENCES "public"."student_charges"("id");



ALTER TABLE ONLY "public"."student_fee_adjustments"
    ADD CONSTRAINT "student_fee_adjustments_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id");



ALTER TABLE ONLY "public"."student_financial_accounts"
    ADD CONSTRAINT "student_financial_accounts_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id");



ALTER TABLE ONLY "public"."student_gpa_records"
    ADD CONSTRAINT "student_gpa_records_academic_year_id_fkey" FOREIGN KEY ("academic_year_id") REFERENCES "public"."academic_years"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_gpa_records"
    ADD CONSTRAINT "student_gpa_records_semester_id_fkey" FOREIGN KEY ("semester_id") REFERENCES "public"."semesters"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_gpa_records"
    ADD CONSTRAINT "student_gpa_records_semester_result_id_fkey" FOREIGN KEY ("semester_result_id") REFERENCES "public"."student_semester_results"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_gpa_records"
    ADD CONSTRAINT "student_gpa_records_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_registrations"
    ADD CONSTRAINT "student_registrations_academic_year_id_fkey" FOREIGN KEY ("academic_year_id") REFERENCES "public"."academic_years"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_registrations"
    ADD CONSTRAINT "student_registrations_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_registrations"
    ADD CONSTRAINT "student_registrations_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_registrations"
    ADD CONSTRAINT "student_registrations_locked_by_fkey" FOREIGN KEY ("locked_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_registrations"
    ADD CONSTRAINT "student_registrations_programme_id_fkey" FOREIGN KEY ("programme_id") REFERENCES "public"."programmes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_registrations"
    ADD CONSTRAINT "student_registrations_programme_version_id_fkey" FOREIGN KEY ("programme_version_id") REFERENCES "public"."programme_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_registrations"
    ADD CONSTRAINT "student_registrations_semester_id_fkey" FOREIGN KEY ("semester_id") REFERENCES "public"."semesters"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_registrations"
    ADD CONSTRAINT "student_registrations_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_registrations"
    ADD CONSTRAINT "student_registrations_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_scholarships"
    ADD CONSTRAINT "student_scholarships_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id");



ALTER TABLE ONLY "public"."student_semester_results"
    ADD CONSTRAINT "student_semester_results_academic_year_id_fkey" FOREIGN KEY ("academic_year_id") REFERENCES "public"."academic_years"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_semester_results"
    ADD CONSTRAINT "student_semester_results_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_semester_results"
    ADD CONSTRAINT "student_semester_results_locked_by_fkey" FOREIGN KEY ("locked_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_semester_results"
    ADD CONSTRAINT "student_semester_results_programme_version_id_fkey" FOREIGN KEY ("programme_version_id") REFERENCES "public"."programme_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_semester_results"
    ADD CONSTRAINT "student_semester_results_published_by_fkey" FOREIGN KEY ("published_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_semester_results"
    ADD CONSTRAINT "student_semester_results_semester_id_fkey" FOREIGN KEY ("semester_id") REFERENCES "public"."semesters"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_semester_results"
    ADD CONSTRAINT "student_semester_results_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_semester_results"
    ADD CONSTRAINT "student_semester_results_submitted_by_fkey" FOREIGN KEY ("submitted_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_transcript_courses"
    ADD CONSTRAINT "student_transcript_courses_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_transcript_courses"
    ADD CONSTRAINT "student_transcript_courses_course_registration_id_fkey" FOREIGN KEY ("course_registration_id") REFERENCES "public"."course_registrations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_transcript_courses"
    ADD CONSTRAINT "student_transcript_courses_course_result_id_fkey" FOREIGN KEY ("course_result_id") REFERENCES "public"."course_results"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_transcript_courses"
    ADD CONSTRAINT "student_transcript_courses_transcript_id_fkey" FOREIGN KEY ("transcript_id") REFERENCES "public"."student_transcripts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."student_transcript_courses"
    ADD CONSTRAINT "student_transcript_courses_transcript_semester_id_fkey" FOREIGN KEY ("transcript_semester_id") REFERENCES "public"."student_transcript_semesters"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."student_transcript_semesters"
    ADD CONSTRAINT "student_transcript_semesters_academic_year_id_fkey" FOREIGN KEY ("academic_year_id") REFERENCES "public"."academic_years"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_transcript_semesters"
    ADD CONSTRAINT "student_transcript_semesters_semester_id_fkey" FOREIGN KEY ("semester_id") REFERENCES "public"."semesters"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_transcript_semesters"
    ADD CONSTRAINT "student_transcript_semesters_semester_result_id_fkey" FOREIGN KEY ("semester_result_id") REFERENCES "public"."student_semester_results"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_transcript_semesters"
    ADD CONSTRAINT "student_transcript_semesters_transcript_id_fkey" FOREIGN KEY ("transcript_id") REFERENCES "public"."student_transcripts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."student_transcripts"
    ADD CONSTRAINT "student_transcripts_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_transcripts"
    ADD CONSTRAINT "student_transcripts_generated_by_fkey" FOREIGN KEY ("generated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_transcripts"
    ADD CONSTRAINT "student_transcripts_issued_by_fkey" FOREIGN KEY ("issued_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_transcripts"
    ADD CONSTRAINT "student_transcripts_programme_version_id_fkey" FOREIGN KEY ("programme_version_id") REFERENCES "public"."programme_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_transcripts"
    ADD CONSTRAINT "student_transcripts_replacement_of_fkey" FOREIGN KEY ("replacement_of") REFERENCES "public"."student_transcripts"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."student_transcripts"
    ADD CONSTRAINT "student_transcripts_revoked_by_fkey" FOREIGN KEY ("revoked_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."student_transcripts"
    ADD CONSTRAINT "student_transcripts_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "public"."students"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."timetable_entries"
    ADD CONSTRAINT "timetable_entries_class_id_fkey" FOREIGN KEY ("class_id") REFERENCES "public"."classes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."timetable_entries"
    ADD CONSTRAINT "timetable_entries_course_offering_id_fkey" FOREIGN KEY ("course_offering_id") REFERENCES "public"."course_offerings"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."timetable_entries"
    ADD CONSTRAINT "timetable_entries_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."timetable_entries"
    ADD CONSTRAINT "timetable_entries_lecturer_assignment_id_fkey" FOREIGN KEY ("lecturer_assignment_id") REFERENCES "public"."lecturer_assignments"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."timetable_entries"
    ADD CONSTRAINT "timetable_entries_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "public"."rooms"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."timetable_entries"
    ADD CONSTRAINT "timetable_entries_timetable_id_fkey" FOREIGN KEY ("timetable_id") REFERENCES "public"."timetables"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."timetable_entries"
    ADD CONSTRAINT "timetable_entries_timetable_slot_id_fkey" FOREIGN KEY ("timetable_slot_id") REFERENCES "public"."timetable_slots"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."timetable_entries"
    ADD CONSTRAINT "timetable_entries_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."timetables"
    ADD CONSTRAINT "timetables_academic_year_id_fkey" FOREIGN KEY ("academic_year_id") REFERENCES "public"."academic_years"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."timetables"
    ADD CONSTRAINT "timetables_campus_id_fkey" FOREIGN KEY ("campus_id") REFERENCES "public"."campuses"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."timetables"
    ADD CONSTRAINT "timetables_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."timetables"
    ADD CONSTRAINT "timetables_locked_by_fkey" FOREIGN KEY ("locked_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."timetables"
    ADD CONSTRAINT "timetables_published_by_fkey" FOREIGN KEY ("published_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."timetables"
    ADD CONSTRAINT "timetables_semester_id_fkey" FOREIGN KEY ("semester_id") REFERENCES "public"."semesters"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."timetables"
    ADD CONSTRAINT "timetables_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_addresses"
    ADD CONSTRAINT "user_addresses_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_preferences"
    ADD CONSTRAINT "user_preferences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_assigned_by_fkey" FOREIGN KEY ("assigned_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "public"."roles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_scopes"
    ADD CONSTRAINT "user_scopes_campus_id_fkey" FOREIGN KEY ("campus_id") REFERENCES "public"."campuses"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."user_scopes"
    ADD CONSTRAINT "user_scopes_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."user_scopes"
    ADD CONSTRAINT "user_scopes_institution_id_fkey" FOREIGN KEY ("institution_id") REFERENCES "public"."institutions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."user_scopes"
    ADD CONSTRAINT "user_scopes_school_id_fkey" FOREIGN KEY ("school_id") REFERENCES "public"."schools"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."user_scopes"
    ADD CONSTRAINT "user_scopes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_status_history"
    ADD CONSTRAINT "user_status_history_changed_by_fkey" FOREIGN KEY ("changed_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_status_history"
    ADD CONSTRAINT "user_status_history_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "public"."academic_qualifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."academic_standing_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."academic_years" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."admission_acceptances" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."admission_decisions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."admission_offers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."alumni_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."applicants" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."application_choices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."application_documents" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."applications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."assessment_mark_corrections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."assessment_marks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."assessment_submissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."assessments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_corrections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."audit_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."certificate_verifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."certificates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."class_students" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."classes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."course_add_drop_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."course_offerings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."course_prerequisites" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."course_registrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."course_result_corrections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."course_result_policies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."course_results" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."courses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."curricula" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."curriculum_courses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."emergency_contacts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."examination_attendance" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."examination_candidate_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."examination_candidates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."examination_invigilators" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."examination_mark_corrections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."examination_marks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."examination_papers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."examination_periods" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."examination_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."fee_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."fee_structures" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."financial_transactions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."grade_scale_details" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."grade_scales" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."graduation_approvals" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."graduation_awards" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."graduation_candidates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."graduation_clearance_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."graduation_clearances" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."graduation_periods" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."guardians" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."invoice_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."invoices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."joining_instructions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."lecturer_assignments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notification_deliveries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notification_queue" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notification_templates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."payment_allocations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."payments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."permissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."programme_versions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."programmes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."refunds" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."registration_approvals" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."role_permissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."roles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rooms" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."security_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."semesters" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_academic_deficiencies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_academic_standings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_cgpa_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_charges" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_course_attempts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_documents" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_fee_adjustments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_financial_accounts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_gpa_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_programme_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_registrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_scholarships" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_semester_results" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_status_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_transcript_courses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_transcript_semesters" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."student_transcripts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."students" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."timetable_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."timetable_slots" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."timetables" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_addresses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_preferences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_roles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_scopes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_status_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_and_store_cgpa"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_and_store_cgpa"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_and_store_cgpa"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."student_semester_results" TO "anon";
GRANT ALL ON TABLE "public"."student_semester_results" TO "authenticated";
GRANT ALL ON TABLE "public"."student_semester_results" TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_and_store_semester_result"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_and_store_semester_result"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_and_store_semester_result"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."course_results" TO "anon";
GRANT ALL ON TABLE "public"."course_results" TO "authenticated";
GRANT ALL ON TABLE "public"."course_results" TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_course_result"("p_course_result_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_course_result"("p_course_result_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_course_result"("p_course_result_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."student_academic_standings" TO "anon";
GRANT ALL ON TABLE "public"."student_academic_standings" TO "authenticated";
GRANT ALL ON TABLE "public"."student_academic_standings" TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_student_academic_standing"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_student_academic_standing"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_student_academic_standing"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_student_cgpa"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_student_cgpa"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_student_cgpa"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_student_semester_gpa"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_student_semester_gpa"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_student_semester_gpa"("p_student_id" "uuid", "p_academic_year_id" "uuid", "p_semester_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."convert_accepted_application_to_student"("p_application_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."convert_accepted_application_to_student"("p_application_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_result_deficiency"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_result_deficiency"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_result_deficiency"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_student_financial_account"("p_student_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_student_financial_account"("p_student_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_student_financial_account"("p_student_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."expire_admission_offers"() TO "anon";
GRANT ALL ON FUNCTION "public"."expire_admission_offers"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."expire_admission_offers"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_graduation_clearances"("p_graduation_candidate_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."generate_graduation_clearances"("p_graduation_candidate_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_graduation_clearances"("p_graduation_candidate_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_library_loan_number"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_library_loan_number"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_library_loan_number"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_procurement_request_number"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_procurement_request_number"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_procurement_request_number"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_purchase_order_number"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_purchase_order_number"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_purchase_order_number"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_staff_employee_number"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_staff_employee_number"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_staff_employee_number"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_staff_leave_request_number"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_staff_leave_request_number"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_staff_leave_request_number"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_transcript_number"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_transcript_number"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_transcript_number"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_transcript_verification_code"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_transcript_verification_code"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_transcript_verification_code"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_grade_for_mark"("p_grade_scale_id" "uuid", "p_total_mark" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."get_grade_for_mark"("p_grade_scale_id" "uuid", "p_total_mark" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_grade_for_mark"("p_grade_scale_id" "uuid", "p_total_mark" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."post_financial_transaction"("p_transaction_number" character varying, "p_student_id" "uuid", "p_transaction_type" character varying, "p_debit" numeric, "p_credit" numeric, "p_reference" character varying, "p_description" "text", "p_created_by" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."post_financial_transaction"("p_transaction_number" character varying, "p_student_id" "uuid", "p_transaction_type" character varying, "p_debit" numeric, "p_credit" numeric, "p_reference" character varying, "p_description" "text", "p_created_by" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."prepare_student_transcript"() TO "anon";
GRANT ALL ON FUNCTION "public"."prepare_student_transcript"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prepare_student_transcript"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_add_drop_after_lock"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_add_drop_after_lock"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_add_drop_after_lock"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_alumni_hard_delete"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_alumni_hard_delete"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_alumni_hard_delete"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_assessment_mark_delete"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_assessment_mark_delete"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_assessment_mark_delete"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_course_result_delete"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_course_result_delete"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_course_result_delete"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_examination_mark_delete"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_examination_mark_delete"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_examination_mark_delete"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_financial_account_delete"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_financial_account_delete"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_financial_account_delete"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_financial_history_delete"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_financial_history_delete"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_financial_history_delete"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_financial_transaction_delete"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_financial_transaction_delete"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_financial_transaction_delete"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_invalid_offer_status_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_invalid_offer_status_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_invalid_offer_status_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_issued_certificate_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_issued_certificate_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_issued_certificate_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_issued_transcript_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_issued_transcript_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_issued_transcript_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_locked_assessment_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_locked_assessment_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_locked_assessment_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_locked_assessment_mark_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_locked_assessment_mark_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_locked_assessment_mark_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_locked_attendance_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_locked_attendance_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_locked_attendance_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_locked_course_registration_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_locked_course_registration_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_locked_course_registration_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_locked_course_result_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_locked_course_result_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_locked_course_result_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_locked_examination_mark_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_locked_examination_mark_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_locked_examination_mark_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_locked_examination_paper_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_locked_examination_paper_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_locked_examination_paper_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_locked_examination_session_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_locked_examination_session_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_locked_examination_session_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_locked_semester_result_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_locked_semester_result_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_locked_semester_result_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_locked_timetable_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_locked_timetable_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_locked_timetable_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_notification_history_delete"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_notification_history_delete"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_notification_history_delete"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_reviewed_assessment_correction_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_reviewed_assessment_correction_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_reviewed_assessment_correction_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_reviewed_course_result_correction_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_reviewed_course_result_correction_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_reviewed_course_result_correction_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_reviewed_examination_correction_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_reviewed_examination_correction_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_reviewed_examination_correction_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."protect_alumni_identity"() TO "anon";
GRANT ALL ON FUNCTION "public"."protect_alumni_identity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."protect_alumni_identity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."protect_posted_financial_transaction"() TO "anon";
GRANT ALL ON FUNCTION "public"."protect_posted_financial_transaction"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."protect_posted_financial_transaction"() TO "service_role";



GRANT ALL ON FUNCTION "public"."record_student_status_history"() TO "anon";
GRANT ALL ON FUNCTION "public"."record_student_status_history"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_student_status_history"() TO "service_role";



GRANT ALL ON FUNCTION "public"."refresh_all_invoice_financials"() TO "anon";
GRANT ALL ON FUNCTION "public"."refresh_all_invoice_financials"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."refresh_all_invoice_financials"() TO "service_role";



GRANT ALL ON FUNCTION "public"."refresh_invoice_financials"("p_invoice_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."refresh_invoice_financials"("p_invoice_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."refresh_invoice_financials"("p_invoice_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."refresh_registration_credits"() TO "anon";
GRANT ALL ON FUNCTION "public"."refresh_registration_credits"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."refresh_registration_credits"() TO "service_role";



GRANT ALL ON FUNCTION "public"."refresh_student_financial_account"("p_student_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."refresh_student_financial_account"("p_student_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."refresh_student_financial_account"("p_student_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_students_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_students_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_students_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_admission_offer_after_acceptance"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_admission_offer_after_acceptance"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_admission_offer_after_acceptance"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_application_after_admission_acceptance"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_application_after_admission_acceptance"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_application_after_admission_acceptance"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_attendance_session_timestamps"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_attendance_session_timestamps"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_attendance_session_timestamps"() TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_alumni_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_alumni_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_alumni_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_finance_automation_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_finance_automation_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_finance_automation_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_finance_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_finance_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_finance_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_notification_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_notification_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_notification_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_generate_graduation_clearances"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_generate_graduation_clearances"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_generate_graduation_clearances"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_refresh_after_payment_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_refresh_after_payment_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_refresh_after_payment_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_refresh_after_refund"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_refresh_after_refund"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_refresh_after_refund"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_refresh_financials_after_allocation"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_refresh_financials_after_allocation"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_refresh_financials_after_allocation"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_refresh_invoice_after_item"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_refresh_invoice_after_item"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_refresh_invoice_after_item"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_refresh_student_financial_account"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_refresh_student_financial_account"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_refresh_student_financial_account"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_library_loan_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_library_loan_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_library_loan_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_admission_acceptance"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_admission_acceptance"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_admission_acceptance"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_admission_decision_application"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_admission_decision_application"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_admission_decision_application"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_admission_offer"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_admission_offer"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_admission_offer"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_alumni_integrity"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_alumni_integrity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_alumni_integrity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_alumni_record"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_alumni_record"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_alumni_record"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_alumni_record_integrity"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_alumni_record_integrity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_alumni_record_integrity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_assessment_correction_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_assessment_correction_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_assessment_correction_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_assessment_course_offering"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_assessment_course_offering"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_assessment_course_offering"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_assessment_mark"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_assessment_mark"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_assessment_mark"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_assessment_mark_correction"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_assessment_mark_correction"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_assessment_mark_correction"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_assessment_mark_registration"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_assessment_mark_registration"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_assessment_mark_registration"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_assessment_mark_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_assessment_mark_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_assessment_mark_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_assessment_status_transition"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_assessment_status_transition"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_assessment_status_transition"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_assessment_weight"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_assessment_weight"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_assessment_weight"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_attendance_record_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_attendance_record_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_attendance_record_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_attendance_record_student"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_attendance_record_student"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_attendance_record_student"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_attendance_session_consistency"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_attendance_session_consistency"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_attendance_session_consistency"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_attendance_status_transition"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_attendance_status_transition"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_attendance_status_transition"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_attendance_timetable_entry"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_attendance_timetable_entry"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_attendance_timetable_entry"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_certificate"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_certificate"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_certificate"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_certificate_integrity"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_certificate_integrity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_certificate_integrity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_certificate_replacement"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_certificate_replacement"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_certificate_replacement"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_certificate_verification_integrity"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_certificate_verification_integrity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_certificate_verification_integrity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_class_capacity_against_offering"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_class_capacity_against_offering"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_class_capacity_against_offering"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_class_course_offering_consistency"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_class_course_offering_consistency"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_class_course_offering_consistency"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_class_student_capacity"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_class_student_capacity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_class_student_capacity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_class_student_registration"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_class_student_registration"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_class_student_registration"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_course_registration"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_course_registration"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_course_registration"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_course_result_approval"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_course_result_approval"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_course_result_approval"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_course_result_context"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_course_result_context"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_course_result_context"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_course_result_correction"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_course_result_correction"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_course_result_correction"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_course_result_lock"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_course_result_lock"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_course_result_lock"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_course_result_publication"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_course_result_publication"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_course_result_publication"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_course_result_status_transition"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_course_result_status_transition"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_course_result_status_transition"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_course_result_submission"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_course_result_submission"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_course_result_submission"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_examination_attendance"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_examination_attendance"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_examination_attendance"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_examination_candidate"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_examination_candidate"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_examination_candidate"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_examination_candidate_number"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_examination_candidate_number"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_examination_candidate_number"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_examination_candidate_registration"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_examination_candidate_registration"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_examination_candidate_registration"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_examination_candidate_session"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_examination_candidate_session"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_examination_candidate_session"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_examination_invigilator_conflict"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_examination_invigilator_conflict"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_examination_invigilator_conflict"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_examination_mark"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_examination_mark"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_examination_mark"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_examination_mark_correction"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_examination_mark_correction"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_examination_mark_correction"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_examination_paper_context"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_examination_paper_context"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_examination_paper_context"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_examination_room_conflict"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_examination_room_conflict"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_examination_room_conflict"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_examination_session"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_examination_session"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_examination_session"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_examination_session_capacity"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_examination_session_capacity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_examination_session_capacity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_financial_transaction"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_financial_transaction"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_financial_transaction"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_financial_transaction_row"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_financial_transaction_row"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_financial_transaction_row"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_gpa_record"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_gpa_record"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_gpa_record"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_graduation_academic_integrity"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_graduation_academic_integrity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_graduation_academic_integrity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_graduation_approval"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_graduation_approval"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_graduation_approval"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_graduation_approval_completeness"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_graduation_approval_completeness"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_graduation_approval_completeness"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_graduation_approval_integrity"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_graduation_approval_integrity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_graduation_approval_integrity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_graduation_award"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_graduation_award"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_graduation_award"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_graduation_award_integrity"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_graduation_award_integrity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_graduation_award_integrity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_graduation_candidate"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_graduation_candidate"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_graduation_candidate"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_graduation_candidate_clearance_completeness"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_graduation_candidate_clearance_completeness"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_graduation_candidate_clearance_completeness"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_graduation_candidate_transition"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_graduation_candidate_transition"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_graduation_candidate_transition"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_graduation_clearance"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_graduation_clearance"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_graduation_clearance"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_graduation_clearance_integrity"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_graduation_clearance_integrity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_graduation_clearance_integrity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_lecturer_assignment_consistency"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_lecturer_assignment_consistency"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_lecturer_assignment_consistency"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_notification_delivery"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_notification_delivery"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_notification_delivery"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_notification_number"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_notification_number"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_notification_number"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_notification_queue"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_notification_queue"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_notification_queue"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_payment_allocation_integrity"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_payment_allocation_integrity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_payment_allocation_integrity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_payment_integrity"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_payment_integrity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_payment_integrity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_refund_integrity"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_refund_integrity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_refund_integrity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_registration_credit_limit"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_registration_credit_limit"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_registration_credit_limit"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_registration_status_transition"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_registration_status_transition"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_registration_status_transition"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_semester_result_status_transition"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_semester_result_status_transition"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_semester_result_status_transition"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_staff_leave_request"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_staff_leave_request"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_staff_leave_request"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_student_registration"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_student_registration"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_student_registration"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_student_status_transition"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_student_status_transition"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_student_status_transition"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_timetable_class_conflict"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_timetable_class_conflict"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_timetable_class_conflict"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_timetable_course_offering_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_timetable_course_offering_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_timetable_course_offering_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_timetable_lecturer_conflict"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_timetable_lecturer_conflict"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_timetable_lecturer_conflict"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_timetable_room_capacity"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_timetable_room_capacity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_timetable_room_capacity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_timetable_room_conflict"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_timetable_room_conflict"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_timetable_room_conflict"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_timetable_room_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_timetable_room_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_timetable_room_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_timetable_status_transition"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_timetable_status_transition"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_timetable_status_transition"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_transcript_insert_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_transcript_insert_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_transcript_insert_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_transcript_issue"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_transcript_issue"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_transcript_issue"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_transcript_replacement"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_transcript_replacement"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_transcript_replacement"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_transcript_replacement_cycle"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_transcript_replacement_cycle"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_transcript_replacement_cycle"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_transcript_status_transition"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_transcript_status_transition"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_transcript_status_transition"() TO "service_role";



GRANT ALL ON TABLE "public"."academic_qualifications" TO "anon";
GRANT ALL ON TABLE "public"."academic_qualifications" TO "authenticated";
GRANT ALL ON TABLE "public"."academic_qualifications" TO "service_role";



GRANT ALL ON TABLE "public"."academic_standing_rules" TO "anon";
GRANT ALL ON TABLE "public"."academic_standing_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."academic_standing_rules" TO "service_role";



GRANT ALL ON TABLE "public"."academic_years" TO "anon";
GRANT ALL ON TABLE "public"."academic_years" TO "authenticated";
GRANT ALL ON TABLE "public"."academic_years" TO "service_role";



GRANT ALL ON TABLE "public"."admission_acceptances" TO "anon";
GRANT ALL ON TABLE "public"."admission_acceptances" TO "authenticated";
GRANT ALL ON TABLE "public"."admission_acceptances" TO "service_role";



GRANT ALL ON TABLE "public"."admission_decisions" TO "anon";
GRANT ALL ON TABLE "public"."admission_decisions" TO "authenticated";
GRANT ALL ON TABLE "public"."admission_decisions" TO "service_role";



GRANT ALL ON TABLE "public"."admission_offers" TO "anon";
GRANT ALL ON TABLE "public"."admission_offers" TO "authenticated";
GRANT ALL ON TABLE "public"."admission_offers" TO "service_role";



GRANT ALL ON TABLE "public"."alumni_records" TO "anon";
GRANT ALL ON TABLE "public"."alumni_records" TO "authenticated";
GRANT ALL ON TABLE "public"."alumni_records" TO "service_role";



GRANT ALL ON TABLE "public"."applicants" TO "anon";
GRANT ALL ON TABLE "public"."applicants" TO "authenticated";
GRANT ALL ON TABLE "public"."applicants" TO "service_role";



GRANT ALL ON TABLE "public"."application_choices" TO "anon";
GRANT ALL ON TABLE "public"."application_choices" TO "authenticated";
GRANT ALL ON TABLE "public"."application_choices" TO "service_role";



GRANT ALL ON TABLE "public"."application_documents" TO "anon";
GRANT ALL ON TABLE "public"."application_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."application_documents" TO "service_role";



GRANT ALL ON TABLE "public"."applications" TO "anon";
GRANT ALL ON TABLE "public"."applications" TO "authenticated";
GRANT ALL ON TABLE "public"."applications" TO "service_role";



GRANT ALL ON TABLE "public"."assessment_mark_corrections" TO "anon";
GRANT ALL ON TABLE "public"."assessment_mark_corrections" TO "authenticated";
GRANT ALL ON TABLE "public"."assessment_mark_corrections" TO "service_role";



GRANT ALL ON TABLE "public"."assessment_marks" TO "anon";
GRANT ALL ON TABLE "public"."assessment_marks" TO "authenticated";
GRANT ALL ON TABLE "public"."assessment_marks" TO "service_role";



GRANT ALL ON TABLE "public"."assessment_submissions" TO "anon";
GRANT ALL ON TABLE "public"."assessment_submissions" TO "authenticated";
GRANT ALL ON TABLE "public"."assessment_submissions" TO "service_role";



GRANT ALL ON TABLE "public"."assessments" TO "anon";
GRANT ALL ON TABLE "public"."assessments" TO "authenticated";
GRANT ALL ON TABLE "public"."assessments" TO "service_role";



GRANT ALL ON TABLE "public"."asset_assignments" TO "anon";
GRANT ALL ON TABLE "public"."asset_assignments" TO "authenticated";
GRANT ALL ON TABLE "public"."asset_assignments" TO "service_role";



GRANT ALL ON TABLE "public"."asset_categories" TO "anon";
GRANT ALL ON TABLE "public"."asset_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."asset_categories" TO "service_role";



GRANT ALL ON TABLE "public"."asset_maintenance" TO "anon";
GRANT ALL ON TABLE "public"."asset_maintenance" TO "authenticated";
GRANT ALL ON TABLE "public"."asset_maintenance" TO "service_role";



GRANT ALL ON TABLE "public"."assets" TO "anon";
GRANT ALL ON TABLE "public"."assets" TO "authenticated";
GRANT ALL ON TABLE "public"."assets" TO "service_role";



GRANT ALL ON TABLE "public"."asset_summary" TO "anon";
GRANT ALL ON TABLE "public"."asset_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."asset_summary" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_corrections" TO "anon";
GRANT ALL ON TABLE "public"."attendance_corrections" TO "authenticated";
GRANT ALL ON TABLE "public"."attendance_corrections" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_records" TO "anon";
GRANT ALL ON TABLE "public"."attendance_records" TO "authenticated";
GRANT ALL ON TABLE "public"."attendance_records" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_sessions" TO "anon";
GRANT ALL ON TABLE "public"."attendance_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."attendance_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."audit_logs" TO "anon";
GRANT ALL ON TABLE "public"."audit_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."audit_logs" TO "service_role";



GRANT ALL ON TABLE "public"."campuses" TO "anon";
GRANT ALL ON TABLE "public"."campuses" TO "authenticated";
GRANT ALL ON TABLE "public"."campuses" TO "service_role";



GRANT ALL ON TABLE "public"."certificate_verifications" TO "anon";
GRANT ALL ON TABLE "public"."certificate_verifications" TO "authenticated";
GRANT ALL ON TABLE "public"."certificate_verifications" TO "service_role";



GRANT ALL ON TABLE "public"."certificates" TO "anon";
GRANT ALL ON TABLE "public"."certificates" TO "authenticated";
GRANT ALL ON TABLE "public"."certificates" TO "service_role";



GRANT ALL ON TABLE "public"."class_students" TO "anon";
GRANT ALL ON TABLE "public"."class_students" TO "authenticated";
GRANT ALL ON TABLE "public"."class_students" TO "service_role";



GRANT ALL ON TABLE "public"."classes" TO "anon";
GRANT ALL ON TABLE "public"."classes" TO "authenticated";
GRANT ALL ON TABLE "public"."classes" TO "service_role";



GRANT ALL ON TABLE "public"."course_add_drop_requests" TO "anon";
GRANT ALL ON TABLE "public"."course_add_drop_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."course_add_drop_requests" TO "service_role";



GRANT ALL ON TABLE "public"."course_offerings" TO "anon";
GRANT ALL ON TABLE "public"."course_offerings" TO "authenticated";
GRANT ALL ON TABLE "public"."course_offerings" TO "service_role";



GRANT ALL ON TABLE "public"."course_prerequisites" TO "anon";
GRANT ALL ON TABLE "public"."course_prerequisites" TO "authenticated";
GRANT ALL ON TABLE "public"."course_prerequisites" TO "service_role";



GRANT ALL ON TABLE "public"."course_registrations" TO "anon";
GRANT ALL ON TABLE "public"."course_registrations" TO "authenticated";
GRANT ALL ON TABLE "public"."course_registrations" TO "service_role";



GRANT ALL ON TABLE "public"."course_result_corrections" TO "anon";
GRANT ALL ON TABLE "public"."course_result_corrections" TO "authenticated";
GRANT ALL ON TABLE "public"."course_result_corrections" TO "service_role";



GRANT ALL ON TABLE "public"."course_result_policies" TO "anon";
GRANT ALL ON TABLE "public"."course_result_policies" TO "authenticated";
GRANT ALL ON TABLE "public"."course_result_policies" TO "service_role";



GRANT ALL ON TABLE "public"."courses" TO "anon";
GRANT ALL ON TABLE "public"."courses" TO "authenticated";
GRANT ALL ON TABLE "public"."courses" TO "service_role";



GRANT ALL ON TABLE "public"."curricula" TO "anon";
GRANT ALL ON TABLE "public"."curricula" TO "authenticated";
GRANT ALL ON TABLE "public"."curricula" TO "service_role";



GRANT ALL ON TABLE "public"."curriculum_courses" TO "anon";
GRANT ALL ON TABLE "public"."curriculum_courses" TO "authenticated";
GRANT ALL ON TABLE "public"."curriculum_courses" TO "service_role";



GRANT ALL ON TABLE "public"."departments" TO "anon";
GRANT ALL ON TABLE "public"."departments" TO "authenticated";
GRANT ALL ON TABLE "public"."departments" TO "service_role";



GRANT ALL ON TABLE "public"."emergency_contacts" TO "anon";
GRANT ALL ON TABLE "public"."emergency_contacts" TO "authenticated";
GRANT ALL ON TABLE "public"."emergency_contacts" TO "service_role";



GRANT ALL ON TABLE "public"."examination_attendance" TO "anon";
GRANT ALL ON TABLE "public"."examination_attendance" TO "authenticated";
GRANT ALL ON TABLE "public"."examination_attendance" TO "service_role";



GRANT ALL ON TABLE "public"."examination_candidate_sessions" TO "anon";
GRANT ALL ON TABLE "public"."examination_candidate_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."examination_candidate_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."examination_candidates" TO "anon";
GRANT ALL ON TABLE "public"."examination_candidates" TO "authenticated";
GRANT ALL ON TABLE "public"."examination_candidates" TO "service_role";



GRANT ALL ON TABLE "public"."examination_invigilators" TO "anon";
GRANT ALL ON TABLE "public"."examination_invigilators" TO "authenticated";
GRANT ALL ON TABLE "public"."examination_invigilators" TO "service_role";



GRANT ALL ON TABLE "public"."examination_mark_corrections" TO "anon";
GRANT ALL ON TABLE "public"."examination_mark_corrections" TO "authenticated";
GRANT ALL ON TABLE "public"."examination_mark_corrections" TO "service_role";



GRANT ALL ON TABLE "public"."examination_marks" TO "anon";
GRANT ALL ON TABLE "public"."examination_marks" TO "authenticated";
GRANT ALL ON TABLE "public"."examination_marks" TO "service_role";



GRANT ALL ON TABLE "public"."examination_papers" TO "anon";
GRANT ALL ON TABLE "public"."examination_papers" TO "authenticated";
GRANT ALL ON TABLE "public"."examination_papers" TO "service_role";



GRANT ALL ON TABLE "public"."examination_periods" TO "anon";
GRANT ALL ON TABLE "public"."examination_periods" TO "authenticated";
GRANT ALL ON TABLE "public"."examination_periods" TO "service_role";



GRANT ALL ON TABLE "public"."examination_sessions" TO "anon";
GRANT ALL ON TABLE "public"."examination_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."examination_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."fee_items" TO "anon";
GRANT ALL ON TABLE "public"."fee_items" TO "authenticated";
GRANT ALL ON TABLE "public"."fee_items" TO "service_role";



GRANT ALL ON TABLE "public"."fee_structures" TO "anon";
GRANT ALL ON TABLE "public"."fee_structures" TO "authenticated";
GRANT ALL ON TABLE "public"."fee_structures" TO "service_role";



GRANT ALL ON TABLE "public"."financial_transactions" TO "anon";
GRANT ALL ON TABLE "public"."financial_transactions" TO "authenticated";
GRANT ALL ON TABLE "public"."financial_transactions" TO "service_role";



GRANT ALL ON TABLE "public"."grade_scale_details" TO "anon";
GRANT ALL ON TABLE "public"."grade_scale_details" TO "authenticated";
GRANT ALL ON TABLE "public"."grade_scale_details" TO "service_role";



GRANT ALL ON TABLE "public"."grade_scales" TO "anon";
GRANT ALL ON TABLE "public"."grade_scales" TO "authenticated";
GRANT ALL ON TABLE "public"."grade_scales" TO "service_role";



GRANT ALL ON TABLE "public"."graduation_approvals" TO "anon";
GRANT ALL ON TABLE "public"."graduation_approvals" TO "authenticated";
GRANT ALL ON TABLE "public"."graduation_approvals" TO "service_role";



GRANT ALL ON TABLE "public"."graduation_awards" TO "anon";
GRANT ALL ON TABLE "public"."graduation_awards" TO "authenticated";
GRANT ALL ON TABLE "public"."graduation_awards" TO "service_role";



GRANT ALL ON TABLE "public"."graduation_candidates" TO "anon";
GRANT ALL ON TABLE "public"."graduation_candidates" TO "authenticated";
GRANT ALL ON TABLE "public"."graduation_candidates" TO "service_role";



GRANT ALL ON TABLE "public"."graduation_clearance_items" TO "anon";
GRANT ALL ON TABLE "public"."graduation_clearance_items" TO "authenticated";
GRANT ALL ON TABLE "public"."graduation_clearance_items" TO "service_role";



GRANT ALL ON TABLE "public"."graduation_clearances" TO "anon";
GRANT ALL ON TABLE "public"."graduation_clearances" TO "authenticated";
GRANT ALL ON TABLE "public"."graduation_clearances" TO "service_role";



GRANT ALL ON TABLE "public"."graduation_periods" TO "anon";
GRANT ALL ON TABLE "public"."graduation_periods" TO "authenticated";
GRANT ALL ON TABLE "public"."graduation_periods" TO "service_role";



GRANT ALL ON TABLE "public"."guardians" TO "anon";
GRANT ALL ON TABLE "public"."guardians" TO "authenticated";
GRANT ALL ON TABLE "public"."guardians" TO "service_role";



GRANT ALL ON TABLE "public"."hostel_allocations" TO "anon";
GRANT ALL ON TABLE "public"."hostel_allocations" TO "authenticated";
GRANT ALL ON TABLE "public"."hostel_allocations" TO "service_role";



GRANT ALL ON TABLE "public"."hostel_beds" TO "anon";
GRANT ALL ON TABLE "public"."hostel_beds" TO "authenticated";
GRANT ALL ON TABLE "public"."hostel_beds" TO "service_role";



GRANT ALL ON TABLE "public"."hostel_fees" TO "anon";
GRANT ALL ON TABLE "public"."hostel_fees" TO "authenticated";
GRANT ALL ON TABLE "public"."hostel_fees" TO "service_role";



GRANT ALL ON TABLE "public"."hostel_rooms" TO "anon";
GRANT ALL ON TABLE "public"."hostel_rooms" TO "authenticated";
GRANT ALL ON TABLE "public"."hostel_rooms" TO "service_role";



GRANT ALL ON TABLE "public"."hostels" TO "anon";
GRANT ALL ON TABLE "public"."hostels" TO "authenticated";
GRANT ALL ON TABLE "public"."hostels" TO "service_role";



GRANT ALL ON TABLE "public"."hostel_occupancy_summary" TO "anon";
GRANT ALL ON TABLE "public"."hostel_occupancy_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."hostel_occupancy_summary" TO "service_role";



GRANT ALL ON TABLE "public"."institutions" TO "anon";
GRANT ALL ON TABLE "public"."institutions" TO "authenticated";
GRANT ALL ON TABLE "public"."institutions" TO "service_role";



GRANT ALL ON TABLE "public"."inventory_categories" TO "anon";
GRANT ALL ON TABLE "public"."inventory_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_categories" TO "service_role";



GRANT ALL ON TABLE "public"."inventory_items" TO "anon";
GRANT ALL ON TABLE "public"."inventory_items" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_items" TO "service_role";



GRANT ALL ON TABLE "public"."inventory_stock_summary" TO "anon";
GRANT ALL ON TABLE "public"."inventory_stock_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_stock_summary" TO "service_role";



GRANT ALL ON TABLE "public"."inventory_transactions" TO "anon";
GRANT ALL ON TABLE "public"."inventory_transactions" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_transactions" TO "service_role";



GRANT ALL ON TABLE "public"."invoice_items" TO "anon";
GRANT ALL ON TABLE "public"."invoice_items" TO "authenticated";
GRANT ALL ON TABLE "public"."invoice_items" TO "service_role";



GRANT ALL ON TABLE "public"."invoices" TO "anon";
GRANT ALL ON TABLE "public"."invoices" TO "authenticated";
GRANT ALL ON TABLE "public"."invoices" TO "service_role";



GRANT ALL ON TABLE "public"."joining_instructions" TO "anon";
GRANT ALL ON TABLE "public"."joining_instructions" TO "authenticated";
GRANT ALL ON TABLE "public"."joining_instructions" TO "service_role";



GRANT ALL ON TABLE "public"."lecturer_assignments" TO "anon";
GRANT ALL ON TABLE "public"."lecturer_assignments" TO "authenticated";
GRANT ALL ON TABLE "public"."lecturer_assignments" TO "service_role";



GRANT ALL ON TABLE "public"."library_fines" TO "anon";
GRANT ALL ON TABLE "public"."library_fines" TO "authenticated";
GRANT ALL ON TABLE "public"."library_fines" TO "service_role";



GRANT ALL ON TABLE "public"."library_items" TO "anon";
GRANT ALL ON TABLE "public"."library_items" TO "authenticated";
GRANT ALL ON TABLE "public"."library_items" TO "service_role";



GRANT ALL ON TABLE "public"."library_inventory_summary" TO "anon";
GRANT ALL ON TABLE "public"."library_inventory_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."library_inventory_summary" TO "service_role";



GRANT ALL ON SEQUENCE "public"."library_loan_number_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."library_loan_number_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."library_loan_number_seq" TO "service_role";



GRANT ALL ON TABLE "public"."library_loans" TO "anon";
GRANT ALL ON TABLE "public"."library_loans" TO "authenticated";
GRANT ALL ON TABLE "public"."library_loans" TO "service_role";



GRANT ALL ON TABLE "public"."library_members" TO "anon";
GRANT ALL ON TABLE "public"."library_members" TO "authenticated";
GRANT ALL ON TABLE "public"."library_members" TO "service_role";



GRANT ALL ON TABLE "public"."library_reservations" TO "anon";
GRANT ALL ON TABLE "public"."library_reservations" TO "authenticated";
GRANT ALL ON TABLE "public"."library_reservations" TO "service_role";



GRANT ALL ON TABLE "public"."notification_deliveries" TO "anon";
GRANT ALL ON TABLE "public"."notification_deliveries" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_deliveries" TO "service_role";



GRANT ALL ON TABLE "public"."notification_queue" TO "anon";
GRANT ALL ON TABLE "public"."notification_queue" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_queue" TO "service_role";



GRANT ALL ON TABLE "public"."notification_templates" TO "anon";
GRANT ALL ON TABLE "public"."notification_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_templates" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."payment_allocations" TO "anon";
GRANT ALL ON TABLE "public"."payment_allocations" TO "authenticated";
GRANT ALL ON TABLE "public"."payment_allocations" TO "service_role";



GRANT ALL ON TABLE "public"."payments" TO "anon";
GRANT ALL ON TABLE "public"."payments" TO "authenticated";
GRANT ALL ON TABLE "public"."payments" TO "service_role";



GRANT ALL ON TABLE "public"."permissions" TO "anon";
GRANT ALL ON TABLE "public"."permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."permissions" TO "service_role";



GRANT ALL ON TABLE "public"."procurement_request_items" TO "anon";
GRANT ALL ON TABLE "public"."procurement_request_items" TO "authenticated";
GRANT ALL ON TABLE "public"."procurement_request_items" TO "service_role";



GRANT ALL ON SEQUENCE "public"."procurement_request_number_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."procurement_request_number_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."procurement_request_number_seq" TO "service_role";



GRANT ALL ON TABLE "public"."procurement_requests" TO "anon";
GRANT ALL ON TABLE "public"."procurement_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."procurement_requests" TO "service_role";



GRANT ALL ON TABLE "public"."procurement_request_summary" TO "anon";
GRANT ALL ON TABLE "public"."procurement_request_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."procurement_request_summary" TO "service_role";



GRANT ALL ON TABLE "public"."programme_versions" TO "anon";
GRANT ALL ON TABLE "public"."programme_versions" TO "authenticated";
GRANT ALL ON TABLE "public"."programme_versions" TO "service_role";



GRANT ALL ON TABLE "public"."programmes" TO "anon";
GRANT ALL ON TABLE "public"."programmes" TO "authenticated";
GRANT ALL ON TABLE "public"."programmes" TO "service_role";



GRANT ALL ON TABLE "public"."purchase_order_items" TO "anon";
GRANT ALL ON TABLE "public"."purchase_order_items" TO "authenticated";
GRANT ALL ON TABLE "public"."purchase_order_items" TO "service_role";



GRANT ALL ON SEQUENCE "public"."purchase_order_number_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."purchase_order_number_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."purchase_order_number_seq" TO "service_role";



GRANT ALL ON TABLE "public"."purchase_orders" TO "anon";
GRANT ALL ON TABLE "public"."purchase_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."purchase_orders" TO "service_role";



GRANT ALL ON TABLE "public"."refunds" TO "anon";
GRANT ALL ON TABLE "public"."refunds" TO "authenticated";
GRANT ALL ON TABLE "public"."refunds" TO "service_role";



GRANT ALL ON TABLE "public"."registration_approvals" TO "anon";
GRANT ALL ON TABLE "public"."registration_approvals" TO "authenticated";
GRANT ALL ON TABLE "public"."registration_approvals" TO "service_role";



GRANT ALL ON TABLE "public"."role_permissions" TO "anon";
GRANT ALL ON TABLE "public"."role_permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."role_permissions" TO "service_role";



GRANT ALL ON TABLE "public"."roles" TO "anon";
GRANT ALL ON TABLE "public"."roles" TO "authenticated";
GRANT ALL ON TABLE "public"."roles" TO "service_role";



GRANT ALL ON TABLE "public"."rooms" TO "anon";
GRANT ALL ON TABLE "public"."rooms" TO "authenticated";
GRANT ALL ON TABLE "public"."rooms" TO "service_role";



GRANT ALL ON TABLE "public"."schools" TO "anon";
GRANT ALL ON TABLE "public"."schools" TO "authenticated";
GRANT ALL ON TABLE "public"."schools" TO "service_role";



GRANT ALL ON TABLE "public"."security_logs" TO "anon";
GRANT ALL ON TABLE "public"."security_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."security_logs" TO "service_role";



GRANT ALL ON TABLE "public"."semesters" TO "anon";
GRANT ALL ON TABLE "public"."semesters" TO "authenticated";
GRANT ALL ON TABLE "public"."semesters" TO "service_role";



GRANT ALL ON TABLE "public"."staff" TO "anon";
GRANT ALL ON TABLE "public"."staff" TO "authenticated";
GRANT ALL ON TABLE "public"."staff" TO "service_role";



GRANT ALL ON TABLE "public"."staff_attendance" TO "anon";
GRANT ALL ON TABLE "public"."staff_attendance" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_attendance" TO "service_role";



GRANT ALL ON TABLE "public"."staff_attendance_adjustments" TO "anon";
GRANT ALL ON TABLE "public"."staff_attendance_adjustments" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_attendance_adjustments" TO "service_role";



GRANT ALL ON TABLE "public"."staff_attendance_summary" TO "anon";
GRANT ALL ON TABLE "public"."staff_attendance_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_attendance_summary" TO "service_role";



GRANT ALL ON TABLE "public"."staff_documents" TO "anon";
GRANT ALL ON TABLE "public"."staff_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_documents" TO "service_role";



GRANT ALL ON SEQUENCE "public"."staff_employee_number_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."staff_employee_number_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."staff_employee_number_seq" TO "service_role";



GRANT ALL ON TABLE "public"."staff_employment_history" TO "anon";
GRANT ALL ON TABLE "public"."staff_employment_history" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_employment_history" TO "service_role";



GRANT ALL ON TABLE "public"."staff_leave_approvals" TO "anon";
GRANT ALL ON TABLE "public"."staff_leave_approvals" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_leave_approvals" TO "service_role";



GRANT ALL ON TABLE "public"."staff_leave_balances" TO "anon";
GRANT ALL ON TABLE "public"."staff_leave_balances" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_leave_balances" TO "service_role";



GRANT ALL ON SEQUENCE "public"."staff_leave_request_number_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."staff_leave_request_number_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."staff_leave_request_number_seq" TO "service_role";



GRANT ALL ON TABLE "public"."staff_leave_requests" TO "anon";
GRANT ALL ON TABLE "public"."staff_leave_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_leave_requests" TO "service_role";



GRANT ALL ON TABLE "public"."staff_leave_types" TO "anon";
GRANT ALL ON TABLE "public"."staff_leave_types" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_leave_types" TO "service_role";



GRANT ALL ON TABLE "public"."staff_leave_summary" TO "anon";
GRANT ALL ON TABLE "public"."staff_leave_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_leave_summary" TO "service_role";



GRANT ALL ON TABLE "public"."staff_lifecycle_events" TO "anon";
GRANT ALL ON TABLE "public"."staff_lifecycle_events" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_lifecycle_events" TO "service_role";



GRANT ALL ON TABLE "public"."staff_qualifications" TO "anon";
GRANT ALL ON TABLE "public"."staff_qualifications" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_qualifications" TO "service_role";



GRANT ALL ON TABLE "public"."staff_summary" TO "anon";
GRANT ALL ON TABLE "public"."staff_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_summary" TO "service_role";



GRANT ALL ON TABLE "public"."student_academic_deficiencies" TO "anon";
GRANT ALL ON TABLE "public"."student_academic_deficiencies" TO "authenticated";
GRANT ALL ON TABLE "public"."student_academic_deficiencies" TO "service_role";



GRANT ALL ON TABLE "public"."student_cgpa_records" TO "anon";
GRANT ALL ON TABLE "public"."student_cgpa_records" TO "authenticated";
GRANT ALL ON TABLE "public"."student_cgpa_records" TO "service_role";



GRANT ALL ON TABLE "public"."student_charges" TO "anon";
GRANT ALL ON TABLE "public"."student_charges" TO "authenticated";
GRANT ALL ON TABLE "public"."student_charges" TO "service_role";



GRANT ALL ON TABLE "public"."student_course_attempts" TO "anon";
GRANT ALL ON TABLE "public"."student_course_attempts" TO "authenticated";
GRANT ALL ON TABLE "public"."student_course_attempts" TO "service_role";



GRANT ALL ON TABLE "public"."student_documents" TO "anon";
GRANT ALL ON TABLE "public"."student_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."student_documents" TO "service_role";



GRANT ALL ON TABLE "public"."student_fee_adjustments" TO "anon";
GRANT ALL ON TABLE "public"."student_fee_adjustments" TO "authenticated";
GRANT ALL ON TABLE "public"."student_fee_adjustments" TO "service_role";



GRANT ALL ON TABLE "public"."student_financial_accounts" TO "service_role";



GRANT ALL ON TABLE "public"."student_gpa_records" TO "anon";
GRANT ALL ON TABLE "public"."student_gpa_records" TO "authenticated";
GRANT ALL ON TABLE "public"."student_gpa_records" TO "service_role";



GRANT ALL ON TABLE "public"."student_profiles" TO "anon";
GRANT ALL ON TABLE "public"."student_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."student_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."student_programme_history" TO "anon";
GRANT ALL ON TABLE "public"."student_programme_history" TO "authenticated";
GRANT ALL ON TABLE "public"."student_programme_history" TO "service_role";



GRANT ALL ON TABLE "public"."student_registrations" TO "anon";
GRANT ALL ON TABLE "public"."student_registrations" TO "authenticated";
GRANT ALL ON TABLE "public"."student_registrations" TO "service_role";



GRANT ALL ON TABLE "public"."student_scholarships" TO "anon";
GRANT ALL ON TABLE "public"."student_scholarships" TO "authenticated";
GRANT ALL ON TABLE "public"."student_scholarships" TO "service_role";



GRANT ALL ON TABLE "public"."student_status_history" TO "anon";
GRANT ALL ON TABLE "public"."student_status_history" TO "authenticated";
GRANT ALL ON TABLE "public"."student_status_history" TO "service_role";



GRANT ALL ON TABLE "public"."student_transcript_courses" TO "anon";
GRANT ALL ON TABLE "public"."student_transcript_courses" TO "authenticated";
GRANT ALL ON TABLE "public"."student_transcript_courses" TO "service_role";



GRANT ALL ON TABLE "public"."student_transcript_semesters" TO "anon";
GRANT ALL ON TABLE "public"."student_transcript_semesters" TO "authenticated";
GRANT ALL ON TABLE "public"."student_transcript_semesters" TO "service_role";



GRANT ALL ON TABLE "public"."student_transcripts" TO "anon";
GRANT ALL ON TABLE "public"."student_transcripts" TO "authenticated";
GRANT ALL ON TABLE "public"."student_transcripts" TO "service_role";



GRANT ALL ON TABLE "public"."students" TO "anon";
GRANT ALL ON TABLE "public"."students" TO "authenticated";
GRANT ALL ON TABLE "public"."students" TO "service_role";



GRANT ALL ON TABLE "public"."suppliers" TO "anon";
GRANT ALL ON TABLE "public"."suppliers" TO "authenticated";
GRANT ALL ON TABLE "public"."suppliers" TO "service_role";



GRANT ALL ON TABLE "public"."timetable_entries" TO "anon";
GRANT ALL ON TABLE "public"."timetable_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."timetable_entries" TO "service_role";



GRANT ALL ON TABLE "public"."timetable_slots" TO "anon";
GRANT ALL ON TABLE "public"."timetable_slots" TO "authenticated";
GRANT ALL ON TABLE "public"."timetable_slots" TO "service_role";



GRANT ALL ON TABLE "public"."timetables" TO "anon";
GRANT ALL ON TABLE "public"."timetables" TO "authenticated";
GRANT ALL ON TABLE "public"."timetables" TO "service_role";



GRANT ALL ON TABLE "public"."user_addresses" TO "anon";
GRANT ALL ON TABLE "public"."user_addresses" TO "authenticated";
GRANT ALL ON TABLE "public"."user_addresses" TO "service_role";



GRANT ALL ON TABLE "public"."user_preferences" TO "anon";
GRANT ALL ON TABLE "public"."user_preferences" TO "authenticated";
GRANT ALL ON TABLE "public"."user_preferences" TO "service_role";



GRANT ALL ON TABLE "public"."user_profiles" TO "anon";
GRANT ALL ON TABLE "public"."user_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."user_roles" TO "anon";
GRANT ALL ON TABLE "public"."user_roles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_roles" TO "service_role";



GRANT ALL ON TABLE "public"."user_scopes" TO "anon";
GRANT ALL ON TABLE "public"."user_scopes" TO "authenticated";
GRANT ALL ON TABLE "public"."user_scopes" TO "service_role";



GRANT ALL ON TABLE "public"."user_status_history" TO "anon";
GRANT ALL ON TABLE "public"."user_status_history" TO "authenticated";
GRANT ALL ON TABLE "public"."user_status_history" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT ALL ON TABLE "public"."v_invoice_financial_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."v_invoice_financial_summary" TO "service_role";



GRANT ALL ON TABLE "public"."v_student_financial_summary" TO "anon";
GRANT ALL ON TABLE "public"."v_student_financial_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."v_student_financial_summary" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







