-- IDMC iMIS Section 22D
-- Correct student-activation authority without changing existing identities.

BEGIN;

INSERT INTO public.permissions(
  permission_code, permission_name, module_code, action_code, description, status
) VALUES (
  'students.activate', 'Activate student', 'STUDENTS', 'ACTIVATE',
  'Activate an admitted student from PENDING_ACTIVATION to ACTIVE', 'ACTIVE'
)
ON CONFLICT (permission_code) DO UPDATE SET
  permission_name = excluded.permission_name,
  module_code = excluded.module_code,
  action_code = excluded.action_code,
  description = excluded.description,
  status = 'ACTIVE',
  updated_at = now();

INSERT INTO public.role_permissions(role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON p.permission_code = 'students.activate'
WHERE r.role_code IN (
  'SUPER_ADMIN', 'ADMIN', 'REGISTRAR', 'ACADEMIC_OFFICER', 'ADMISSIONS_OFFICER'
)
  AND r.status = 'ACTIVE'
ON CONFLICT DO NOTHING;

DELETE FROM public.role_permissions rp
USING public.roles r, public.permissions p
WHERE rp.role_id = r.id
  AND rp.permission_id = p.id
  AND r.role_code = 'LECTURER'
  AND p.permission_code = 'students.activate';

COMMIT;
