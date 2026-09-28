-- ============================================================
-- IDMC iMIS
-- Acceptance -> Application synchronization compatibility fix
--
-- Current applications table uses:
--     status
--
-- NOT:
--     application_status
--
-- No table dropped.
-- No data deleted.
-- No admission record recreated.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.sync_application_after_admission_acceptance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$

DECLARE
    v_application_id uuid;

BEGIN

    SELECT application_id
    INTO v_application_id
    FROM public.admission_offers
    WHERE id = NEW.admission_offer_id;

    IF v_application_id IS NULL THEN
        RAISE EXCEPTION
            'No application found for admission offer %',
            NEW.admission_offer_id;
    END IF;


    IF NEW.acceptance_status = 'ACCEPTED' THEN

        UPDATE public.applications
        SET
            status = 'ACCEPTED',
            updated_at = now()
        WHERE id = v_application_id
          AND status IN (
              'SUBMITTED',
              'UNDER_REVIEW',
              'ELIGIBLE',
              'SELECTED',
              'ADMISSION_OFFERED',
              'ACCEPTED'
          );

    ELSIF NEW.acceptance_status = 'DECLINED' THEN

        UPDATE public.applications
        SET
            status = 'REJECTED',
            updated_at = now()
        WHERE id = v_application_id
          AND status <> 'CONVERTED_TO_STUDENT';

    END IF;


    RETURN NEW;

END;
$function$;


DROP TRIGGER IF EXISTS
    trg_sync_application_after_admission_acceptance
ON public.admission_acceptances;


CREATE TRIGGER trg_sync_application_after_admission_acceptance
AFTER INSERT OR UPDATE OF acceptance_status
ON public.admission_acceptances
FOR EACH ROW
EXECUTE FUNCTION public.sync_application_after_admission_acceptance();


COMMENT ON FUNCTION
public.sync_application_after_admission_acceptance()
IS
'Synchronizes admission acceptance with applications.status.';


COMMIT;
