-- ============================================================
-- IDMC iMIS
-- Migration: 202609150008
-- Assessment Integrity Hardening
-- ============================================================

-- ------------------------------------------------------------
-- 1. Validate assessment mark -> student registration linkage
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_assessment_mark_registration()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_registration_student uuid;
    v_registration_offering uuid;
    v_assessment_offering uuid;
BEGIN
    SELECT
        sr.student_id,
        cr.course_offering_id
    INTO
        v_registration_student,
        v_registration_offering
    FROM public.course_registrations cr
    INNER JOIN public.student_registrations sr
        ON sr.id = cr.student_registration_id
    WHERE cr.id = NEW.course_registration_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Assessment mark requires a valid course registration.';
    END IF;

    SELECT course_offering_id
    INTO v_assessment_offering
    FROM public.assessments
    WHERE id = NEW.assessment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Assessment does not exist.';
    END IF;

    IF NEW.student_id <> v_registration_student THEN
        RAISE EXCEPTION
            'Assessment mark student does not match course registration student.';
    END IF;

    IF v_registration_offering <> v_assessment_offering THEN
        RAISE EXCEPTION
            'Course registration does not belong to the assessment course offering.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_assessment_mark_registration
ON public.assessment_marks;

CREATE TRIGGER trg_validate_assessment_mark_registration
BEFORE INSERT OR UPDATE
ON public.assessment_marks
FOR EACH ROW
EXECUTE FUNCTION public.validate_assessment_mark_registration();


-- ------------------------------------------------------------
-- 2. Require registration for every assessment mark
-- ------------------------------------------------------------

ALTER TABLE public.assessment_marks
ALTER COLUMN course_registration_id SET NOT NULL;


-- ------------------------------------------------------------
-- 3. Assessment mark correction audit table
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.assessment_mark_corrections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    assessment_mark_id uuid NOT NULL
        REFERENCES public.assessment_marks(id)
        ON DELETE RESTRICT,

    requested_by uuid NOT NULL
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    requested_at timestamptz NOT NULL DEFAULT now(),

    old_marks numeric(8,2),
    new_marks numeric(8,2),

    old_grade varchar(20),
    new_grade varchar(20),

    reason text NOT NULL,

    evidence_file_id uuid,

    status varchar(30) NOT NULL DEFAULT 'PENDING'
        CHECK (
            status IN (
                'PENDING',
                'APPROVED',
                'REJECTED',
                'CANCELLED'
            )
        ),

    reviewed_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    reviewed_at timestamptz,

    review_comment text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT assessment_mark_correction_reason_chk
        CHECK (length(trim(reason)) >= 5),

    CONSTRAINT assessment_mark_correction_review_chk
        CHECK (
            status = 'PENDING'
            OR status = 'CANCELLED'
            OR (
                status IN ('APPROVED', 'REJECTED')
                AND reviewed_by IS NOT NULL
                AND reviewed_at IS NOT NULL
            )
        )
);

-- ------------------------------------------------------------
-- 4. Correction indexes
-- ------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_assessment_mark_corrections_mark
ON public.assessment_mark_corrections(assessment_mark_id);

CREATE INDEX IF NOT EXISTS idx_assessment_mark_corrections_status
ON public.assessment_mark_corrections(status);

CREATE INDEX IF NOT EXISTS idx_assessment_mark_corrections_requested_by
ON public.assessment_mark_corrections(requested_by);

CREATE INDEX IF NOT EXISTS idx_assessment_mark_corrections_reviewed_by
ON public.assessment_mark_corrections(reviewed_by);


-- ------------------------------------------------------------
-- 5. One pending correction per assessment mark
-- ------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_assessment_mark_correction
ON public.assessment_mark_corrections(assessment_mark_id)
WHERE status = 'PENDING';


-- ------------------------------------------------------------
-- 6. Protect locked assessment marks
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.prevent_locked_assessment_mark_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_assessment_status varchar(30);
BEGIN
    SELECT status
    INTO v_assessment_status
    FROM public.assessments
    WHERE id = OLD.assessment_id;

    IF v_assessment_status = 'LOCKED' THEN

        IF NEW.marks IS DISTINCT FROM OLD.marks
           OR NEW.grade IS DISTINCT FROM OLD.grade
           OR NEW.remarks IS DISTINCT FROM OLD.remarks
           OR NEW.student_id IS DISTINCT FROM OLD.student_id
           OR NEW.course_registration_id IS DISTINCT FROM OLD.course_registration_id THEN

            RAISE EXCEPTION
                'Locked assessment marks cannot be modified directly. Submit a correction request.';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_locked_assessment_mark_change
ON public.assessment_marks;

CREATE TRIGGER trg_prevent_locked_assessment_mark_change
BEFORE UPDATE
ON public.assessment_marks
FOR EACH ROW
EXECUTE FUNCTION public.prevent_locked_assessment_mark_change();


-- ------------------------------------------------------------
-- 7. Prevent deleting assessment marks
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.prevent_assessment_mark_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_status varchar(30);
BEGIN
    SELECT status
    INTO v_status
    FROM public.assessments
    WHERE id = OLD.assessment_id;

    IF v_status IN ('APPROVED', 'LOCKED') THEN
        RAISE EXCEPTION
            'Approved or locked assessment marks cannot be deleted.';
    END IF;

    RAISE EXCEPTION
        'Assessment marks cannot be deleted. Use the correction workflow.';
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_assessment_mark_delete
ON public.assessment_marks;

CREATE TRIGGER trg_prevent_assessment_mark_delete
BEFORE DELETE
ON public.assessment_marks
FOR EACH ROW
EXECUTE FUNCTION public.prevent_assessment_mark_delete();


-- ------------------------------------------------------------
-- 8. Validate correction request
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_assessment_mark_correction()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_marks numeric(8,2);
    v_current_grade varchar(20);
    v_assessment_id uuid;
    v_assessment_status varchar(30);
    v_max_marks numeric(8,2);
BEGIN

    SELECT
        am.marks,
        am.grade,
        am.assessment_id
    INTO
        v_current_marks,
        v_current_grade,
        v_assessment_id
    FROM public.assessment_marks am
    WHERE am.id = NEW.assessment_mark_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Assessment mark for correction does not exist.';
    END IF;

    SELECT
        status,
        maximum_marks
    INTO
        v_assessment_status,
        v_max_marks
    FROM public.assessments
    WHERE id = v_assessment_id;

    IF v_assessment_status NOT IN ('APPROVED', 'LOCKED') THEN
        RAISE EXCEPTION
            'Correction requests are only allowed for approved or locked assessments.';
    END IF;

    IF NEW.old_marks IS DISTINCT FROM v_current_marks THEN
        RAISE EXCEPTION
            'Correction old_marks does not match the current stored mark.';
    END IF;

    IF NEW.old_grade IS DISTINCT FROM v_current_grade THEN
        RAISE EXCEPTION
            'Correction old_grade does not match the current stored grade.';
    END IF;

    IF NEW.new_marks IS NULL THEN
        RAISE EXCEPTION
            'New marks are required.';
    END IF;

    IF NEW.new_marks < 0 OR NEW.new_marks > v_max_marks THEN
        RAISE EXCEPTION
            'Corrected marks must be between 0 and the assessment maximum marks.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_assessment_mark_correction
ON public.assessment_mark_corrections;

CREATE TRIGGER trg_validate_assessment_mark_correction
BEFORE INSERT OR UPDATE
ON public.assessment_mark_corrections
FOR EACH ROW
EXECUTE FUNCTION public.validate_assessment_mark_correction();


-- ------------------------------------------------------------
-- 9. Reviewed corrections become immutable
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.prevent_reviewed_assessment_correction_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.status IN ('APPROVED', 'REJECTED') THEN

        IF NEW.status IS DISTINCT FROM OLD.status
           OR NEW.old_marks IS DISTINCT FROM OLD.old_marks
           OR NEW.new_marks IS DISTINCT FROM OLD.new_marks
           OR NEW.old_grade IS DISTINCT FROM OLD.old_grade
           OR NEW.new_grade IS DISTINCT FROM OLD.new_grade
           OR NEW.reason IS DISTINCT FROM OLD.reason
           OR NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by
           OR NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at
           OR NEW.review_comment IS DISTINCT FROM OLD.review_comment THEN

            RAISE EXCEPTION
                'Reviewed assessment correction requests are immutable.';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_reviewed_assessment_correction_change
ON public.assessment_mark_corrections;

CREATE TRIGGER trg_prevent_reviewed_assessment_correction_change
BEFORE UPDATE
ON public.assessment_mark_corrections
FOR EACH ROW
EXECUTE FUNCTION public.prevent_reviewed_assessment_correction_change();


-- ------------------------------------------------------------
-- 10. Correction status workflow
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_assessment_correction_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.status = 'PENDING' THEN

        IF NEW.status NOT IN ('APPROVED', 'REJECTED', 'CANCELLED') THEN
            RAISE EXCEPTION
                'Pending correction can only become APPROVED, REJECTED or CANCELLED.';
        END IF;

    ELSIF OLD.status IN ('APPROVED', 'REJECTED', 'CANCELLED') THEN

        IF NEW.status <> OLD.status THEN
            RAISE EXCEPTION
                'Finalized correction requests cannot change status.';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_assessment_correction_status
ON public.assessment_mark_corrections;

CREATE TRIGGER trg_validate_assessment_correction_status
BEFORE UPDATE
ON public.assessment_mark_corrections
FOR EACH ROW
EXECUTE FUNCTION public.validate_assessment_correction_status();


-- ------------------------------------------------------------
-- 11. Updated timestamp
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_assessment_mark_corrections_updated_at
ON public.assessment_mark_corrections;

CREATE TRIGGER trg_assessment_mark_corrections_updated_at
BEFORE UPDATE
ON public.assessment_mark_corrections
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ------------------------------------------------------------
-- 12. RLS
-- ------------------------------------------------------------

ALTER TABLE public.assessment_mark_corrections
ENABLE ROW LEVEL SECURITY;


-- ------------------------------------------------------------
-- 13. Documentation
-- ------------------------------------------------------------

COMMENT ON TABLE public.assessment_mark_corrections IS
'Formal audited workflow for correcting approved or locked assessment marks.';

COMMENT ON COLUMN public.assessment_mark_corrections.reason IS
'Mandatory business reason for requesting a mark correction.';

COMMENT ON COLUMN public.assessment_mark_corrections.evidence_file_id IS
'Optional supporting evidence reference.';

COMMENT ON COLUMN public.assessment_mark_corrections.status IS
'Correction workflow status: PENDING, APPROVED, REJECTED or CANCELLED.';


-- ============================================================
-- END OF MIGRATION
-- ============================================================
