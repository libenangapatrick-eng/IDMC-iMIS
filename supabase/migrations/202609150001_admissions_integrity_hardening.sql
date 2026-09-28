-- ============================================================
-- IDMC iMIS
-- Migration: Admissions Integrity Hardening
-- Version: 202609150001
-- ============================================================

-- ------------------------------------------------------------
-- 1. Only one active admission offer per application
-- ------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_admission_offer_application
ON public.admission_offers (application_id)
WHERE offer_status IN ('ISSUED', 'ACCEPTED');


-- ------------------------------------------------------------
-- 2. Only one approved admission decision per application
-- ------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_approved_admission_decision_application
ON public.admission_decisions (application_id)
WHERE decision_status = 'APPROVED';


-- ------------------------------------------------------------
-- 3. Only one accepted acceptance per offer
-- ------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_accepted_admission_offer
ON public.admission_acceptances (admission_offer_id)
WHERE acceptance_status = 'ACCEPTED';


-- ------------------------------------------------------------
-- 4. Validate admission decision belongs to application choice
-- ------------------------------------------------------------
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


DROP TRIGGER IF EXISTS trg_validate_admission_decision_application
ON public.admission_decisions;

CREATE TRIGGER trg_validate_admission_decision_application
BEFORE INSERT OR UPDATE
ON public.admission_decisions
FOR EACH ROW
EXECUTE FUNCTION public.validate_admission_decision_application();


-- ------------------------------------------------------------
-- 5. Validate admission offer
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_admission_offer()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    -- Offer must reference a valid application choice
    IF NOT EXISTS (
        SELECT 1
        FROM public.application_choices ac
        WHERE ac.id = NEW.application_choice_id
          AND ac.application_id = NEW.application_id
    ) THEN
        RAISE EXCEPTION
            'Admission offer choice does not belong to the specified application';
    END IF;


    -- Offer must reference a valid approved decision
    IF NEW.admission_decision_id IS NOT NULL THEN

        IF NOT EXISTS (
            SELECT 1
            FROM public.admission_decisions ad
            WHERE ad.id = NEW.admission_decision_id
              AND ad.application_id = NEW.application_id
              AND ad.decision_status = 'APPROVED'
        ) THEN
            RAISE EXCEPTION
                'Admission offer must reference an approved decision belonging to the same application';
        END IF;

    END IF;


    -- Issued/accepted offers must have expiry date
    IF NEW.offer_status IN ('ISSUED', 'ACCEPTED')
       AND NEW.expiry_date IS NULL THEN
        RAISE EXCEPTION
            'Issued or accepted admission offers must have an expiry date';
    END IF;


    -- Cannot issue an already expired offer
    IF NEW.offer_status = 'ISSUED'
       AND NEW.expiry_date < CURRENT_DATE THEN
        RAISE EXCEPTION
            'Cannot issue an admission offer that has already expired';
    END IF;


    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_admission_offer
ON public.admission_offers;

CREATE TRIGGER trg_validate_admission_offer
BEFORE INSERT OR UPDATE
ON public.admission_offers
FOR EACH ROW
EXECUTE FUNCTION public.validate_admission_offer();


-- ------------------------------------------------------------
-- 6. Validate acceptance
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_admission_acceptance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_offer_status varchar;
    v_expiry_date date;
BEGIN

    SELECT offer_status, expiry_date
    INTO v_offer_status, v_expiry_date
    FROM public.admission_offers
    WHERE id = NEW.admission_offer_id
    FOR UPDATE;


    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Admission offer does not exist';
    END IF;


    -- Only issued offers can be accepted
    IF NEW.acceptance_status = 'ACCEPTED'
       AND v_offer_status <> 'ISSUED' THEN
        RAISE EXCEPTION
            'Only an ISSUED admission offer can be accepted';
    END IF;


    -- Expired offer cannot be accepted
    IF NEW.acceptance_status = 'ACCEPTED'
       AND v_expiry_date < CURRENT_DATE THEN
        RAISE EXCEPTION
            'Admission offer has expired and cannot be accepted';
    END IF;


    -- Automatically record acceptance time
    IF NEW.acceptance_status = 'ACCEPTED'
       AND NEW.accepted_at IS NULL THEN
        NEW.accepted_at := now();
    END IF;


    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_admission_acceptance
ON public.admission_acceptances;

CREATE TRIGGER trg_validate_admission_acceptance
BEFORE INSERT OR UPDATE
ON public.admission_acceptances
FOR EACH ROW
EXECUTE FUNCTION public.validate_admission_acceptance();


-- ------------------------------------------------------------
-- 7. Prevent invalid offer status transitions
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prevent_invalid_offer_status_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.offer_status = 'ACCEPTED'
       AND NEW.offer_status = 'ISSUED' THEN
        RAISE EXCEPTION
            'An ACCEPTED admission offer cannot return to ISSUED';
    END IF;


    IF OLD.offer_status = 'EXPIRED'
       AND NEW.offer_status = 'ISSUED' THEN
        RAISE EXCEPTION
            'An EXPIRED admission offer cannot return to ISSUED';
    END IF;


    IF OLD.offer_status = 'CANCELLED'
       AND NEW.offer_status = 'ISSUED' THEN
        RAISE EXCEPTION
            'A CANCELLED admission offer cannot return to ISSUED';
    END IF;


    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_prevent_invalid_offer_status_change
ON public.admission_offers;

CREATE TRIGGER trg_prevent_invalid_offer_status_change
BEFORE UPDATE OF offer_status
ON public.admission_offers
FOR EACH ROW
EXECUTE FUNCTION public.prevent_invalid_offer_status_change();


-- ------------------------------------------------------------
-- 8. Synchronize offer status after acceptance
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_admission_offer_after_acceptance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.acceptance_status = 'ACCEPTED' THEN

        UPDATE public.admission_offers
        SET offer_status = 'ACCEPTED',
            updated_at = now()
        WHERE id = NEW.admission_offer_id;

    ELSIF NEW.acceptance_status = 'DECLINED' THEN

        UPDATE public.admission_offers
        SET offer_status = 'CANCELLED',
            updated_at = now()
        WHERE id = NEW.admission_offer_id;

    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_sync_admission_offer_after_acceptance
ON public.admission_acceptances;

CREATE TRIGGER trg_sync_admission_offer_after_acceptance
AFTER INSERT OR UPDATE
ON public.admission_acceptances
FOR EACH ROW
EXECUTE FUNCTION public.sync_admission_offer_after_acceptance();


-- ------------------------------------------------------------
-- 9. Synchronize application after acceptance
-- ------------------------------------------------------------
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
        SET application_status = 'ACCEPTED',
            updated_at = now()
        WHERE id = v_application_id
          AND application_status IN ('SELECTED', 'ADMISSION_OFFERED');

    ELSIF NEW.acceptance_status = 'DECLINED' THEN

        UPDATE public.applications
        SET application_status = 'REJECTED',
            updated_at = now()
        WHERE id = v_application_id
          AND application_status IN ('SELECTED', 'ADMISSION_OFFERED');

    END IF;


    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_sync_application_after_admission_acceptance
ON public.admission_acceptances;

CREATE TRIGGER trg_sync_application_after_admission_acceptance
AFTER INSERT OR UPDATE
ON public.admission_acceptances
FOR EACH ROW
EXECUTE FUNCTION public.sync_application_after_admission_acceptance();


-- ------------------------------------------------------------
-- 10. Automatic offer expiry
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_admission_offers()
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_count integer;
BEGIN

    UPDATE public.admission_offers
    SET offer_status = 'EXPIRED',
        updated_at = now()
    WHERE offer_status = 'ISSUED'
      AND expiry_date < CURRENT_DATE;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN v_count;
END;
$$;


-- ------------------------------------------------------------
-- 11. Enable pg_cron if available
-- ------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;


-- ------------------------------------------------------------
-- 12. Schedule daily automatic expiry
-- Tanzania = UTC+3
-- 00:05 UTC = 03:05 Tanzania
-- ------------------------------------------------------------
DO $schedule$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM cron.job
        WHERE jobname = 'idmc-expire-admission-offers'
    ) THEN

        PERFORM cron.schedule(
            'idmc-expire-admission-offers',
            '5 0 * * *',
            'SELECT public.expire_admission_offers();'
        );

    END IF;

END
$schedule$;


-- ------------------------------------------------------------
-- 13. Documentation
-- ------------------------------------------------------------
COMMENT ON INDEX public.uq_active_admission_offer_application IS
'Prevents more than one active admission offer per application.';

COMMENT ON INDEX public.uq_approved_admission_decision_application IS
'Prevents more than one approved admission decision per application.';

COMMENT ON INDEX public.uq_accepted_admission_offer IS
'Prevents multiple accepted admission acceptance records for one offer.';

COMMENT ON FUNCTION public.expire_admission_offers() IS
'Automatically changes expired ISSUED admission offers to EXPIRED.';
