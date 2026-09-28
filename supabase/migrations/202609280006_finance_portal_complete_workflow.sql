BEGIN;

-- Additive finance workflow. Existing billing records and migrations are preserved.

ALTER TABLE public.fee_structures
  ADD COLUMN IF NOT EXISTS billing_frequency varchar(30) NOT NULL DEFAULT 'SEMESTER',
  ADD COLUMN IF NOT EXISTS semesters_per_year integer NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS published_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS published_at timestamptz,
  ADD COLUMN IF NOT EXISTS locked_at timestamptz;

ALTER TABLE public.fee_items
  ADD COLUMN IF NOT EXISTS annual_amount numeric(18,2),
  ADD COLUMN IF NOT EXISTS semester_amount numeric(18,2),
  ADD COLUMN IF NOT EXISTS amount_confirmed boolean NOT NULL DEFAULT true;

UPDATE public.fee_items fi
SET semester_amount = COALESCE(fi.semester_amount, fi.amount),
    annual_amount = COALESCE(fi.annual_amount, fi.amount * 2)
WHERE fi.semester_amount IS NULL OR fi.annual_amount IS NULL;

CREATE TABLE IF NOT EXISTS public.institutional_fee_catalog (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fee_code varchar(100) NOT NULL UNIQUE,
  fee_name varchar(200) NOT NULL,
  category varchar(50) NOT NULL DEFAULT 'OTHER',
  default_semester_amount numeric(18,2),
  default_annual_amount numeric(18,2),
  amount_confirmed boolean NOT NULL DEFAULT false,
  is_mandatory boolean NOT NULL DEFAULT true,
  display_order integer NOT NULL DEFAULT 0,
  status varchar(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.institutional_fee_catalog
  (fee_code, fee_name, category, default_semester_amount, default_annual_amount, amount_confirmed, is_mandatory, display_order)
VALUES
 ('APPLICATION','Application Fee','OTHER',15000,15000,true,true,1),
 ('TUITION_CERT','Tuition Fee - Certificate','TUITION',650000,1300000,true,true,2),
 ('TUITION_DIP','Tuition Fee - Diploma','TUITION',650000,1300000,true,true,3),
 ('REGISTRATION','Registration Fee','REGISTRATION',NULL,NULL,false,true,4),
 ('NACTVET_QA','NACTVET Quality Assurance Fee','OTHER',NULL,NULL,false,true,5),
 ('NACTVET_VERIFY','NACTVET Registration/Verification Fee','OTHER',NULL,NULL,false,true,6),
 ('STUDENT_UNION','Student Union Fee','OTHER',NULL,NULL,false,true,7),
 ('EXAMINATION','Examination Fee','EXAMINATION',NULL,NULL,false,true,8),
 ('STUDENT_ID','Student ID Card Fee','STUDENT_ID',NULL,NULL,false,true,9),
 ('LIBRARY','Library Fee','LIBRARY',NULL,NULL,false,true,10),
 ('ICT','ICT/Computer Services Fee','ICT',NULL,NULL,false,true,11),
 ('MEDICAL','Medical/Health Services Fee','MEDICAL',NULL,NULL,false,true,12),
 ('FIELD','Field/Practical Training Fee','FIELD_PRACTICAL',NULL,NULL,false,false,13),
 ('CAUTION','Caution Money','OTHER',NULL,NULL,false,true,14),
 ('HOSTEL','Hostel/Accommodation Fee','HOSTEL',100000,200000,true,false,15),
 ('MEALS','Meals/Food Fee','OTHER',NULL,NULL,false,false,16),
 ('ACADEMIC_ADMIN','Examination/Academic Administration Fee','OTHER',NULL,NULL,false,true,17),
 ('GRADUATION','Graduation Fee','GRADUATION',NULL,NULL,false,false,18),
 ('CERT_TRANSCRIPT','Certificate/Transcript Fee','CERTIFICATION',NULL,NULL,false,false,19),
 ('OTHER_INST','Other Institutional Charges','OTHER',NULL,NULL,false,false,20),
 ('LATE_PAYMENT','Late Payment Fee','LATE_FEE',NULL,NULL,false,false,21),
 ('WELFARE','Student Welfare Fee','OTHER',NULL,NULL,false,true,22),
 ('SPORTS','Sports & Recreation Fee','OTHER',NULL,NULL,false,true,23),
 ('SECURITY','Security/Maintenance Fee','OTHER',NULL,NULL,false,true,24),
 ('ACCOM_DEPOSIT','Accommodation Deposit','HOSTEL',NULL,NULL,false,false,25),
 ('STATUTORY','Other Statutory Charges','OTHER',NULL,NULL,false,false,26)
ON CONFLICT (fee_code) DO UPDATE SET
  fee_name = EXCLUDED.fee_name,
  category = EXCLUDED.category,
  default_semester_amount = COALESCE(public.institutional_fee_catalog.default_semester_amount, EXCLUDED.default_semester_amount),
  default_annual_amount = COALESCE(public.institutional_fee_catalog.default_annual_amount, EXCLUDED.default_annual_amount),
  amount_confirmed = public.institutional_fee_catalog.amount_confirmed OR EXCLUDED.amount_confirmed,
  display_order = EXCLUDED.display_order,
  updated_at = now();

CREATE TABLE IF NOT EXISTS public.student_fee_structure_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE RESTRICT,
  fee_structure_id uuid NOT NULL REFERENCES public.fee_structures(id) ON DELETE RESTRICT,
  semester varchar(50) NOT NULL,
  invoice_id uuid REFERENCES public.invoices(id) ON DELETE SET NULL,
  assignment_status varchar(30) NOT NULL DEFAULT 'PENDING'
    CHECK (assignment_status IN ('PENDING','INVOICED','FAILED','CANCELLED')),
  error_message text,
  assigned_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(student_id, fee_structure_id, semester)
);

ALTER TABLE public.student_payment_requests
  ADD COLUMN IF NOT EXISTS receipt_file_path text,
  ADD COLUMN IF NOT EXISTS receipt_file_name varchar(255),
  ADD COLUMN IF NOT EXISTS receipt_mime_type varchar(100),
  ADD COLUMN IF NOT EXISTS receipt_uploaded_at timestamptz,
  ADD COLUMN IF NOT EXISTS receipt_uploaded_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reviewed_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
  ADD COLUMN IF NOT EXISTS finance_notes text,
  ADD COLUMN IF NOT EXISTS payment_id uuid REFERENCES public.payments(id) ON DELETE SET NULL;

ALTER TABLE public.student_payment_requests
  DROP CONSTRAINT IF EXISTS student_payment_requests_request_status_check;
ALTER TABLE public.student_payment_requests
  ADD CONSTRAINT student_payment_requests_request_status_check
  CHECK (request_status IN (
    'PENDING_PROVIDER','ISSUED','RECEIPT_UPLOADED','UNDER_REVIEW',
    'CONFIRMED','PAID','REJECTED','FAILED','EXPIRED','CANCELLED'
  ));

CREATE TABLE IF NOT EXISTS public.finance_expense_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_number varchar(100) NOT NULL UNIQUE,
  requested_by uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  expense_type varchar(40) NOT NULL CHECK (expense_type IN ('PURCHASE','MEETING_ALLOWANCE','TRAVEL','OPERATIONS','OTHER')),
  title varchar(200) NOT NULL,
  description text NOT NULL,
  amount numeric(18,2) NOT NULL CHECK (amount > 0),
  currency_code varchar(10) NOT NULL DEFAULT 'TZS',
  meeting_date date,
  status varchar(40) NOT NULL DEFAULT 'SUBMITTED'
    CHECK (status IN ('DRAFT','SUBMITTED','FINANCE_REVIEWED','PRINCIPAL_APPROVED','REJECTED','PAYMENT_PROCESSING','PAID','CANCELLED')),
  finance_reviewed_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  finance_reviewed_at timestamptz,
  finance_comment text,
  approved_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  approved_at timestamptz,
  approval_comment text,
  paid_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  paid_at timestamptz,
  payment_reference varchar(150),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.finance_expense_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_request_id uuid NOT NULL REFERENCES public.finance_expense_requests(id) ON DELETE CASCADE,
  staff_id uuid REFERENCES public.staff(id) ON DELETE RESTRICT,
  participant_name varchar(200) NOT NULL,
  allowance_amount numeric(18,2) NOT NULL DEFAULT 0 CHECK (allowance_amount >= 0),
  payment_status varchar(30) NOT NULL DEFAULT 'PENDING' CHECK (payment_status IN ('PENDING','APPROVED','PAID','CANCELLED')),
  payment_reference varchar(150),
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(expense_request_id, staff_id)
);

CREATE TABLE IF NOT EXISTS public.finance_workflow_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type varchar(60) NOT NULL,
  entity_id uuid NOT NULL,
  action varchar(60) NOT NULL,
  previous_status varchar(40),
  new_status varchar(40),
  comment text,
  performed_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  performed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fee_assignments_student ON public.student_fee_structure_assignments(student_id, assigned_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_requests_status ON public.student_payment_requests(request_status, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_expense_status ON public.finance_expense_requests(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_expense_requester ON public.finance_expense_requests(requested_by, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_finance_history_entity ON public.finance_workflow_history(entity_type, entity_id, performed_at DESC);

INSERT INTO public.roles(role_code,role_name,description,is_system_role,status)
VALUES
 ('PRINCIPAL','Principal','Institutional executive approval authority',true,'ACTIVE'),
 ('DIRECTOR','Director','Institutional executive approval authority',true,'ACTIVE')
ON CONFLICT (role_code) DO UPDATE SET status='ACTIVE',updated_at=now();

INSERT INTO public.permissions(permission_code, permission_name, module_code, action_code, description, status)
VALUES
 ('finance.portal.view','View Finance Portal','FINANCE','PORTAL_VIEW','View the institutional finance workspace','ACTIVE'),
 ('finance.fees.publish','Publish Fee Structures','FINANCE','FEES_PUBLISH','Publish fee structures and assign billing','ACTIVE'),
 ('finance.payments.confirm','Confirm Student Payments','FINANCE','PAYMENTS_CONFIRM','Review proof and confirm student payment','ACTIVE'),
 ('finance.expenses.review','Review Expense Requests','FINANCE','EXPENSE_REVIEW','Finance review of expenses and allowances','ACTIVE'),
 ('finance.expenses.approve','Approve Expense Requests','FINANCE','EXPENSE_APPROVE','Principal or Director final expense approval','ACTIVE'),
 ('finance.expenses.pay','Pay Approved Expenses','FINANCE','EXPENSE_PAY','Record payment of approved expenses','ACTIVE'),
 ('staff.finance.request_own','Request Own Expense or Allowance','FINANCE','EXPENSE_REQUEST','Staff submits an expense or meeting allowance request','ACTIVE'),
 ('students.payments.upload_receipt','Upload Own Payment Receipt','FINANCE','RECEIPT_UPLOAD','Student uploads proof for own payment request','ACTIVE')
ON CONFLICT (permission_code) DO UPDATE SET
  permission_name=EXCLUDED.permission_name,
  description=EXCLUDED.description,
  status='ACTIVE',
  updated_at=now();

INSERT INTO public.role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p
WHERE r.role_code IN ('SUPER_ADMIN','ADMIN','FINANCE_OFFICER','ACCOUNTANT','FINANCE_MANAGER')
  AND p.permission_code IN ('finance.portal.view','finance.fees.publish','finance.payments.confirm','finance.expenses.review','finance.expenses.pay')
ON CONFLICT DO NOTHING;

INSERT INTO public.role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p
WHERE r.role_code IN ('SUPER_ADMIN','ADMIN','PRINCIPAL','DIRECTOR')
  AND p.permission_code IN ('finance.portal.view','finance.expenses.approve')
ON CONFLICT DO NOTHING;

INSERT INTO public.role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p
WHERE r.role_code='STUDENT' AND p.permission_code='students.payments.upload_receipt'
ON CONFLICT DO NOTHING;

INSERT INTO public.role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p
WHERE r.role_code <> 'STUDENT' AND r.status='ACTIVE' AND p.permission_code='staff.finance.request_own'
ON CONFLICT DO NOTHING;

COMMIT;
