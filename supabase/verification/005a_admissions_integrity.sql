-- ============================================================
-- IDMC iMIS
-- Migration 005A
-- Admissions Integrity, Acceptance & Automatic Expiry
-- PostgreSQL / Supabase
-- ============================================================

-- ============================================================
-- 1. ONE ACTIVE OFFER PER APPLICATION
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS
uq_active_admission_offer_application
ON public.admission_offers(application_id)
WHERE offer_status IN ('ISSUED', 'ACCEPTED');


-- ============================================================
-- 2. ONE APPROVED DECISION PER APPLICATION
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS
uq_approved_admission_decision_application
ON public.admission_decisions(application_id)
WHERE decision_status = 'APPROVED';


-- ============================================================
-- 3. SINGLE ACCEPTANCE PER OFFER
--
-- The base table already has:
-- admission_offer_id UUID NOT NULL UNIQUE
--
-- This additional partial unique index explicitly guarantees
-- only one ACCEPTED acceptance for each offer.
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS
uq_accepted_admission_offer
ON public.admission_acceptances(admission_offer_id)
WHERE acceptance_status = 'ACCEPTED';


-- ============================================================
-- 4. VALIDATE ADMISSION DECISION
--
-- application_choice must belong to same application.
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_admission_decision_application()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.application_choice_id IS NOT NULL THEN

        IF NOT EXISTS (
            SELECT 1
            FROM public.application_choices ac
            WHERE ac.id = NEW.application_choice_id
              AND ac.application_id = NEW.application_id
        ) THEN

            RAISE EXCEPTION
                'Admission decision choice does not belong to the specified application';

        END IF;

    END IF;

    RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS
trg_validate_admission_decision_application
ON public.admission_decisions;

CREATE TRIGGER
trg_validate_admission_decision_application
BEFORE INSERT OR UPDATE
ON public.admission_decisions
FOR EACH ROW
EXECUTE FUNCTION public.validate_admission_decision_application();


-- ============================================================
-- 5. VALIDATE ADMISSION OFFER
--
-- Rules:
-- - Application must be SELECTED
-- - Programme must be an application choice
-- - Decision must belong to same application
-- - Decision must be APPROVED
-- - Offer cannot already be expired
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_admission_offer()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    -- --------------------------------------------------------
    -- ACTIVE OFFER
    -- --------------------------------------------------------

    IF NEW.offer_status IN ('ISSUED', 'ACCEPTED') THEN

        IF NOT EXISTS (
            SELECT 1
            FROM public.applications a
            WHERE a.id = NEW.application_id
              AND a.status IN ('SELECTED', 'ADMISSION_OFFERED')
        ) THEN

            RAISE EXCEPTION
                'Admission offer cannot be issued because the application is not selected or offer-ready';

        END IF;


        -- ----------------------------------------------------
        -- Programme must be one of application choices
        -- ----------------------------------------------------

        IF NOT EXISTS (
            SELECT 1
            FROM public.application_choices ac
            WHERE ac.application_id = NEW.application_id
              AND ac.programme_id = NEW.programme_id
              AND ac.status IN (
                  'PENDING',
                  'ELIGIBLE',
                  'SELECTED'
              )
        ) THEN

            RAISE EXCEPTION
                'Admission offer programme is not a valid programme choice for this application';

        END IF;


        -- ----------------------------------------------------
        -- Cannot create already expired offer
        -- ----------------------------------------------------

        IF NEW.expiry_date IS NOT NULL
           AND NEW.expiry_date < CURRENT_DATE THEN

            RAISE EXCEPTION
                'Admission offer cannot be issued because its expiry date has passed';

        END IF;

    END IF;


    -- --------------------------------------------------------
    -- DECISION VALIDATION
    -- --------------------------------------------------------

    IF NEW.decision_id IS NOT NULL THEN

        IF NOT EXISTS (
            SELECT 1
            FROM public.admission_decisions ad
            WHERE ad.id = NEW.decision_id
              AND ad.application_id = NEW.application_id
        ) THEN

            RAISE EXCEPTION
                'Admission offer decision does not belong to this application';

        END IF;


        IF NEW.offer_status IN ('ISSUED', 'ACCEPTED') THEN

            IF NOT EXISTS (
                SELECT 1
                FROM public.admission_decisions ad
                WHERE ad.id = NEW.decision_id
                  AND ad.decision_status = 'APPROVED'
            ) THEN

                RAISE EXCEPTION
                    'Admission offer requires an APPROVED admission decision';

            END IF;

        END IF;

    END IF;


    RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS
trg_validate_admission_offer
ON public.admission_offers;

CREATE TRIGGER
trg_validate_admission_offer
BEFORE INSERT OR UPDATE
ON public.admission_offers
FOR EACH ROW
EXECUTE FUNCTION public.validate_admission_offer();


-- ============================================================
-- 6. ACCEPTANCE VALIDATION
--
-- Critical security rule:
-- EXPIRED offers cannot be accepted.
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_admission_acceptance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_offer public.admission_offers%ROWTYPE;
BEGIN

    SELECT *
    INTO v_offer
    FROM public.admission_offers
    WHERE id = NEW.admission_offer_id
    FOR UPDATE;


    IF NOT FOUND THEN

        RAISE EXCEPTION
            'Admission offer does not exist';

    END IF;


    -- ========================================================
    -- ACCEPTED
    -- ========================================================

    IF NEW.acceptance_status = 'ACCEPTED' THEN

        -- Only ISSUED offers can be accepted
        IF v_offer.offer_status <> 'ISSUED' THEN

            RAISE EXCEPTION
                'Only an ISSUED admission offer can be accepted. Current status: %',
                v_offer.offer_status;

        END IF;


        -- Expiry protection
        IF v_offer.expiry_date IS NOT NULL
           AND v_offer.expiry_date < CURRENT_DATE THEN

            RAISE EXCEPTION
                'Admission offer has expired and cannot be accepted';

        END IF;


        -- Automatically set acceptance timestamp
        IF NEW.accepted_at IS NULL THEN

            NEW.accepted_at := now();

        END IF;


        -- Accepted offer cannot have declined timestamp
        NEW.declined_at := NULL;

    END IF;


    -- ========================================================
    -- DECLINED
    -- ========================================================

    IF NEW.acceptance_status = 'DECLINED' THEN

        IF v_offer.offer_status NOT IN (
            'ISSUED'
        ) THEN

            RAISE EXCEPTION
                'Only an ISSUED admission offer can be declined';

        END IF;


        IF NEW.declined_at IS NULL THEN

            NEW.declined_at := now();

        END IF;


        NEW.accepted_at := NULL;

    END IF;


    -- ========================================================
    -- PENDING
    -- ========================================================

    IF NEW.acceptance_status = 'PENDING' THEN

        NEW.accepted_at := NULL;
        NEW.declined_at := NULL;

    END IF;


    -- ========================================================
    -- EXPIRED
    -- ========================================================

    IF NEW.acceptance_status = 'EXPIRED' THEN

        NEW.accepted_at := NULL;

        IF NEW.declined_at IS NULL THEN
            NEW.declined_at := now();
        END IF;

    END IF;


    RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS
trg_validate_admission_acceptance
ON public.admission_acceptances;

CREATE TRIGGER
trg_validate_admission_acceptance
BEFORE INSERT OR UPDATE
ON public.admission_acceptances
FOR EACH ROW
EXECUTE FUNCTION public.validate_admission_acceptance();


-- ============================================================
-- 7. PREVENT INVALID OFFER STATUS CHANGES
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_invalid_offer_status_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    -- ACCEPTED cannot return to ISSUED
    IF OLD.offer_status = 'ACCEPTED'
       AND NEW.offer_status = 'ISSUED' THEN

        RAISE EXCEPTION
            'An ACCEPTED admission offer cannot be changed back to ISSUED';

    END IF;


    -- DECLINED cannot become ACCEPTED
    IF OLD.offer_status = 'DECLINED'
       AND NEW.offer_status = 'ACCEPTED' THEN

        RAISE EXCEPTION
            'A DECLINED admission offer cannot become ACCEPTED';

    END IF;


    -- CANCELLED cannot become ACCEPTED
    IF OLD.offer_status = 'CANCELLED'
       AND NEW.offer_status = 'ACCEPTED' THEN

        RAISE EXCEPTION
            'A CANCELLED admission offer cannot become ACCEPTED';

    END IF;


    -- EXPIRED cannot become ACCEPTED
    IF OLD.offer_status = 'EXPIRED'
       AND NEW.offer_status = 'ACCEPTED' THEN

        RAISE EXCEPTION
            'An EXPIRED admission offer cannot become ACCEPTED';

    END IF;


    RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS
trg_prevent_invalid_offer_status_change
ON public.admission_offers;

CREATE TRIGGER
trg_prevent_invalid_offer_status_change
BEFORE UPDATE
ON public.admission_offers
FOR EACH ROW
EXECUTE FUNCTION public.prevent_invalid_offer_status_change();


-- ============================================================
-- 8. SYNCHRONIZE OFFER STATUS AFTER ACCEPTANCE
-- ============================================================

CREATE OR REPLACE FUNCTION public.sync_admission_offer_after_acceptance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.acceptance_status = 'ACCEPTED' THEN

        UPDATE public.admission_offers
        SET
            offer_status = 'ACCEPTED',
            updated_at = now()
        WHERE id = NEW.admission_offer_id
          AND offer_status = 'ISSUED';


    ELSIF NEW.acceptance_status = 'DECLINED' THEN

        UPDATE public.admission_offers
        SET
            offer_status = 'DECLINED',
            updated_at = now()
        WHERE id = NEW.admission_offer_id
          AND offer_status = 'ISSUED';


    ELSIF NEW.acceptance_status = 'EXPIRED' THEN

        UPDATE public.admission_offers
        SET
            offer_status = 'EXPIRED',
            updated_at = now()
        WHERE id = NEW.admission_offer_id
          AND offer_status = 'ISSUED';

    END IF;


    RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS
trg_sync_admission_offer_after_acceptance
ON public.admission_acceptances;

CREATE TRIGGER
trg_sync_admission_offer_after_acceptance
AFTER INSERT OR UPDATE
ON public.admission_acceptances
FOR EACH ROW
EXECUTE FUNCTION public.sync_admission_offer_after_acceptance();


-- ============================================================
-- 9. SYNCHRONIZE APPLICATION STATUS
-- ============================================================

CREATE OR REPLACE FUNCTION public.sync_application_after_admission_acceptance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_application_id uuid;
BEGIN

    SELECT application_id
    INTO v_application_id
    FROM public.admission_offers
    WHERE id = NEW.admission_offer_id;


    IF NEW.acceptance_status = 'ACCEPTED' THEN

        UPDATE public.applications
        SET
            status = 'ACCEPTED',
            updated_at = now()
        WHERE id = v_application_id
          AND status IN (
              'SELECTED',
              'ADMISSION_OFFERED'
          );


    ELSIF NEW.acceptance_status = 'DECLINED' THEN

        UPDATE public.applications
        SET
            status = 'REJECTED',
            updated_at = now()
        WHERE id = v_application_id
          AND status = 'ADMISSION_OFFERED';

    END IF;


    RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS
trg_sync_application_after_admission_acceptance
ON public.admission_acceptances;

CREATE TRIGGER
trg_sync_application_after_admission_acceptance
AFTER INSERT OR UPDATE
ON public.admission_acceptances
FOR EACH ROW
EXECUTE FUNCTION public.sync_application_after_admission_acceptance();


-- ============================================================
-- 10. AUTOMATIC OFFER EXPIRY FUNCTION
--
-- Any ISSUED offer whose expiry_date has passed becomes EXPIRED.
-- ============================================================

CREATE OR REPLACE FUNCTION public.expire_admission_offers()
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_count integer;
BEGIN

    UPDATE public.admission_offers
    SET
        offer_status = 'EXPIRED',
        updated_at = now()
    WHERE offer_status = 'ISSUED'
      AND expiry_date IS NOT NULL
      AND expiry_date < CURRENT_DATE;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN v_count;

END;
$$;


-- ============================================================
-- 11. ENABLE SUPABASE pg_cron
--
-- pg_cron runs the expiry function automatically.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_cron
WITH SCHEMA pg_catalog;


-- Remove previous IDMC expiry schedule if it exists
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'idmc-expire-admission-offers';


-- Run every day at 00:05 UTC.
--
-- Tanzania is UTC+3.
-- Therefore this runs at 03:05 Tanzania time.
-- ============================================================

SELECT cron.schedule(
    'idmc-expire-admission-offers',
    '5 0 * * *',
    $$SELECT public.expire_admission_offers();$$
);


-- ============================================================
-- 12. DOCUMENTATION
-- ============================================================

COMMENT ON INDEX public.uq_active_admission_offer_application IS
'Ensures that an application can have only one active admission offer.';

COMMENT ON INDEX public.uq_accepted_admission_offer IS
'Ensures that an admission offer can have only one accepted acceptance record.';

COMMENT ON FUNCTION public.expire_admission_offers() IS
'Marks ISSUED admission offers as EXPIRED when their expiry date has passed.';

