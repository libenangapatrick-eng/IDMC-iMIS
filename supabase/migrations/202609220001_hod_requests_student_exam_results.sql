-- IDMC iMIS: department student requests + secure student examination results
BEGIN;

ALTER TABLE public.course_results
  ADD COLUMN IF NOT EXISTS supplementary_mark numeric(8,2);

DO $$ BEGIN
  ALTER TABLE public.course_results
    ADD CONSTRAINT course_results_supplementary_mark_range
    CHECK (supplementary_mark IS NULL OR supplementary_mark BETWEEN 0 AND 100);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

INSERT INTO public.roles(role_code, role_name, description, is_system_role, status)
VALUES
  ('HOD', 'Head of Department', 'Department-level academic and student request oversight.', true, 'ACTIVE'),
  ('DEPUTY_HOD', 'Deputy Head of Department', 'Delegated department-level academic and student request oversight.', true, 'ACTIVE')
ON CONFLICT (role_code) DO UPDATE SET
  role_name = EXCLUDED.role_name,
  description = EXCLUDED.description,
  status = 'ACTIVE',
  updated_at = now();

INSERT INTO public.permissions(permission_code, permission_name, module_code, action_code, description, status)
VALUES
  ('results.self.view', 'View own published examination results', 'RESULTS', 'SELF_VIEW', 'Student can view only results linked to their own account.', 'ACTIVE'),
  ('student_requests.view_department', 'View department student requests', 'STUDENT_REQUESTS', 'DEPARTMENT_VIEW', 'View student requests for the staff member department.', 'ACTIVE'),
  ('student_requests.decide_department', 'Decide department student requests', 'STUDENT_REQUESTS', 'DEPARTMENT_DECIDE', 'Approve or reject pending student requests in the staff member department.', 'ACTIVE')
ON CONFLICT (permission_code) DO UPDATE SET
  permission_name = EXCLUDED.permission_name,
  description = EXCLUDED.description,
  status = 'ACTIVE',
  updated_at = now();

INSERT INTO public.role_permissions(role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.role_code = 'STUDENT'
  AND p.permission_code = 'results.self.view'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- A student must never receive the generic all-students results permission.
DELETE FROM public.role_permissions rp
USING public.roles r, public.permissions p
WHERE rp.role_id = r.id
  AND rp.permission_id = p.id
  AND r.role_code = 'STUDENT'
  AND p.permission_code = 'results.view';

INSERT INTO public.role_permissions(role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.role_code IN ('HOD', 'DEPUTY_HOD', 'SUPER_ADMIN', 'ADMIN', 'ACADEMIC_OFFICER', 'REGISTRAR')
  AND p.permission_code IN ('student_requests.view_department', 'student_requests.decide_department')
ON CONFLICT (role_id, permission_id) DO NOTHING;

CREATE OR REPLACE VIEW public.v_hod_student_requests AS
SELECT
  adr.id,
  'ADD_DROP'::text AS request_category,
  adr.request_type,
  adr.request_status,
  adr.reason,
  adr.decision_reason,
  adr.requested_at,
  adr.reviewed_at,
  s.id AS student_id,
  s.student_number,
  trim(concat_ws(' ',
    coalesce(s.first_name, sp.first_name),
    coalesce(s.middle_name, sp.middle_name),
    coalesce(s.last_name, sp.last_name)
  )) AS student_name,
  p.id AS programme_id,
  p.programme_code,
  p.programme_name,
  p.department_id,
  d.department_code,
  d.department_name,
  c.id AS course_id,
  c.course_code,
  c.course_name,
  ay.year_code AS academic_year,
  sem.semester_name,
  sem.semester_number
FROM public.course_add_drop_requests adr
JOIN public.students s ON s.id = adr.student_id
LEFT JOIN public.student_profiles sp ON sp.student_id = s.id
JOIN public.programmes p ON p.id = s.programme_id
LEFT JOIN public.departments d ON d.id = p.department_id
JOIN public.courses c ON c.id = adr.course_id
JOIN public.student_registrations sr ON sr.id = adr.student_registration_id
JOIN public.academic_years ay ON ay.id = sr.academic_year_id
JOIN public.semesters sem ON sem.id = sr.semester_id;

REVOKE ALL ON public.v_hod_student_requests FROM anon, authenticated;
GRANT SELECT ON public.v_hod_student_requests TO service_role;

CREATE INDEX IF NOT EXISTS idx_course_results_student_visibility
  ON public.course_results(student_id, result_status, academic_year_id, semester_id);
CREATE INDEX IF NOT EXISTS idx_add_drop_department_lookup
  ON public.course_add_drop_requests(student_id, request_status, requested_at DESC);

COMMIT;
