-- IDMC iMIS Section 16B: payroll, clinical placement and field practical core
BEGIN;

CREATE TABLE IF NOT EXISTS public.payroll_periods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES public.institutions(id),
  period_code varchar(40) NOT NULL UNIQUE,
  period_name varchar(120) NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  payment_date date,
  status varchar(30) NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','OPEN','CALCULATED','APPROVED','PAID','CLOSED','CANCELLED')),
  notes text,
  created_by uuid REFERENCES public.users(id),
  approved_by uuid REFERENCES public.users(id),
  approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (end_date >= start_date)
);

CREATE TABLE IF NOT EXISTS public.payroll_components (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES public.institutions(id),
  component_code varchar(50) NOT NULL,
  component_name varchar(150) NOT NULL,
  component_type varchar(20) NOT NULL CHECK (component_type IN ('EARNING','DEDUCTION','EMPLOYER_CONTRIBUTION')),
  calculation_type varchar(20) NOT NULL DEFAULT 'FIXED' CHECK (calculation_type IN ('FIXED','PERCENTAGE','FORMULA')),
  default_amount numeric(18,2) NOT NULL DEFAULT 0 CHECK (default_amount >= 0),
  default_percentage numeric(8,4) CHECK (default_percentage IS NULL OR default_percentage BETWEEN 0 AND 100),
  taxable boolean NOT NULL DEFAULT false,
  pensionable boolean NOT NULL DEFAULT false,
  status varchar(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (institution_id, component_code)
);

CREATE TABLE IF NOT EXISTS public.staff_payroll_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_period_id uuid NOT NULL REFERENCES public.payroll_periods(id) ON DELETE CASCADE,
  staff_id uuid NOT NULL REFERENCES public.staff(id),
  basic_salary numeric(18,2) NOT NULL DEFAULT 0 CHECK (basic_salary >= 0),
  gross_pay numeric(18,2) NOT NULL DEFAULT 0 CHECK (gross_pay >= 0),
  total_deductions numeric(18,2) NOT NULL DEFAULT 0 CHECK (total_deductions >= 0),
  net_pay numeric(18,2) NOT NULL DEFAULT 0 CHECK (net_pay >= 0),
  currency_code varchar(10) NOT NULL DEFAULT 'TZS',
  bank_name varchar(150),
  bank_account_number varchar(100),
  payment_reference varchar(150),
  status varchar(30) NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','CALCULATED','APPROVED','PAID','HELD','CANCELLED')),
  paid_at timestamptz,
  notes text,
  created_by uuid REFERENCES public.users(id),
  updated_by uuid REFERENCES public.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (payroll_period_id, staff_id),
  CHECK (net_pay <= gross_pay)
);

CREATE TABLE IF NOT EXISTS public.payroll_entry_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_entry_id uuid NOT NULL REFERENCES public.staff_payroll_entries(id) ON DELETE CASCADE,
  payroll_component_id uuid NOT NULL REFERENCES public.payroll_components(id),
  amount numeric(18,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  description varchar(255),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (payroll_entry_id, payroll_component_id)
);

CREATE TABLE IF NOT EXISTS public.placement_sites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES public.institutions(id),
  site_code varchar(50) NOT NULL UNIQUE,
  site_name varchar(200) NOT NULL,
  site_type varchar(60),
  registration_number varchar(100),
  contact_person varchar(150),
  phone varchar(50),
  email varchar(255),
  physical_address text,
  region varchar(100),
  district varchar(100),
  capacity integer CHECK (capacity IS NULL OR capacity >= 0),
  agreement_start_date date,
  agreement_end_date date,
  status varchar(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE','SUSPENDED')),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (agreement_end_date IS NULL OR agreement_start_date IS NULL OR agreement_end_date >= agreement_start_date)
);

CREATE TABLE IF NOT EXISTS public.clinical_placements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students(id),
  placement_site_id uuid NOT NULL REFERENCES public.placement_sites(id),
  academic_year_id uuid REFERENCES public.academic_years(id),
  semester_id uuid REFERENCES public.semesters(id),
  course_id uuid REFERENCES public.courses(id),
  supervisor_staff_id uuid REFERENCES public.staff(id),
  placement_number varchar(80) NOT NULL UNIQUE,
  department_unit varchar(150),
  start_date date NOT NULL,
  end_date date NOT NULL,
  required_hours numeric(10,2) NOT NULL DEFAULT 0 CHECK (required_hours >= 0),
  completed_hours numeric(10,2) NOT NULL DEFAULT 0 CHECK (completed_hours >= 0),
  status varchar(30) NOT NULL DEFAULT 'PLANNED' CHECK (status IN ('PLANNED','ACTIVE','COMPLETED','DEFERRED','CANCELLED')),
  final_score numeric(6,2) CHECK (final_score IS NULL OR final_score BETWEEN 0 AND 100),
  final_grade varchar(10),
  remarks text,
  created_by uuid REFERENCES public.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (end_date >= start_date)
);

CREATE TABLE IF NOT EXISTS public.clinical_assessments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinical_placement_id uuid NOT NULL REFERENCES public.clinical_placements(id) ON DELETE CASCADE,
  assessment_type varchar(50) NOT NULL,
  assessment_date date NOT NULL DEFAULT CURRENT_DATE,
  assessor_name varchar(150),
  assessor_staff_id uuid REFERENCES public.staff(id),
  score numeric(6,2) CHECK (score IS NULL OR score BETWEEN 0 AND 100),
  competency_rating varchar(30),
  feedback text,
  evidence_url text,
  status varchar(20) NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','SUBMITTED','VERIFIED','LOCKED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.field_organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES public.institutions(id),
  organization_code varchar(50) NOT NULL UNIQUE,
  organization_name varchar(200) NOT NULL,
  industry_sector varchar(120),
  contact_person varchar(150),
  phone varchar(50),
  email varchar(255),
  physical_address text,
  region varchar(100),
  district varchar(100),
  capacity integer CHECK (capacity IS NULL OR capacity >= 0),
  status varchar(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE','SUSPENDED')),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.field_practicals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students(id),
  field_organization_id uuid NOT NULL REFERENCES public.field_organizations(id),
  academic_year_id uuid REFERENCES public.academic_years(id),
  semester_id uuid REFERENCES public.semesters(id),
  course_id uuid REFERENCES public.courses(id),
  supervisor_staff_id uuid REFERENCES public.staff(id),
  practical_number varchar(80) NOT NULL UNIQUE,
  start_date date NOT NULL,
  end_date date NOT NULL,
  required_hours numeric(10,2) NOT NULL DEFAULT 0 CHECK (required_hours >= 0),
  completed_hours numeric(10,2) NOT NULL DEFAULT 0 CHECK (completed_hours >= 0),
  status varchar(30) NOT NULL DEFAULT 'PLANNED' CHECK (status IN ('PLANNED','ACTIVE','COMPLETED','DEFERRED','CANCELLED')),
  supervisor_score numeric(6,2) CHECK (supervisor_score IS NULL OR supervisor_score BETWEEN 0 AND 100),
  academic_score numeric(6,2) CHECK (academic_score IS NULL OR academic_score BETWEEN 0 AND 100),
  final_score numeric(6,2) CHECK (final_score IS NULL OR final_score BETWEEN 0 AND 100),
  final_grade varchar(10),
  remarks text,
  created_by uuid REFERENCES public.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (end_date >= start_date)
);

CREATE TABLE IF NOT EXISTS public.field_practical_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  field_practical_id uuid NOT NULL REFERENCES public.field_practicals(id) ON DELETE CASCADE,
  report_type varchar(40) NOT NULL,
  title varchar(200) NOT NULL,
  file_url text,
  submitted_at timestamptz,
  reviewed_by uuid REFERENCES public.users(id),
  reviewed_at timestamptz,
  score numeric(6,2) CHECK (score IS NULL OR score BETWEEN 0 AND 100),
  feedback text,
  status varchar(20) NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','SUBMITTED','REVIEWED','APPROVED','REJECTED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payroll_entries_period_staff ON public.staff_payroll_entries(payroll_period_id, staff_id);
CREATE INDEX IF NOT EXISTS idx_clinical_student_year ON public.clinical_placements(student_id, academic_year_id);
CREATE INDEX IF NOT EXISTS idx_field_practical_student_year ON public.field_practicals(student_id, academic_year_id);

CREATE OR REPLACE FUNCTION public.idmc_refresh_payroll_entry_totals()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_entry_id uuid := COALESCE(NEW.payroll_entry_id, OLD.payroll_entry_id);
  v_earnings numeric(18,2);
  v_deductions numeric(18,2);
BEGIN
  SELECT
    COALESCE(sum(CASE WHEN pc.component_type='EARNING' THEN pel.amount ELSE 0 END),0),
    COALESCE(sum(CASE WHEN pc.component_type='DEDUCTION' THEN pel.amount ELSE 0 END),0)
  INTO v_earnings, v_deductions
  FROM public.payroll_entry_lines pel
  JOIN public.payroll_components pc ON pc.id=pel.payroll_component_id
  WHERE pel.payroll_entry_id=v_entry_id;

  UPDATE public.staff_payroll_entries
  SET gross_pay=basic_salary+v_earnings,
      total_deductions=v_deductions,
      net_pay=GREATEST(basic_salary+v_earnings-v_deductions,0),
      updated_at=now()
  WHERE id=v_entry_id;
  RETURN COALESCE(NEW,OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_refresh_payroll_entry_totals ON public.payroll_entry_lines;
CREATE TRIGGER trg_refresh_payroll_entry_totals
AFTER INSERT OR UPDATE OR DELETE ON public.payroll_entry_lines
FOR EACH ROW EXECUTE FUNCTION public.idmc_refresh_payroll_entry_totals();

INSERT INTO public.permissions(permission_code,permission_name,module_code,action_code,description,status) VALUES
 ('payroll.view','View payroll','PAYROLL','VIEW','View payroll periods, components and staff payroll entries.','ACTIVE'),
 ('payroll.manage','Manage payroll','PAYROLL','MANAGE','Create and update payroll records.','ACTIVE'),
 ('clinical.view','View clinical placements','CLINICAL','VIEW','View clinical sites, placements and assessments.','ACTIVE'),
 ('clinical.manage','Manage clinical placements','CLINICAL','MANAGE','Manage clinical placement records.','ACTIVE'),
 ('field_practical.view','View field practical','FIELD_PRACTICAL','VIEW','View field practical organizations, placements and reports.','ACTIVE'),
 ('field_practical.manage','Manage field practical','FIELD_PRACTICAL','MANAGE','Manage field practical records.','ACTIVE')
ON CONFLICT(permission_code) DO UPDATE SET permission_name=EXCLUDED.permission_name,description=EXCLUDED.description,status='ACTIVE',updated_at=now();

INSERT INTO public.role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p
WHERE r.role_code IN ('SUPER_ADMIN','ADMIN','HR_OFFICER') AND p.permission_code IN ('payroll.view','payroll.manage')
ON CONFLICT DO NOTHING;

INSERT INTO public.role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p
WHERE r.role_code IN ('SUPER_ADMIN','ADMIN','ACADEMIC_OFFICER','REGISTRAR','HOD','DEPUTY_HOD')
AND p.permission_code IN ('clinical.view','clinical.manage','field_practical.view','field_practical.manage')
ON CONFLICT DO NOTHING;

COMMIT;
