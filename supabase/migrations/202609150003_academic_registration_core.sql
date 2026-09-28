-- ============================================================
-- IDMC iMIS
-- Migration 007
-- Academic Registration Core
-- ============================================================

BEGIN;

-- ============================================================
-- 1. COURSE OFFERINGS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.course_offerings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    academic_year_id uuid NOT NULL
        REFERENCES public.academic_years(id)
        ON DELETE RESTRICT,

    semester_id uuid NOT NULL
        REFERENCES public.semesters(id)
        ON DELETE RESTRICT,

    programme_id uuid NOT NULL
        REFERENCES public.programmes(id)
        ON DELETE RESTRICT,

    programme_version_id uuid
        REFERENCES public.programme_versions(id)
        ON DELETE RESTRICT,

    course_id uuid NOT NULL
        REFERENCES public.courses(id)
        ON DELETE RESTRICT,

    offering_code varchar(80) NOT NULL,

    section_name varchar(100),

    capacity integer NOT NULL DEFAULT 0,

    minimum_students integer NOT NULL DEFAULT 0,

    delivery_mode varchar(30) NOT NULL DEFAULT 'ON_CAMPUS',

    status varchar(30) NOT NULL DEFAULT 'DRAFT',

    registration_open_at timestamptz,

    registration_close_at timestamptz,

    created_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    updated_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_course_offering_code
        UNIQUE (offering_code),

    CONSTRAINT chk_course_offering_capacity
        CHECK (capacity >= 0),

    CONSTRAINT chk_course_offering_minimum_students
        CHECK (minimum_students >= 0),

    CONSTRAINT chk_course_offering_dates
        CHECK (
            registration_close_at IS NULL
            OR registration_open_at IS NULL
            OR registration_close_at >= registration_open_at
        ),

    CONSTRAINT chk_course_offering_delivery_mode
        CHECK (
            delivery_mode IN (
                'ON_CAMPUS',
                'ONLINE',
                'HYBRID',
                'DISTANCE',
                'FIELD',
                'CLINICAL'
            )
        ),

    CONSTRAINT chk_course_offering_status
        CHECK (
            status IN (
                'DRAFT',
                'OPEN',
                'CLOSED',
                'SUSPENDED',
                'COMPLETED',
                'CANCELLED'
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_course_offerings_year
    ON public.course_offerings(academic_year_id);

CREATE INDEX IF NOT EXISTS idx_course_offerings_semester
    ON public.course_offerings(semester_id);

CREATE INDEX IF NOT EXISTS idx_course_offerings_programme
    ON public.course_offerings(programme_id);

CREATE INDEX IF NOT EXISTS idx_course_offerings_programme_version
    ON public.course_offerings(programme_version_id);

CREATE INDEX IF NOT EXISTS idx_course_offerings_course
    ON public.course_offerings(course_id);

CREATE INDEX IF NOT EXISTS idx_course_offerings_status
    ON public.course_offerings(status);

CREATE UNIQUE INDEX IF NOT EXISTS uq_course_offering_course_semester
    ON public.course_offerings(
        academic_year_id,
        semester_id,
        programme_id,
        course_id,
        COALESCE(section_name, '')
    );


-- ============================================================
-- 2. STUDENT REGISTRATIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_registrations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL
        REFERENCES public.students(id)
        ON DELETE RESTRICT,

    academic_year_id uuid NOT NULL
        REFERENCES public.academic_years(id)
        ON DELETE RESTRICT,

    semester_id uuid NOT NULL
        REFERENCES public.semesters(id)
        ON DELETE RESTRICT,

    programme_id uuid NOT NULL
        REFERENCES public.programmes(id)
        ON DELETE RESTRICT,

    programme_version_id uuid
        REFERENCES public.programme_versions(id)
        ON DELETE RESTRICT,

    registration_number varchar(80) NOT NULL,

    registration_status varchar(40) NOT NULL DEFAULT 'DRAFT',

    academic_eligibility_status varchar(30) NOT NULL DEFAULT 'PENDING',

    finance_eligibility_status varchar(30) NOT NULL DEFAULT 'PENDING',

    document_eligibility_status varchar(30) NOT NULL DEFAULT 'PENDING',

    total_registered_credits numeric(8,2) NOT NULL DEFAULT 0,

    minimum_credits numeric(8,2) NOT NULL DEFAULT 0,

    maximum_credits numeric(8,2) NOT NULL DEFAULT 30,

    submitted_at timestamptz,

    approved_at timestamptz,

    approved_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    locked_at timestamptz,

    locked_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    rejection_reason text,

    notes text,

    created_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    updated_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_student_registration_number
        UNIQUE (registration_number),

    CONSTRAINT uq_student_year_semester
        UNIQUE (
            student_id,
            academic_year_id,
            semester_id
        ),

    CONSTRAINT chk_registration_credits
        CHECK (
            minimum_credits >= 0
            AND maximum_credits >= minimum_credits
            AND total_registered_credits >= 0
        ),

    CONSTRAINT chk_registration_status
        CHECK (
            registration_status IN (
                'DRAFT',
                'ELIGIBILITY_PENDING',
                'ELIGIBLE',
                'SUBMITTED',
                'PENDING_APPROVAL',
                'APPROVED',
                'REGISTERED',
                'REJECTED',
                'CANCELLED',
                'LOCKED'
            )
        ),

    CONSTRAINT chk_academic_eligibility
        CHECK (
            academic_eligibility_status IN (
                'PENDING',
                'ELIGIBLE',
                'NOT_ELIGIBLE',
                'OVERRIDE'
            )
        ),

    CONSTRAINT chk_finance_eligibility
        CHECK (
            finance_eligibility_status IN (
                'PENDING',
                'CLEARED',
                'BLOCKED',
                'OVERRIDE'
            )
        ),

    CONSTRAINT chk_document_eligibility
        CHECK (
            document_eligibility_status IN (
                'PENDING',
                'CLEARED',
                'INCOMPLETE',
                'OVERRIDE'
            )
        )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_student_registration
    ON public.student_registrations(
        student_id,
        academic_year_id,
        semester_id
    )
    WHERE registration_status NOT IN ('CANCELLED');


CREATE INDEX IF NOT EXISTS idx_student_registrations_student
    ON public.student_registrations(student_id);

CREATE INDEX IF NOT EXISTS idx_student_registrations_year
    ON public.student_registrations(academic_year_id);

CREATE INDEX IF NOT EXISTS idx_student_registrations_semester
    ON public.student_registrations(semester_id);

CREATE INDEX IF NOT EXISTS idx_student_registrations_programme
    ON public.student_registrations(programme_id);

CREATE INDEX IF NOT EXISTS idx_student_registrations_status
    ON public.student_registrations(registration_status);


-- ============================================================
-- 3. COURSE REGISTRATIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.course_registrations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_registration_id uuid NOT NULL
        REFERENCES public.student_registrations(id)
        ON DELETE CASCADE,

    student_id uuid NOT NULL
        REFERENCES public.students(id)
        ON DELETE RESTRICT,

    course_id uuid NOT NULL
        REFERENCES public.courses(id)
        ON DELETE RESTRICT,

    course_offering_id uuid
        REFERENCES public.course_offerings(id)
        ON DELETE RESTRICT,

    registration_type varchar(30) NOT NULL DEFAULT 'NORMAL',

    registration_status varchar(30) NOT NULL DEFAULT 'SELECTED',

    credits numeric(8,2) NOT NULL,

    attempt_number integer NOT NULL DEFAULT 1,

    is_core boolean NOT NULL DEFAULT false,

    is_elective boolean NOT NULL DEFAULT false,

    prerequisite_status varchar(30) NOT NULL DEFAULT 'PENDING',

    eligibility_status varchar(30) NOT NULL DEFAULT 'PENDING',

    selected_at timestamptz NOT NULL DEFAULT now(),

    approved_at timestamptz,

    approved_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    dropped_at timestamptz,

    drop_reason text,

    notes text,

    created_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    updated_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_course_registration_type
        CHECK (
            registration_type IN (
                'NORMAL',
                'RETAKE',
                'REPEAT',
                'AUDIT',
                'CARRY_FORWARD',
                'SPECIAL'
            )
        ),

    CONSTRAINT chk_course_registration_status
        CHECK (
            registration_status IN (
                'SELECTED',
                'PENDING_APPROVAL',
                'APPROVED',
                'REGISTERED',
                'DROPPED',
                'REJECTED',
                'CANCELLED'
            )
        ),

    CONSTRAINT chk_course_registration_credits
        CHECK (credits > 0),

    CONSTRAINT chk_attempt_number
        CHECK (attempt_number >= 1),

    CONSTRAINT chk_prerequisite_status
        CHECK (
            prerequisite_status IN (
                'PENDING',
                'PASSED',
                'FAILED',
                'NOT_REQUIRED',
                'OVERRIDE'
            )
        ),

    CONSTRAINT chk_course_eligibility
        CHECK (
            eligibility_status IN (
                'PENDING',
                'ELIGIBLE',
                'NOT_ELIGIBLE',
                'OVERRIDE'
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_course_reg_student_registration
    ON public.course_registrations(student_registration_id);

CREATE INDEX IF NOT EXISTS idx_course_reg_student
    ON public.course_registrations(student_id);

CREATE INDEX IF NOT EXISTS idx_course_reg_course
    ON public.course_registrations(course_id);

CREATE INDEX IF NOT EXISTS idx_course_reg_offering
    ON public.course_registrations(course_offering_id);

CREATE INDEX IF NOT EXISTS idx_course_reg_status
    ON public.course_registrations(registration_status);

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_course_registration
    ON public.course_registrations(
        student_registration_id,
        course_id
    )
    WHERE registration_status NOT IN (
        'DROPPED',
        'REJECTED',
        'CANCELLED'
    );


-- ============================================================
-- 4. ADD / DROP REQUESTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.course_add_drop_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_registration_id uuid NOT NULL
        REFERENCES public.student_registrations(id)
        ON DELETE RESTRICT,

    student_id uuid NOT NULL
        REFERENCES public.students(id)
        ON DELETE RESTRICT,

    course_id uuid NOT NULL
        REFERENCES public.courses(id)
        ON DELETE RESTRICT,

    course_offering_id uuid
        REFERENCES public.course_offerings(id)
        ON DELETE RESTRICT,

    request_type varchar(20) NOT NULL,

    request_status varchar(30) NOT NULL DEFAULT 'PENDING',

    reason text,

    decision_reason text,

    requested_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    reviewed_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    requested_at timestamptz NOT NULL DEFAULT now(),

    reviewed_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_add_drop_type
        CHECK (
            request_type IN (
                'ADD',
                'DROP'
            )
        ),

    CONSTRAINT chk_add_drop_status
        CHECK (
            request_status IN (
                'PENDING',
                'APPROVED',
                'REJECTED',
                'CANCELLED'
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_add_drop_student_registration
    ON public.course_add_drop_requests(student_registration_id);

CREATE INDEX IF NOT EXISTS idx_add_drop_student
    ON public.course_add_drop_requests(student_id);

CREATE INDEX IF NOT EXISTS idx_add_drop_course
    ON public.course_add_drop_requests(course_id);

CREATE INDEX IF NOT EXISTS idx_add_drop_status
    ON public.course_add_drop_requests(request_status);


-- ============================================================
-- 5. REGISTRATION APPROVALS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.registration_approvals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_registration_id uuid NOT NULL
        REFERENCES public.student_registrations(id)
        ON DELETE CASCADE,

    approval_level integer NOT NULL,

    approval_role varchar(80) NOT NULL,

    approval_status varchar(30) NOT NULL DEFAULT 'PENDING',

    comments text,

    approved_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    approved_at timestamptz,

    rejected_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_approval_level
        CHECK (approval_level > 0),

    CONSTRAINT chk_registration_approval_status
        CHECK (
            approval_status IN (
                'PENDING',
                'APPROVED',
                'REJECTED',
                'SKIPPED'
            )
        ),

    CONSTRAINT uq_registration_approval_level
        UNIQUE (
            student_registration_id,
            approval_level
        )
);

CREATE INDEX IF NOT EXISTS idx_registration_approvals_registration
    ON public.registration_approvals(student_registration_id);

CREATE INDEX IF NOT EXISTS idx_registration_approvals_status
    ON public.registration_approvals(approval_status);


-- ============================================================
-- 6. REGISTRATION STATUS TRANSITION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_registration_status_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN

    IF TG_OP = 'UPDATE'
       AND OLD.registration_status <> NEW.registration_status
    THEN

        IF OLD.registration_status = 'LOCKED' THEN
            RAISE EXCEPTION
                'Locked registration cannot change status';
        END IF;

        IF OLD.registration_status = 'CANCELLED'
           AND NEW.registration_status <> 'CANCELLED'
        THEN
            RAISE EXCEPTION
                'Cancelled registration cannot be reopened';
        END IF;

        IF OLD.registration_status = 'REGISTERED'
           AND NEW.registration_status NOT IN (
               'LOCKED',
               'CANCELLED'
           )
        THEN
            RAISE EXCEPTION
                'Registered registration can only be locked or cancelled';
        END IF;

        IF OLD.registration_status = 'APPROVED'
           AND NEW.registration_status NOT IN (
               'REGISTERED',
               'CANCELLED'
           )
        THEN
            RAISE EXCEPTION
                'Approved registration must proceed to REGISTERED or CANCELLED';
        END IF;

    END IF;

    IF NEW.registration_status IN (
        'SUBMITTED',
        'PENDING_APPROVAL'
    )
    AND NEW.submitted_at IS NULL
    THEN
        NEW.submitted_at := now();
    END IF;

    IF NEW.registration_status = 'APPROVED'
       AND OLD.registration_status IS DISTINCT FROM 'APPROVED'
    THEN
        NEW.approved_at := COALESCE(NEW.approved_at, now());
    END IF;

    IF NEW.registration_status = 'LOCKED'
       AND OLD.registration_status IS DISTINCT FROM 'LOCKED'
    THEN
        NEW.locked_at := COALESCE(NEW.locked_at, now());
    END IF;

    RETURN NEW;
END;
$function$;


DROP TRIGGER IF EXISTS trg_validate_registration_status
    ON public.student_registrations;

CREATE TRIGGER trg_validate_registration_status
BEFORE INSERT OR UPDATE OF registration_status
ON public.student_registrations
FOR EACH ROW
EXECUTE FUNCTION public.validate_registration_status_transition();


-- ============================================================
-- 7. PREVENT COURSE CHANGES ON LOCKED REGISTRATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_locked_course_registration_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
    v_status varchar(40);
BEGIN

    SELECT registration_status
    INTO v_status
    FROM public.student_registrations
    WHERE id = COALESCE(
        NEW.student_registration_id,
        OLD.student_registration_id
    );

    IF v_status IN ('LOCKED')
    THEN
        RAISE EXCEPTION
            'Cannot modify course registration for a locked student registration';
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$function$;


DROP TRIGGER IF EXISTS trg_prevent_locked_course_registration
    ON public.course_registrations;

CREATE TRIGGER trg_prevent_locked_course_registration
BEFORE INSERT OR UPDATE OR DELETE
ON public.course_registrations
FOR EACH ROW
EXECUTE FUNCTION public.prevent_locked_course_registration_change();


-- ============================================================
-- 8. PREVENT ADD/DROP AFTER LOCK
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_add_drop_after_lock()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
    v_status varchar(40);
BEGIN

    SELECT registration_status
    INTO v_status
    FROM public.student_registrations
    WHERE id = COALESCE(
        NEW.student_registration_id,
        OLD.student_registration_id
    );

    IF v_status IN (
        'LOCKED',
        'CANCELLED'
    )
    THEN
        RAISE EXCEPTION
            'Add/Drop requests are not allowed for locked or cancelled registration';
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$function$;


DROP TRIGGER IF EXISTS trg_prevent_add_drop_after_lock
    ON public.course_add_drop_requests;

CREATE TRIGGER trg_prevent_add_drop_after_lock
BEFORE INSERT OR UPDATE OR DELETE
ON public.course_add_drop_requests
FOR EACH ROW
EXECUTE FUNCTION public.prevent_add_drop_after_lock();


-- ============================================================
-- 9. COURSE REGISTRATION VALIDATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_course_registration()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
    v_student_id uuid;
    v_programme_id uuid;
    v_registration_status varchar(40);
    v_course_status varchar(30);
    v_offering_status varchar(30);
BEGIN

    SELECT
        sr.student_id,
        sr.programme_id,
        sr.registration_status
    INTO
        v_student_id,
        v_programme_id,
        v_registration_status
    FROM public.student_registrations sr
    WHERE sr.id = NEW.student_registration_id;

    IF v_student_id IS NULL THEN
        RAISE EXCEPTION
            'Student registration does not exist';
    END IF;

    IF NEW.student_id <> v_student_id THEN
        RAISE EXCEPTION
            'Course registration student does not match student registration';
    END IF;

    IF v_registration_status IN (
        'LOCKED',
        'CANCELLED'
    )
    THEN
        RAISE EXCEPTION
            'Cannot add course to locked or cancelled registration';
    END IF;

    SELECT status
    INTO v_course_status
    FROM public.courses
    WHERE id = NEW.course_id;

    IF v_course_status IS NULL THEN
        RAISE EXCEPTION
            'Course does not exist';
    END IF;

    IF v_course_status <> 'ACTIVE' THEN
        RAISE EXCEPTION
            'Only ACTIVE courses can be registered';
    END IF;

    IF NEW.course_offering_id IS NOT NULL THEN

        SELECT status
        INTO v_offering_status
        FROM public.course_offerings
        WHERE id = NEW.course_offering_id
          AND course_id = NEW.course_id;

        IF v_offering_status IS NULL THEN
            RAISE EXCEPTION
                'Course offering does not match course';
        END IF;

        IF v_offering_status NOT IN ('OPEN', 'CLOSED') THEN
            RAISE EXCEPTION
                'Invalid course offering status for registration';
        END IF;

    END IF;

    RETURN NEW;
END;
$function$;


DROP TRIGGER IF EXISTS trg_validate_course_registration
    ON public.course_registrations;

CREATE TRIGGER trg_validate_course_registration
BEFORE INSERT OR UPDATE
ON public.course_registrations
FOR EACH ROW
EXECUTE FUNCTION public.validate_course_registration();


-- ============================================================
-- 10. UPDATE TOTAL REGISTERED CREDITS
-- ============================================================

CREATE OR REPLACE FUNCTION public.refresh_registration_credits()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
    v_registration_id uuid;
BEGIN

    v_registration_id :=
        COALESCE(
            NEW.student_registration_id,
            OLD.student_registration_id
        );

    UPDATE public.student_registrations sr
    SET total_registered_credits = COALESCE(
        (
            SELECT SUM(cr.credits)
            FROM public.course_registrations cr
            WHERE cr.student_registration_id = sr.id
              AND cr.registration_status NOT IN (
                  'DROPPED',
                  'REJECTED',
                  'CANCELLED'
              )
        ),
        0
    ),
    updated_at = now()
    WHERE sr.id = v_registration_id;

    RETURN COALESCE(NEW, OLD);
END;
$function$;


DROP TRIGGER IF EXISTS trg_refresh_registration_credits
    ON public.course_registrations;

CREATE TRIGGER trg_refresh_registration_credits
AFTER INSERT OR UPDATE OR DELETE
ON public.course_registrations
FOR EACH ROW
EXECUTE FUNCTION public.refresh_registration_credits();


-- ============================================================
-- 11. CREDIT LIMIT VALIDATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_registration_credit_limit()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
    v_total numeric(8,2);
    v_maximum numeric(8,2);
BEGIN

    SELECT maximum_credits
    INTO v_maximum
    FROM public.student_registrations
    WHERE id = NEW.student_registration_id;

    SELECT COALESCE(
        SUM(credits),
        0
    )
    INTO v_total
    FROM public.course_registrations
    WHERE student_registration_id = NEW.student_registration_id
      AND registration_status NOT IN (
          'DROPPED',
          'REJECTED',
          'CANCELLED'
      )
      AND id <> NEW.id;

    v_total := v_total + NEW.credits;

    IF v_total > v_maximum THEN
        RAISE EXCEPTION
            'Credit limit exceeded. Maximum allowed: %, attempted total: %',
            v_maximum,
            v_total;
    END IF;

    RETURN NEW;
END;
$function$;


DROP TRIGGER IF EXISTS trg_validate_registration_credit_limit
    ON public.course_registrations;

CREATE TRIGGER trg_validate_registration_credit_limit
BEFORE INSERT OR UPDATE OF credits, registration_status
ON public.course_registrations
FOR EACH ROW
WHEN (
    NEW.registration_status NOT IN (
        'DROPPED',
        'REJECTED',
        'CANCELLED'
    )
)
EXECUTE FUNCTION public.validate_registration_credit_limit();


-- ============================================================
-- 12. REGISTRATION ELIGIBILITY VALIDATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_student_registration()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
    v_student_status varchar(40);
    v_student_programme uuid;
BEGIN

    SELECT
        student_status,
        programme_id
    INTO
        v_student_status,
        v_student_programme
    FROM public.students
    WHERE id = NEW.student_id;

    IF v_student_status IS NULL THEN
        RAISE EXCEPTION
            'Student does not exist';
    END IF;

    IF v_student_status NOT IN (
        'ACTIVE',
        'PENDING_ACTIVATION',
        'DEFERRED'
    )
    THEN
        RAISE EXCEPTION
            'Student status % is not eligible for registration',
            v_student_status;
    END IF;

    IF v_student_programme IS NOT NULL
       AND NEW.programme_id <> v_student_programme
    THEN
        RAISE EXCEPTION
            'Registration programme does not match student programme';
    END IF;

    IF NEW.maximum_credits <= 0 THEN
        RAISE EXCEPTION
            'Maximum credits must be greater than zero';
    END IF;

    RETURN NEW;
END;
$function$;


DROP TRIGGER IF EXISTS trg_validate_student_registration
    ON public.student_registrations;

CREATE TRIGGER trg_validate_student_registration
BEFORE INSERT OR UPDATE
ON public.student_registrations
FOR EACH ROW
EXECUTE FUNCTION public.validate_student_registration();


-- ============================================================
-- 13. AUTOMATIC UPDATED_AT TRIGGERS
-- ============================================================

DROP TRIGGER IF EXISTS trg_course_offerings_updated_at
    ON public.course_offerings;

CREATE TRIGGER trg_course_offerings_updated_at
BEFORE UPDATE
ON public.course_offerings
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_student_registrations_updated_at
    ON public.student_registrations;

CREATE TRIGGER trg_student_registrations_updated_at
BEFORE UPDATE
ON public.student_registrations
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_course_registrations_updated_at
    ON public.course_registrations;

CREATE TRIGGER trg_course_registrations_updated_at
BEFORE UPDATE
ON public.course_registrations
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_course_add_drop_updated_at
    ON public.course_add_drop_requests;

CREATE TRIGGER trg_course_add_drop_updated_at
BEFORE UPDATE
ON public.course_add_drop_requests
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_registration_approvals_updated_at
    ON public.registration_approvals;

CREATE TRIGGER trg_registration_approvals_updated_at
BEFORE UPDATE
ON public.registration_approvals
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 14. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE public.course_offerings ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_registrations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.course_registrations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.course_add_drop_requests ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.registration_approvals ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 15. COMMENTS
-- ============================================================

COMMENT ON TABLE public.course_offerings IS
'Courses officially offered to programmes during an academic semester.';

COMMENT ON TABLE public.student_registrations IS
'Main semester registration record for a student.';

COMMENT ON TABLE public.course_registrations IS
'Individual course selections belonging to a student registration.';

COMMENT ON TABLE public.course_add_drop_requests IS
'Formal requests by students to add or drop courses.';

COMMENT ON TABLE public.registration_approvals IS
'Approval workflow for student academic registration.';


COMMIT;
