-- ============================================================
-- IDMC iMIS
-- Migration 010
-- ATTENDANCE CORE
-- ============================================================

BEGIN;

-- ============================================================
-- 1. ATTENDANCE SESSIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.attendance_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    class_id uuid NOT NULL
        REFERENCES public.classes(id),

    course_offering_id uuid NOT NULL
        REFERENCES public.course_offerings(id),

    timetable_entry_id uuid
        REFERENCES public.timetable_entries(id),

    session_date date NOT NULL,

    start_time time NOT NULL,

    end_time time NOT NULL,

    session_type varchar(30) NOT NULL DEFAULT 'LECTURE'
        CHECK (
            session_type IN (
                'LECTURE',
                'PRACTICAL',
                'TUTORIAL',
                'SEMINAR',
                'CLINICAL',
                'FIELD',
                'EXAM',
                'OTHER'
            )
        ),

    topic varchar(255),

    venue_room_id uuid
        REFERENCES public.rooms(id),

    conducted_by uuid
        REFERENCES public.users(id),

    status varchar(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (
            status IN (
                'DRAFT',
                'OPEN',
                'SUBMITTED',
                'LOCKED',
                'CANCELLED'
            )
        ),

    opened_at timestamptz,

    submitted_at timestamptz,

    locked_at timestamptz,

    locked_by uuid
        REFERENCES public.users(id),

    notes text,

    created_by uuid
        REFERENCES public.users(id),

    updated_by uuid
        REFERENCES public.users(id),

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT attendance_sessions_time_valid
        CHECK (end_time > start_time),

    CONSTRAINT attendance_sessions_date_valid
        CHECK (session_date IS NOT NULL)
);


-- ============================================================
-- 2. ATTENDANCE RECORDS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.attendance_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    attendance_session_id uuid NOT NULL
        REFERENCES public.attendance_sessions(id)
        ON DELETE CASCADE,

    student_id uuid NOT NULL
        REFERENCES public.students(id),

    course_registration_id uuid
        REFERENCES public.course_registrations(id),

    attendance_status varchar(20) NOT NULL DEFAULT 'ABSENT'
        CHECK (
            attendance_status IN (
                'PRESENT',
                'ABSENT',
                'LATE',
                'EXCUSED'
            )
        ),

    check_in_time timestamptz,

    minutes_late integer NOT NULL DEFAULT 0
        CHECK (minutes_late >= 0),

    remarks text,

    marked_by uuid
        REFERENCES public.users(id),

    marked_at timestamptz,

    correction_required boolean NOT NULL DEFAULT false,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT attendance_records_unique_student_session
        UNIQUE (attendance_session_id, student_id)
);


-- ============================================================
-- 3. ATTENDANCE CORRECTIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.attendance_corrections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    attendance_record_id uuid NOT NULL
        REFERENCES public.attendance_records(id)
        ON DELETE CASCADE,

    requested_by uuid NOT NULL
        REFERENCES public.users(id),

    requested_at timestamptz NOT NULL DEFAULT now(),

    old_status varchar(20),

    new_status varchar(20),

    old_check_in_time timestamptz,

    new_check_in_time timestamptz,

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
        REFERENCES public.users(id),

    reviewed_at timestamptz,

    review_comment text,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT attendance_corrections_reason_required
        CHECK (length(trim(reason)) >= 5)
);


-- ============================================================
-- 4. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_attendance_sessions_class_date
ON public.attendance_sessions (
    class_id,
    session_date
);

CREATE INDEX IF NOT EXISTS idx_attendance_sessions_course_date
ON public.attendance_sessions (
    course_offering_id,
    session_date
);

CREATE INDEX IF NOT EXISTS idx_attendance_sessions_status
ON public.attendance_sessions (
    status
);

CREATE INDEX IF NOT EXISTS idx_attendance_records_session
ON public.attendance_records (
    attendance_session_id
);

CREATE INDEX IF NOT EXISTS idx_attendance_records_student
ON public.attendance_records (
    student_id
);

CREATE INDEX IF NOT EXISTS idx_attendance_records_student_status
ON public.attendance_records (
    student_id,
    attendance_status
);

CREATE INDEX IF NOT EXISTS idx_attendance_corrections_record
ON public.attendance_corrections (
    attendance_record_id
);

CREATE INDEX IF NOT EXISTS idx_attendance_corrections_status
ON public.attendance_corrections (
    status
);


-- ============================================================
-- 5. VALIDATE SESSION CLASS / COURSE OFFERING
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_attendance_session_consistency()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_class_offering_id uuid;
BEGIN
    SELECT course_offering_id
    INTO v_class_offering_id
    FROM public.classes
    WHERE id = NEW.class_id;

    IF v_class_offering_id IS NULL THEN
        RAISE EXCEPTION
            'Class % does not exist or has no course offering',
            NEW.class_id;
    END IF;

    IF v_class_offering_id <> NEW.course_offering_id THEN
        RAISE EXCEPTION
            'Attendance session course offering does not match class course offering';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_attendance_session_consistency
ON public.attendance_sessions;

CREATE TRIGGER trg_validate_attendance_session_consistency
BEFORE INSERT OR UPDATE OF class_id, course_offering_id
ON public.attendance_sessions
FOR EACH ROW
EXECUTE FUNCTION public.validate_attendance_session_consistency();


-- ============================================================
-- 6. VALIDATE TIMETABLE ENTRY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_attendance_timetable_entry()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_class_id uuid;
    v_course_offering_id uuid;
BEGIN
    IF NEW.timetable_entry_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT
        class_id,
        course_offering_id
    INTO
        v_class_id,
        v_course_offering_id
    FROM public.timetable_entries
    WHERE id = NEW.timetable_entry_id;

    IF v_class_id IS NULL THEN
        RAISE EXCEPTION
            'Timetable entry % does not exist',
            NEW.timetable_entry_id;
    END IF;

    IF v_class_id <> NEW.class_id THEN
        RAISE EXCEPTION
            'Timetable entry class does not match attendance session class';
    END IF;

    IF v_course_offering_id <> NEW.course_offering_id THEN
        RAISE EXCEPTION
            'Timetable entry course offering does not match attendance session course offering';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_attendance_timetable_entry
ON public.attendance_sessions;

CREATE TRIGGER trg_validate_attendance_timetable_entry
BEFORE INSERT OR UPDATE OF timetable_entry_id, class_id, course_offering_id
ON public.attendance_sessions
FOR EACH ROW
EXECUTE FUNCTION public.validate_attendance_timetable_entry();


-- ============================================================
-- 7. VALIDATE ATTENDANCE RECORD STUDENT
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_attendance_record_student()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_class_id uuid;
    v_session_offering_id uuid;
    v_registered_offering_id uuid;
    v_registered_student_id uuid;
BEGIN
    SELECT
        class_id,
        course_offering_id
    INTO
        v_session_class_id,
        v_session_offering_id
    FROM public.attendance_sessions
    WHERE id = NEW.attendance_session_id;

    IF v_session_class_id IS NULL THEN
        RAISE EXCEPTION
            'Attendance session % does not exist',
            NEW.attendance_session_id;
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
                'Attendance student does not match course registration student';
        END IF;

        IF v_registered_offering_id <> v_session_offering_id THEN
            RAISE EXCEPTION
                'Attendance course registration does not match session course offering';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_attendance_record_student
ON public.attendance_records;

CREATE TRIGGER trg_validate_attendance_record_student
BEFORE INSERT OR UPDATE OF
    attendance_session_id,
    student_id,
    course_registration_id
ON public.attendance_records
FOR EACH ROW
EXECUTE FUNCTION public.validate_attendance_record_student();


-- ============================================================
-- 8. PREVENT MODIFICATION AFTER LOCK
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_locked_attendance_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_status varchar;
BEGIN
    SELECT status
    INTO v_status
    FROM public.attendance_sessions
    WHERE id = COALESCE(
        NEW.attendance_session_id,
        OLD.attendance_session_id
    );

    IF v_status = 'LOCKED' THEN
        RAISE EXCEPTION
            'Attendance session % is LOCKED and cannot be modified',
            COALESCE(
                NEW.attendance_session_id,
                OLD.attendance_session_id
            );
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;


DROP TRIGGER IF EXISTS trg_prevent_locked_attendance_change
ON public.attendance_records;

CREATE TRIGGER trg_prevent_locked_attendance_change
BEFORE INSERT OR UPDATE OR DELETE
ON public.attendance_records
FOR EACH ROW
EXECUTE FUNCTION public.prevent_locked_attendance_change();


-- ============================================================
-- 9. ATTENDANCE SESSION STATUS TRANSITIONS
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_attendance_status_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.status = 'LOCKED'
       AND NEW.status <> 'LOCKED' THEN

        RAISE EXCEPTION
            'Locked attendance session cannot be reopened';
    END IF;

    IF OLD.status = 'CANCELLED'
       AND NEW.status <> 'CANCELLED' THEN

        RAISE EXCEPTION
            'Cancelled attendance session cannot be reopened';
    END IF;

    IF NEW.status = 'OPEN'
       AND OLD.status NOT IN ('DRAFT', 'OPEN') THEN

        RAISE EXCEPTION
            'Invalid attendance status transition from % to %',
            OLD.status,
            NEW.status;
    END IF;

    IF NEW.status = 'SUBMITTED'
       AND OLD.status NOT IN ('OPEN', 'SUBMITTED') THEN

        RAISE EXCEPTION
            'Attendance must be OPEN before submission';
    END IF;

    IF NEW.status = 'LOCKED'
       AND OLD.status NOT IN ('SUBMITTED', 'LOCKED') THEN

        RAISE EXCEPTION
            'Attendance must be SUBMITTED before locking';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_attendance_status_transition
ON public.attendance_sessions;

CREATE TRIGGER trg_validate_attendance_status_transition
BEFORE UPDATE OF status
ON public.attendance_sessions
FOR EACH ROW
EXECUTE FUNCTION public.validate_attendance_status_transition();


-- ============================================================
-- 10. AUTOMATIC TIMESTAMPS FOR STATUS EVENTS
-- ============================================================

CREATE OR REPLACE FUNCTION public.sync_attendance_session_timestamps()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.status = 'OPEN'
       AND OLD.status <> 'OPEN'
       AND NEW.opened_at IS NULL THEN

        NEW.opened_at := now();
    END IF;

    IF NEW.status = 'SUBMITTED'
       AND OLD.status <> 'SUBMITTED'
       AND NEW.submitted_at IS NULL THEN

        NEW.submitted_at := now();
    END IF;

    IF NEW.status = 'LOCKED'
       AND OLD.status <> 'LOCKED'
       AND NEW.locked_at IS NULL THEN

        NEW.locked_at := now();
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_sync_attendance_session_timestamps
ON public.attendance_sessions;

CREATE TRIGGER trg_sync_attendance_session_timestamps
BEFORE UPDATE OF status
ON public.attendance_sessions
FOR EACH ROW
EXECUTE FUNCTION public.sync_attendance_session_timestamps();


-- ============================================================
-- 11. VALIDATE ATTENDANCE STATUS / CHECK-IN
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_attendance_record_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.attendance_status = 'PRESENT'
       AND NEW.check_in_time IS NULL THEN

        NEW.minutes_late := 0;
    END IF;

    IF NEW.attendance_status = 'ABSENT' THEN

        NEW.check_in_time := NULL;
        NEW.minutes_late := 0;
    END IF;

    IF NEW.attendance_status = 'EXCUSED' THEN

        NEW.minutes_late := 0;
    END IF;

    IF NEW.attendance_status = 'LATE'
       AND NEW.minutes_late <= 0 THEN

        RAISE EXCEPTION
            'LATE attendance must have minutes_late greater than zero';
    END IF;

    NEW.marked_at := COALESCE(NEW.marked_at, now());

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_attendance_record_status
ON public.attendance_records;

CREATE TRIGGER trg_validate_attendance_record_status
BEFORE INSERT OR UPDATE OF
    attendance_status,
    check_in_time,
    minutes_late
ON public.attendance_records
FOR EACH ROW
EXECUTE FUNCTION public.validate_attendance_record_status();


-- ============================================================
-- 12. UPDATED_AT TRIGGERS
-- ============================================================

DROP TRIGGER IF EXISTS trg_attendance_sessions_updated_at
ON public.attendance_sessions;

CREATE TRIGGER trg_attendance_sessions_updated_at
BEFORE UPDATE ON public.attendance_sessions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_attendance_records_updated_at
ON public.attendance_records;

CREATE TRIGGER trg_attendance_records_updated_at
BEFORE UPDATE ON public.attendance_records
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_attendance_corrections_updated_at
ON public.attendance_corrections;

CREATE TRIGGER trg_attendance_corrections_updated_at
BEFORE UPDATE ON public.attendance_corrections
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 13. RLS
-- ============================================================

ALTER TABLE public.attendance_sessions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.attendance_corrections ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 14. COMMENTS
-- ============================================================

COMMENT ON TABLE public.attendance_sessions IS
'Attendance session master records for scheduled academic teaching activities.';

COMMENT ON TABLE public.attendance_records IS
'Student-level attendance records for each attendance session.';

COMMENT ON TABLE public.attendance_corrections IS
'Controlled workflow for correcting attendance after submission or locking.';


COMMIT;
