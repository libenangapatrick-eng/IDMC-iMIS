-- ============================================================
-- IDMC iMIS
-- Admission Offer schema compatibility repair
--
-- Current admission_offers contract:
--   application_id
--   programme_id
--   decision_id
--   offer_number
--   offer_date
--   expiry_date
--   offer_status
--
-- Old trigger referenced:
--   application_choice_id
--   admission_decision_id
--
-- This migration aligns the trigger with the live schema.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.validate_admission_offer()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_choice_exists boolean;
BEGIN

    -- --------------------------------------------------------
    -- Application must exist
    -- --------------------------------------------------------

    IF NOT EXISTS (
        SELECT 1
        FROM public.applications a
        WHERE a.id = NEW.application_id
    ) THEN
        RAISE EXCEPTION
            'Admission offer references invalid application %',
            NEW.application_id;
    END IF;


    -- --------------------------------------------------------
    -- Programme must belong to one of this application's
    -- programme choices.
    --
    -- admission_offers now stores programme_id rather than
    -- application_choice_id.
    -- --------------------------------------------------------

    SELECT EXISTS (
        SELECT 1
        FROM public.application_choices ac
        WHERE ac.application_id = NEW.application_id
          AND ac.programme_id = NEW.programme_id
    )
    INTO v_choice_exists;

    IF NOT v_choice_exists THEN
        RAISE EXCEPTION
            'Admission offer programme % is not a choice of application %',
            NEW.programme_id,
            NEW.application_id;
    END IF;


    -- --------------------------------------------------------
    -- Decision validation.
    --
    -- admission_offers now stores decision_id rather than
    -- admission_decision_id.
    -- --------------------------------------------------------

    IF NEW.decision_id IS NOT NULL THEN

        IF NOT EXISTS (
            SELECT 1
            FROM public.admission_decisions ad
            WHERE ad.id = NEW.decision_id
              AND ad.application_id = NEW.application_id
              AND ad.decision_status = 'APPROVED'
        ) THEN
            RAISE EXCEPTION
                'Admission offer decision % must be APPROVED and belong to application %',
                NEW.decision_id,
                NEW.application_id;
        END IF;

    END IF;


    -- --------------------------------------------------------
    -- Issued / accepted offers require expiry date
    -- --------------------------------------------------------

    IF NEW.offer_status IN ('ISSUED', 'ACCEPTED')
       AND NEW.expiry_date IS NULL THEN

        RAISE EXCEPTION
            'Issued or accepted admission offers must have an expiry date';

    END IF;


    -- --------------------------------------------------------
    -- Cannot issue an expired offer
    -- --------------------------------------------------------

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


COMMENT ON FUNCTION public.validate_admission_offer()
IS
'Validates admission offers using current schema: application_id, programme_id and decision_id.';


COMMIT;
