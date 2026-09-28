-- ============================================================
-- IDMC iMIS
-- Migration 011
-- ASSESSMENT / COURSEWORK CORE
-- ============================================================

BEGIN;

-- ============================================================
-- 1. ASSESSMENTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.assessments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    course_offering_id uuid NOT NULL
        REFERENCES public.course_offerings(id),

    assessment_code varchar(50) NOT NULL,

    assessment_name varchar(255) NOT NULL,

    assessment_type varchar(30) NOT NULL
        CHECK (
            assessment_type IN (
                'ASSIGNMENT',
                'QUIZ',
                'TEST',
                'PRACTICAL',
                'PRESENTATION',
                'PROJECT',
                'CONTINUOUS_ASSESSMENT',
                'OTHER'
            )
        ),

    assessment_number integer,

    maximum_marks numeric(6,2) NOT NULL
        CHECK (maximum_marks > 0),

    weight_percentage numeric(6,2) NOT NULL
        CHECK (
            weight_percentage > 0
            AND weight_percentage <= 100
        ),

    due_date date,

    due_time time,

    status varchar(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (
            status IN (
                'DRAFT',
                'OPEN',
                'SUBMITTED',
                'UNDER_REVIEW',
                'APPROVED',
                'LOCKED',
                'CANCELLED'
            )
        ),

    instructions text,

    created_by uuid
        REFERENCES public.users(id),

    updated_by uuid
        REFERENCES public.users(id),

    approved_by uuid
        REFERENCES public.users(id),

    approved_at timestamptz,

    locked_by uuid
        REFERENCES public.users(id),

    locked_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT assessments_unique_code
        UNIQUE (course_offering_id, assessment_code)
);


-- ============================================================
-- 2. ASSESSMENT MARKS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.assessment_marks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    assessment_id uuid NOT NULL
        REFERENCES public.assessments(id)
        ON DELETE CASCADE,

    student_id uuid NOT NULL
        REFERENCES public.students(id),

    course_registration_id uuid
        REFERENCES public.course_registrations(id),

    marks numeric(8,2) NOT NULL
        DEFAULT 0
        CHECK (marks >= 0),

    percentage numeric(8,4),

    grade varchar(10),

    remarks text,

    status varchar(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (
            status IN (
                'DRAFT',
                'SUBMITTED',
                'APPROVED',
                'LOCKED',
                'CORRECTION_PENDING',
                'CANCELLED'
            )
        ),

    entered_by uuid
        REFERENCES public.users(id),

    entered_at timestamptz,

    submitted_by uuid
        REFERENCES public.users(id),

    submitted_at timestamptz,

    approved_by uuid
        REFERENCES public.users(id),

    approved_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT assessment_marks_unique_student
        UNIQUE (assessment_id, student_id)
);


-- ============================================================
-- 3. ASSESSMENT SUBMISSIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.assessment_submissions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    assessment_id uuid NOT NULL
        REFERENCES public.assessments(id)
        ON DELETE CASCADE,

    student_id uuid NOT NULL
        REFERENCES public.students(id),

    submitted_at timestamptz,

    submission_status varchar(30) NOT NULL DEFAULT 'NOT_SUBMITTED'
        CHECK (
            submission_status IN (
                'NOT_SUBMITTED',
                'SUBMITTED',
                'LATE',
                'ACCEPTED',
                'REJECTED',
                'CANCELLED'
            )
        ),

    file_id uuid,

    submission_reference varchar(100),

    remarks text,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT assessment_submissions_unique_student
        UNIQUE (assessment_id, student_id)
);


-- ============================================================
-- 4. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_assessments_course_offering
ON public.assessments(course_offering_id);

CREATE INDEX IF NOT EXISTS idx_assessments_status
ON public.assessments(status);

CREATE INDEX IF NOT EXISTS idx_assessment_marks_assessment
ON public.assessment_marks(assessment_id);

CREATE INDEX IF NOT EXISTS idx_assessment_marks_student
ON public.assessment_marks(student_id);

CREATE INDEX IF NOT EXISTS idx_assessment_marks_status
ON public.assessment_marks(status);

CREATE INDEX IF NOT EXISTS idx_assessment_submissions_assessment
ON public.assessment_submissions(assessment_id);

CREATE INDEX IF NOT EXISTS idx_assessment_submissions_student
ON public.assessment_submissions(student_id);


-- ============================================================
-- 5. ASSESSMENT COURSE CONSISTENCY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_assessment_course_offering()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_status varchar;
BEGIN
    SELECT status
    INTO v_status
    FROM public.course_offerings
    WHERE id = NEW.course_offering_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION
            'Course offering % does not exist',
            NEW.course_offering_id;
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_assessment_course_offering
ON public.assessments;

CREATE TRIGGER trg_validate_assessment_course_offering
BEFORE INSERT OR UPDATE OF course_offering_id
ON public.assessments
FOR EACH ROW
EXECUTE FUNCTION public.validate_assessment_course_offering();


-- ============================================================
-- 6. VALIDATE ASSESSMENT MARK
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_assessment_mark()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_maximum_marks numeric;
    v_course_offering_id uuid;
    v_registered_offering_id uuid;
    v_registered_student_id uuid;
BEGIN

    SELECT
        maximum_marks,
        course_offering_id
    INTO
        v_maximum_marks,
        v_course_offering_id
    FROM public.assessments
    WHERE id = NEW.assessment_id;

    IF v_maximum_marks IS NULL THEN
        RAISE EXCEPTION
            'Assessment % does not exist',
            NEW.assessment_id;
    END IF;

    IF NEW.marks > v_maximum_marks THEN
        RAISE EXCEPTION
            'Marks (%) cannot exceed maximum marks (%)',
            NEW.marks,
            v_maximum_marks;
    END IF;

    IF NEW.course_registration_id IS NOT NULL THEN

        SELECT
            cr.course_offering_id,
            sr.student_id
        INTO
            v_registered_offering_id,
            v_registered_student_id
        FROM public.course_registrations cr
        JOIN public.student_registrations sr
            ON sr.id = cr.student_registration_id
        WHERE cr.id = NEW.course_registration_id;

        IF v_registered_student_id IS NULL THEN
            RAISE EXCEPTION
                'Course registration % is invalid',
                NEW.course_registration_id;
        END IF;

        IF v_registered_student_id <> NEW.student_id THEN
            RAISE EXCEPTION
                'Student does not match course registration';
        END IF;

        IF v_registered_offering_id <> v_course_offering_id THEN
            RAISE EXCEPTION
                'Course registration does not match assessment course';
        END IF;

    END IF;

    NEW.percentage :=
        ROUND(
            (NEW.marks / v_maximum_marks) * 100,
            4
        );

    NEW.entered_at :=
        COALESCE(NEW.entered_at, now());

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_assessment_mark
ON public.assessment_marks;

CREATE TRIGGER trg_validate_assessment_mark
BEFORE INSERT OR UPDATE OF
    assessment_id,
    student_id,
    course_registration_id,
    marks
ON public.assessment_marks
FOR EACH ROW
EXECUTE FUNCTION public.validate_assessment_mark();


-- ============================================================
-- 7. ASSESSMENT WEIGHT CONTROL
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_assessment_weight()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_total numeric;
BEGIN

    SELECT COALESCE(SUM(weight_percentage), 0)
    INTO v_total
    FROM public.assessments
    WHERE course_offering_id = NEW.course_offering_id
      AND id <> COALESCE(NEW.id, gen_random_uuid())
      AND status <> 'CANCELLED';

    v_total := v_total + NEW.weight_percentage;

    IF v_total > 100 THEN
        RAISE EXCEPTION
            'Total assessment weight for course offering cannot exceed 100%%. Current total: %',
            v_total;
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_assessment_weight
ON public.assessments;

CREATE TRIGGER trg_validate_assessment_weight
BEFORE INSERT OR UPDATE OF
    course_offering_id,
    weight_percentage,
    status
ON public.assessments
FOR EACH ROW
EXECUTE FUNCTION public.validate_assessment_weight();


-- ============================================================
-- 8. LOCKED ASSESSMENT PROTECTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_locked_assessment_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_status varchar;
BEGIN

    SELECT status
    INTO v_status
    FROM public.assessments
    WHERE id = COALESCE(
        NEW.assessment_id,
        OLD.assessment_id
    );

    IF v_status = 'LOCKED' THEN
        RAISE EXCEPTION
            'Assessment is LOCKED and cannot be modified';
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;


DROP TRIGGER IF EXISTS trg_prevent_locked_assessment_mark_change
ON public.assessment_marks;

CREATE TRIGGER trg_prevent_locked_assessment_mark_change
BEFORE INSERT OR UPDATE OR DELETE
ON public.assessment_marks
FOR EACH ROW
EXECUTE FUNCTION public.prevent_locked_assessment_change();


-- ============================================================
-- 9. ASSESSMENT STATUS TRANSITIONS
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_assessment_status_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.status = 'LOCKED'
       AND NEW.status <> 'LOCKED' THEN
        RAISE EXCEPTION
            'Locked assessment cannot be reopened';
    END IF;

    IF OLD.status = 'CANCELLED'
       AND NEW.status <> 'CANCELLED' THEN
        RAISE EXCEPTION
            'Cancelled assessment cannot be reopened';
    END IF;

    IF NEW.status = 'OPEN'
       AND OLD.status NOT IN ('DRAFT', 'OPEN') THEN
        RAISE EXCEPTION
            'Assessment must be DRAFT before opening';
    END IF;

    IF NEW.status = 'SUBMITTED'
       AND OLD.status NOT IN ('OPEN', 'SUBMITTED') THEN
        RAISE EXCEPTION
            'Assessment must be OPEN before submission';
    END IF;

    IF NEW.status = 'UNDER_REVIEW'
       AND OLD.status NOT IN ('SUBMITTED', 'UNDER_REVIEW') THEN
        RAISE EXCEPTION
            'Assessment must be SUBMITTED before review';
    END IF;

    IF NEW.status = 'APPROVED'
       AND OLD.status NOT IN ('UNDER_REVIEW', 'APPROVED') THEN
        RAISE EXCEPTION
            'Assessment must be UNDER_REVIEW before approval';
    END IF;

    IF NEW.status = 'LOCKED'
       AND OLD.status NOT IN ('APPROVED', 'LOCKED') THEN
        RAISE EXCEPTION
            'Assessment must be APPROVED before locking';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_assessment_status_transition
ON public.assessments;

CREATE TRIGGER trg_validate_assessment_status_transition
BEFORE UPDATE OF status
ON public.assessments
FOR EACH ROW
EXECUTE FUNCTION public.validate_assessment_status_transition();


-- ============================================================
-- 10. MARK STATUS PROTECTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_assessment_mark_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.status = 'LOCKED'
       AND NEW.status <> 'LOCKED' THEN
        RAISE EXCEPTION
            'Locked assessment mark cannot be reopened';
    END IF;

    IF NEW.status = 'SUBMITTED'
       AND OLD.status <> 'SUBMITTED'
       AND OLD.status <> 'DRAFT' THEN
        RAISE EXCEPTION
            'Assessment mark must be DRAFT before submission';
    END IF;

    IF NEW.status = 'APPROVED'
       AND OLD.status NOT IN ('SUBMITTED', 'APPROVED') THEN
        RAISE EXCEPTION
            'Assessment mark must be SUBMITTED before approval';
    END IF;

    IF NEW.status = 'LOCKED'
       AND OLD.status NOT IN ('APPROVED', 'LOCKED') THEN
        RAISE EXCEPTION
            'Assessment mark must be APPROVED before locking';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_assessment_mark_status
ON public.assessment_marks;

CREATE TRIGGER trg_validate_assessment_mark_status
BEFORE UPDATE OF status
ON public.assessment_marks
FOR EACH ROW
EXECUTE FUNCTION public.validate_assessment_mark_status();


-- ============================================================
-- 11. UPDATED_AT
-- ============================================================

DROP TRIGGER IF EXISTS trg_assessments_updated_at
ON public.assessments;

CREATE TRIGGER trg_assessments_updated_at
BEFORE UPDATE ON public.assessments
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_assessment_marks_updated_at
ON public.assessment_marks;

CREATE TRIGGER trg_assessment_marks_updated_at
BEFORE UPDATE ON public.assessment_marks
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_assessment_submissions_updated_at
ON public.assessment_submissions;

CREATE TRIGGER trg_assessment_submissions_updated_at
BEFORE UPDATE ON public.assessment_submissions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 12. RLS
-- ============================================================

ALTER TABLE public.assessments ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.assessment_marks ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.assessment_submissions ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 13. COMMENTS
-- ============================================================

COMMENT ON TABLE public.assessments IS
'Course assessment definitions including coursework, tests, practicals and projects.';

COMMENT ON TABLE public.assessment_marks IS
'Student-level assessment marks with controlled approval and locking.';

COMMENT ON TABLE public.assessment_submissions IS
'Student assessment submission records and associated submission metadata.';


COMMIT;
