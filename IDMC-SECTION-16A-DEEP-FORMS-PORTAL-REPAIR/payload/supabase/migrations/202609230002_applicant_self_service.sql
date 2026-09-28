-- IDMC iMIS: applicant self-service role and least-privilege portal access
BEGIN;

INSERT INTO public.roles(role_code, role_name, description, is_system_role, status)
VALUES ('APPLICANT', 'Applicant', 'Admission applicant with access only to personal application records.', true, 'ACTIVE')
ON CONFLICT (role_code) DO UPDATE SET
  role_name = EXCLUDED.role_name,
  description = EXCLUDED.description,
  status = 'ACTIVE',
  updated_at = now();

INSERT INTO public.permissions(permission_code, permission_name, module_code, action_code, description, status)
VALUES ('portal.applicant', 'Access applicant portal', 'PORTAL', 'APPLICANT', 'Access the ownership-scoped applicant self-service portal.', 'ACTIVE')
ON CONFLICT (permission_code) DO UPDATE SET
  permission_name = EXCLUDED.permission_name,
  description = EXCLUDED.description,
  status = 'ACTIVE',
  updated_at = now();

INSERT INTO public.role_permissions(role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.role_code = 'APPLICANT' AND p.permission_code = 'portal.applicant'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Accelerate ownership checks without mutating any existing duplicate data.
CREATE INDEX IF NOT EXISTS idx_applicants_auth_user_id
  ON public.applicants(auth_user_id)
  WHERE auth_user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_applications_applicant_created
  ON public.applications(applicant_id, created_at DESC);

COMMIT;
