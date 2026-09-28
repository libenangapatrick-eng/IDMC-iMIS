-- IDMC iMIS Section 17: secure self-service action layer
BEGIN;

CREATE TABLE IF NOT EXISTS public.student_payment_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE RESTRICT,
  invoice_id uuid REFERENCES public.invoices(id) ON DELETE SET NULL,
  request_number varchar(80) NOT NULL UNIQUE,
  provider varchar(40) NOT NULL DEFAULT 'GEPG',
  amount numeric(18,2) NOT NULL CHECK (amount > 0),
  currency_code varchar(10) NOT NULL DEFAULT 'TZS',
  payer_phone varchar(50),
  control_number varchar(100),
  provider_reference varchar(150),
  request_status varchar(30) NOT NULL DEFAULT 'PENDING_PROVIDER'
    CHECK (request_status IN ('PENDING_PROVIDER','ISSUED','PAID','FAILED','EXPIRED','CANCELLED')),
  provider_message text,
  requested_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  issued_at timestamptz,
  paid_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_payment_requests_student ON public.student_payment_requests(student_id, requested_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_open_payment_request ON public.student_payment_requests(student_id, invoice_id)
  WHERE request_status IN ('PENDING_PROVIDER','ISSUED');

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('idmc-private-documents', 'idmc-private-documents', false, 6291456,
        ARRAY['application/pdf','image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO UPDATE SET public = false, file_size_limit = 6291456,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

INSERT INTO public.permissions (permission_code, permission_name, module_code, action_code, description, status)
VALUES
 ('students.registration.manage_own','Manage Own Registration','REGISTRATION','MANAGE_OWN','Student ownership-scoped registration actions','ACTIVE'),
 ('students.payments.request_own','Request Own Payment','FINANCE','REQUEST_OWN','Student ownership-scoped payment request','ACTIVE'),
 ('staff.self.manage','Manage Own Staff Profile','HUMAN_RESOURCES','SELF_MANAGE','Staff self-service profile and leave actions','ACTIVE')
ON CONFLICT (permission_code) DO UPDATE SET status='ACTIVE', updated_at=now();

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p
WHERE r.role_code='STUDENT' AND p.permission_code IN ('students.registration.manage_own','students.payments.request_own')
ON CONFLICT DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p
WHERE r.role_code <> 'STUDENT' AND r.status='ACTIVE' AND p.permission_code='staff.self.manage'
ON CONFLICT DO NOTHING;

COMMIT;
