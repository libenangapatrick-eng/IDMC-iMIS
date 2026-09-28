BEGIN;

-- REGNO is the public academic identity used by result imports.
CREATE UNIQUE INDEX IF NOT EXISTS uq_students_student_number_ci
    ON public.students (lower(student_number));

CREATE TABLE IF NOT EXISTS public.result_import_batches (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    file_name varchar(255) NOT NULL,
    status varchar(30) NOT NULL DEFAULT 'UPLOADED'
        CHECK (status IN ('UPLOADED','VALIDATING','VALIDATED','IMPORTING','IMPORTED','FAILED','CANCELLED')),
    total_rows integer NOT NULL DEFAULT 0,
    valid_rows integer NOT NULL DEFAULT 0,
    invalid_rows integer NOT NULL DEFAULT 0,
    duplicate_rows integer NOT NULL DEFAULT 0,
    created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    confirmed_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    validated_at timestamptz,
    imported_at timestamptz,
    failure_message text
);

CREATE TABLE IF NOT EXISTS public.result_import_rows (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id uuid NOT NULL REFERENCES public.result_import_batches(id) ON DELETE CASCADE,
    row_number integer NOT NULL,
    regno varchar(80),
    academic_year varchar(30),
    semester varchar(50),
    course_code varchar(50),
    coursework_mark numeric(8,2),
    examination_mark numeric(8,2),
    result_type varchar(30) NOT NULL DEFAULT 'NORMAL',
    remarks text,
    validation_status varchar(20) NOT NULL DEFAULT 'PENDING'
        CHECK (validation_status IN ('PENDING','VALID','INVALID','IMPORTED')),
    error_codes text[] NOT NULL DEFAULT '{}',
    error_message text,
    student_id uuid REFERENCES public.students(id) ON DELETE RESTRICT,
    academic_year_id uuid REFERENCES public.academic_years(id) ON DELETE RESTRICT,
    semester_id uuid REFERENCES public.semesters(id) ON DELETE RESTRICT,
    course_id uuid REFERENCES public.courses(id) ON DELETE RESTRICT,
    course_offering_id uuid REFERENCES public.course_offerings(id) ON DELETE RESTRICT,
    course_registration_id uuid REFERENCES public.course_registrations(id) ON DELETE RESTRICT,
    credits numeric(8,2),
    course_result_id uuid REFERENCES public.course_results(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (batch_id, row_number)
);

CREATE INDEX IF NOT EXISTS idx_result_import_rows_batch
    ON public.result_import_rows(batch_id, validation_status);

ALTER TABLE public.result_import_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.result_import_rows ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.course_results
    ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS calculated_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS reviewed_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS reviewed_at timestamptz;

CREATE OR REPLACE FUNCTION public.prevent_protected_course_result_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.result_status IN ('PUBLISHED','LOCKED') AND (
        NEW.student_id IS DISTINCT FROM OLD.student_id OR
        NEW.course_offering_id IS DISTINCT FROM OLD.course_offering_id OR
        NEW.course_registration_id IS DISTINCT FROM OLD.course_registration_id OR
        NEW.coursework_mark IS DISTINCT FROM OLD.coursework_mark OR
        NEW.examination_mark IS DISTINCT FROM OLD.examination_mark OR
        NEW.total_mark IS DISTINCT FROM OLD.total_mark OR
        NEW.grade_code IS DISTINCT FROM OLD.grade_code OR
        NEW.grade_point IS DISTINCT FROM OLD.grade_point OR
        NEW.pass_status IS DISTINCT FROM OLD.pass_status
    ) THEN
        RAISE EXCEPTION 'Published or locked results may only be changed through Result Correction';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_protected_course_result_change ON public.course_results;
CREATE TRIGGER trg_prevent_protected_course_result_change
BEFORE UPDATE ON public.course_results
FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_course_result_change();

CREATE OR REPLACE FUNCTION public.validate_result_import_batch(p_batch_id uuid)
RETURNS public.result_import_batches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r public.result_import_rows%ROWTYPE;
    v_errors text[];
    v_student public.students%ROWTYPE;
    v_year public.academic_years%ROWTYPE;
    v_semester public.semesters%ROWTYPE;
    v_course public.courses%ROWTYPE;
    v_offering public.course_offerings%ROWTYPE;
    v_registration public.course_registrations%ROWTYPE;
    v_policy public.course_result_policies%ROWTYPE;
    v_existing_status text;
    v_duplicate_count integer;
    v_batch public.result_import_batches%ROWTYPE;
BEGIN
    UPDATE public.result_import_batches
    SET status = 'VALIDATING', failure_message = NULL
    WHERE id = p_batch_id;

    FOR r IN SELECT * FROM public.result_import_rows WHERE batch_id = p_batch_id ORDER BY row_number LOOP
        v_errors := '{}';
        v_student := NULL; v_year := NULL; v_semester := NULL; v_course := NULL;
        v_offering := NULL; v_registration := NULL; v_policy := NULL; v_existing_status := NULL;

        IF nullif(trim(r.regno), '') IS NULL THEN v_errors := array_append(v_errors, 'REGNO_MISSING'); END IF;
        IF nullif(trim(r.academic_year), '') IS NULL THEN v_errors := array_append(v_errors, 'ACADEMIC_YEAR_MISSING'); END IF;
        IF nullif(trim(r.semester), '') IS NULL THEN v_errors := array_append(v_errors, 'SEMESTER_MISSING'); END IF;
        IF nullif(trim(r.course_code), '') IS NULL THEN v_errors := array_append(v_errors, 'COURSE_CODE_MISSING'); END IF;
        IF r.coursework_mark IS NULL THEN v_errors := array_append(v_errors, 'COURSEWORK_MISSING'); END IF;
        IF r.examination_mark IS NULL THEN v_errors := array_append(v_errors, 'EXAMINATION_MISSING'); END IF;
        IF r.coursework_mark < 0 THEN v_errors := array_append(v_errors, 'COURSEWORK_BELOW_ZERO'); END IF;
        IF r.examination_mark < 0 THEN v_errors := array_append(v_errors, 'EXAMINATION_BELOW_ZERO'); END IF;
        IF r.result_type NOT IN ('NORMAL','SUPPLEMENTARY','SPECIAL','RESIT','RETAKE','REPEAT','CARRY_FORWARD','MAKEUP') THEN
            v_errors := array_append(v_errors, 'INVALID_RESULT_TYPE');
        END IF;

        SELECT count(*) INTO v_duplicate_count
        FROM public.result_import_rows d
        WHERE d.batch_id = p_batch_id
          AND lower(trim(d.regno)) = lower(trim(r.regno))
          AND lower(trim(d.academic_year)) = lower(trim(r.academic_year))
          AND lower(trim(d.semester)) = lower(trim(r.semester))
          AND lower(trim(d.course_code)) = lower(trim(r.course_code));
        IF v_duplicate_count > 1 THEN v_errors := array_append(v_errors, 'DUPLICATE_IN_FILE'); END IF;

        SELECT * INTO v_student FROM public.students s
        WHERE lower(s.student_number) = lower(trim(r.regno)) LIMIT 1;
        IF v_student.id IS NULL THEN
            v_errors := array_append(v_errors, 'UNKNOWN_REGNO');
        ELSIF v_student.student_status <> 'ACTIVE' THEN
            v_errors := array_append(v_errors, 'INACTIVE_STUDENT');
        END IF;

        SELECT * INTO v_year FROM public.academic_years ay
        WHERE lower(ay.year_code) = lower(trim(r.academic_year))
           OR lower(ay.year_name) = lower(trim(r.academic_year)) LIMIT 1;
        IF v_year.id IS NULL THEN v_errors := array_append(v_errors, 'UNKNOWN_ACADEMIC_YEAR'); END IF;

        IF v_year.id IS NOT NULL THEN
            SELECT * INTO v_semester FROM public.semesters s
            WHERE s.academic_year_id = v_year.id
              AND (lower(s.semester_code) = lower(trim(r.semester))
                OR lower(s.semester_name) = lower(trim(r.semester))) LIMIT 1;
        END IF;
        IF v_semester.id IS NULL THEN v_errors := array_append(v_errors, 'UNKNOWN_SEMESTER'); END IF;

        SELECT * INTO v_course FROM public.courses c
        WHERE lower(c.course_code) = lower(trim(r.course_code)) AND c.status = 'ACTIVE' LIMIT 1;
        IF v_course.id IS NULL THEN v_errors := array_append(v_errors, 'UNKNOWN_COURSE'); END IF;

        IF v_year.id IS NOT NULL AND v_semester.id IS NOT NULL AND v_course.id IS NOT NULL THEN
            SELECT * INTO v_offering FROM public.course_offerings co
            WHERE co.academic_year_id = v_year.id AND co.semester_id = v_semester.id
              AND co.course_id = v_course.id AND co.status <> 'CANCELLED' LIMIT 1;
        END IF;
        IF v_offering.id IS NULL THEN v_errors := array_append(v_errors, 'COURSE_NOT_OFFERED'); END IF;

        IF v_student.id IS NOT NULL AND v_offering.id IS NOT NULL THEN
            SELECT * INTO v_registration FROM public.course_registrations cr
            WHERE cr.student_id = v_student.id AND cr.course_id = v_course.id
              AND cr.course_offering_id = v_offering.id
              AND cr.registration_status NOT IN ('DROPPED','CANCELLED') LIMIT 1;
        END IF;
        IF v_registration.id IS NULL THEN v_errors := array_append(v_errors, 'STUDENT_NOT_REGISTERED_FOR_COURSE'); END IF;

        IF v_offering.id IS NOT NULL THEN
            SELECT * INTO v_policy FROM public.course_result_policies p
            WHERE p.course_offering_id = v_offering.id AND p.status IN ('ACTIVE','LOCKED') LIMIT 1;
        END IF;
        IF v_policy.id IS NULL THEN
            v_errors := array_append(v_errors, 'RESULT_POLICY_MISSING');
        ELSE
            IF r.coursework_mark > v_policy.coursework_weight THEN v_errors := array_append(v_errors, 'COURSEWORK_ABOVE_MAXIMUM'); END IF;
            IF r.examination_mark > v_policy.examination_weight THEN v_errors := array_append(v_errors, 'EXAMINATION_ABOVE_MAXIMUM'); END IF;
        END IF;

        IF v_student.id IS NOT NULL AND v_offering.id IS NOT NULL AND v_registration.id IS NOT NULL THEN
            SELECT cr.result_status INTO v_existing_status FROM public.course_results cr
            WHERE cr.student_id = v_student.id AND cr.course_offering_id = v_offering.id
              AND cr.course_registration_id = v_registration.id LIMIT 1;
        END IF;
        IF v_existing_status IS NOT NULL AND v_existing_status NOT IN ('DRAFT','CALCULATED') THEN
            v_errors := array_append(v_errors, 'EXISTING_RESULT_REQUIRES_CORRECTION');
        END IF;

        UPDATE public.result_import_rows SET
            validation_status = CASE WHEN cardinality(v_errors) = 0 THEN 'VALID' ELSE 'INVALID' END,
            error_codes = v_errors,
            error_message = CASE WHEN cardinality(v_errors) = 0 THEN NULL ELSE array_to_string(v_errors, ', ') END,
            student_id = v_student.id, academic_year_id = v_year.id, semester_id = v_semester.id,
            course_id = v_course.id, course_offering_id = v_offering.id,
            course_registration_id = v_registration.id, credits = v_registration.credits
        WHERE id = r.id;
    END LOOP;

    UPDATE public.result_import_batches b SET
        status = 'VALIDATED', validated_at = now(),
        total_rows = (SELECT count(*) FROM public.result_import_rows WHERE batch_id = p_batch_id),
        valid_rows = (SELECT count(*) FROM public.result_import_rows WHERE batch_id = p_batch_id AND validation_status = 'VALID'),
        invalid_rows = (SELECT count(*) FROM public.result_import_rows WHERE batch_id = p_batch_id AND validation_status = 'INVALID'),
        duplicate_rows = (SELECT count(*) FROM public.result_import_rows WHERE batch_id = p_batch_id AND 'DUPLICATE_IN_FILE' = ANY(error_codes))
    WHERE b.id = p_batch_id RETURNING * INTO v_batch;
    RETURN v_batch;
END;
$$;

CREATE OR REPLACE FUNCTION public.calculate_imported_course_result(p_course_result_id uuid, p_actor_id uuid)
RETURNS public.course_results
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result public.course_results%ROWTYPE;
    v_policy public.course_result_policies%ROWTYPE;
    v_grade record;
    v_total numeric(8,2);
BEGIN
    SELECT * INTO v_result FROM public.course_results WHERE id = p_course_result_id FOR UPDATE;
    IF v_result.id IS NULL THEN RAISE EXCEPTION 'Course result does not exist'; END IF;
    SELECT * INTO v_policy FROM public.course_result_policies
    WHERE course_offering_id = v_result.course_offering_id AND status IN ('ACTIVE','LOCKED') LIMIT 1;
    IF v_policy.id IS NULL THEN RAISE EXCEPTION 'Active result policy is required'; END IF;
    IF v_result.coursework_mark < 0 OR v_result.coursework_mark > v_policy.coursework_weight THEN
        RAISE EXCEPTION 'Coursework mark is outside the configured maximum';
    END IF;
    IF v_result.examination_mark < 0 OR v_result.examination_mark > v_policy.examination_weight THEN
        RAISE EXCEPTION 'Examination mark is outside the configured maximum';
    END IF;
    v_total := round(coalesce(v_result.coursework_mark,0) + coalesce(v_result.examination_mark,0), 2);
    SELECT * INTO v_grade FROM public.get_grade_for_mark(v_policy.grade_scale_id, v_total) LIMIT 1;
    IF v_grade.grade_code IS NULL THEN RAISE EXCEPTION 'No grade definition exists for total mark %', v_total; END IF;
    UPDATE public.course_results SET total_mark = v_total, grade_code = v_grade.grade_code,
        grade_point = v_grade.grade_point, pass_status = v_grade.pass_status,
        result_status = 'CALCULATED', calculated_by = p_actor_id, calculated_at = now(), updated_at = now()
    WHERE id = p_course_result_id RETURNING * INTO v_result;
    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_result_import_batch(p_batch_id uuid, p_actor_id uuid)
RETURNS public.result_import_batches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r public.result_import_rows%ROWTYPE;
    v_result_id uuid;
    v_batch public.result_import_batches%ROWTYPE;
BEGIN
    SELECT * INTO v_batch FROM public.result_import_batches WHERE id = p_batch_id FOR UPDATE;
    IF v_batch.id IS NULL THEN RAISE EXCEPTION 'Result import batch does not exist'; END IF;
    IF v_batch.status <> 'VALIDATED' THEN RAISE EXCEPTION 'Only a validated batch may be imported'; END IF;
    IF v_batch.valid_rows = 0 THEN RAISE EXCEPTION 'The batch has no valid rows'; END IF;
    UPDATE public.result_import_batches SET status = 'IMPORTING' WHERE id = p_batch_id;

    FOR r IN SELECT * FROM public.result_import_rows WHERE batch_id = p_batch_id AND validation_status = 'VALID' ORDER BY row_number LOOP
        v_result_id := NULL;
        INSERT INTO public.course_results (
            student_id, course_offering_id, course_registration_id, academic_year_id, semester_id,
            credits, coursework_mark, examination_mark, result_type, remarks, result_status,
            attempt_number, created_by, updated_at
        ) VALUES (
            r.student_id, r.course_offering_id, r.course_registration_id, r.academic_year_id, r.semester_id,
            coalesce(r.credits,0), r.coursework_mark, r.examination_mark, r.result_type, r.remarks, 'DRAFT',
            1, p_actor_id, now()
        )
        ON CONFLICT (student_id, course_offering_id, course_registration_id) DO UPDATE SET
            coursework_mark = EXCLUDED.coursework_mark, examination_mark = EXCLUDED.examination_mark,
            result_type = EXCLUDED.result_type, remarks = EXCLUDED.remarks, result_status = 'DRAFT', updated_at = now()
        WHERE public.course_results.result_status IN ('DRAFT','CALCULATED')
        RETURNING id INTO v_result_id;
        IF v_result_id IS NULL THEN RAISE EXCEPTION 'Row % targets a protected result; use Result Correction', r.row_number; END IF;
        PERFORM public.calculate_imported_course_result(v_result_id, p_actor_id);
        UPDATE public.result_import_rows SET validation_status = 'IMPORTED', course_result_id = v_result_id WHERE id = r.id;
    END LOOP;

    UPDATE public.result_import_batches SET status = 'IMPORTED', confirmed_by = p_actor_id, imported_at = now()
    WHERE id = p_batch_id RETURNING * INTO v_batch;
    RETURN v_batch;
END;
$$;

INSERT INTO public.permissions (permission_code, permission_name, module_code, action_code, description, status)
VALUES ('results.import','Import results by REGNO','RESULTS','IMPORT','Validate, preview and import course results by REGNO','ACTIVE')
ON CONFLICT (permission_code) DO UPDATE SET permission_name=excluded.permission_name,
    module_code=excluded.module_code, action_code=excluded.action_code,
    description=excluded.description, status='ACTIVE', updated_at=now();

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r CROSS JOIN public.permissions p
WHERE r.role_code IN ('SUPER_ADMIN','ADMIN','REGISTRAR','EXAM_OFFICER','EXAMINATIONS_OFFICER','ACADEMIC_OFFICER')
  AND p.permission_code = 'results.import'
ON CONFLICT DO NOTHING;

REVOKE ALL ON FUNCTION public.validate_result_import_batch(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.calculate_imported_course_result(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.confirm_result_import_batch(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_result_import_batch(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.calculate_imported_course_result(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.confirm_result_import_batch(uuid, uuid) TO service_role;

COMMIT;
