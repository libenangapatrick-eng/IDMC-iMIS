-- ============================================================
-- IDMC iMIS
-- Migration 019
-- Alumni Lifecycle & Integrity Hardening
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Dependency checks
-- ------------------------------------------------------------

DO $$
BEGIN

    IF to_regclass('public.alumni_records') IS NULL THEN
        RAISE EXCEPTION
            'Migration 019 dependency missing: public.alumni_records does not exist';
    END IF;

    IF to_regclass('public.students') IS NULL THEN
        RAISE EXCEPTION
            'Migration 019 dependency missing: public.students does not exist';
    END IF;

    IF to_regclass('public.graduation_candidates') IS NULL THEN
        RAISE EXCEPTION
            'Migration 019 dependency missing: public.graduation_candidates does not exist';
    END IF;

    IF to_regclass('public.graduation_awards') IS NULL THEN
        RAISE EXCEPTION
            'Migration 019 dependency missing: public.graduation_awards does not exist';
    END IF;

END
$$;


-- ------------------------------------------------------------
-- 2. Validate alumni status values
-- ------------------------------------------------------------

DO $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.alumni_records'::regclass
          AND conname = 'alumni_records_status_check'
    ) THEN

        ALTER TABLE public.alumni_records
        ADD CONSTRAINT alumni_records_status_check
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE',
                'DECEASED',
                'UNSUBSCRIBED'
            )
        );

    END IF;

END
$$;


-- ------------------------------------------------------------
-- 3. Alumni number must be meaningful
-- ------------------------------------------------------------

DO $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.alumni_records'::regclass
          AND conname = 'alumni_records_number_not_blank'
    ) THEN

        ALTER TABLE public.alumni_records
        ADD CONSTRAINT alumni_records_number_not_blank
        CHECK (length(trim(alumni_number)) > 0);

    END IF;

END
$$;


-- ------------------------------------------------------------
-- 4. Graduation year validation
-- ------------------------------------------------------------

DO $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.alumni_records'::regclass
          AND conname = 'alumni_records_graduation_year_valid'
    ) THEN

        ALTER TABLE public.alumni_records
        ADD CONSTRAINT alumni_records_graduation_year_valid
        CHECK (
            graduation_year >= 2000
            AND graduation_year <= EXTRACT(YEAR FROM CURRENT_DATE)::integer + 1
        );

    END IF;

END
$$;


-- ------------------------------------------------------------
-- 5. Validate alumni relationships
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_alumni_record_integrity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_candidate_student_id uuid;
    v_award_candidate_id uuid;
    v_candidate_year integer;
BEGIN

    -- Student must exist
    IF NOT EXISTS (
        SELECT 1
        FROM public.students s
        WHERE s.id = NEW.student_id
    ) THEN
        RAISE EXCEPTION
            'Alumni integrity error: student % does not exist',
            NEW.student_id;
    END IF;


    -- Graduation candidate relationship
    IF NEW.graduation_candidate_id IS NOT NULL THEN

        SELECT
            gc.student_id
        INTO
            v_candidate_student_id
        FROM public.graduation_candidates gc
        WHERE gc.id = NEW.graduation_candidate_id;

        IF v_candidate_student_id IS NULL THEN
            RAISE EXCEPTION
                'Alumni integrity error: graduation candidate % does not exist',
                NEW.graduation_candidate_id;
        END IF;

        IF v_candidate_student_id <> NEW.student_id THEN
            RAISE EXCEPTION
                'Alumni integrity error: student does not match graduation candidate';
        END IF;

    END IF;


    -- Graduation award relationship
    IF NEW.graduation_award_id IS NOT NULL THEN

        SELECT
            ga.graduation_candidate_id
        INTO
            v_award_candidate_id
        FROM public.graduation_awards ga
        WHERE ga.id = NEW.graduation_award_id;

        IF v_award_candidate_id IS NULL THEN
            RAISE EXCEPTION
                'Alumni integrity error: graduation award % does not exist',
                NEW.graduation_award_id;
        END IF;

        IF NEW.graduation_candidate_id IS NOT NULL
           AND v_award_candidate_id <> NEW.graduation_candidate_id THEN

            RAISE EXCEPTION
                'Alumni integrity error: graduation award does not match graduation candidate';

        END IF;

    END IF;


    -- Graduation year cannot be in the future
    IF NEW.graduation_year > EXTRACT(YEAR FROM CURRENT_DATE)::integer THEN
        RAISE EXCEPTION
            'Alumni integrity error: graduation year cannot be in the future';
    END IF;


    RETURN NEW;

END
$$;


DROP TRIGGER IF EXISTS trg_validate_alumni_record_integrity
ON public.alumni_records;

CREATE TRIGGER trg_validate_alumni_record_integrity
BEFORE INSERT OR UPDATE
ON public.alumni_records
FOR EACH ROW
EXECUTE FUNCTION public.validate_alumni_record_integrity();


-- ------------------------------------------------------------
-- 6. Prevent changing core alumni identity after creation
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.protect_alumni_identity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF TG_OP = 'UPDATE' THEN

        IF NEW.student_id IS DISTINCT FROM OLD.student_id THEN
            RAISE EXCEPTION
                'Alumni identity is immutable: student_id cannot be changed';
        END IF;

        IF NEW.alumni_number IS DISTINCT FROM OLD.alumni_number THEN
            RAISE EXCEPTION
                'Alumni identity is immutable: alumni_number cannot be changed';
        END IF;

    END IF;

    RETURN NEW;

END
$$;


DROP TRIGGER IF EXISTS trg_protect_alumni_identity
ON public.alumni_records;

CREATE TRIGGER trg_protect_alumni_identity
BEFORE UPDATE
ON public.alumni_records
FOR EACH ROW
EXECUTE FUNCTION public.protect_alumni_identity();


-- ------------------------------------------------------------
-- 7. Keep updated_at current
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.touch_alumni_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END
$$;


DROP TRIGGER IF EXISTS trg_touch_alumni_updated_at
ON public.alumni_records;

CREATE TRIGGER trg_touch_alumni_updated_at
BEFORE UPDATE
ON public.alumni_records
FOR EACH ROW
EXECUTE FUNCTION public.touch_alumni_updated_at();


-- ------------------------------------------------------------
-- 8. Search/report indexes
-- ------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_alumni_records_student
ON public.alumni_records(student_id);

CREATE INDEX IF NOT EXISTS idx_alumni_records_graduation_candidate
ON public.alumni_records(graduation_candidate_id);

CREATE INDEX IF NOT EXISTS idx_alumni_records_graduation_award
ON public.alumni_records(graduation_award_id);

CREATE INDEX IF NOT EXISTS idx_alumni_records_graduation_year
ON public.alumni_records(graduation_year);

CREATE INDEX IF NOT EXISTS idx_alumni_records_status
ON public.alumni_records(status);

CREATE INDEX IF NOT EXISTS idx_alumni_records_email
ON public.alumni_records(email);

CREATE INDEX IF NOT EXISTS idx_alumni_records_current_employer
ON public.alumni_records(current_employer);


-- ------------------------------------------------------------
-- 9. Protect historical alumni records from physical deletion
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.prevent_alumni_hard_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    RAISE EXCEPTION
        'Alumni records cannot be physically deleted. Change status instead.';

END
$$;


DROP TRIGGER IF EXISTS trg_prevent_alumni_hard_delete
ON public.alumni_records;

CREATE TRIGGER trg_prevent_alumni_hard_delete
BEFORE DELETE
ON public.alumni_records
FOR EACH ROW
EXECUTE FUNCTION public.prevent_alumni_hard_delete();


-- ------------------------------------------------------------
-- 10. Ensure one alumni record per student
-- ------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_alumni_records_student
ON public.alumni_records(student_id);


-- ------------------------------------------------------------
-- 11. Ensure one alumni record per graduation candidate
-- ------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_alumni_records_graduation_candidate
ON public.alumni_records(graduation_candidate_id)
WHERE graduation_candidate_id IS NOT NULL;


-- ------------------------------------------------------------
-- 12. Ensure one alumni record per graduation award
-- ------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_alumni_records_graduation_award
ON public.alumni_records(graduation_award_id)
WHERE graduation_award_id IS NOT NULL;


COMMIT;

-- ============================================================
-- END MIGRATION 019
-- ============================================================
