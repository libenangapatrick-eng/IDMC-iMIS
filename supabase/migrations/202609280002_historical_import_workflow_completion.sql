-- IDMC iMIS Section 22C
-- Resumable historical imports and set-based semester provisioning.
-- Additive and idempotent; no student or academic record is deleted.

BEGIN;

CREATE OR REPLACE FUNCTION public.provision_historical_semester(
  p_cohort_year integer,
  p_programme_version_id uuid,
  p_academic_year_id uuid,
  p_semester_id uuid,
  p_actor uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_programme_id uuid;
  v_curriculum_id uuid;
  v_year_code text;
  v_year_number integer;
  v_semester_number integer;
  v_students integer := 0;
  v_courses integer := 0;
  v_offerings integer := 0;
  v_registrations integer := 0;
  v_course_registrations integer := 0;
BEGIN
  SELECT programme_id INTO v_programme_id
  FROM public.programme_versions WHERE id = p_programme_version_id;
  IF v_programme_id IS NULL THEN RAISE EXCEPTION 'Programme version was not found.'; END IF;

  SELECT id INTO v_curriculum_id FROM public.curricula
  WHERE programme_version_id = p_programme_version_id
  ORDER BY (status = 'ACTIVE') DESC, created_at DESC LIMIT 1;
  IF v_curriculum_id IS NULL THEN RAISE EXCEPTION 'Programme version has no curriculum.'; END IF;

  SELECT year_code INTO v_year_code FROM public.academic_years WHERE id = p_academic_year_id;
  SELECT semester_number INTO v_semester_number FROM public.semesters
  WHERE id = p_semester_id AND academic_year_id = p_academic_year_id;
  IF v_year_code IS NULL OR v_semester_number IS NULL THEN RAISE EXCEPTION 'Academic year and semester do not match.'; END IF;

  v_year_number := split_part(v_year_code, '/', 1)::integer - p_cohort_year + 1;
  IF v_year_number < 1 THEN RAISE EXCEPTION 'Academic year is before the selected cohort.'; END IF;

  SELECT count(*) INTO v_students FROM public.students
  WHERE admission_year = p_cohort_year
    AND programme_version_id = p_programme_version_id
    AND archived_at IS NULL;

  SELECT count(*) INTO v_courses FROM public.curriculum_courses
  WHERE curriculum_id = v_curriculum_id
    AND COALESCE(year_number, v_year_number) = v_year_number
    AND semester_number = v_semester_number;

  IF v_students = 0 THEN RAISE EXCEPTION 'No imported students match the selected cohort and programme version.'; END IF;
  IF v_courses = 0 THEN RAISE EXCEPTION 'No curriculum courses are mapped for this year of study and semester.'; END IF;

  INSERT INTO public.course_offerings(
    academic_year_id, semester_id, programme_id, programme_version_id,
    course_id, offering_code, section_name, capacity, delivery_mode,
    status, created_by, updated_by
  )
  SELECT p_academic_year_id, p_semester_id, v_programme_id, p_programme_version_id,
    cc.course_id,
    'HIST-' || replace(v_year_code, '/', '') || '-S' || v_semester_number || '-' || left(p_programme_version_id::text, 8) || '-' ||
      left(regexp_replace(c.course_code, '[^A-Za-z0-9]+', '', 'g'), 30),
    'HISTORICAL', v_students, 'ON_CAMPUS', 'COMPLETED', p_actor, p_actor
  FROM public.curriculum_courses cc
  JOIN public.courses c ON c.id = cc.course_id
  WHERE cc.curriculum_id = v_curriculum_id
    AND COALESCE(cc.year_number, v_year_number) = v_year_number
    AND cc.semester_number = v_semester_number
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_offerings = ROW_COUNT;

  INSERT INTO public.student_registrations(
    student_id, academic_year_id, semester_id, programme_id, programme_version_id,
    registration_number, registration_status, academic_eligibility_status,
    finance_eligibility_status, document_eligibility_status,
    minimum_credits, maximum_credits, approved_at, approved_by, locked_at, locked_by,
    notes, created_by, updated_by
  )
  SELECT s.id, p_academic_year_id, p_semester_id, v_programme_id, p_programme_version_id,
    left('HIST-' || replace(v_year_code, '/', '') || '-S' || v_semester_number || '-' ||
      regexp_replace(s.student_number, '[^A-Za-z0-9]+', '', 'g'), 80),
    'LOCKED', 'ELIGIBLE', 'OVERRIDE', 'OVERRIDE', 0, 99,
    now(), p_actor, now(), p_actor,
    'Historical semester provisioned from approved cohort curriculum.', p_actor, p_actor
  FROM public.students s
  WHERE s.admission_year = p_cohort_year
    AND s.programme_version_id = p_programme_version_id
    AND s.archived_at IS NULL
  ON CONFLICT (student_id, academic_year_id, semester_id) DO NOTHING;
  GET DIAGNOSTICS v_registrations = ROW_COUNT;

  INSERT INTO public.course_registrations(
    student_registration_id, student_id, course_id, course_offering_id,
    registration_type, registration_status, credits, attempt_number,
    is_core, is_elective, prerequisite_status, eligibility_status,
    approved_at, approved_by, notes, created_by, updated_by
  )
  SELECT sr.id, sr.student_id, cc.course_id, co.id,
    'NORMAL', 'REGISTERED', COALESCE(cc.credit_units, c.credit_units, 1), 1,
    cc.is_compulsory, NOT cc.is_compulsory, 'OVERRIDE', 'ELIGIBLE',
    now(), p_actor, 'Historical curriculum registration.', p_actor, p_actor
  FROM public.student_registrations sr
  JOIN public.students s ON s.id = sr.student_id
  JOIN public.curriculum_courses cc ON cc.curriculum_id = v_curriculum_id
    AND COALESCE(cc.year_number, v_year_number) = v_year_number
    AND cc.semester_number = v_semester_number
  JOIN public.courses c ON c.id = cc.course_id
  JOIN public.course_offerings co ON co.academic_year_id = p_academic_year_id
    AND co.semester_id = p_semester_id
    AND co.programme_id = v_programme_id
    AND co.programme_version_id = p_programme_version_id
    AND co.course_id = cc.course_id
  WHERE sr.academic_year_id = p_academic_year_id
    AND sr.semester_id = p_semester_id
    AND s.admission_year = p_cohort_year
    AND s.programme_version_id = p_programme_version_id
    AND s.archived_at IS NULL
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_course_registrations = ROW_COUNT;

  UPDATE public.student_registrations sr SET
    total_registered_credits = COALESCE((
      SELECT sum(cr.credits) FROM public.course_registrations cr
      WHERE cr.student_registration_id = sr.id
        AND cr.registration_status NOT IN ('DROPPED','REJECTED','CANCELLED')
    ), 0),
    updated_at = now(), updated_by = p_actor
  FROM public.students s
  WHERE s.id = sr.student_id
    AND sr.academic_year_id = p_academic_year_id
    AND sr.semester_id = p_semester_id
    AND s.admission_year = p_cohort_year
    AND s.programme_version_id = p_programme_version_id;

  RETURN jsonb_build_object(
    'cohortYear', p_cohort_year, 'yearOfStudy', v_year_number,
    'students', v_students, 'courses', v_courses,
    'offeringsCreated', v_offerings, 'registrationsCreated', v_registrations,
    'courseRegistrationsCreated', v_course_registrations
  );
END;
$$;

CREATE INDEX IF NOT EXISTS idx_students_historical_planning
  ON public.students(admission_year, programme_version_id, student_number)
  WHERE archived_at IS NULL;

COMMIT;
