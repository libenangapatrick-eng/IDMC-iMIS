-- ============================================================
-- IDMC iMIS
-- Migration 006
-- Student Core, Lifecycle & Applicant-to-Student Conversion
-- Version: 202609150002
-- ============================================================

-- ============================================================
-- 1. STUDENTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.students (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_number varchar(50) NOT NULL,
    applicant_id uuid NOT NULL,
    source_application_id uuid NOT NULL,
    admission_offer_id uuid NOT NULL,

    programme_id uuid NOT NULL,
    programme_version_id uuid,

    student_status varchar(40) NOT NULL DEFAULT 'PENDING_ACTIVATION',

    admission_date date,
    enrollment_date date,
    expected_completion_date date,
    actual_completion_date date,

    activated_at timestamptz,
    suspended_at timestamptz,
    withdrawn_at timestamptz,
    graduated_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_students_student_number
        UNIQUE (student_number),

    CONSTRAINT uq_students_source_application
        UNIQUE (source_application_id),

    CONSTRAINT uq_students_admission_offer
        UNIQUE (admission_offer_id),

    CONSTRAINT chk_students_status
        CHECK (
            student_status IN (
                'PENDING_ACTIVATION',
                'ACTIVE',
                'DEFERRED',
                'SUSPENDED',
                'WITHDRAWN',
                'COMPLETED',
                'GRADUATED',
                'EXPELLED',
                'DECEASED',
                'INACTIVE'
            )
        ),

    CONSTRAINT fk_students_applicant
        FOREIGN KEY (applicant_id)
        REFERENCES public.applicants(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_students_application
        FOREIGN KEY (source_application_id)
        REFERENCES public.applications(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_students_admission_offer
        FOREIGN KEY (admission_offer_id)
        REFERENCES public.admission_offers(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_students_programme
        FOREIGN KEY (programme_id)
        REFERENCES public.programmes(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_students_programme_version
        FOREIGN KEY (programme_version_id)
        REFERENCES public.programme_versions(id)
        ON DELETE RESTRICT
);


-- ============================================================
-- 2. STUDENT PROFILES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_profiles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL,

    first_name varchar(100),
    middle_name varchar(100),
    last_name varchar(100),

    preferred_name varchar(150),

    date_of_birth date,
    gender varchar(30),
    nationality varchar(100),

    national_id_number varchar(100),
    passport_number varchar(100),

    phone varchar(50),
    alternate_phone varchar(50),
    email varchar(255),

    profile_photo_url text,

    disability_status varchar(100),
    blood_group varchar(20),

    marital_status varchar(30),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_student_profiles_student
        UNIQUE (student_id),

    CONSTRAINT fk_student_profiles_student
        FOREIGN KEY (student_id)
        REFERENCES public.students(id)
        ON DELETE CASCADE,

    CONSTRAINT chk_student_profiles_gender
        CHECK (
            gender IS NULL
            OR gender IN (
                'MALE',
                'FEMALE',
                'OTHER',
                'PREFER_NOT_TO_SAY'
            )
        ),

    CONSTRAINT chk_student_profiles_marital_status
        CHECK (
            marital_status IS NULL
            OR marital_status IN (
                'SINGLE',
                'MARRIED',
                'DIVORCED',
                'WIDOWED',
                'SEPARATED',
                'PREFER_NOT_TO_SAY'
            )
        )
);


-- ============================================================
-- 3. GUARDIANS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.guardians (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL,

    full_name varchar(200) NOT NULL,
    relationship varchar(100) NOT NULL,

    phone varchar(50),
    alternate_phone varchar(50),
    email varchar(255),

    occupation varchar(150),
    organisation varchar(200),

    address_line_1 varchar(255),
    address_line_2 varchar(255),
    city varchar(100),
    district varchar(100),
    region varchar(100),
    country varchar(100) DEFAULT 'Tanzania',

    is_primary boolean NOT NULL DEFAULT false,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_guardians_student
        FOREIGN KEY (student_id)
        REFERENCES public.students(id)
        ON DELETE CASCADE
);


-- ============================================================
-- 4. EMERGENCY CONTACTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.emergency_contacts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL,

    full_name varchar(200) NOT NULL,
    relationship varchar(100) NOT NULL,

    phone varchar(50) NOT NULL,
    alternate_phone varchar(50),
    email varchar(255),

    address_line_1 varchar(255),
    city varchar(100),
    district varchar(100),
    region varchar(100),
    country varchar(100) DEFAULT 'Tanzania',

    is_primary boolean NOT NULL DEFAULT false,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_emergency_contacts_student
        FOREIGN KEY (student_id)
        REFERENCES public.students(id)
        ON DELETE CASCADE
);


-- ============================================================
-- 5. STUDENT DOCUMENTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL,

    document_type varchar(100) NOT NULL,
    document_number varchar(150),

    file_url text,
    file_name varchar(255),
    mime_type varchar(100),

    verification_status varchar(40) NOT NULL DEFAULT 'PENDING',

    verified_by uuid,
    verified_at timestamptz,
    verification_notes text,

    uploaded_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_student_documents_student
        FOREIGN KEY (student_id)
        REFERENCES public.students(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_student_documents_verified_by
        FOREIGN KEY (verified_by)
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    CONSTRAINT chk_student_document_verification
        CHECK (
            verification_status IN (
                'PENDING',
                'VERIFIED',
                'REJECTED',
                'EXPIRED'
            )
        )
);


-- ============================================================
-- 6. STUDENT STATUS HISTORY
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_status_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL,

    old_status varchar(40),
    new_status varchar(40) NOT NULL,

    reason text,

    changed_by uuid,

    changed_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_student_status_history_student
        FOREIGN KEY (student_id)
        REFERENCES public.students(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_student_status_history_changed_by
        FOREIGN KEY (changed_by)
        REFERENCES public.users(id)
        ON DELETE SET NULL
);


-- ============================================================
-- 7. STUDENT PROGRAMME HISTORY
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_programme_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL,

    programme_id uuid NOT NULL,
    programme_version_id uuid,

    change_type varchar(40) NOT NULL DEFAULT 'INITIAL',

    effective_from date NOT NULL DEFAULT CURRENT_DATE,
    effective_to date,

    reason text,

    approved_by uuid,
    approved_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_student_programme_history_student
        FOREIGN KEY (student_id)
        REFERENCES public.students(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_student_programme_history_programme
        FOREIGN KEY (programme_id)
        REFERENCES public.programmes(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_student_programme_history_programme_version
        FOREIGN KEY (programme_version_id)
        REFERENCES public.programme_versions(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_student_programme_history_approved_by
        FOREIGN KEY (approved_by)
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    CONSTRAINT chk_student_programme_change_type
        CHECK (
            change_type IN (
                'INITIAL',
                'TRANSFER',
                'PROGRAMME_CHANGE',
                'RE_ADMISSION',
                'READMISSION'
            )
        ),

    CONSTRAINT chk_student_programme_dates
        CHECK (
            effective_to IS NULL
            OR effective_to >= effective_from
        )
);


-- ============================================================
-- 8. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_students_applicant
ON public.students(applicant_id);

CREATE INDEX IF NOT EXISTS idx_students_application
ON public.students(source_application_id);

CREATE INDEX IF NOT EXISTS idx_students_offer
ON public.students(admission_offer_id);

CREATE INDEX IF NOT EXISTS idx_students_programme
ON public.students(programme_id);

CREATE INDEX IF NOT EXISTS idx_students_programme_version
ON public.students(programme_version_id);

CREATE INDEX IF NOT EXISTS idx_students_status
ON public.students(student_status);

CREATE INDEX IF NOT EXISTS idx_students_status_programme
ON public.students(student_status, programme_id);

CREATE INDEX IF NOT EXISTS idx_student_profiles_email
ON public.student_profiles(email);

CREATE INDEX IF NOT EXISTS idx_student_profiles_phone
ON public.student_profiles(phone);

CREATE INDEX IF NOT EXISTS idx_student_profiles_national_id
ON public.student_profiles(national_id_number);

CREATE INDEX IF NOT EXISTS idx_guardians_student
ON public.guardians(student_id);

CREATE INDEX IF NOT EXISTS idx_guardians_primary
ON public.guardians(student_id, is_primary);

CREATE INDEX IF NOT EXISTS idx_emergency_contacts_student
ON public.emergency_contacts(student_id);

CREATE INDEX IF NOT EXISTS idx_emergency_contacts_primary
ON public.emergency_contacts(student_id, is_primary);

CREATE INDEX IF NOT EXISTS idx_student_documents_student
ON public.student_documents(student_id);

CREATE INDEX IF NOT EXISTS idx_student_documents_status
ON public.student_documents(verification_status);

CREATE INDEX IF NOT EXISTS idx_student_status_history_student
ON public.student_status_history(student_id);

CREATE INDEX IF NOT EXISTS idx_student_status_history_changed_at
ON public.student_status_history(changed_at);

CREATE INDEX IF NOT EXISTS idx_student_programme_history_student
ON public.student_programme_history(student_id);

CREATE INDEX IF NOT EXISTS idx_student_programme_history_programme
ON public.student_programme_history(programme_id);

CREATE INDEX IF NOT EXISTS idx_student_programme_history_dates
ON public.student_programme_history(effective_from, effective_to);


-- ============================================================
-- 9. UPDATED_AT TRIGGERS
-- ============================================================

DROP TRIGGER IF EXISTS trg_students_updated_at
ON public.students;

CREATE TRIGGER trg_students_updated_at
BEFORE UPDATE ON public.students
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_student_profiles_updated_at
ON public.student_profiles;

CREATE TRIGGER trg_student_profiles_updated_at
BEFORE UPDATE ON public.student_profiles
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_guardians_updated_at
ON public.guardians;

CREATE TRIGGER trg_guardians_updated_at
BEFORE UPDATE ON public.guardians
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_emergency_contacts_updated_at
ON public.emergency_contacts;

CREATE TRIGGER trg_emergency_contacts_updated_at
BEFORE UPDATE ON public.emergency_contacts
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_student_documents_updated_at
ON public.student_documents;

CREATE TRIGGER trg_student_documents_updated_at
BEFORE UPDATE ON public.student_documents
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_student_programme_history_updated_at
ON public.student_programme_history;

CREATE TRIGGER trg_student_programme_history_updated_at
BEFORE UPDATE ON public.student_programme_history
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 10. STUDENT STATUS VALIDATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_student_status_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN

    -- New students must start from PENDING_ACTIVATION
    IF TG_OP = 'INSERT'
       AND NEW.student_status <> 'PENDING_ACTIVATION' THEN

        RAISE EXCEPTION
            'A newly created student must start with PENDING_ACTIVATION';
    END IF;


    -- No status change
    IF TG_OP = 'UPDATE'
       AND OLD.student_status = NEW.student_status THEN

        RETURN NEW;
    END IF;


    -- Graduated students cannot become active again
    IF OLD.student_status = 'GRADUATED'
       AND NEW.student_status <> 'GRADUATED' THEN

        RAISE EXCEPTION
            'A GRADUATED student cannot return to another lifecycle state';
    END IF;


    -- Completed students cannot return to active
    IF OLD.student_status = 'COMPLETED'
       AND NEW.student_status IN (
           'ACTIVE',
           'PENDING_ACTIVATION',
           'DEFERRED'
       ) THEN

        RAISE EXCEPTION
            'A COMPLETED student cannot return to an active lifecycle state';
    END IF;


    -- Expelled students cannot return
    IF OLD.student_status = 'EXPELLED'
       AND NEW.student_status <> 'EXPELLED' THEN

        RAISE EXCEPTION
            'An EXPELLED student cannot return to another lifecycle state';
    END IF;


    -- Deceased students cannot return
    IF OLD.student_status = 'DECEASED'
       AND NEW.student_status <> 'DECEASED' THEN

        RAISE EXCEPTION
            'A DECEASED student cannot return to another lifecycle state';
    END IF;


    -- Set lifecycle timestamps
    IF NEW.student_status = 'ACTIVE'
       AND OLD.student_status <> 'ACTIVE'
       AND NEW.activated_at IS NULL THEN

        NEW.activated_at := now();
    END IF;


    IF NEW.student_status = 'SUSPENDED'
       AND OLD.student_status <> 'SUSPENDED'
       AND NEW.suspended_at IS NULL THEN

        NEW.suspended_at := now();
    END IF;


    IF NEW.student_status = 'WITHDRAWN'
       AND OLD.student_status <> 'WITHDRAWN'
       AND NEW.withdrawn_at IS NULL THEN

        NEW.withdrawn_at := now();
    END IF;


    IF NEW.student_status = 'GRADUATED'
       AND OLD.student_status <> 'GRADUATED'
       AND NEW.graduated_at IS NULL THEN

        NEW.graduated_at := now();
    END IF;


    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_student_status
ON public.students;

CREATE TRIGGER trg_validate_student_status
BEFORE INSERT OR UPDATE OF student_status
ON public.students
FOR EACH ROW
EXECUTE FUNCTION public.validate_student_status_transition();


-- ============================================================
-- 11. AUTOMATIC STUDENT STATUS HISTORY
-- ============================================================

CREATE OR REPLACE FUNCTION public.record_student_status_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN

        INSERT INTO public.student_status_history (
            student_id,
            old_status,
            new_status,
            reason,
            changed_by
        )
        VALUES (
            NEW.id,
            NULL,
            NEW.student_status,
            'Student record created',
            NULL
        );

    ELSIF OLD.student_status IS DISTINCT FROM NEW.student_status THEN

        INSERT INTO public.student_status_history (
            student_id,
            old_status,
            new_status,
            reason,
            changed_by
        )
        VALUES (
            NEW.id,
            OLD.student_status,
            NEW.student_status,
            NULL,
            NULL
        );

    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_record_student_status_history
ON public.students;

CREATE TRIGGER trg_record_student_status_history
AFTER INSERT OR UPDATE OF student_status
ON public.students
FOR EACH ROW
EXECUTE FUNCTION public.record_student_status_history();


-- ============================================================
-- 12. SINGLE PRIMARY GUARDIAN
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_primary_guardian_per_student
ON public.guardians(student_id)
WHERE is_primary = true;


-- ============================================================
-- 13. SINGLE PRIMARY EMERGENCY CONTACT
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_primary_emergency_contact_per_student
ON public.emergency_contacts(student_id)
WHERE is_primary = true;


-- ============================================================
-- 14. ONLY ONE ACTIVE PROGRAMME AT A TIME
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_student_active_programme
ON public.student_programme_history(student_id)
WHERE effective_to IS NULL;


-- ============================================================
-- 15. APPLICANT -> STUDENT CONVERSION FUNCTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.convert_accepted_application_to_student(
    p_application_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE

    v_application public.applications%ROWTYPE;
    v_offer public.admission_offers%ROWTYPE;
    v_acceptance public.admission_acceptances%ROWTYPE;
    v_choice public.application_choices%ROWTYPE;

    v_student_id uuid;
    v_student_number varchar(50);

BEGIN

    -- --------------------------------------------------------
    -- Lock application row
    -- This prevents two conversion processes from
    -- converting the same application simultaneously.
    -- --------------------------------------------------------

    SELECT *
    INTO v_application
    FROM public.applications
    WHERE id = p_application_id
    FOR UPDATE;


    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Application % does not exist',
            p_application_id;
    END IF;


    -- --------------------------------------------------------
    -- Already converted?
    -- --------------------------------------------------------

    SELECT id
    INTO v_student_id
    FROM public.students
    WHERE source_application_id = p_application_id;


    IF FOUND THEN

        RETURN v_student_id;

    END IF;


    -- --------------------------------------------------------
    -- Application must be ACCEPTED
    -- --------------------------------------------------------

    IF v_application.application_status <> 'ACCEPTED' THEN

        RAISE EXCEPTION
            'Application % cannot be converted because its status is %; expected ACCEPTED',
            p_application_id,
            v_application.application_status;

    END IF;


    -- --------------------------------------------------------
    -- Get accepted admission offer
    -- --------------------------------------------------------

    SELECT ao.*
    INTO v_offer
    FROM public.admission_offers ao
    INNER JOIN public.admission_acceptances aa
        ON aa.admission_offer_id = ao.id
    WHERE ao.application_id = p_application_id
      AND aa.acceptance_status = 'ACCEPTED'
    ORDER BY aa.accepted_at DESC NULLS LAST
    LIMIT 1
    FOR UPDATE OF ao;


    IF NOT FOUND THEN

        RAISE EXCEPTION
            'Application % has no accepted admission offer',
            p_application_id;

    END IF;


    -- --------------------------------------------------------
    -- Offer must still be valid
    -- --------------------------------------------------------

    IF v_offer.offer_status <> 'ACCEPTED' THEN

        RAISE EXCEPTION
            'Admission offer % is not in ACCEPTED status',
            v_offer.id;

    END IF;


    IF v_offer.expiry_date < CURRENT_DATE THEN

        RAISE EXCEPTION
            'Admission offer % has expired',
            v_offer.id;

    END IF;


    -- --------------------------------------------------------
    -- Get selected application choice
    -- --------------------------------------------------------

    SELECT *
    INTO v_choice
    FROM public.application_choices
    WHERE id = v_offer.application_choice_id
      AND application_id = p_application_id
    FOR UPDATE;


    IF NOT FOUND THEN

        RAISE EXCEPTION
            'Admission offer % does not reference a valid application choice',
            v_offer.id;

    END IF;


    -- --------------------------------------------------------
    -- Generate safe student number
    --
    -- Advisory transaction lock serializes number generation.
    -- --------------------------------------------------------

    PERFORM pg_advisory_xact_lock(
        hashtextextended('IDMC_STUDENT_NUMBER', 0)
    );


    SELECT
        'IDMC/' ||
        EXTRACT(YEAR FROM CURRENT_DATE)::integer::text ||
        '/' ||
        LPAD(
            (
                COALESCE(
                    MAX(
                        NULLIF(
                            substring(student_number from '[0-9]+$'),
                            ''
                        )::bigint
                    ),
                    0
                ) + 1
            )::text,
            5,
            '0'
        )
    INTO v_student_number
    FROM public.students
    WHERE student_number LIKE
        'IDMC/' || EXTRACT(YEAR FROM CURRENT_DATE)::integer::text || '/%';


    -- --------------------------------------------------------
    -- Create student
    -- --------------------------------------------------------

    INSERT INTO public.students (
        student_number,
        applicant_id,
        source_application_id,
        admission_offer_id,
        programme_id,
        programme_version_id,
        student_status,
        admission_date,
        enrollment_date
    )
    VALUES (
        v_student_number,
        v_application.applicant_id,
        p_application_id,
        v_offer.id,
        v_choice.programme_id,
        NULL,
        'PENDING_ACTIVATION',
        CURRENT_DATE,
        NULL
    )
    RETURNING id
    INTO v_student_id;


    -- --------------------------------------------------------
    -- Create initial programme history
    -- --------------------------------------------------------

    INSERT INTO public.student_programme_history (
        student_id,
        programme_id,
        programme_version_id,
        change_type,
        effective_from,
        reason
    )
    VALUES (
        v_student_id,
        v_choice.programme_id,
        NULL,
        'INITIAL',
        CURRENT_DATE,
        'Initial programme assigned during admission conversion'
    );


    -- --------------------------------------------------------
    -- Move application to CONVERTED_TO_STUDENT
    -- --------------------------------------------------------

    UPDATE public.applications
    SET application_status = 'CONVERTED_TO_STUDENT',
        updated_at = now()
    WHERE id = p_application_id;


    RETURN v_student_id;

END;
$$;


-- ============================================================
-- 16. FUNCTION ACCESS CONTROL
-- ============================================================

REVOKE EXECUTE
ON FUNCTION public.convert_accepted_application_to_student(uuid)
FROM PUBLIC;

REVOKE EXECUTE
ON FUNCTION public.convert_accepted_application_to_student(uuid)
FROM anon;

REVOKE EXECUTE
ON FUNCTION public.convert_accepted_application_to_student(uuid)
FROM authenticated;

GRANT EXECUTE
ON FUNCTION public.convert_accepted_application_to_student(uuid)
TO service_role;


-- ============================================================
-- 17. RLS
-- ============================================================

ALTER TABLE public.students
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_profiles
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.guardians
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.emergency_contacts
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_documents
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_status_history
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_programme_history
ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 18. COMMENTS
-- ============================================================

COMMENT ON TABLE public.students IS
'Core student master record created only after successful admission conversion.';

COMMENT ON COLUMN public.students.student_status IS
'Student lifecycle state: PENDING_ACTIVATION, ACTIVE, DEFERRED, SUSPENDED, WITHDRAWN, COMPLETED, GRADUATED, EXPELLED, DECEASED or INACTIVE.';

COMMENT ON COLUMN public.students.source_application_id IS
'Original admission application. UNIQUE prevents duplicate applicant-to-student conversion.';

COMMENT ON TABLE public.student_status_history IS
'Immutable-style lifecycle history of student status changes.';

COMMENT ON TABLE public.student_programme_history IS
'Historical record of programme assignments and programme changes.';

COMMENT ON FUNCTION public.convert_accepted_application_to_student(uuid) IS
'Atomically converts one accepted admission application into exactly one student record.';
