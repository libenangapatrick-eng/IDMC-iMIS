-- ============================================================
-- IDMC iMIS
-- Migration 010: Examination Integrity Hardening
-- ============================================================

BEGIN;

-- ============================================================
-- 1. FIX / HARDEN EXAMINATION CANDIDATE VALIDATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_examination_candidate()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_registration_student uuid;
    v_registration_offering uuid;
    v_paper_offering uuid;
    v_period_id uuid;
    v_candidate_count integer;
BEGIN

    SELECT
        sr.student_id,
        cr.course_offering_id
    INTO
        v_registration_student,
        v_registration_offering
    FROM public.course_registrations cr
    JOIN public.student_registrations sr
        ON sr.id = cr.student_registration_id
    WHERE cr.id = NEW.course_registration_id;

    IF v_registration_student IS NULL THEN
        RAISE EXCEPTION
            'Invalid examination candidate: course registration does not exist';
    END IF;

    IF v_registration_student <> NEW.student_id THEN
        RAISE EXCEPTION
            'Examination candidate student does not match course registration student';
    END IF;

    SELECT
        ep.id,
        ep.course_offering_id
    INTO
        v_period_id,
        v_paper_offering
    FROM public.examination_papers ep
    WHERE ep.id = NEW.examination_paper_id;

    IF v_period_id IS NULL THEN
        RAISE EXCEPTION
            'Invalid examination candidate: examination paper does not exist';
    END IF;

    IF v_registration_offering <> v_paper_offering THEN
        RAISE EXCEPTION
            'Examination candidate course registration does not match examination paper course offering';
    END IF;

    SELECT COUNT(*)
    INTO v_candidate_count
    FROM public.examination_candidates ec
    WHERE ec.examination_paper_id = NEW.examination_paper_id
      AND ec.student_id = NEW.student_id
      AND ec.id <> COALESCE(NEW.id, gen_random_uuid());

    IF v_candidate_count > 0 THEN
        RAISE EXCEPTION
            'Student is already registered as a candidate for this examination paper';
    END IF;

    RETURN NEW;
END;
$$;


-- ============================================================
-- 2. EXAMINATION PAPER MUST MATCH PERIOD CONTEXT
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_examination_paper_context()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_period_year uuid;
    v_period_semester uuid;
    v_offering_year uuid;
    v_offering_semester uuid;
BEGIN

    SELECT academic_year_id, semester_id
    INTO v_period_year, v_period_semester
    FROM public.examination_periods
    WHERE id = NEW.examination_period_id;

    IF v_period_year IS NULL OR v_period_semester IS NULL THEN
        RAISE EXCEPTION
            'Examination period is invalid or missing academic context';
    END IF;

    SELECT academic_year_id, semester_id
    INTO v_offering_year, v_offering_semester
    FROM public.course_offerings
    WHERE id = NEW.course_offering_id;

    IF v_offering_year IS NULL OR v_offering_semester IS NULL THEN
        RAISE EXCEPTION
            'Course offering is invalid or missing academic context';
    END IF;

    IF v_period_year <> v_offering_year
       OR v_period_semester <> v_offering_semester THEN
        RAISE EXCEPTION
            'Examination paper course offering does not belong to the examination period academic year and semester';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_examination_paper_context
ON public.examination_papers;

CREATE TRIGGER trg_validate_examination_paper_context
BEFORE INSERT OR UPDATE
ON public.examination_papers
FOR EACH ROW
EXECUTE FUNCTION public.validate_examination_paper_context();


-- ============================================================
-- 3. CANDIDATE MUST HAVE A VALID REGISTRATION STATUS
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_examination_candidate_registration()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_registration_status varchar;
BEGIN

    SELECT status
    INTO v_registration_status
    FROM public.course_registrations
    WHERE id = NEW.course_registration_id;

    IF v_registration_status IS NULL THEN
        RAISE EXCEPTION
            'Course registration does not exist';
    END IF;

    IF v_registration_status NOT IN
        ('APPROVED', 'REGISTERED', 'LOCKED') THEN

        RAISE EXCEPTION
            'Student course registration is not valid for examination eligibility. Current status: %',
            v_registration_status;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_examination_candidate_registration
ON public.examination_candidates;

CREATE TRIGGER trg_validate_examination_candidate_registration
BEFORE INSERT OR UPDATE
ON public.examination_candidates
FOR EACH ROW
EXECUTE FUNCTION public.validate_examination_candidate_registration();


-- ============================================================
-- 4. CANDIDATE NUMBER UNIQUENESS WITHIN EXAMINATION PERIOD
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_examination_candidate_number()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_period_id uuid;
    v_existing integer;
BEGIN

    IF NEW.candidate_number IS NULL
       OR trim(NEW.candidate_number) = '' THEN
        RETURN NEW;
    END IF;

    SELECT examination_period_id
    INTO v_period_id
    FROM public.examination_papers
    WHERE id = NEW.examination_paper_id;

    SELECT COUNT(*)
    INTO v_existing
    FROM public.examination_candidates ec
    JOIN public.examination_papers ep
        ON ep.id = ec.examination_paper_id
    WHERE ep.examination_period_id = v_period_id
      AND ec.candidate_number = NEW.candidate_number
      AND ec.id <> COALESCE(NEW.id, gen_random_uuid());

    IF v_existing > 0 THEN
        RAISE EXCEPTION
            'Candidate number % is already in use within this examination period',
            NEW.candidate_number;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_examination_candidate_number
ON public.examination_candidates;

CREATE TRIGGER trg_validate_examination_candidate_number
BEFORE INSERT OR UPDATE
ON public.examination_candidates
FOR EACH ROW
EXECUTE FUNCTION public.validate_examination_candidate_number();


-- ============================================================
-- 5. CANDIDATE SESSION ASSIGNMENT
-- ============================================================

CREATE TABLE IF NOT EXISTS public.examination_candidate_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    examination_session_id uuid NOT NULL
        REFERENCES public.examination_sessions(id)
        ON DELETE RESTRICT,

    examination_candidate_id uuid NOT NULL
        REFERENCES public.examination_candidates(id)
        ON DELETE RESTRICT,

    seat_number varchar(50),

    assignment_status varchar(30) NOT NULL DEFAULT 'ASSIGNED'
        CHECK (
            assignment_status IN (
                'ASSIGNED',
                'CONFIRMED',
                'MOVED',
                'CANCELLED'
            )
        ),

    assigned_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    assigned_at timestamptz NOT NULL DEFAULT now(),

    notes text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS
uq_exam_candidate_one_session
ON public.examination_candidate_sessions(examination_candidate_id)
WHERE assignment_status IN ('ASSIGNED','CONFIRMED','MOVED');

CREATE UNIQUE INDEX IF NOT EXISTS
uq_exam_session_candidate
ON public.examination_candidate_sessions(
    examination_session_id,
    examination_candidate_id
);

CREATE UNIQUE INDEX IF NOT EXISTS
uq_exam_session_seat
ON public.examination_candidate_sessions(
    examination_session_id,
    seat_number
)
WHERE seat_number IS NOT NULL
  AND assignment_status IN ('ASSIGNED','CONFIRMED','MOVED');


-- ============================================================
-- 6. VALIDATE CANDIDATE SESSION ASSIGNMENT
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_examination_candidate_session()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_candidate_paper uuid;
    v_session_paper uuid;
    v_session_capacity integer;
    v_assigned_count integer;
BEGIN

    SELECT examination_paper_id
    INTO v_candidate_paper
    FROM public.examination_candidates
    WHERE id = NEW.examination_candidate_id;

    SELECT examination_paper_id, capacity
    INTO v_session_paper, v_session_capacity
    FROM public.examination_sessions
    WHERE id = NEW.examination_session_id;

    IF v_candidate_paper IS NULL THEN
        RAISE EXCEPTION
            'Examination candidate does not exist';
    END IF;

    IF v_session_paper IS NULL THEN
        RAISE EXCEPTION
            'Examination session does not exist';
    END IF;

    IF v_candidate_paper <> v_session_paper THEN
        RAISE EXCEPTION
            'Candidate and examination session belong to different examination papers';
    END IF;

    IF NEW.assignment_status IN ('ASSIGNED','CONFIRMED','MOVED') THEN

        PERFORM pg_advisory_xact_lock(
            hashtextextended(NEW.examination_session_id::text, 0)
        );

        SELECT COUNT(*)
        INTO v_assigned_count
        FROM public.examination_candidate_sessions ecs
        WHERE ecs.examination_session_id = NEW.examination_session_id
          AND ecs.assignment_status IN
              ('ASSIGNED','CONFIRMED','MOVED')
          AND ecs.id <> COALESCE(NEW.id, gen_random_uuid());

        IF v_assigned_count >= v_session_capacity THEN
            RAISE EXCEPTION
                'Examination session has reached its candidate capacity';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_examination_candidate_session
ON public.examination_candidate_sessions;

CREATE TRIGGER trg_validate_examination_candidate_session
BEFORE INSERT OR UPDATE
ON public.examination_candidate_sessions
FOR EACH ROW
EXECUTE FUNCTION public.validate_examination_candidate_session();


-- ============================================================
-- 7. EXAMINATION ATTENDANCE VALIDATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_examination_attendance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_paper uuid;
    v_candidate_paper uuid;
BEGIN

    SELECT examination_paper_id
    INTO v_session_paper
    FROM public.examination_sessions
    WHERE id = NEW.examination_session_id;

    SELECT examination_paper_id
    INTO v_candidate_paper
    FROM public.examination_candidates
    WHERE id = NEW.examination_candidate_id;

    IF v_session_paper IS NULL
       OR v_candidate_paper IS NULL THEN
        RAISE EXCEPTION
            'Invalid examination attendance session or candidate';
    END IF;

    IF v_session_paper <> v_candidate_paper THEN
        RAISE EXCEPTION
            'Examination attendance candidate does not belong to this session paper';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.examination_candidate_sessions ecs
        WHERE ecs.examination_session_id = NEW.examination_session_id
          AND ecs.examination_candidate_id = NEW.examination_candidate_id
          AND ecs.assignment_status IN
              ('ASSIGNED','CONFIRMED','MOVED')
    ) THEN
        RAISE EXCEPTION
            'Candidate must be assigned to the examination session before attendance can be recorded';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_examination_attendance
ON public.examination_attendance;

CREATE TRIGGER trg_validate_examination_attendance
BEFORE INSERT OR UPDATE
ON public.examination_attendance
FOR EACH ROW
EXECUTE FUNCTION public.validate_examination_attendance();


-- ============================================================
-- 8. EXAMINATION SESSION CAPACITY MUST MATCH ROOM CAPACITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_examination_session_capacity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_capacity integer;
BEGIN

    SELECT capacity
    INTO v_room_capacity
    FROM public.rooms
    WHERE id = NEW.room_id;

    IF v_room_capacity IS NULL THEN
        RAISE EXCEPTION
            'Examination session room does not exist';
    END IF;

    IF NEW.capacity IS NULL
       OR NEW.capacity <= 0 THEN
        RAISE EXCEPTION
            'Examination session capacity must be greater than zero';
    END IF;

    IF NEW.capacity > v_room_capacity THEN
        RAISE EXCEPTION
            'Examination session capacity (%) cannot exceed room capacity (%)',
            NEW.capacity,
            v_room_capacity;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_examination_session_capacity
ON public.examination_sessions;

CREATE TRIGGER trg_validate_examination_session_capacity
BEFORE INSERT OR UPDATE
ON public.examination_sessions
FOR EACH ROW
EXECUTE FUNCTION public.validate_examination_session_capacity();


-- ============================================================
-- 9. INVIGILATOR OVERLAP PROTECTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_examination_invigilator_conflict()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_start timestamptz;
    v_end timestamptz;
    v_conflict integer;
BEGIN

    SELECT start_at, end_at
    INTO v_start, v_end
    FROM public.examination_sessions
    WHERE id = NEW.examination_session_id;

    IF v_start IS NULL OR v_end IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT COUNT(*)
    INTO v_conflict
    FROM public.examination_invigilators ei
    JOIN public.examination_sessions es
        ON es.id = ei.examination_session_id
    WHERE ei.user_id = NEW.user_id
      AND ei.status IN ('ASSIGNED','CONFIRMED')
      AND es.status NOT IN ('CANCELLED','COMPLETED','LOCKED')
      AND es.start_at < v_end
      AND es.end_at > v_start
      AND ei.id <> COALESCE(NEW.id, gen_random_uuid());

    IF v_conflict > 0 THEN
        RAISE EXCEPTION
            'Invigilator is already assigned to another overlapping examination session';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_examination_invigilator_conflict
ON public.examination_invigilators;

CREATE TRIGGER trg_validate_examination_invigilator_conflict
BEFORE INSERT OR UPDATE
ON public.examination_invigilators
FOR EACH ROW
EXECUTE FUNCTION public.validate_examination_invigilator_conflict();


-- ============================================================
-- 10. LOCKED EXAMINATION PAPER PROTECTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_locked_examination_paper_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.status = 'LOCKED' THEN

        IF NEW.status <> OLD.status
           OR NEW.examination_period_id <> OLD.examination_period_id
           OR NEW.course_offering_id <> OLD.course_offering_id
           OR NEW.paper_code <> OLD.paper_code
           OR NEW.max_marks <> OLD.max_marks
           OR NEW.duration_minutes <> OLD.duration_minutes THEN

            RAISE EXCEPTION
                'Locked examination paper cannot be modified';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_locked_examination_paper_change
ON public.examination_papers;

CREATE TRIGGER trg_prevent_locked_examination_paper_change
BEFORE UPDATE
ON public.examination_papers
FOR EACH ROW
EXECUTE FUNCTION public.prevent_locked_examination_paper_change();


-- ============================================================
-- 11. LOCKED EXAMINATION SESSION PROTECTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_locked_examination_session_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.status = 'LOCKED' THEN
        IF NEW.status <> OLD.status
           OR NEW.examination_paper_id <> OLD.examination_paper_id
           OR NEW.room_id <> OLD.room_id
           OR NEW.start_at <> OLD.start_at
           OR NEW.end_at <> OLD.end_at THEN

            RAISE EXCEPTION
                'Locked examination session cannot be modified';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_locked_examination_session_change
ON public.examination_sessions;

CREATE TRIGGER trg_prevent_locked_examination_session_change
BEFORE UPDATE
ON public.examination_sessions
FOR EACH ROW
EXECUTE FUNCTION public.prevent_locked_examination_session_change();


-- ============================================================
-- 12. EXAMINATION MARK CORRECTION WORKFLOW
-- ============================================================

CREATE TABLE IF NOT EXISTS public.examination_mark_corrections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    examination_mark_id uuid NOT NULL
        REFERENCES public.examination_marks(id)
        ON DELETE RESTRICT,

    requested_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    requested_at timestamptz NOT NULL DEFAULT now(),

    old_marks numeric(8,2) NOT NULL,
    new_marks numeric(8,2) NOT NULL,

    old_grade varchar(10),
    new_grade varchar(10),

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

    reviewed_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    reviewed_at timestamptz,
    review_comment text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS
uq_pending_examination_mark_correction
ON public.examination_mark_corrections(examination_mark_id)
WHERE status = 'PENDING';


-- ============================================================
-- 13. VALIDATE EXAMINATION MARK CORRECTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_examination_mark_correction()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_marks numeric(8,2);
    v_max_marks numeric(8,2);
    v_mark_status varchar;
BEGIN

    SELECT
        em.marks,
        ep.max_marks,
        em.status
    INTO
        v_current_marks,
        v_max_marks,
        v_mark_status
    FROM public.examination_marks em
    JOIN public.examination_papers ep
        ON ep.id = em.examination_paper_id
    WHERE em.id = NEW.examination_mark_id;

    IF v_current_marks IS NULL THEN
        RAISE EXCEPTION
            'Examination mark does not exist';
    END IF;

    IF v_mark_status NOT IN
        ('APPROVED','LOCKED','CORRECTION_PENDING') THEN

        RAISE EXCEPTION
            'Examination mark is not eligible for correction workflow';
    END IF;

    IF NEW.old_marks <> v_current_marks THEN
        RAISE EXCEPTION
            'Correction old_marks does not match the current examination mark';
    END IF;

    IF NEW.new_marks < 0
       OR NEW.new_marks > v_max_marks THEN
        RAISE EXCEPTION
            'New examination marks must be between 0 and the paper maximum marks';
    END IF;

    IF trim(COALESCE(NEW.reason,'')) = '' THEN
        RAISE EXCEPTION
            'Correction reason is required';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_examination_mark_correction
ON public.examination_mark_corrections;

CREATE TRIGGER trg_validate_examination_mark_correction
BEFORE INSERT OR UPDATE
ON public.examination_mark_corrections
FOR EACH ROW
EXECUTE FUNCTION public.validate_examination_mark_correction();


-- ============================================================
-- 14. PREVENT DIRECT MODIFICATION OF LOCKED EXAM MARKS
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_locked_examination_mark_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.status = 'LOCKED' THEN

        IF NEW.marks <> OLD.marks
           OR NEW.grade <> OLD.grade
           OR NEW.percentage <> OLD.percentage
           OR NEW.student_id <> OLD.student_id
           OR NEW.course_registration_id <> OLD.course_registration_id
           OR NEW.examination_paper_id <> OLD.examination_paper_id THEN

            RAISE EXCEPTION
                'Locked examination mark cannot be directly modified. Use examination mark correction workflow.';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_locked_examination_mark_change
ON public.examination_marks;

CREATE TRIGGER trg_prevent_locked_examination_mark_change
BEFORE UPDATE
ON public.examination_marks
FOR EACH ROW
EXECUTE FUNCTION public.prevent_locked_examination_mark_change();


-- ============================================================
-- 15. PREVENT DELETE OF EXAMINATION MARKS
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_examination_mark_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    RAISE EXCEPTION
        'Examination marks cannot be deleted. Use the formal correction workflow.';
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_examination_mark_delete
ON public.examination_marks;

CREATE TRIGGER trg_prevent_examination_mark_delete
BEFORE DELETE
ON public.examination_marks
FOR EACH ROW
EXECUTE FUNCTION public.prevent_examination_mark_delete();


-- ============================================================
-- 16. PREVENT REVIEWED CORRECTION FROM BEING MODIFIED
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_reviewed_examination_correction_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.status IN ('APPROVED','REJECTED','CANCELLED') THEN

        IF NEW.status <> OLD.status
           OR NEW.old_marks <> OLD.old_marks
           OR NEW.new_marks <> OLD.new_marks
           OR NEW.old_grade IS DISTINCT FROM OLD.old_grade
           OR NEW.new_grade IS DISTINCT FROM OLD.new_grade
           OR NEW.reason <> OLD.reason THEN

            RAISE EXCEPTION
                'Reviewed examination mark correction cannot be modified';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_reviewed_examination_correction_change
ON public.examination_mark_corrections;

CREATE TRIGGER trg_prevent_reviewed_examination_correction_change
BEFORE UPDATE
ON public.examination_mark_corrections
FOR EACH ROW
EXECUTE FUNCTION public.prevent_reviewed_examination_correction_change();


-- ============================================================
-- 17. UPDATED_AT TRIGGERS
-- ============================================================

DROP TRIGGER IF EXISTS trg_examination_candidate_sessions_updated_at
ON public.examination_candidate_sessions;

CREATE TRIGGER trg_examination_candidate_sessions_updated_at
BEFORE UPDATE
ON public.examination_candidate_sessions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_examination_mark_corrections_updated_at
ON public.examination_mark_corrections;

CREATE TRIGGER trg_examination_mark_corrections_updated_at
BEFORE UPDATE
ON public.examination_mark_corrections
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 18. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS
idx_exam_candidate_sessions_session
ON public.examination_candidate_sessions(examination_session_id);

CREATE INDEX IF NOT EXISTS
idx_exam_candidate_sessions_candidate
ON public.examination_candidate_sessions(examination_candidate_id);

CREATE INDEX IF NOT EXISTS
idx_exam_attendance_session_candidate
ON public.examination_attendance(
    examination_session_id,
    examination_candidate_id
);

CREATE INDEX IF NOT EXISTS
idx_exam_invigilators_user
ON public.examination_invigilators(user_id);

CREATE INDEX IF NOT EXISTS
idx_exam_marks_student
ON public.examination_marks(student_id);

CREATE INDEX IF NOT EXISTS
idx_exam_marks_paper
ON public.examination_marks(examination_paper_id);

CREATE INDEX IF NOT EXISTS
idx_exam_mark_corrections_mark
ON public.examination_mark_corrections(examination_mark_id);


-- ============================================================
-- 19. RLS
-- ============================================================

ALTER TABLE public.examination_candidate_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.examination_mark_corrections ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 20. COMMENTS
-- ============================================================

COMMENT ON TABLE public.examination_candidate_sessions IS
'Controls examination room/session assignment and seating for each candidate.';

COMMENT ON TABLE public.examination_mark_corrections IS
'Formal approval workflow for correcting examination marks after submission/approval/locking.';


COMMIT;
