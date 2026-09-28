-- ============================================================
-- IDMC iMIS
-- Migration 009
-- Timetable Integrity Hardening
-- ============================================================

BEGIN;

-- ============================================================
-- 1. ONE ACTIVE TIMETABLE PER
--    ACADEMIC YEAR + SEMESTER + CAMPUS
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_timetables_active_context
ON public.timetables (
    academic_year_id,
    semester_id,
    campus_id
)
WHERE status IN ('DRAFT', 'REVIEW', 'APPROVED', 'PUBLISHED', 'LOCKED');


-- ============================================================
-- 2. VALIDATE COURSE OFFERING / CLASS CONSISTENCY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_class_course_offering_consistency()
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
            'Class % does not have a valid course offering',
            NEW.class_id;
    END IF;

    IF v_class_offering_id <> NEW.course_offering_id THEN
        RAISE EXCEPTION
            'Timetable entry course offering does not match the class course offering';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_class_course_offering_consistency
ON public.timetable_entries;

CREATE TRIGGER trg_validate_class_course_offering_consistency
BEFORE INSERT OR UPDATE OF class_id, course_offering_id
ON public.timetable_entries
FOR EACH ROW
EXECUTE FUNCTION public.validate_class_course_offering_consistency();


-- ============================================================
-- 3. VALIDATE LECTURER ASSIGNMENT CONSISTENCY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_lecturer_assignment_consistency()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_assignment_offering_id uuid;
    v_assignment_class_id uuid;
BEGIN
    IF NEW.lecturer_assignment_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT
        course_offering_id,
        class_id
    INTO
        v_assignment_offering_id,
        v_assignment_class_id
    FROM public.lecturer_assignments
    WHERE id = NEW.lecturer_assignment_id;

    IF v_assignment_offering_id IS NULL THEN
        RAISE EXCEPTION
            'Lecturer assignment % does not exist',
            NEW.lecturer_assignment_id;
    END IF;

    IF v_assignment_offering_id <> NEW.course_offering_id THEN
        RAISE EXCEPTION
            'Lecturer assignment course offering does not match timetable entry course offering';
    END IF;

    IF v_assignment_class_id IS NOT NULL
       AND v_assignment_class_id <> NEW.class_id THEN
        RAISE EXCEPTION
            'Lecturer assignment class does not match timetable entry class';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_lecturer_assignment_consistency
ON public.timetable_entries;

CREATE TRIGGER trg_validate_lecturer_assignment_consistency
BEFORE INSERT OR UPDATE OF lecturer_assignment_id, class_id, course_offering_id
ON public.timetable_entries
FOR EACH ROW
EXECUTE FUNCTION public.validate_lecturer_assignment_consistency();


-- ============================================================
-- 4. ROOM CAPACITY MUST COVER CLASS CAPACITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_timetable_room_capacity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_capacity integer;
    v_class_capacity integer;
BEGIN
    SELECT capacity
    INTO v_room_capacity
    FROM public.rooms
    WHERE id = NEW.room_id;

    SELECT capacity
    INTO v_class_capacity
    FROM public.classes
    WHERE id = NEW.class_id;

    IF v_room_capacity IS NULL THEN
        RAISE EXCEPTION
            'Room % does not have a valid capacity',
            NEW.room_id;
    END IF;

    IF v_class_capacity IS NULL THEN
        RAISE EXCEPTION
            'Class % does not have a valid capacity',
            NEW.class_id;
    END IF;

    IF v_room_capacity < v_class_capacity THEN
        RAISE EXCEPTION
            'Room capacity (%) is smaller than class capacity (%)',
            v_room_capacity,
            v_class_capacity;
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_timetable_room_capacity
ON public.timetable_entries;

CREATE TRIGGER trg_validate_timetable_room_capacity
BEFORE INSERT OR UPDATE OF room_id, class_id
ON public.timetable_entries
FOR EACH ROW
EXECUTE FUNCTION public.validate_timetable_room_capacity();


-- ============================================================
-- 5. COURSE OFFERING CAPACITY MUST COVER CLASS CAPACITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_class_capacity_against_offering()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_offering_capacity integer;
BEGIN
    SELECT capacity
    INTO v_offering_capacity
    FROM public.course_offerings
    WHERE id = NEW.course_offering_id;

    IF v_offering_capacity IS NOT NULL
       AND NEW.capacity > v_offering_capacity THEN
        RAISE EXCEPTION
            'Class capacity (%) cannot exceed course offering capacity (%)',
            NEW.capacity,
            v_offering_capacity;
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_class_capacity_against_offering
ON public.classes;

CREATE TRIGGER trg_validate_class_capacity_against_offering
BEFORE INSERT OR UPDATE OF capacity, course_offering_id
ON public.classes
FOR EACH ROW
EXECUTE FUNCTION public.validate_class_capacity_against_offering();


-- ============================================================
-- 6. CLASS STUDENT COURSE CONSISTENCY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_class_student_registration()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_class_offering_id uuid;
    v_registration_offering_id uuid;
    v_registration_student_id uuid;
BEGIN
    SELECT course_offering_id
    INTO v_class_offering_id
    FROM public.classes
    WHERE id = NEW.class_id;

    SELECT
        cr.course_offering_id,
        sr.student_id
    INTO
        v_registration_offering_id,
        v_registration_student_id
    FROM public.course_registrations cr
    JOIN public.student_registrations sr
        ON sr.id = cr.student_registration_id
    WHERE cr.id = NEW.course_registration_id;

    IF v_class_offering_id IS NULL THEN
        RAISE EXCEPTION
            'Class % does not have a valid course offering',
            NEW.class_id;
    END IF;

    IF v_registration_offering_id IS NULL THEN
        RAISE EXCEPTION
            'Course registration % is invalid',
            NEW.course_registration_id;
    END IF;

    IF v_registration_offering_id <> v_class_offering_id THEN
        RAISE EXCEPTION
            'Student course registration does not match class course offering';
    END IF;

    IF v_registration_student_id <> NEW.student_id THEN
        RAISE EXCEPTION
            'Student does not match the student in course registration';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_class_student_registration
ON public.class_students;

CREATE TRIGGER trg_validate_class_student_registration
BEFORE INSERT OR UPDATE OF class_id, student_id, course_registration_id
ON public.class_students
FOR EACH ROW
EXECUTE FUNCTION public.validate_class_student_registration();


-- ============================================================
-- 7. CLASS CAPACITY ENFORCEMENT
--    Transaction-level advisory lock protects concurrent inserts
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_class_student_capacity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_class_capacity integer;
    v_current_count integer;
BEGIN
    PERFORM pg_advisory_xact_lock(
        hashtextextended(
            'IDMC_CLASS_CAPACITY:' || NEW.class_id::text,
            0
        )
    );

    SELECT capacity
    INTO v_class_capacity
    FROM public.classes
    WHERE id = NEW.class_id;

    SELECT COUNT(*)::integer
    INTO v_current_count
    FROM public.class_students
    WHERE class_id = NEW.class_id
      AND enrollment_status IN ('ACTIVE', 'ENROLLED');

    IF v_class_capacity IS NOT NULL
       AND v_current_count >= v_class_capacity THEN
        RAISE EXCEPTION
            'Class % has reached its capacity of % students',
            NEW.class_id,
            v_class_capacity;
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_class_student_capacity
ON public.class_students;

CREATE TRIGGER trg_validate_class_student_capacity
BEFORE INSERT
ON public.class_students
FOR EACH ROW
EXECUTE FUNCTION public.validate_class_student_capacity();


-- ============================================================
-- 8. CLASS CAPACITY MUST BE POSITIVE
-- ============================================================

ALTER TABLE public.classes
DROP CONSTRAINT IF EXISTS classes_capacity_positive;

ALTER TABLE public.classes
ADD CONSTRAINT classes_capacity_positive
CHECK (capacity IS NULL OR capacity > 0);


-- ============================================================
-- 9. ROOM CAPACITY MUST BE POSITIVE
-- ============================================================

ALTER TABLE public.rooms
DROP CONSTRAINT IF EXISTS rooms_capacity_positive;

ALTER TABLE public.rooms
ADD CONSTRAINT rooms_capacity_positive
CHECK (capacity IS NULL OR capacity > 0);


-- ============================================================
-- 10. TIMETABLE ENTRY MUST USE A VALID ROOM
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_timetable_room_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_status varchar;
BEGIN
    SELECT status
    INTO v_room_status
    FROM public.rooms
    WHERE id = NEW.room_id;

    IF v_room_status IS NULL THEN
        RAISE EXCEPTION
            'Room % does not exist',
            NEW.room_id;
    END IF;

    IF v_room_status NOT IN ('ACTIVE', 'AVAILABLE') THEN
        RAISE EXCEPTION
            'Room % is not available for timetable scheduling',
            NEW.room_id;
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_timetable_room_status
ON public.timetable_entries;

CREATE TRIGGER trg_validate_timetable_room_status
BEFORE INSERT OR UPDATE OF room_id
ON public.timetable_entries
FOR EACH ROW
EXECUTE FUNCTION public.validate_timetable_room_status();


-- ============================================================
-- 11. TIMETABLE ENTRY COURSE OFFERING MUST BE ACTIVE
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_timetable_course_offering_status()
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

    IF v_status NOT IN ('PLANNED', 'OPEN', 'ACTIVE') THEN
        RAISE EXCEPTION
            'Course offering % is not available for timetable scheduling',
            NEW.course_offering_id;
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_timetable_course_offering_status
ON public.timetable_entries;

CREATE TRIGGER trg_validate_timetable_course_offering_status
BEFORE INSERT OR UPDATE OF course_offering_id
ON public.timetable_entries
FOR EACH ROW
EXECUTE FUNCTION public.validate_timetable_course_offering_status();


-- ============================================================
-- 12. INDEXES FOR CONFLICT DETECTION
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_timetable_entries_timetable_room
ON public.timetable_entries (timetable_id, room_id, timetable_slot_id);

CREATE INDEX IF NOT EXISTS idx_timetable_entries_timetable_class
ON public.timetable_entries (timetable_id, class_id, timetable_slot_id);

CREATE INDEX IF NOT EXISTS idx_lecturer_assignments_offering_class
ON public.lecturer_assignments (
    course_offering_id,
    class_id,
    lecturer_user_id
);

CREATE INDEX IF NOT EXISTS idx_class_students_class_status
ON public.class_students (class_id, enrollment_status);


-- ============================================================
-- 13. UPDATED_AT TRIGGERS
-- ============================================================

DROP TRIGGER IF EXISTS trg_rooms_updated_at
ON public.rooms;

CREATE TRIGGER trg_rooms_updated_at
BEFORE UPDATE ON public.rooms
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_classes_updated_at
ON public.classes;

CREATE TRIGGER trg_classes_updated_at
BEFORE UPDATE ON public.classes
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_class_students_updated_at
ON public.class_students;

CREATE TRIGGER trg_class_students_updated_at
BEFORE UPDATE ON public.class_students
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_lecturer_assignments_updated_at
ON public.lecturer_assignments;

CREATE TRIGGER trg_lecturer_assignments_updated_at
BEFORE UPDATE ON public.lecturer_assignments
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_timetable_slots_updated_at
ON public.timetable_slots;

CREATE TRIGGER trg_timetable_slots_updated_at
BEFORE UPDATE ON public.timetable_slots
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_timetables_updated_at
ON public.timetables;

CREATE TRIGGER trg_timetables_updated_at
BEFORE UPDATE ON public.timetables
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_timetable_entries_updated_at
ON public.timetable_entries;

CREATE TRIGGER trg_timetable_entries_updated_at
BEFORE UPDATE ON public.timetable_entries
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


COMMIT;
