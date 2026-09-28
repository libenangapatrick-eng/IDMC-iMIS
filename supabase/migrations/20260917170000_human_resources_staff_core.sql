-- ============================================================
-- IDMC iMIS
-- Migration: Human Resources & Staff Core
-- Version: 20260917170000
-- ============================================================

BEGIN;

-- ============================================================
-- 1. STAFF
-- ============================================================

CREATE SEQUENCE IF NOT EXISTS public.staff_employee_number_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    NO CYCLE;


CREATE TABLE IF NOT EXISTS public.staff (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    institution_id uuid NOT NULL
        REFERENCES public.institutions(id)
        ON DELETE RESTRICT,

    user_id uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    department_id uuid NULL
        REFERENCES public.departments(id)
        ON DELETE SET NULL,

    employee_number varchar(50) NOT NULL UNIQUE,

    staff_category varchar(40) NOT NULL DEFAULT 'ADMINISTRATIVE'
        CHECK (
            staff_category IN (
                'ACADEMIC',
                'ADMINISTRATIVE',
                'CLINICAL',
                'TECHNICAL',
                'SUPPORT',
                'MANAGEMENT',
                'OTHER'
            )
        ),

    employment_type varchar(40) NOT NULL DEFAULT 'FULL_TIME'
        CHECK (
            employment_type IN (
                'FULL_TIME',
                'PART_TIME',
                'CONTRACT',
                'TEMPORARY',
                'VOLUNTEER',
                'INTERNSHIP',
                'OTHER'
            )
        ),

    employment_status varchar(40) NOT NULL DEFAULT 'ACTIVE'
        CHECK (
            employment_status IN (
                'ACTIVE',
                'ON_LEAVE',
                'SUSPENDED',
                'RESIGNED',
                'TERMINATED',
                'RETIRED',
                'INACTIVE'
            )
        ),

    first_name varchar(100) NOT NULL,
    middle_name varchar(100),
    last_name varchar(100) NOT NULL,

    gender varchar(20)
        CHECK (
            gender IS NULL
            OR gender IN ('MALE', 'FEMALE', 'OTHER')
        ),

    date_of_birth date,

    nationality varchar(100) DEFAULT 'Tanzanian',

    national_id varchar(100),
    passport_number varchar(100),

    marital_status varchar(30)
        CHECK (
            marital_status IS NULL
            OR marital_status IN (
                'SINGLE',
                'MARRIED',
                'DIVORCED',
                'WIDOWED',
                'OTHER'
            )
        ),

    phone varchar(50),
    email varchar(255),

    physical_address text,
    postal_address text,

    job_title varchar(150),
    appointment_date date,
    confirmation_date date,
    contract_start_date date,
    contract_end_date date,

    highest_qualification varchar(255),
    professional_registration_number varchar(150),

    emergency_contact_name varchar(200),
    emergency_contact_phone varchar(50),
    emergency_contact_relationship varchar(100),

    profile_photo_url text,

    notes text,

    created_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    updated_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_staff_user
        UNIQUE (user_id),

    CONSTRAINT uq_staff_national_id
        UNIQUE (national_id),

    CONSTRAINT uq_staff_passport
        UNIQUE (passport_number)
);


-- ============================================================
-- 2. STAFF EMPLOYMENT HISTORY
-- ============================================================

CREATE TABLE IF NOT EXISTS public.staff_employment_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    staff_id uuid NOT NULL
        REFERENCES public.staff(id)
        ON DELETE CASCADE,

    department_id uuid NULL
        REFERENCES public.departments(id)
        ON DELETE SET NULL,

    job_title varchar(150),

    employment_type varchar(40) NOT NULL DEFAULT 'FULL_TIME'
        CHECK (
            employment_type IN (
                'FULL_TIME',
                'PART_TIME',
                'CONTRACT',
                'TEMPORARY',
                'VOLUNTEER',
                'INTERNSHIP',
                'OTHER'
            )
        ),

    start_date date NOT NULL,
    end_date date,

    reason_for_change varchar(255),

    notes text,

    created_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 3. STAFF QUALIFICATIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.staff_qualifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    staff_id uuid NOT NULL
        REFERENCES public.staff(id)
        ON DELETE CASCADE,

    qualification_level varchar(100) NOT NULL,

    qualification_name varchar(255) NOT NULL,

    institution_name varchar(255),

    field_of_study varchar(255),

    start_year integer,

    completion_year integer,

    certificate_number varchar(150),

    verification_status varchar(30) NOT NULL DEFAULT 'PENDING'
        CHECK (
            verification_status IN (
                'PENDING',
                'VERIFIED',
                'REJECTED'
            )
        ),

    verification_notes text,

    verified_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    verified_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 4. STAFF DOCUMENTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.staff_documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    staff_id uuid NOT NULL
        REFERENCES public.staff(id)
        ON DELETE CASCADE,

    document_type varchar(100) NOT NULL,

    document_name varchar(255) NOT NULL,

    document_url text,

    storage_path text,

    document_number varchar(150),

    issue_date date,
    expiry_date date,

    verification_status varchar(30) NOT NULL DEFAULT 'PENDING'
        CHECK (
            verification_status IN (
                'PENDING',
                'VERIFIED',
                'REJECTED',
                'EXPIRED'
            )
        ),

    verification_notes text,

    verified_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    verified_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 5. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_staff_institution
    ON public.staff(institution_id);

CREATE INDEX IF NOT EXISTS idx_staff_department
    ON public.staff(department_id);

CREATE INDEX IF NOT EXISTS idx_staff_user
    ON public.staff(user_id);

CREATE INDEX IF NOT EXISTS idx_staff_status
    ON public.staff(employment_status);

CREATE INDEX IF NOT EXISTS idx_staff_category
    ON public.staff(staff_category);

CREATE INDEX IF NOT EXISTS idx_staff_employment_type
    ON public.staff(employment_type);

CREATE INDEX IF NOT EXISTS idx_staff_last_name
    ON public.staff(last_name);

CREATE INDEX IF NOT EXISTS idx_staff_employment_history_staff
    ON public.staff_employment_history(staff_id);

CREATE INDEX IF NOT EXISTS idx_staff_qualification_staff
    ON public.staff_qualifications(staff_id);

CREATE INDEX IF NOT EXISTS idx_staff_qualification_status
    ON public.staff_qualifications(verification_status);

CREATE INDEX IF NOT EXISTS idx_staff_documents_staff
    ON public.staff_documents(staff_id);

CREATE INDEX IF NOT EXISTS idx_staff_documents_expiry
    ON public.staff_documents(expiry_date);

CREATE INDEX IF NOT EXISTS idx_staff_documents_status
    ON public.staff_documents(verification_status);


-- ============================================================
-- 6. UPDATED_AT TRIGGERS
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_staff_updated_at
ON public.staff;

CREATE TRIGGER trg_staff_updated_at
BEFORE UPDATE ON public.staff
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_staff_qualifications_updated_at
ON public.staff_qualifications;

CREATE TRIGGER trg_staff_qualifications_updated_at
BEFORE UPDATE ON public.staff_qualifications
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_staff_documents_updated_at
ON public.staff_documents;

CREATE TRIGGER trg_staff_documents_updated_at
BEFORE UPDATE ON public.staff_documents
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 7. EMPLOYEE NUMBER GENERATOR
-- ============================================================

CREATE OR REPLACE FUNCTION public.generate_staff_employee_number()
RETURNS trigger
LANGUAGE plpgsql
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


DROP TRIGGER IF EXISTS trg_generate_staff_employee_number
ON public.staff;

CREATE TRIGGER trg_generate_staff_employee_number
BEFORE INSERT ON public.staff
FOR EACH ROW
EXECUTE FUNCTION public.generate_staff_employee_number();


-- ============================================================
-- 8. PERMISSIONS
-- ============================================================

INSERT INTO public.permissions (
    permission_code,
    permission_name,
    module_code,
    action_code
)
VALUES
    (
        'staff.view',
        'View staff',
        'HUMAN_RESOURCES',
        'STAFF_VIEW'
    ),
    (
        'staff.manage',
        'Manage staff',
        'HUMAN_RESOURCES',
        'STAFF_MANAGE'
    ),
    (
        'hr.view',
        'View human resources',
        'HUMAN_RESOURCES',
        'HR_VIEW'
    ),
    (
        'hr.manage',
        'Manage human resources',
        'HUMAN_RESOURCES',
        'HR_MANAGE'
    ),
    (
        'staff.documents.verify',
        'Verify staff documents',
        'HUMAN_RESOURCES',
        'STAFF_DOCUMENT_VERIFY'
    )
ON CONFLICT (permission_code)
DO NOTHING;


-- ============================================================
-- 9. ADMIN PERMISSIONS
-- ============================================================

INSERT INTO public.role_permissions (
    role_id,
    permission_id
)
SELECT
    r.id,
    p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.role_code = 'ADMIN'
  AND p.permission_code IN (
      'staff.view',
      'staff.manage',
      'hr.view',
      'hr.manage',
      'staff.documents.verify'
  )
ON CONFLICT DO NOTHING;


-- ============================================================
-- 10. HR OFFICER ROLE
-- ============================================================

INSERT INTO public.roles (
    role_code,
    role_name,
    is_system_role,
    status
)
VALUES (
    'HR_OFFICER',
    'Human Resources Officer',
    FALSE,
    'ACTIVE'
)
ON CONFLICT (role_code)
DO NOTHING;


INSERT INTO public.role_permissions (
    role_id,
    permission_id
)
SELECT
    r.id,
    p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.role_code = 'HR_OFFICER'
  AND p.permission_code IN (
      'staff.view',
      'staff.manage',
      'hr.view',
      'hr.manage',
      'staff.documents.verify'
  )
ON CONFLICT DO NOTHING;


-- ============================================================
-- 11. STAFF SUMMARY VIEW
-- ============================================================

CREATE OR REPLACE VIEW public.staff_summary
AS
SELECT
    s.id,
    s.employee_number,
    s.institution_id,
    s.user_id,
    s.department_id,

    trim(
        concat_ws(
            ' ',
            s.first_name,
            s.middle_name,
            s.last_name
        )
    ) AS staff_name,

    s.staff_category,
    s.employment_type,
    s.employment_status,
    s.gender,
    s.phone,
    s.email,
    s.job_title,
    s.appointment_date,
    s.confirmation_date,

    d.department_name,

    s.created_at,
    s.updated_at

FROM public.staff s
LEFT JOIN public.departments d
    ON d.id = s.department_id;


-- ============================================================
-- 12. COMMENTS
-- ============================================================

COMMENT ON TABLE public.staff IS
'Core institutional staff records.';

COMMENT ON TABLE public.staff_employment_history IS
'Historical staff employment and assignment records.';

COMMENT ON TABLE public.staff_qualifications IS
'Professional and academic qualifications of staff.';

COMMENT ON TABLE public.staff_documents IS
'Documents associated with staff records.';

COMMIT;

-- ============================================================
-- END MIGRATION
-- ============================================================

