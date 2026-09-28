-- ============================================================
-- IDMC iMIS
-- Migration 014
-- Transcript Workflow Hardening
-- Validated against actual remote schema
-- ============================================================

BEGIN;

-- ============================================================
-- 1. TRANSCRIPT INSERT STATUS PROTECTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_transcript_insert_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.transcript_status IS NULL THEN
        NEW.transcript_status := 'DRAFT';
    END IF;

    IF NEW.transcript_status NOT IN (
        'DRAFT',
        'GENERATED',
        'REVIEW'
    ) THEN

        RAISE EXCEPTION
            'New transcript cannot be inserted directly with status %. '
            'Transcript must enter through DRAFT, GENERATED or REVIEW workflow.',
            NEW.transcript_status;

    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_transcript_insert_status
ON public.student_transcripts;

CREATE TRIGGER trg_validate_transcript_insert_status
BEFORE INSERT ON public.student_transcripts
FOR EACH ROW
EXECUTE FUNCTION public.validate_transcript_insert_status();


-- ============================================================
-- 2. HARDEN TRANSCRIPT STATUS TRANSITIONS
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_transcript_status_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.transcript_status = OLD.transcript_status THEN
        RETURN NEW;
    END IF;


    -- DRAFT -> GENERATED
    IF OLD.transcript_status = 'DRAFT'
       AND NEW.transcript_status = 'GENERATED' THEN
        RETURN NEW;
    END IF;


    -- GENERATED -> REVIEW / DRAFT
    IF OLD.transcript_status = 'GENERATED'
       AND NEW.transcript_status IN ('REVIEW', 'DRAFT') THEN
        RETURN NEW;
    END IF;


    -- REVIEW -> APPROVED / DRAFT
    IF OLD.transcript_status = 'REVIEW'
       AND NEW.transcript_status IN ('APPROVED', 'DRAFT') THEN
        RETURN NEW;
    END IF;


    -- APPROVED -> ISSUED
    IF OLD.transcript_status = 'APPROVED'
       AND NEW.transcript_status = 'ISSUED' THEN
        RETURN NEW;
    END IF;


    -- ISSUED -> REVOKED / SUPERSEDED
    IF OLD.transcript_status = 'ISSUED'
       AND NEW.transcript_status IN ('REVOKED', 'SUPERSEDED') THEN
        RETURN NEW;
    END IF;


    -- REVOKED -> SUPERSEDED
    IF OLD.transcript_status = 'REVOKED'
       AND NEW.transcript_status = 'SUPERSEDED' THEN
        RETURN NEW;
    END IF;


    RAISE EXCEPTION
        'Invalid transcript status transition: % -> %',
        OLD.transcript_status,
        NEW.transcript_status;

END;
$$;


DROP TRIGGER IF EXISTS trg_validate_transcript_status_transition
ON public.student_transcripts;

CREATE TRIGGER trg_validate_transcript_status_transition
BEFORE UPDATE ON public.student_transcripts
FOR EACH ROW
EXECUTE FUNCTION public.validate_transcript_status_transition();


-- ============================================================
-- 3. HARDEN TRANSCRIPT ISSUE PROCESS
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_transcript_issue()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.transcript_status = 'ISSUED'
       AND OLD.transcript_status <> 'ISSUED' THEN

        IF OLD.transcript_status <> 'APPROVED' THEN
            RAISE EXCEPTION
                'Only APPROVED transcripts can be ISSUED.';
        END IF;


        IF NEW.approved_at IS NULL THEN
            RAISE EXCEPTION
                'Transcript approval timestamp is required before issuing.';
        END IF;


        IF NEW.approved_by IS NULL THEN
            RAISE EXCEPTION
                'Transcript approver is required before issuing.';
        END IF;


        IF NEW.transcript_number IS NULL
           OR trim(NEW.transcript_number) = '' THEN

            RAISE EXCEPTION
                'Transcript number is required before issuing.';

        END IF;


        IF NEW.verification_code IS NULL
           OR trim(NEW.verification_code) = '' THEN

            RAISE EXCEPTION
                'Verification code is required before issuing.';

        END IF;


        IF NEW.issued_by IS NULL THEN
            RAISE EXCEPTION
                'Transcript issuer is required before issuing.';
        END IF;


        NEW.issued_at := COALESCE(
            NEW.issued_at,
            now()
        );

    END IF;


    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_transcript_issue
ON public.student_transcripts;

CREATE TRIGGER trg_validate_transcript_issue
BEFORE UPDATE ON public.student_transcripts
FOR EACH ROW
EXECUTE FUNCTION public.validate_transcript_issue();


-- ============================================================
-- 4. ISSUED / SUPERSEDED TRANSCRIPT IMMUTABILITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_issued_transcript_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.transcript_status IN ('ISSUED', 'SUPERSEDED') THEN

        -- Only status/audit lifecycle fields may change.
        IF NEW.student_id IS DISTINCT FROM OLD.student_id
           OR NEW.transcript_number IS DISTINCT FROM OLD.transcript_number
           OR NEW.programme_version_id IS DISTINCT FROM OLD.programme_version_id
           OR NEW.transcript_type IS DISTINCT FROM OLD.transcript_type
           OR NEW.issue_reason IS DISTINCT FROM OLD.issue_reason
           OR NEW.cumulative_credits IS DISTINCT FROM OLD.cumulative_credits
           OR NEW.cumulative_earned_credits IS DISTINCT FROM OLD.cumulative_earned_credits
           OR NEW.cumulative_quality_points IS DISTINCT FROM OLD.cumulative_quality_points
           OR NEW.cgpa IS DISTINCT FROM OLD.cgpa
           OR NEW.final_academic_standing IS DISTINCT FROM OLD.final_academic_standing
           OR NEW.verification_code IS DISTINCT FROM OLD.verification_code
           OR NEW.document_file_id IS DISTINCT FROM OLD.document_file_id THEN

            RAISE EXCEPTION
                'Issued/Superseded transcript is immutable. '
                'Create a replacement transcript instead.';

        END IF;

    END IF;


    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_prevent_issued_transcript_change
ON public.student_transcripts;

CREATE TRIGGER trg_prevent_issued_transcript_change
BEFORE UPDATE ON public.student_transcripts
FOR EACH ROW
EXECUTE FUNCTION public.prevent_issued_transcript_change();


-- ============================================================
-- 5. REPLACEMENT TRANSCRIPT VALIDATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_transcript_replacement()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_status varchar;
    v_old_student uuid;
BEGIN

    IF NEW.replacement_of IS NULL THEN
        RETURN NEW;
    END IF;


    IF NEW.replacement_of = NEW.id THEN
        RAISE EXCEPTION
            'A transcript cannot replace itself.';
    END IF;


    SELECT
        transcript_status,
        student_id
    INTO
        v_old_status,
        v_old_student
    FROM public.student_transcripts
    WHERE id = NEW.replacement_of;


    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Replacement transcript references a transcript that does not exist.';
    END IF;


    IF v_old_status NOT IN (
        'ISSUED',
        'REVOKED',
        'SUPERSEDED'
    ) THEN

        RAISE EXCEPTION
            'Only ISSUED, REVOKED or SUPERSEDED transcripts may be replaced.';

    END IF;


    IF v_old_student IS DISTINCT FROM NEW.student_id THEN
        RAISE EXCEPTION
            'Replacement transcript must belong to the same student.';
    END IF;


    -- Replacement must still follow the normal workflow.
    IF NEW.transcript_status NOT IN (
        'DRAFT',
        'GENERATED',
        'REVIEW'
    ) THEN

        RAISE EXCEPTION
            'Replacement transcript must enter the normal workflow before approval/issue.';

    END IF;


    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_transcript_replacement
ON public.student_transcripts;

CREATE TRIGGER trg_validate_transcript_replacement
BEFORE INSERT OR UPDATE ON public.student_transcripts
FOR EACH ROW
EXECUTE FUNCTION public.validate_transcript_replacement();


-- ============================================================
-- 6. PREVENT REPLACEMENT CYCLES
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_transcript_replacement_cycle()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_current uuid;
    v_count integer := 0;
BEGIN

    IF NEW.replacement_of IS NULL THEN
        RETURN NEW;
    END IF;


    IF NEW.replacement_of = NEW.id THEN
        RAISE EXCEPTION
            'A transcript cannot replace itself.';
    END IF;


    v_current := NEW.replacement_of;


    WHILE v_current IS NOT NULL AND v_count < 50 LOOP

        SELECT replacement_of
        INTO v_current
        FROM public.student_transcripts
        WHERE id = v_current;

        v_count := v_count + 1;


        IF v_current = NEW.id THEN
            RAISE EXCEPTION
                'Transcript replacement cycle detected.';
        END IF;

    END LOOP;


    IF v_count >= 50 THEN
        RAISE EXCEPTION
            'Transcript replacement chain exceeds the permitted depth.';
    END IF;


    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_transcript_replacement_cycle
ON public.student_transcripts;

CREATE TRIGGER trg_validate_transcript_replacement_cycle
BEFORE INSERT OR UPDATE ON public.student_transcripts
FOR EACH ROW
EXECUTE FUNCTION public.validate_transcript_replacement_cycle();


-- ============================================================
-- 7. ONLY ONE ACTIVE DRAFT/REVIEW/APPROVAL TRANSCRIPT
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_student_active_transcript_workflow
ON public.student_transcripts
(
    student_id,
    transcript_type
)
WHERE transcript_status IN (
    'DRAFT',
    'GENERATED',
    'REVIEW',
    'APPROVED'
);


-- ============================================================
-- 8. TRANSCRIPT COURSE MARK VALIDATION
-- ============================================================

ALTER TABLE public.student_transcript_courses
DROP CONSTRAINT IF EXISTS student_transcript_courses_marks_valid;

ALTER TABLE public.student_transcript_courses
ADD CONSTRAINT student_transcript_courses_marks_valid
CHECK (
    total_mark IS NULL
    OR (
        total_mark >= 0
        AND total_mark <= 100
    )
);


-- ============================================================
-- 9. TRANSCRIPT COURSE GRADE POINT VALIDATION
-- ============================================================

ALTER TABLE public.student_transcript_courses
DROP CONSTRAINT IF EXISTS student_transcript_courses_grade_point_valid;

ALTER TABLE public.student_transcript_courses
ADD CONSTRAINT student_transcript_courses_grade_point_valid
CHECK (
    grade_point IS NULL
    OR (
        grade_point >= 0
        AND grade_point <= 5
    )
);


-- ============================================================
-- 10. TRANSCRIPT COURSE CREDITS VALIDATION
-- ============================================================

ALTER TABLE public.student_transcript_courses
DROP CONSTRAINT IF EXISTS student_transcript_courses_credits_valid;

ALTER TABLE public.student_transcript_courses
ADD CONSTRAINT student_transcript_courses_credits_valid
CHECK (
    credits IS NULL
    OR credits > 0
);


-- ============================================================
-- 11. TRANSCRIPT SEMESTER GPA VALIDATION
-- ============================================================

ALTER TABLE public.student_transcript_semesters
DROP CONSTRAINT IF EXISTS student_transcript_semesters_gpa_valid;

ALTER TABLE public.student_transcript_semesters
ADD CONSTRAINT student_transcript_semesters_gpa_valid
CHECK (
    gpa IS NULL
    OR (
        gpa >= 0
        AND gpa <= 5
    )
);


-- ============================================================
-- 12. TRANSCRIPT SEMESTER CREDITS VALIDATION
-- ============================================================

ALTER TABLE public.student_transcript_semesters
DROP CONSTRAINT IF EXISTS student_transcript_semesters_registered_credits_valid;

ALTER TABLE public.student_transcript_semesters
ADD CONSTRAINT student_transcript_semesters_registered_credits_valid
CHECK (registered_credits >= 0);


ALTER TABLE public.student_transcript_semesters
DROP CONSTRAINT IF EXISTS student_transcript_semesters_attempted_credits_valid;

ALTER TABLE public.student_transcript_semesters
ADD CONSTRAINT student_transcript_semesters_attempted_credits_valid
CHECK (attempted_credits >= 0);


ALTER TABLE public.student_transcript_semesters
DROP CONSTRAINT IF EXISTS student_transcript_semesters_earned_credits_valid;

ALTER TABLE public.student_transcript_semesters
ADD CONSTRAINT student_transcript_semesters_earned_credits_valid
CHECK (earned_credits >= 0);


-- ============================================================
-- 13. TRANSCRIPT SEMESTER SEQUENCE
-- ============================================================

ALTER TABLE public.student_transcript_semesters
DROP CONSTRAINT IF EXISTS student_transcript_semesters_sequence_positive;

ALTER TABLE public.student_transcript_semesters
ADD CONSTRAINT student_transcript_semesters_sequence_positive
CHECK (sequence_no > 0);


-- ============================================================
-- 14. DUPLICATE COURSE RESULT PROTECTION
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_transcript_course_result
ON public.student_transcript_courses
(
    transcript_id,
    course_result_id
)
WHERE course_result_id IS NOT NULL;


-- ============================================================
-- 15. DUPLICATE SEMESTER PROTECTION
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_transcript_semester_context
ON public.student_transcript_semesters
(
    transcript_id,
    academic_year_id,
    semester_id
);


-- ============================================================
-- 16. DEFICIENCY DUPLICATE PROTECTION
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_student_course_open_deficiency
ON public.student_academic_deficiencies
(
    student_id,
    course_id,
    deficiency_type
)
WHERE deficiency_status IN (
    'OPEN',
    'IN_PROGRESS'
)
AND course_id IS NOT NULL;


-- ============================================================
-- 17. TRANSCRIPT VERIFICATION INDEX
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_student_transcripts_verification
ON public.student_transcripts
(
    verification_code
)
WHERE verification_code IS NOT NULL;


CREATE INDEX IF NOT EXISTS idx_student_transcripts_student_status
ON public.student_transcripts
(
    student_id,
    transcript_status
);


CREATE INDEX IF NOT EXISTS idx_student_transcript_courses_transcript
ON public.student_transcript_courses
(
    transcript_id
);


CREATE INDEX IF NOT EXISTS idx_student_transcript_semesters_transcript
ON public.student_transcript_semesters
(
    transcript_id
);


-- ============================================================
-- 18. RLS
-- ============================================================

ALTER TABLE public.student_transcripts
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_transcript_semesters
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_transcript_courses
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_academic_standings
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_course_attempts
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_academic_deficiencies
ENABLE ROW LEVEL SECURITY;


COMMIT;

-- ============================================================
-- END MIGRATION 014
-- ============================================================
