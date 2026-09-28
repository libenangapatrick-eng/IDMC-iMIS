-- ============================================================
-- IDMC iMIS
-- Migration: 202609150009
-- Examination Core
-- ============================================================

-- ============================================================
-- 1. EXAMINATION PERIODS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.examination_periods (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    academic_year_id uuid NOT NULL
        REFERENCES public.academic_years(id)
        ON DELETE RESTRICT,

    semester_id uuid NOT NULL
        REFERENCES public.semesters(id)
        ON DELETE RESTRICT,

    period_code varchar(50) NOT NULL,
    period_name varchar(150) NOT NULL,

    examination_type varchar(30) NOT NULL DEFAULT 'END_OF_SEMESTER'
        CHECK (
            examination_type IN (
                'END_OF_SEMESTER',
                'MID_SEMESTER',
                'SUPPLEMENTARY',
                'SPECIAL',
                'RESIT',
                'MAKEUP',
                'OTHER'
            )
        ),

    start_date date NOT NULL,
    end_date date NOT NULL,

    status varchar(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (
            status IN (
                'DRAFT',
                'PLANNING',
                'APPROVED',
                'PUBLISHED',
                'ONGOING',
                'COMPLETED',
                'LOCKED',
                'CANCELLED'
            )
        ),

    approved_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    approved_at timestamptz,

    published_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    published_at timestamptz,

    locked_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    locked_at timestamptz,

    notes text,

    created_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    updated_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT examination_period_dates_chk
        CHECK (end_date >= start_date),

    CONSTRAINT examination_period_code_uq
        UNIQUE (period_code)
);

CREATE INDEX IF NOT EXISTS idx_examination_periods_academic_year
ON public.examination_periods(academic_year_id);

CREATE INDEX IF NOT EXISTS idx_examination_periods_semester
ON public.examination_periods(semester_id);

CREATE INDEX IF NOT EXISTS idx_examination_periods_status
ON public.examination_periods(status);


-- ============================================================
-- 2. EXAMINATION PAPERS / COURSE EXAMS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.examination_papers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    examination_period_id uuid NOT NULL
        REFERENCES public.examination_periods(id)
        ON DELETE RESTRICT,

    course_offering_id uuid NOT NULL
        REFERENCES public.course_offerings(id)
        ON DELETE RESTRICT,

    paper_code varchar(80) NOT NULL,
    paper_title varchar(200) NOT NULL,

    examination_type varchar(30) NOT NULL DEFAULT 'FINAL'
        CHECK (
            examination_type IN (
                'FINAL',
                'SUPPLEMENTARY',
                'SPECIAL',
                'RESIT',
                'MAKEUP'
            )
        ),

    maximum_marks numeric(8,2) NOT NULL DEFAULT 100
        CHECK (maximum_marks > 0),

    duration_minutes integer NOT NULL
        CHECK (duration_minutes > 0),

    instructions text,

    status varchar(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (
            status IN (
                'DRAFT',
                'SCHEDULED',
                'APPROVED',
                'PUBLISHED',
                'COMPLETED',
                'LOCKED',
                'CANCELLED'
            )
        ),

    created_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    updated_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    approved_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    approved_at timestamptz,

    locked_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    locked_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT examination_paper_code_uq
        UNIQUE (examination_period_id, paper_code)
);

CREATE INDEX IF NOT EXISTS idx_examination_papers_period
ON public.examination_papers(examination_period_id);

CREATE INDEX IF NOT EXISTS idx_examination_papers_offering
ON public.examination_papers(course_offering_id);

CREATE INDEX IF NOT EXISTS idx_examination_papers_status
ON public.examination_papers(status);


-- ============================================================
-- 3. EXAMINATION CANDIDATES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.examination_candidates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    examination_paper_id uuid NOT NULL
        REFERENCES public.examination_papers(id)
        ON DELETE RESTRICT,

    student_id uuid NOT NULL
        REFERENCES public.students(id)
        ON DELETE RESTRICT,

    course_registration_id uuid NOT NULL
        REFERENCES public.course_registrations(id)
        ON DELETE RESTRICT,

    candidate_number varchar(80),

    eligibility_status varchar(30) NOT NULL DEFAULT 'PENDING'
        CHECK (
            eligibility_status IN (
                'PENDING',
                'ELIGIBLE',
                'INELIGIBLE',
                'WITHHELD'
            )
        ),

    eligibility_reason text,

    attendance_status varchar(30) NOT NULL DEFAULT 'NOT_MARKED'
        CHECK (
            attendance_status IN (
                'NOT_MARKED',
                'PRESENT',
                'ABSENT',
                'LATE',
                'EXCUSED'
            )
        ),

    candidate_status varchar(30) NOT NULL DEFAULT 'ACTIVE'
        CHECK (
            candidate_status IN (
                'ACTIVE',
                'WITHDRAWN',
                'DEFERRED',
                'DISQUALIFIED',
                'CANCELLED'
            )
        ),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT examination_candidate_uq
        UNIQUE (examination_paper_id, student_id)
);

CREATE INDEX IF NOT EXISTS idx_examination_candidates_paper
ON public.examination_candidates(examination_paper_id);

CREATE INDEX IF NOT EXISTS idx_examination_candidates_student
ON public.examination_candidates(student_id);

CREATE INDEX IF NOT EXISTS idx_examination_candidates_registration
ON public.examination_candidates(course_registration_id);

CREATE INDEX IF NOT EXISTS idx_examination_candidates_status
ON public.examination_candidates(eligibility_status);


-- ============================================================
-- 4. EXAMINATION SESSIONS / TIMETABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS public.examination_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    examination_paper_id uuid NOT NULL
        REFERENCES public.examination_papers(id)
        ON DELETE RESTRICT,

    campus_id uuid NOT NULL
        REFERENCES public.campuses(id)
        ON DELETE RESTRICT,

    room_id uuid NOT NULL
        REFERENCES public.rooms(id)
        ON DELETE RESTRICT,

    examination_date date NOT NULL,

    start_time time NOT NULL,
    end_time time NOT NULL,

    session_code varchar(80) NOT NULL,

    capacity integer NOT NULL
        CHECK (capacity > 0),

    status varchar(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (
            status IN (
                'DRAFT',
                'SCHEDULED',
                'APPROVED',
                'PUBLISHED',
                'ONGOING',
                'COMPLETED',
                'LOCKED',
                'CANCELLED'
            )
        ),

    created_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    updated_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    approved_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    approved_at timestamptz,

    locked_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    locked_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT examination_session_time_chk
        CHECK (end_time > start_time),

    CONSTRAINT examination_session_code_uq
        UNIQUE (session_code)
);

CREATE INDEX IF NOT EXISTS idx_examination_sessions_paper
ON public.examination_sessions(examination_paper_id);

CREATE INDEX IF NOT EXISTS idx_examination_sessions_room
ON public.examination_sessions(room_id);

CREATE INDEX IF NOT EXISTS idx_examination_sessions_date
ON public.examination_sessions(examination_date);


-- ============================================================
-- 5. EXAMINATION INVIGILATORS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.examination_invigilators (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    examination_session_id uuid NOT NULL
        REFERENCES public.examination_sessions(id)
        ON DELETE RESTRICT,

    user_id uuid NOT NULL
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    assignment_role varchar(30) NOT NULL DEFAULT 'INVIGILATOR'
        CHECK (
            assignment_role IN (
                'CHIEF_INVIGILATOR',
                'INVIGILATOR',
                'RELIEF_INVIGILATOR',
                'SUPERVISOR'
            )
        ),

    status varchar(30) NOT NULL DEFAULT 'ASSIGNED'
        CHECK (
            status IN (
                'ASSIGNED',
                'CONFIRMED',
                'DECLINED',
                'COMPLETED',
                'CANCELLED'
            )
        ),

    assigned_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    assigned_at timestamptz NOT NULL DEFAULT now(),

    confirmed_at timestamptz,

    notes text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT examination_invigilator_uq
        UNIQUE (examination_session_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_examination_invigilators_session
ON public.examination_invigilators(examination_session_id);

CREATE INDEX IF NOT EXISTS idx_examination_invigilators_user
ON public.examination_invigilators(user_id);


-- ============================================================
-- 6. EXAMINATION ATTENDANCE
-- ============================================================

CREATE TABLE IF NOT EXISTS public.examination_attendance (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    examination_session_id uuid NOT NULL
        REFERENCES public.examination_sessions(id)
        ON DELETE RESTRICT,

    examination_candidate_id uuid NOT NULL
        REFERENCES public.examination_candidates(id)
        ON DELETE RESTRICT,

    attendance_status varchar(30) NOT NULL DEFAULT 'PRESENT'
        CHECK (
            attendance_status IN (
                'PRESENT',
                'ABSENT',
                'LATE',
                'EXCUSED'
            )
        ),

    check_in_time timestamptz,

    seat_number varchar(30),

    identity_verified boolean NOT NULL DEFAULT false,

    remarks text,

    marked_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    marked_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT examination_attendance_uq
        UNIQUE (examination_session_id, examination_candidate_id)
);

CREATE INDEX IF NOT EXISTS idx_examination_attendance_session
ON public.examination_attendance(examination_session_id);

CREATE INDEX IF NOT EXISTS idx_examination_attendance_candidate
ON public.examination_attendance(examination_candidate_id);


-- ============================================================
-- 7. EXAMINATION MARKS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.examination_marks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    examination_paper_id uuid NOT NULL
        REFERENCES public.examination_papers(id)
        ON DELETE RESTRICT,

    examination_candidate_id uuid NOT NULL
        REFERENCES public.examination_candidates(id)
        ON DELETE RESTRICT,

    student_id uuid NOT NULL
        REFERENCES public.students(id)
        ON DELETE RESTRICT,

    course_registration_id uuid NOT NULL
        REFERENCES public.course_registrations(id)
        ON DELETE RESTRICT,

    marks numeric(8,2)
        CHECK (marks >= 0),

    percentage numeric(8,4),

    grade varchar(20),

    remarks text,

    status varchar(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (
            status IN (
                'DRAFT',
                'SUBMITTED',
                'UNDER_REVIEW',
                'APPROVED',
                'LOCKED',
                'CORRECTION_PENDING'
            )
        ),

    entered_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    entered_at timestamptz,

    submitted_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    submitted_at timestamptz,

    approved_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    approved_at timestamptz,

    locked_by uuid
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    locked_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT examination_mark_uq
        UNIQUE (examination_paper_id, examination_candidate_id)
);

CREATE INDEX IF NOT EXISTS idx_examination_marks_paper
ON public.examination_marks(examination_paper_id);

CREATE INDEX IF NOT EXISTS idx_examination_marks_candidate
ON public.examination_marks(examination_candidate_id);

CREATE INDEX IF NOT EXISTS idx_examination_marks_student
ON public.examination_marks(student_id);

CREATE INDEX IF NOT EXISTS idx_examination_marks_registration
ON public.examination_marks(course_registration_id);

CREATE INDEX IF NOT EXISTS idx_examination_marks_status
ON public.examination_marks(status);


-- ============================================================
-- 8. VALIDATE EXAMINATION CANDIDATE
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_examination_candidate()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_registration_student uuid;
    v_registration_offering uuid;
    v_paper_offering uuid;
BEGIN

    SELECT
        cr.student_registration_id,
        sr.student_id,
        cr.course_offering_id
    INTO
        v_registration_student,
        v_registration_student,
        v_registration_offering
    FROM public.course_registrations cr
    JOIN public.student_registrations sr
        ON sr.id = cr.student_registration_id
    WHERE cr.id = NEW.course_registration_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Examination candidate requires a valid course registration.';
    END IF;

    SELECT course_offering_id
    INTO v_paper_offering
    FROM public.examination_papers
    WHERE id = NEW.examination_paper_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Examination paper does not exist.';
    END IF;

    IF NEW.student_id <> v_registration_student THEN
        RAISE EXCEPTION
            'Candidate student does not match course registration.';
    END IF;

    IF v_registration_offering <> v_paper_offering THEN
        RAISE EXCEPTION
            'Candidate course registration does not match examination paper course offering.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_examination_candidate
ON public.examination_candidates;

CREATE TRIGGER trg_validate_examination_candidate
BEFORE INSERT OR UPDATE
ON public.examination_candidates
FOR EACH ROW
EXECUTE FUNCTION public.validate_examination_candidate();


-- ============================================================
-- 9. VALIDATE EXAMINATION MARK
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_examination_mark()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_candidate_student uuid;
    v_candidate_registration uuid;
    v_candidate_paper uuid;
    v_maximum_marks numeric(8,2);
BEGIN

    SELECT
        student_id,
        course_registration_id,
        examination_paper_id
    INTO
        v_candidate_student,
        v_candidate_registration,
        v_candidate_paper
    FROM public.examination_candidates
    WHERE id = NEW.examination_candidate_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Examination candidate does not exist.';
    END IF;

    SELECT maximum_marks
    INTO v_maximum_marks
    FROM public.examination_papers
    WHERE id = NEW.examination_paper_id;

    IF NEW.student_id <> v_candidate_student THEN
        RAISE EXCEPTION
            'Examination mark student does not match candidate.';
    END IF;

    IF NEW.course_registration_id <> v_candidate_registration THEN
        RAISE EXCEPTION
            'Examination mark registration does not match candidate registration.';
    END IF;

    IF NEW.examination_paper_id <> v_candidate_paper THEN
        RAISE EXCEPTION
            'Examination mark paper does not match candidate paper.';
    END IF;

    IF NEW.marks IS NOT NULL THEN

        IF NEW.marks > v_maximum_marks THEN
            RAISE EXCEPTION
                'Examination marks cannot exceed maximum marks.';
        END IF;

        NEW.percentage :=
            ROUND(
                (NEW.marks / v_maximum_marks) * 100,
                4
            );

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_examination_mark
ON public.examination_marks;

CREATE TRIGGER trg_validate_examination_mark
BEFORE INSERT OR UPDATE
ON public.examination_marks
FOR EACH ROW
EXECUTE FUNCTION public.validate_examination_mark();


-- ============================================================
-- 10. VALIDATE EXAMINATION SESSION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_examination_session()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_paper_period uuid;
    v_period_start date;
    v_period_end date;
    v_room_campus uuid;
    v_room_capacity integer;
BEGIN

    SELECT
        ep.id,
        ep.start_date,
        ep.end_date
    INTO
        v_paper_period,
        v_period_start,
        v_period_end
    FROM public.examination_papers epaper
    JOIN public.examination_periods ep
        ON ep.id = epaper.examination_period_id
    WHERE epaper.id = NEW.examination_paper_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Examination paper or examination period does not exist.';
    END IF;

    IF NEW.examination_date < v_period_start
       OR NEW.examination_date > v_period_end THEN
        RAISE EXCEPTION
            'Examination session date must fall within the examination period.';
    END IF;

    SELECT campus_id, capacity
    INTO v_room_campus, v_room_capacity
    FROM public.rooms
    WHERE id = NEW.room_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Examination room does not exist.';
    END IF;

    IF v_room_campus <> NEW.campus_id THEN
        RAISE EXCEPTION
            'Examination room does not belong to the selected campus.';
    END IF;

    IF NEW.capacity > v_room_capacity THEN
        RAISE EXCEPTION
            'Examination session capacity cannot exceed room capacity.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_examination_session
ON public.examination_sessions;

CREATE TRIGGER trg_validate_examination_session
BEFORE INSERT OR UPDATE
ON public.examination_sessions
FOR EACH ROW
EXECUTE FUNCTION public.validate_examination_session();


-- ============================================================
-- 11. TIMETABLE ROOM CONFLICT
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_examination_room_conflict()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF EXISTS (
        SELECT 1
        FROM public.examination_sessions es
        WHERE es.room_id = NEW.room_id
          AND es.examination_date = NEW.examination_date
          AND es.id <> NEW.id
          AND es.status <> 'CANCELLED'
          AND NEW.start_time < es.end_time
          AND NEW.end_time > es.start_time
    ) THEN

        RAISE EXCEPTION
            'Examination room conflict detected for the selected date and time.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_examination_room_conflict
ON public.examination_sessions;

CREATE TRIGGER trg_validate_examination_room_conflict
BEFORE INSERT OR UPDATE
ON public.examination_sessions
FOR EACH ROW
EXECUTE FUNCTION public.validate_examination_room_conflict();


-- ============================================================
-- 12. PROTECT LOCKED EXAMINATION MARKS
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_locked_examination_mark_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.status = 'LOCKED' THEN

        IF NEW.marks IS DISTINCT FROM OLD.marks
           OR NEW.grade IS DISTINCT FROM OLD.grade
           OR NEW.percentage IS DISTINCT FROM OLD.percentage
           OR NEW.student_id IS DISTINCT FROM OLD.student_id
           OR NEW.course_registration_id IS DISTINCT FROM OLD.course_registration_id
           OR NEW.examination_candidate_id IS DISTINCT FROM OLD.examination_candidate_id THEN

            RAISE EXCEPTION
                'Locked examination marks cannot be modified directly. Use correction workflow.';
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
-- 13. UPDATED_AT TRIGGERS
-- ============================================================

DROP TRIGGER IF EXISTS trg_examination_periods_updated_at
ON public.examination_periods;

CREATE TRIGGER trg_examination_periods_updated_at
BEFORE UPDATE
ON public.examination_periods
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_examination_papers_updated_at
ON public.examination_papers;

CREATE TRIGGER trg_examination_papers_updated_at
BEFORE UPDATE
ON public.examination_papers
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_examination_candidates_updated_at
ON public.examination_candidates;

CREATE TRIGGER trg_examination_candidates_updated_at
BEFORE UPDATE
ON public.examination_candidates
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_examination_sessions_updated_at
ON public.examination_sessions;

CREATE TRIGGER trg_examination_sessions_updated_at
BEFORE UPDATE
ON public.examination_sessions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_examination_invigilators_updated_at
ON public.examination_invigilators;

CREATE TRIGGER trg_examination_invigilators_updated_at
BEFORE UPDATE
ON public.examination_invigilators
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_examination_attendance_updated_at
ON public.examination_attendance;

CREATE TRIGGER trg_examination_attendance_updated_at
BEFORE UPDATE
ON public.examination_attendance
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_examination_marks_updated_at
ON public.examination_marks;

CREATE TRIGGER trg_examination_marks_updated_at
BEFORE UPDATE
ON public.examination_marks
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 14. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE public.examination_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.examination_papers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.examination_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.examination_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.examination_invigilators ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.examination_attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.examination_marks ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 15. DOCUMENTATION
-- ============================================================

COMMENT ON TABLE public.examination_periods IS
'Controls examination periods for academic semesters and examination cycles.';

COMMENT ON TABLE public.examination_papers IS
'Defines examination papers linked to course offerings.';

COMMENT ON TABLE public.examination_candidates IS
'Stores students eligible to sit specific examination papers.';

COMMENT ON TABLE public.examination_sessions IS
'Stores examination timetable sessions, rooms, dates and times.';

COMMENT ON TABLE public.examination_invigilators IS
'Stores invigilator assignments for examination sessions.';

COMMENT ON TABLE public.examination_attendance IS
'Stores candidate attendance during examination sessions.';

COMMENT ON TABLE public.examination_marks IS
'Stores examination marks prior to integration into the Results Engine.';


-- ============================================================
-- END OF MIGRATION
-- ============================================================
