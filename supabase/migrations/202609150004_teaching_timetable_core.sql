-- ============================================================
-- IDMC iMIS
-- Migration 008
-- Teaching, Classes, Lecturer Assignment & Timetable Core
-- ============================================================

BEGIN;

-- ============================================================
-- 1. ROOMS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.rooms (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    campus_id uuid NOT NULL
        REFERENCES public.campuses(id)
        ON DELETE RESTRICT,

    room_code varchar(50) NOT NULL,

    room_name varchar(150) NOT NULL,

    room_type varchar(40) NOT NULL DEFAULT 'LECTURE_ROOM',

    capacity integer NOT NULL DEFAULT 0,

    building_name varchar(150),

    floor_number varchar(30),

    location_description text,

    status varchar(30) NOT NULL DEFAULT 'ACTIVE',

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_room_code
        UNIQUE (campus_id, room_code),

    CONSTRAINT chk_room_capacity
        CHECK (capacity >= 0),

    CONSTRAINT chk_room_type
        CHECK (
            room_type IN (
                'LECTURE_ROOM',
                'LABORATORY',
                'COMPUTER_LAB',
                'SEMINAR_ROOM',
                'HALL',
                'OFFICE',
                'CLINICAL_ROOM',
                'OTHER'
            )
        ),

    CONSTRAINT chk_room_status
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE',
                'MAINTENANCE',
                'CLOSED'
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_rooms_campus
    ON public.rooms(campus_id);

CREATE INDEX IF NOT EXISTS idx_rooms_status
    ON public.rooms(status);

CREATE INDEX IF NOT EXISTS idx_rooms_type
    ON public.rooms(room_type);


-- ============================================================
-- 2. CLASSES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.classes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    course_offering_id uuid NOT NULL
        REFERENCES public.course_offerings(id)
        ON DELETE RESTRICT,

    class_code varchar(80) NOT NULL,

    class_name varchar(150) NOT NULL,

    class_type varchar(30) NOT NULL DEFAULT 'LECTURE',

    capacity integer NOT NULL DEFAULT 0,

    status varchar(30) NOT NULL DEFAULT 'ACTIVE',

    created_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    updated_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_class_code
        UNIQUE (class_code),

    CONSTRAINT chk_class_capacity
        CHECK (capacity >= 0),

    CONSTRAINT chk_class_type
        CHECK (
            class_type IN (
                'LECTURE',
                'TUTORIAL',
                'PRACTICAL',
                'LAB',
                'SEMINAR',
                'CLINICAL',
                'FIELD'
            )
        ),

    CONSTRAINT chk_class_status
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE',
                'CANCELLED',
                'COMPLETED'
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_classes_offering
    ON public.classes(course_offering_id);

CREATE INDEX IF NOT EXISTS idx_classes_status
    ON public.classes(status);


-- ============================================================
-- 3. CLASS STUDENTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.class_students (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    class_id uuid NOT NULL
        REFERENCES public.classes(id)
        ON DELETE CASCADE,

    student_id uuid NOT NULL
        REFERENCES public.students(id)
        ON DELETE RESTRICT,

    course_registration_id uuid
        REFERENCES public.course_registrations(id)
        ON DELETE RESTRICT,

    enrollment_status varchar(30) NOT NULL DEFAULT 'ACTIVE',

    enrolled_at timestamptz NOT NULL DEFAULT now(),

    withdrawn_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_class_student
        UNIQUE (class_id, student_id),

    CONSTRAINT chk_class_student_status
        CHECK (
            enrollment_status IN (
                'ACTIVE',
                'WITHDRAWN',
                'COMPLETED',
                'CANCELLED'
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_class_students_class
    ON public.class_students(class_id);

CREATE INDEX IF NOT EXISTS idx_class_students_student
    ON public.class_students(student_id);

CREATE INDEX IF NOT EXISTS idx_class_students_course_registration
    ON public.class_students(course_registration_id);


-- ============================================================
-- 4. LECTURER ASSIGNMENTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.lecturer_assignments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    course_offering_id uuid NOT NULL
        REFERENCES public.course_offerings(id)
        ON DELETE RESTRICT,

    class_id uuid
        REFERENCES public.classes(id)
        ON DELETE RESTRICT,

    lecturer_user_id uuid NOT NULL
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    assignment_role varchar(40) NOT NULL DEFAULT 'LECTURER',

    workload_hours numeric(8,2) NOT NULL DEFAULT 0,

    assignment_status varchar(30) NOT NULL DEFAULT 'ACTIVE',

    assigned_at timestamptz NOT NULL DEFAULT now(),

    assigned_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    notes text,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_lecturer_assignment_role
        CHECK (
            assignment_role IN (
                'LECTURER',
                'CO_LECTURER',
                'TUTOR',
                'LAB_INSTRUCTOR',
                'CLINICAL_SUPERVISOR'
            )
        ),

    CONSTRAINT chk_lecturer_workload
        CHECK (workload_hours >= 0),

    CONSTRAINT chk_lecturer_assignment_status
        CHECK (
            assignment_status IN (
                'ACTIVE',
                'INACTIVE',
                'COMPLETED',
                'CANCELLED'
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_lecturer_assignments_offering
    ON public.lecturer_assignments(course_offering_id);

CREATE INDEX IF NOT EXISTS idx_lecturer_assignments_class
    ON public.lecturer_assignments(class_id);

CREATE INDEX IF NOT EXISTS idx_lecturer_assignments_lecturer
    ON public.lecturer_assignments(lecturer_user_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_lecturer_offering
    ON public.lecturer_assignments(
        course_offering_id,
        lecturer_user_id,
        COALESCE(class_id, '00000000-0000-0000-0000-000000000000'::uuid)
    )
    WHERE assignment_status = 'ACTIVE';


-- ============================================================
-- 5. TIMETABLE SLOTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.timetable_slots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    slot_code varchar(50) NOT NULL UNIQUE,

    day_of_week integer NOT NULL,

    start_time time NOT NULL,

    end_time time NOT NULL,

    duration_minutes integer NOT NULL,

    status varchar(30) NOT NULL DEFAULT 'ACTIVE',

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_day_of_week
        CHECK (day_of_week BETWEEN 1 AND 7),

    CONSTRAINT chk_slot_time
        CHECK (end_time > start_time),

    CONSTRAINT chk_slot_duration
        CHECK (duration_minutes > 0),

    CONSTRAINT chk_slot_status
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE'
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_timetable_slots_day
    ON public.timetable_slots(day_of_week);

CREATE INDEX IF NOT EXISTS idx_timetable_slots_time
    ON public.timetable_slots(start_time, end_time);


-- ============================================================
-- 6. TIMETABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.timetables (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    academic_year_id uuid NOT NULL
        REFERENCES public.academic_years(id)
        ON DELETE RESTRICT,

    semester_id uuid NOT NULL
        REFERENCES public.semesters(id)
        ON DELETE RESTRICT,

    campus_id uuid NOT NULL
        REFERENCES public.campuses(id)
        ON DELETE RESTRICT,

    timetable_code varchar(80) NOT NULL UNIQUE,

    timetable_name varchar(150) NOT NULL,

    status varchar(30) NOT NULL DEFAULT 'DRAFT',

    published_at timestamptz,

    published_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    locked_at timestamptz,

    locked_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    updated_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_timetable_status
        CHECK (
            status IN (
                'DRAFT',
                'UNDER_REVIEW',
                'APPROVED',
                'PUBLISHED',
                'LOCKED',
                'CANCELLED'
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_timetables_year
    ON public.timetables(academic_year_id);

CREATE INDEX IF NOT EXISTS idx_timetables_semester
    ON public.timetables(semester_id);

CREATE INDEX IF NOT EXISTS idx_timetables_campus
    ON public.timetables(campus_id);

CREATE INDEX IF NOT EXISTS idx_timetables_status
    ON public.timetables(status);


-- ============================================================
-- 7. TIMETABLE ENTRIES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.timetable_entries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    timetable_id uuid NOT NULL
        REFERENCES public.timetables(id)
        ON DELETE CASCADE,

    class_id uuid NOT NULL
        REFERENCES public.classes(id)
        ON DELETE RESTRICT,

    course_offering_id uuid NOT NULL
        REFERENCES public.course_offerings(id)
        ON DELETE RESTRICT,

    lecturer_assignment_id uuid
        REFERENCES public.lecturer_assignments(id)
        ON DELETE RESTRICT,

    room_id uuid NOT NULL
        REFERENCES public.rooms(id)
        ON DELETE RESTRICT,

    timetable_slot_id uuid NOT NULL
        REFERENCES public.timetable_slots(id)
        ON DELETE RESTRICT,

    entry_date date,

    entry_type varchar(30) NOT NULL DEFAULT 'REGULAR',

    status varchar(30) NOT NULL DEFAULT 'DRAFT',

    notes text,

    created_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    updated_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_timetable_entry_type
        CHECK (
            entry_type IN (
                'REGULAR',
                'MAKE_UP',
                'SPECIAL',
                'EXAM',
                'PRACTICAL',
                'CLINICAL'
            )
        ),

    CONSTRAINT chk_timetable_entry_status
        CHECK (
            status IN (
                'DRAFT',
                'CONFIRMED',
                'CANCELLED'
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_timetable_entries_timetable
    ON public.timetable_entries(timetable_id);

CREATE INDEX IF NOT EXISTS idx_timetable_entries_class
    ON public.timetable_entries(class_id);

CREATE INDEX IF NOT EXISTS idx_timetable_entries_course_offering
    ON public.timetable_entries(course_offering_id);

CREATE INDEX IF NOT EXISTS idx_timetable_entries_lecturer
    ON public.timetable_entries(lecturer_assignment_id);

CREATE INDEX IF NOT EXISTS idx_timetable_entries_room
    ON public.timetable_entries(room_id);

CREATE INDEX IF NOT EXISTS idx_timetable_entries_slot
    ON public.timetable_entries(timetable_slot_id);


-- ============================================================
-- 8. TIMETABLE ROOM CONFLICT
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_timetable_room_conflict()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN

    IF EXISTS (
        SELECT 1
        FROM public.timetable_entries te
        JOIN public.timetable_slots ts
            ON ts.id = te.timetable_slot_id
        WHERE te.id <> NEW.id
          AND te.room_id = NEW.room_id
          AND te.timetable_id = NEW.timetable_id
          AND te.status <> 'CANCELLED'
          AND ts.day_of_week = (
              SELECT day_of_week
              FROM public.timetable_slots
              WHERE id = NEW.timetable_slot_id
          )
          AND ts.start_time < (
              SELECT end_time
              FROM public.timetable_slots
              WHERE id = NEW.timetable_slot_id
          )
          AND ts.end_time > (
              SELECT start_time
              FROM public.timetable_slots
              WHERE id = NEW.timetable_slot_id
          )
    )
    THEN
        RAISE EXCEPTION
            'Timetable room conflict detected';
    END IF;

    RETURN NEW;
END;
$function$;


CREATE TRIGGER trg_validate_timetable_room_conflict
BEFORE INSERT OR UPDATE
ON public.timetable_entries
FOR EACH ROW
EXECUTE FUNCTION public.validate_timetable_room_conflict();


-- ============================================================
-- 9. TIMETABLE CLASS CONFLICT
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_timetable_class_conflict()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN

    IF EXISTS (
        SELECT 1
        FROM public.timetable_entries te
        JOIN public.timetable_slots ts
            ON ts.id = te.timetable_slot_id
        JOIN public.timetable_slots ns
            ON ns.id = NEW.timetable_slot_id
        WHERE te.id <> NEW.id
          AND te.class_id = NEW.class_id
          AND te.timetable_id = NEW.timetable_id
          AND te.status <> 'CANCELLED'
          AND ts.day_of_week = ns.day_of_week
          AND ts.start_time < ns.end_time
          AND ts.end_time > ns.start_time
    )
    THEN
        RAISE EXCEPTION
            'Timetable class conflict detected';
    END IF;

    RETURN NEW;
END;
$function$;


CREATE TRIGGER trg_validate_timetable_class_conflict
BEFORE INSERT OR UPDATE
ON public.timetable_entries
FOR EACH ROW
EXECUTE FUNCTION public.validate_timetable_class_conflict();


-- ============================================================
-- 10. TIMETABLE LECTURER CONFLICT
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_timetable_lecturer_conflict()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN

    IF NEW.lecturer_assignment_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.timetable_entries te
        JOIN public.lecturer_assignments la
            ON la.id = te.lecturer_assignment_id
        JOIN public.timetable_slots ts
            ON ts.id = te.timetable_slot_id
        JOIN public.timetable_slots ns
            ON ns.id = NEW.timetable_slot_id
        JOIN public.lecturer_assignments nla
            ON nla.id = NEW.lecturer_assignment_id
        WHERE te.id <> NEW.id
          AND la.lecturer_user_id = nla.lecturer_user_id
          AND te.timetable_id = NEW.timetable_id
          AND te.status <> 'CANCELLED'
          AND ts.day_of_week = ns.day_of_week
          AND ts.start_time < ns.end_time
          AND ts.end_time > ns.start_time
    )
    THEN
        RAISE EXCEPTION
            'Timetable lecturer conflict detected';
    END IF;

    RETURN NEW;
END;
$function$;


CREATE TRIGGER trg_validate_timetable_lecturer_conflict
BEFORE INSERT OR UPDATE
ON public.timetable_entries
FOR EACH ROW
EXECUTE FUNCTION public.validate_timetable_lecturer_conflict();


-- ============================================================
-- 11. PREVENT CHANGES TO LOCKED TIMETABLE
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_locked_timetable_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
    v_status varchar(30);
BEGIN

    SELECT status
    INTO v_status
    FROM public.timetables
    WHERE id = COALESCE(
        NEW.timetable_id,
        OLD.timetable_id
    );

    IF v_status = 'LOCKED' THEN
        RAISE EXCEPTION
            'Locked timetable cannot be modified';
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$function$;


CREATE TRIGGER trg_prevent_locked_timetable_change
BEFORE INSERT OR UPDATE OR DELETE
ON public.timetable_entries
FOR EACH ROW
EXECUTE FUNCTION public.prevent_locked_timetable_change();


-- ============================================================
-- 12. TIMETABLE STATUS PROTECTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_timetable_status_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN

    IF TG_OP = 'UPDATE'
       AND OLD.status <> NEW.status
    THEN

        IF OLD.status = 'LOCKED' THEN
            RAISE EXCEPTION
                'Locked timetable cannot change status';
        END IF;

        IF OLD.status = 'CANCELLED'
           AND NEW.status <> 'CANCELLED'
        THEN
            RAISE EXCEPTION
                'Cancelled timetable cannot be reopened';
        END IF;

    END IF;

    IF NEW.status = 'PUBLISHED'
       AND OLD.status IS DISTINCT FROM 'PUBLISHED'
    THEN
        NEW.published_at := COALESCE(
            NEW.published_at,
            now()
        );
    END IF;

    IF NEW.status = 'LOCKED'
       AND OLD.status IS DISTINCT FROM 'LOCKED'
    THEN
        NEW.locked_at := COALESCE(
            NEW.locked_at,
            now()
        );
    END IF;

    RETURN NEW;
END;
$function$;


CREATE TRIGGER trg_validate_timetable_status
BEFORE INSERT OR UPDATE OF status
ON public.timetables
FOR EACH ROW
EXECUTE FUNCTION public.validate_timetable_status_transition();


-- ============================================================
-- 13. UPDATED_AT TRIGGERS
-- ============================================================

CREATE TRIGGER trg_rooms_updated_at
BEFORE UPDATE ON public.rooms
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_classes_updated_at
BEFORE UPDATE ON public.classes
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_class_students_updated_at
BEFORE UPDATE ON public.class_students
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_lecturer_assignments_updated_at
BEFORE UPDATE ON public.lecturer_assignments
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_timetable_slots_updated_at
BEFORE UPDATE ON public.timetable_slots
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_timetables_updated_at
BEFORE UPDATE ON public.timetables
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_timetable_entries_updated_at
BEFORE UPDATE ON public.timetable_entries
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 14. RLS
-- ============================================================

ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.class_students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lecturer_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.timetable_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.timetables ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.timetable_entries ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 15. COMMENTS
-- ============================================================

COMMENT ON TABLE public.rooms IS
'Academic and operational rooms available for teaching and timetable allocation.';

COMMENT ON TABLE public.classes IS
'Teaching classes linked to course offerings.';

COMMENT ON TABLE public.class_students IS
'Students enrolled into teaching classes.';

COMMENT ON TABLE public.lecturer_assignments IS
'Lecturer and teaching staff assignments to course offerings/classes.';

COMMENT ON TABLE public.timetable_slots IS
'Reusable weekly timetable time slots.';

COMMENT ON TABLE public.timetables IS
'Academic timetable master records per academic year, semester and campus.';

COMMENT ON TABLE public.timetable_entries IS
'Individual class timetable entries with room, lecturer and time allocation.';


COMMIT;
