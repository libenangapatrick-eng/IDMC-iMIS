-- ============================================================
-- IDMC iMIS
-- Migration 005: Applications & Admissions
-- PostgreSQL / Supabase Safe
-- ============================================================

-- ------------------------------------------------------------
-- 1. Applicants
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.applicants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    applicant_number varchar(50) NOT NULL UNIQUE,

    first_name varchar(100) NOT NULL,
    middle_name varchar(100),
    last_name varchar(100) NOT NULL,

    gender varchar(30),
    date_of_birth date,

    nationality varchar(100),
    national_id_number varchar(100),
    passport_number varchar(100),

    email varchar(255) NOT NULL,
    phone varchar(50),

    address_line_1 varchar(255),
    address_line_2 varchar(255),
    city varchar(100),
    district varchar(100),
    region varchar(100),
    country varchar(100) DEFAULT 'Tanzania',

    disability_status boolean NOT NULL DEFAULT false,
    disability_details text,

    applicant_type varchar(50) NOT NULL DEFAULT 'NEW',

    status varchar(30) NOT NULL DEFAULT 'ACTIVE',

    auth_user_id uuid
        REFERENCES auth.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT applicants_gender_check
        CHECK (
            gender IS NULL
            OR gender IN (
                'MALE',
                'FEMALE',
                'OTHER',
                'PREFER_NOT_TO_SAY'
            )
        ),

    CONSTRAINT applicants_type_check
        CHECK (
            applicant_type IN (
                'NEW',
                'TRANSFER',
                'CONTINUING',
                'INTERNATIONAL',
                'OTHER'
            )
        ),

    CONSTRAINT applicants_status_check
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE',
                'BLACKLISTED',
                'CONVERTED',
                'ARCHIVED'
            )
        )
);

-- ------------------------------------------------------------
-- 2. Applications
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.applications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    applicant_id uuid NOT NULL
        REFERENCES public.applicants(id)
        ON DELETE RESTRICT,

    academic_year_id uuid NOT NULL
        REFERENCES public.academic_years(id)
        ON DELETE RESTRICT,

    application_number varchar(50) NOT NULL UNIQUE,

    application_type varchar(50) NOT NULL DEFAULT 'NEW',

    application_round varchar(50),

    submitted_at timestamptz,

    status varchar(40) NOT NULL DEFAULT 'DRAFT',

    payment_status varchar(30) NOT NULL DEFAULT 'PENDING',

    verification_status varchar(30) NOT NULL DEFAULT 'PENDING',

    eligibility_status varchar(30) NOT NULL DEFAULT 'PENDING',

    selection_status varchar(30) NOT NULL DEFAULT 'PENDING',

    completion_percentage numeric(5,2) NOT NULL DEFAULT 0,

    correction_count integer NOT NULL DEFAULT 0,

    correction_deadline timestamptz,

    reviewed_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    reviewed_at timestamptz,

    review_comments text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT applications_type_check
        CHECK (
            application_type IN (
                'NEW',
                'TRANSFER',
                'POSTGRADUATE',
                'SHORT_COURSE',
                'INTERNATIONAL',
                'OTHER'
            )
        ),

    CONSTRAINT applications_status_check
        CHECK (
            status IN (
                'DRAFT',
                'SUBMITTED',
                'PAYMENT_PENDING',
                'PAYMENT_CONFIRMED',
                'UNDER_REVIEW',
                'CORRECTION_REQUIRED',
                'VERIFIED',
                'ELIGIBLE',
                'INELIGIBLE',
                'SELECTED',
                'WAITLISTED',
                'ADMISSION_OFFERED',
                'ACCEPTED',
                'REJECTED',
                'CANCELLED',
                'CONVERTED_TO_STUDENT'
            )
        ),

    CONSTRAINT applications_payment_status_check
        CHECK (
            payment_status IN (
                'PENDING',
                'UNPAID',
                'PAID',
                'FAILED',
                'WAIVED',
                'REFUNDED'
            )
        ),

    CONSTRAINT applications_verification_status_check
        CHECK (
            verification_status IN (
                'PENDING',
                'IN_PROGRESS',
                'VERIFIED',
                'REJECTED',
                'CORRECTION_REQUIRED'
            )
        ),

    CONSTRAINT applications_eligibility_status_check
        CHECK (
            eligibility_status IN (
                'PENDING',
                'ELIGIBLE',
                'INELIGIBLE',
                'CONDITIONAL'
            )
        ),

    CONSTRAINT applications_selection_status_check
        CHECK (
            selection_status IN (
                'PENDING',
                'SELECTED',
                'WAITLISTED',
                'NOT_SELECTED'
            )
        ),

    CONSTRAINT applications_completion_check
        CHECK (
            completion_percentage >= 0
            AND completion_percentage <= 100
        ),

    CONSTRAINT applications_correction_count_check
        CHECK (correction_count >= 0)
);

-- ------------------------------------------------------------
-- 3. Application Choices
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.application_choices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    application_id uuid NOT NULL
        REFERENCES public.applications(id)
        ON DELETE CASCADE,

    programme_id uuid NOT NULL
        REFERENCES public.programmes(id)
        ON DELETE RESTRICT,

    choice_number integer NOT NULL,

    preference_type varchar(30) NOT NULL DEFAULT 'PREFERRED',

    status varchar(30) NOT NULL DEFAULT 'PENDING',

    decision_reason text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT application_choices_number_check
        CHECK (choice_number > 0),

    CONSTRAINT application_choices_preference_check
        CHECK (
            preference_type IN (
                'PREFERRED',
                'ALTERNATIVE'
            )
        ),

    CONSTRAINT application_choices_status_check
        CHECK (
            status IN (
                'PENDING',
                'ELIGIBLE',
                'INELIGIBLE',
                'SELECTED',
                'WAITLISTED',
                'REJECTED',
                'WITHDRAWN'
            )
        ),

    CONSTRAINT uq_application_choice_number
        UNIQUE (application_id, choice_number),

    CONSTRAINT uq_application_programme
        UNIQUE (application_id, programme_id)
);

-- ------------------------------------------------------------
-- 4. Academic Qualifications
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.academic_qualifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    applicant_id uuid NOT NULL
        REFERENCES public.applicants(id)
        ON DELETE CASCADE,

    qualification_type varchar(50) NOT NULL,

    institution_name varchar(255) NOT NULL,

    country varchar(100),

    award_name varchar(200),

    index_number varchar(100),

    registration_number varchar(100),

    start_year integer,

    completion_year integer,

    grade varchar(100),

    gpa numeric(5,2),

    field_of_study varchar(200),

    verification_status varchar(30) NOT NULL DEFAULT 'PENDING',

    verified_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    verified_at timestamptz,

    verification_comments text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT academic_qualifications_type_check
        CHECK (
            qualification_type IN (
                'PRIMARY',
                'SECONDARY',
                'CERTIFICATE',
                'DIPLOMA',
                'ADVANCED_DIPLOMA',
                'BACHELOR',
                'POSTGRADUATE_DIPLOMA',
                'MASTERS',
                'PHD',
                'PROFESSIONAL',
                'OTHER'
            )
        ),

    CONSTRAINT academic_qualifications_year_check
        CHECK (
            completion_year IS NULL
            OR start_year IS NULL
            OR completion_year >= start_year
        ),

    CONSTRAINT academic_qualifications_gpa_check
        CHECK (
            gpa IS NULL
            OR gpa >= 0
        ),

    CONSTRAINT academic_qualifications_verification_check
        CHECK (
            verification_status IN (
                'PENDING',
                'VERIFIED',
                'REJECTED',
                'REQUIRES_REVIEW'
            )
        )
);

-- ------------------------------------------------------------
-- 5. Application Documents
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.application_documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    application_id uuid NOT NULL
        REFERENCES public.applications(id)
        ON DELETE CASCADE,

    document_type varchar(80) NOT NULL,

    document_name varchar(255) NOT NULL,

    file_url text NOT NULL,

    file_size bigint,

    mime_type varchar(100),

    document_number varchar(100),

    issue_date date,

    expiry_date date,

    verification_status varchar(30) NOT NULL DEFAULT 'PENDING',

    verified_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    verified_at timestamptz,

    rejection_reason text,

    uploaded_at timestamptz NOT NULL DEFAULT now(),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT application_documents_file_size_check
        CHECK (
            file_size IS NULL
            OR file_size >= 0
        ),

    CONSTRAINT application_documents_date_check
        CHECK (
            expiry_date IS NULL
            OR issue_date IS NULL
            OR expiry_date >= issue_date
        ),

    CONSTRAINT application_documents_status_check
        CHECK (
            verification_status IN (
                'PENDING',
                'UNDER_REVIEW',
                'VERIFIED',
                'REJECTED',
                'EXPIRED',
                'CORRECTION_REQUIRED'
            )
        )
);

-- ------------------------------------------------------------
-- 6. Admission Decisions
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.admission_decisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    application_id uuid NOT NULL
        REFERENCES public.applications(id)
        ON DELETE RESTRICT,

    application_choice_id uuid
        REFERENCES public.application_choices(id)
        ON DELETE RESTRICT,

    decision_type varchar(40) NOT NULL,

    decision_status varchar(30) NOT NULL DEFAULT 'PENDING',

    decision_date timestamptz,

    decision_reason text,

    capacity_check boolean NOT NULL DEFAULT false,

    academic_check boolean NOT NULL DEFAULT false,

    document_check boolean NOT NULL DEFAULT false,

    approved_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    approved_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT admission_decisions_type_check
        CHECK (
            decision_type IN (
                'SELECTED',
                'WAITLISTED',
                'REJECTED',
                'CONDITIONAL'
            )
        ),

    CONSTRAINT admission_decisions_status_check
        CHECK (
            decision_status IN (
                'PENDING',
                'APPROVED',
                'REJECTED',
                'CANCELLED'
            )
        )
);

-- ------------------------------------------------------------
-- 7. Admission Offers
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.admission_offers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    application_id uuid NOT NULL
        REFERENCES public.applications(id)
        ON DELETE RESTRICT,

    programme_id uuid NOT NULL
        REFERENCES public.programmes(id)
        ON DELETE RESTRICT,

    decision_id uuid
        REFERENCES public.admission_decisions(id)
        ON DELETE SET NULL,

    offer_number varchar(60) NOT NULL UNIQUE,

    offer_date date NOT NULL DEFAULT CURRENT_DATE,

    expiry_date date,

    offer_status varchar(30) NOT NULL DEFAULT 'ISSUED',

    admission_conditions text,

    admission_letter_url text,

    joining_instructions_url text,

    issued_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    issued_at timestamptz NOT NULL DEFAULT now(),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT admission_offers_status_check
        CHECK (
            offer_status IN (
                'DRAFT',
                'ISSUED',
                'ACCEPTED',
                'DECLINED',
                'EXPIRED',
                'CANCELLED'
            )
        ),

    CONSTRAINT admission_offers_date_check
        CHECK (
            expiry_date IS NULL
            OR expiry_date >= offer_date
        )
);

-- ------------------------------------------------------------
-- 8. Admission Acceptances
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.admission_acceptances (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    admission_offer_id uuid NOT NULL UNIQUE
        REFERENCES public.admission_offers(id)
        ON DELETE CASCADE,

    acceptance_status varchar(30) NOT NULL DEFAULT 'PENDING',

    accepted_at timestamptz,

    declined_at timestamptz,

    decline_reason text,

    acceptance_ip_address inet,

    acceptance_user_agent text,

    accepted_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT admission_acceptances_status_check
        CHECK (
            acceptance_status IN (
                'PENDING',
                'ACCEPTED',
                'DECLINED',
                'EXPIRED'
            )
        )
);

-- ------------------------------------------------------------
-- 9. Joining Instructions
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.joining_instructions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    academic_year_id uuid NOT NULL
        REFERENCES public.academic_years(id)
        ON DELETE RESTRICT,

    programme_id uuid
        REFERENCES public.programmes(id)
        ON DELETE RESTRICT,

    title varchar(255) NOT NULL,

    description text,

    document_url text,

    version_number integer NOT NULL DEFAULT 1,

    status varchar(30) NOT NULL DEFAULT 'DRAFT',

    published_at timestamptz,

    published_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT joining_instructions_version_check
        CHECK (version_number > 0),

    CONSTRAINT joining_instructions_status_check
        CHECK (
            status IN (
                'DRAFT',
                'PUBLISHED',
                'ARCHIVED'
            )
        )
);

-- ------------------------------------------------------------
-- 10. Indexes
-- ------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_applicants_email
    ON public.applicants(email);

CREATE INDEX IF NOT EXISTS idx_applicants_phone
    ON public.applicants(phone);

CREATE INDEX IF NOT EXISTS idx_applicants_auth_user
    ON public.applicants(auth_user_id);

CREATE INDEX IF NOT EXISTS idx_applicants_status
    ON public.applicants(status);

CREATE INDEX IF NOT EXISTS idx_applicants_national_id
    ON public.applicants(national_id_number);

CREATE INDEX IF NOT EXISTS idx_applicants_passport
    ON public.applicants(passport_number);

CREATE INDEX IF NOT EXISTS idx_applications_applicant
    ON public.applications(applicant_id);

CREATE INDEX IF NOT EXISTS idx_applications_academic_year
    ON public.applications(academic_year_id);

CREATE INDEX IF NOT EXISTS idx_applications_status
    ON public.applications(status);

CREATE INDEX IF NOT EXISTS idx_applications_payment_status
    ON public.applications(payment_status);

CREATE INDEX IF NOT EXISTS idx_applications_verification_status
    ON public.applications(verification_status);

CREATE INDEX IF NOT EXISTS idx_applications_selection_status
    ON public.applications(selection_status);

CREATE INDEX IF NOT EXISTS idx_application_choices_application
    ON public.application_choices(application_id);

CREATE INDEX IF NOT EXISTS idx_application_choices_programme
    ON public.application_choices(programme_id);

CREATE INDEX IF NOT EXISTS idx_application_choices_status
    ON public.application_choices(status);

CREATE INDEX IF NOT EXISTS idx_academic_qualifications_applicant
    ON public.academic_qualifications(applicant_id);

CREATE INDEX IF NOT EXISTS idx_academic_qualifications_type
    ON public.academic_qualifications(qualification_type);

CREATE INDEX IF NOT EXISTS idx_academic_qualifications_verification
    ON public.academic_qualifications(verification_status);

CREATE INDEX IF NOT EXISTS idx_application_documents_application
    ON public.application_documents(application_id);

CREATE INDEX IF NOT EXISTS idx_application_documents_type
    ON public.application_documents(document_type);

CREATE INDEX IF NOT EXISTS idx_application_documents_status
    ON public.application_documents(verification_status);

CREATE INDEX IF NOT EXISTS idx_admission_decisions_application
    ON public.admission_decisions(application_id);

CREATE INDEX IF NOT EXISTS idx_admission_decisions_choice
    ON public.admission_decisions(application_choice_id);

CREATE INDEX IF NOT EXISTS idx_admission_decisions_status
    ON public.admission_decisions(decision_status);

CREATE INDEX IF NOT EXISTS idx_admission_offers_application
    ON public.admission_offers(application_id);

CREATE INDEX IF NOT EXISTS idx_admission_offers_programme
    ON public.admission_offers(programme_id);

CREATE INDEX IF NOT EXISTS idx_admission_offers_status
    ON public.admission_offers(offer_status);

CREATE INDEX IF NOT EXISTS idx_admission_acceptances_status
    ON public.admission_acceptances(acceptance_status);

CREATE INDEX IF NOT EXISTS idx_joining_instructions_year
    ON public.joining_instructions(academic_year_id);

CREATE INDEX IF NOT EXISTS idx_joining_instructions_programme
    ON public.joining_instructions(programme_id);

CREATE INDEX IF NOT EXISTS idx_joining_instructions_status
    ON public.joining_instructions(status);

-- ------------------------------------------------------------
-- 11. Updated-at triggers
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_applicants_updated_at
ON public.applicants;

CREATE TRIGGER trg_applicants_updated_at
BEFORE UPDATE ON public.applicants
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_applications_updated_at
ON public.applications;

CREATE TRIGGER trg_applications_updated_at
BEFORE UPDATE ON public.applications
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_application_choices_updated_at
ON public.application_choices;

CREATE TRIGGER trg_application_choices_updated_at
BEFORE UPDATE ON public.application_choices
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_academic_qualifications_updated_at
ON public.academic_qualifications;

CREATE TRIGGER trg_academic_qualifications_updated_at
BEFORE UPDATE ON public.academic_qualifications
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_application_documents_updated_at
ON public.application_documents;

CREATE TRIGGER trg_application_documents_updated_at
BEFORE UPDATE ON public.application_documents
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_admission_decisions_updated_at
ON public.admission_decisions;

CREATE TRIGGER trg_admission_decisions_updated_at
BEFORE UPDATE ON public.admission_decisions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_admission_offers_updated_at
ON public.admission_offers;

CREATE TRIGGER trg_admission_offers_updated_at
BEFORE UPDATE ON public.admission_offers
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_admission_acceptances_updated_at
ON public.admission_acceptances;

CREATE TRIGGER trg_admission_acceptances_updated_at
BEFORE UPDATE ON public.admission_acceptances
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_joining_instructions_updated_at
ON public.joining_instructions;

CREATE TRIGGER trg_joining_instructions_updated_at
BEFORE UPDATE ON public.joining_instructions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- ------------------------------------------------------------
-- 12. Row Level Security
-- ------------------------------------------------------------

ALTER TABLE public.applicants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.application_choices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.academic_qualifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.application_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admission_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admission_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admission_acceptances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.joining_instructions ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------
-- 13. Documentation
-- ------------------------------------------------------------

COMMENT ON TABLE public.applicants IS
'Applicant master records for the IDMC admissions process.';

COMMENT ON TABLE public.applications IS
'Online admission applications and their complete lifecycle.';

COMMENT ON TABLE public.application_choices IS
'Programme choices submitted by an applicant within an application.';

COMMENT ON TABLE public.academic_qualifications IS
'Academic qualifications submitted by applicants.';

COMMENT ON TABLE public.application_documents IS
'Documents uploaded as part of an application and their verification status.';

COMMENT ON TABLE public.admission_decisions IS
'Formal academic/admission selection decisions.';

COMMENT ON TABLE public.admission_offers IS
'Admission offers issued to successful applicants.';

COMMENT ON TABLE public.admission_acceptances IS
'Applicant acceptance or decline of an admission offer.';

COMMENT ON TABLE public.joining_instructions IS
'Published joining instructions by academic year and programme.';

