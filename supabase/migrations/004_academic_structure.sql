-- ============================================================
-- IDMC iMIS
-- Migration 004: Academic Structure Foundation
-- PostgreSQL / Supabase Safe
-- ============================================================

-- ------------------------------------------------------------
-- 1. Academic Years
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.academic_years (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    year_code varchar(20) NOT NULL UNIQUE,
    year_name varchar(100) NOT NULL,

    start_date date NOT NULL,
    end_date date NOT NULL,

    status varchar(30) NOT NULL DEFAULT 'PLANNED',

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT academic_years_status_check
        CHECK (status IN (
            'PLANNED',
            'ACTIVE',
            'CLOSED',
            'ARCHIVED'
        )),

    CONSTRAINT academic_years_date_check
        CHECK (end_date > start_date)
);

-- ------------------------------------------------------------
-- 2. Semesters
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.semesters (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    academic_year_id uuid NOT NULL
        REFERENCES public.academic_years(id)
        ON DELETE CASCADE,

    semester_code varchar(30) NOT NULL,
    semester_name varchar(100) NOT NULL,

    semester_number integer NOT NULL,

    start_date date NOT NULL,
    end_date date NOT NULL,

    status varchar(30) NOT NULL DEFAULT 'PLANNED',

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT semesters_number_check
        CHECK (semester_number > 0),

    CONSTRAINT semesters_status_check
        CHECK (status IN (
            'PLANNED',
            'ACTIVE',
            'CLOSED',
            'ARCHIVED'
        )),

    CONSTRAINT semesters_date_check
        CHECK (end_date > start_date),

    CONSTRAINT uq_semester_year_code
        UNIQUE (academic_year_id, semester_code),

    CONSTRAINT uq_semester_year_number
        UNIQUE (academic_year_id, semester_number)
);

-- ------------------------------------------------------------
-- 3. Programmes
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.programmes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    institution_id uuid NOT NULL
        REFERENCES public.institutions(id)
        ON DELETE RESTRICT,

    school_id uuid
        REFERENCES public.schools(id)
        ON DELETE RESTRICT,

    department_id uuid
        REFERENCES public.departments(id)
        ON DELETE RESTRICT,

    programme_code varchar(50) NOT NULL,
    programme_name varchar(200) NOT NULL,

    programme_type varchar(50) NOT NULL DEFAULT 'ACADEMIC',

    award_level varchar(50) NOT NULL,

    duration_years numeric(4,2),

    mode_of_study varchar(50) NOT NULL DEFAULT 'FULL_TIME',

    description text,

    status varchar(30) NOT NULL DEFAULT 'ACTIVE',

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT programmes_type_check
        CHECK (programme_type IN (
            'ACADEMIC',
            'PROFESSIONAL',
            'SHORT_COURSE',
            'CERTIFICATE',
            'OTHER'
        )),

    CONSTRAINT programmes_mode_check
        CHECK (mode_of_study IN (
            'FULL_TIME',
            'PART_TIME',
            'EVENING',
            'WEEKEND',
            'DISTANCE',
            'ONLINE',
            'BLENDED'
        )),

    CONSTRAINT programmes_status_check
        CHECK (status IN (
            'ACTIVE',
            'INACTIVE',
            'SUSPENDED',
            'ARCHIVED'
        )),

    CONSTRAINT uq_programme_institution_code
        UNIQUE (institution_id, programme_code)
);

-- ------------------------------------------------------------
-- 4. Programme Versions
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.programme_versions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    programme_id uuid NOT NULL
        REFERENCES public.programmes(id)
        ON DELETE CASCADE,

    version_code varchar(50) NOT NULL,
    version_name varchar(150),

    effective_from date NOT NULL,
    effective_to date,

    total_credits numeric(8,2),

    status varchar(30) NOT NULL DEFAULT 'DRAFT',

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT programme_versions_status_check
        CHECK (status IN (
            'DRAFT',
            'ACTIVE',
            'RETIRED',
            'ARCHIVED'
        )),

    CONSTRAINT programme_versions_date_check
        CHECK (
            effective_to IS NULL
            OR effective_to >= effective_from
        ),

    CONSTRAINT programme_versions_credits_check
        CHECK (
            total_credits IS NULL
            OR total_credits >= 0
        ),

    CONSTRAINT uq_programme_version
        UNIQUE (programme_id, version_code)
);

-- ------------------------------------------------------------
-- 5. Courses
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.courses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    institution_id uuid NOT NULL
        REFERENCES public.institutions(id)
        ON DELETE RESTRICT,

    department_id uuid
        REFERENCES public.departments(id)
        ON DELETE RESTRICT,

    course_code varchar(50) NOT NULL,
    course_name varchar(200) NOT NULL,

    course_short_name varchar(100),

    credit_units numeric(6,2) NOT NULL DEFAULT 0,

    contact_hours numeric(6,2),

    course_type varchar(50) NOT NULL DEFAULT 'CORE',

    level varchar(50),

    description text,

    status varchar(30) NOT NULL DEFAULT 'ACTIVE',

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT courses_credit_check
        CHECK (credit_units >= 0),

    CONSTRAINT courses_contact_hours_check
        CHECK (
            contact_hours IS NULL
            OR contact_hours >= 0
        ),

    CONSTRAINT courses_type_check
        CHECK (course_type IN (
            'CORE',
            'ELECTIVE',
            'OPTIONAL',
            'GENERAL',
            'PRACTICAL',
            'FIELD',
            'CLINICAL',
            'PROJECT',
            'OTHER'
        )),

    CONSTRAINT courses_status_check
        CHECK (status IN (
            'ACTIVE',
            'INACTIVE',
            'RETIRED',
            'ARCHIVED'
        )),

    CONSTRAINT uq_course_institution_code
        UNIQUE (institution_id, course_code)
);

-- ------------------------------------------------------------
-- 6. Curricula
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.curricula (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    programme_version_id uuid NOT NULL
        REFERENCES public.programme_versions(id)
        ON DELETE CASCADE,

    curriculum_code varchar(50) NOT NULL,
    curriculum_name varchar(200) NOT NULL,

    effective_from date NOT NULL,
    effective_to date,

    total_credits numeric(8,2),

    status varchar(30) NOT NULL DEFAULT 'DRAFT',

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT curricula_status_check
        CHECK (status IN (
            'DRAFT',
            'ACTIVE',
            'RETIRED',
            'ARCHIVED'
        )),

    CONSTRAINT curricula_date_check
        CHECK (
            effective_to IS NULL
            OR effective_to >= effective_from
        ),

    CONSTRAINT curricula_credits_check
        CHECK (
            total_credits IS NULL
            OR total_credits >= 0
        ),

    CONSTRAINT uq_curriculum_programme_code
        UNIQUE (programme_version_id, curriculum_code)
);

-- ------------------------------------------------------------
-- 7. Curriculum Courses
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.curriculum_courses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    curriculum_id uuid NOT NULL
        REFERENCES public.curricula(id)
        ON DELETE CASCADE,

    course_id uuid NOT NULL
        REFERENCES public.courses(id)
        ON DELETE RESTRICT,

    semester_number integer NOT NULL,

    year_number integer,

    course_category varchar(50) NOT NULL DEFAULT 'CORE',

    is_compulsory boolean NOT NULL DEFAULT true,

    credit_units numeric(6,2),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT curriculum_courses_semester_check
        CHECK (semester_number > 0),

    CONSTRAINT curriculum_courses_year_check
        CHECK (
            year_number IS NULL
            OR year_number > 0
        ),

    CONSTRAINT curriculum_courses_category_check
        CHECK (course_category IN (
            'CORE',
            'ELECTIVE',
            'OPTIONAL',
            'GENERAL',
            'PRACTICAL',
            'FIELD',
            'CLINICAL',
            'PROJECT',
            'OTHER'
        )),

    CONSTRAINT curriculum_courses_credit_check
        CHECK (
            credit_units IS NULL
            OR credit_units >= 0
        ),

    CONSTRAINT uq_curriculum_course
        UNIQUE (curriculum_id, course_id)
);

-- ------------------------------------------------------------
-- 8. Course Prerequisites
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.course_prerequisites (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    course_id uuid NOT NULL
        REFERENCES public.courses(id)
        ON DELETE CASCADE,

    prerequisite_course_id uuid NOT NULL
        REFERENCES public.courses(id)
        ON DELETE RESTRICT,

    minimum_grade varchar(20),

    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT course_prerequisite_self_check
        CHECK (course_id <> prerequisite_course_id),

    CONSTRAINT uq_course_prerequisite
        UNIQUE (course_id, prerequisite_course_id)
);

-- ------------------------------------------------------------
-- 9. Indexes
-- ------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_academic_years_status
    ON public.academic_years(status);

CREATE INDEX IF NOT EXISTS idx_academic_years_dates
    ON public.academic_years(start_date, end_date);

CREATE INDEX IF NOT EXISTS idx_semesters_academic_year
    ON public.semesters(academic_year_id);

CREATE INDEX IF NOT EXISTS idx_semesters_status
    ON public.semesters(status);

CREATE INDEX IF NOT EXISTS idx_programmes_institution
    ON public.programmes(institution_id);

CREATE INDEX IF NOT EXISTS idx_programmes_school
    ON public.programmes(school_id);

CREATE INDEX IF NOT EXISTS idx_programmes_department
    ON public.programmes(department_id);

CREATE INDEX IF NOT EXISTS idx_programmes_status
    ON public.programmes(status);

CREATE INDEX IF NOT EXISTS idx_programme_versions_programme
    ON public.programme_versions(programme_id);

CREATE INDEX IF NOT EXISTS idx_programme_versions_status
    ON public.programme_versions(status);

CREATE INDEX IF NOT EXISTS idx_courses_institution
    ON public.courses(institution_id);

CREATE INDEX IF NOT EXISTS idx_courses_department
    ON public.courses(department_id);

CREATE INDEX IF NOT EXISTS idx_courses_status
    ON public.courses(status);

CREATE INDEX IF NOT EXISTS idx_curricula_programme_version
    ON public.curricula(programme_version_id);

CREATE INDEX IF NOT EXISTS idx_curricula_status
    ON public.curricula(status);

CREATE INDEX IF NOT EXISTS idx_curriculum_courses_curriculum
    ON public.curriculum_courses(curriculum_id);

CREATE INDEX IF NOT EXISTS idx_curriculum_courses_course
    ON public.curriculum_courses(course_id);

CREATE INDEX IF NOT EXISTS idx_curriculum_courses_semester
    ON public.curriculum_courses(semester_number);

CREATE INDEX IF NOT EXISTS idx_course_prerequisites_course
    ON public.course_prerequisites(course_id);

CREATE INDEX IF NOT EXISTS idx_course_prerequisites_prerequisite
    ON public.course_prerequisites(prerequisite_course_id);

-- ------------------------------------------------------------
-- 10. Updated-at triggers
-- Uses function created in Migration 001
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_academic_years_updated_at
ON public.academic_years;

CREATE TRIGGER trg_academic_years_updated_at
BEFORE UPDATE ON public.academic_years
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_semesters_updated_at
ON public.semesters;

CREATE TRIGGER trg_semesters_updated_at
BEFORE UPDATE ON public.semesters
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_programmes_updated_at
ON public.programmes;

CREATE TRIGGER trg_programmes_updated_at
BEFORE UPDATE ON public.programmes
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_programme_versions_updated_at
ON public.programme_versions;

CREATE TRIGGER trg_programme_versions_updated_at
BEFORE UPDATE ON public.programme_versions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_courses_updated_at
ON public.courses;

CREATE TRIGGER trg_courses_updated_at
BEFORE UPDATE ON public.courses
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_curricula_updated_at
ON public.curricula;

CREATE TRIGGER trg_curricula_updated_at
BEFORE UPDATE ON public.curricula
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_curriculum_courses_updated_at
ON public.curriculum_courses;

CREATE TRIGGER trg_curriculum_courses_updated_at
BEFORE UPDATE ON public.curriculum_courses
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- ------------------------------------------------------------
-- 11. Row Level Security
-- Backend API will control access through RBAC.
-- ------------------------------------------------------------

ALTER TABLE public.academic_years ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.semesters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.programmes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.programme_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.curricula ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.curriculum_courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_prerequisites ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------
-- 12. Documentation comments
-- ------------------------------------------------------------

COMMENT ON TABLE public.academic_years IS
'Institutional academic years used across academic operations.';

COMMENT ON TABLE public.semesters IS
'Academic periods belonging to an academic year.';

COMMENT ON TABLE public.programmes IS
'Academic programmes offered by the institution.';

COMMENT ON TABLE public.programme_versions IS
'Versioned academic programme definitions.';

COMMENT ON TABLE public.courses IS
'Institutional course catalogue.';

COMMENT ON TABLE public.curricula IS
'Curriculum definitions attached to programme versions.';

COMMENT ON TABLE public.curriculum_courses IS
'Courses and their placement within a curriculum.';

COMMENT ON TABLE public.course_prerequisites IS
'Prerequisite relationships between courses.';
