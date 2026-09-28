-- ============================================================
-- IDMC iMIS
-- Migration 025
-- Finance Refresh Student Financial Account Fix
-- ============================================================

CREATE OR REPLACE FUNCTION public.refresh_student_financial_account(
    p_student_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_total_charged numeric := 0;
    v_total_paid numeric := 0;
    v_total_refunded numeric := 0;
    v_total_scholarship numeric := 0;
    v_total_waiver numeric := 0;
    v_total_adjustments numeric := 0;
BEGIN

    IF p_student_id IS NULL THEN
        RAISE EXCEPTION 'Student ID cannot be null';
    END IF;

    /*
     * ----------------------------------------------------------
     * TOTAL CHARGED
     * ----------------------------------------------------------
     * student_charges.net_amount is authoritative because it
     * already represents the net charge after scholarship,
     * waiver and adjustments.
     */
    SELECT
        COALESCE(SUM(sc.net_amount), 0)
    INTO v_total_charged
    FROM public.student_charges sc
    WHERE sc.student_id = p_student_id
      AND COALESCE(sc.status, 'ACTIVE')
            NOT IN ('CANCELLED', 'VOID', 'REVERSED');


    /*
     * ----------------------------------------------------------
     * SCHOLARSHIP INFORMATION
     * ----------------------------------------------------------
     */
    SELECT
        COALESCE(SUM(sc.scholarship_amount), 0)
    INTO v_total_scholarship
    FROM public.student_charges sc
    WHERE sc.student_id = p_student_id
      AND COALESCE(sc.status, 'ACTIVE')
            NOT IN ('CANCELLED', 'VOID', 'REVERSED');


    /*
     * ----------------------------------------------------------
     * WAIVER INFORMATION
     * ----------------------------------------------------------
     */
    SELECT
        COALESCE(SUM(sc.waiver_amount), 0)
    INTO v_total_waiver
    FROM public.student_charges sc
    WHERE sc.student_id = p_student_id
      AND COALESCE(sc.status, 'ACTIVE')
            NOT IN ('CANCELLED', 'VOID', 'REVERSED');


    /*
     * ----------------------------------------------------------
     * ADJUSTMENT INFORMATION
     * ----------------------------------------------------------
     */
    SELECT
        COALESCE(SUM(sc.adjustment_amount), 0)
    INTO v_total_adjustments
    FROM public.student_charges sc
    WHERE sc.student_id = p_student_id
      AND COALESCE(sc.status, 'ACTIVE')
            NOT IN ('CANCELLED', 'VOID', 'REVERSED');


    /*
     * ----------------------------------------------------------
     * TOTAL PAID
     * ----------------------------------------------------------
     * payment_allocations does NOT contain student_id.
     *
     * Correct relationship:
     *
     * payment_allocations.payment_id
     *        ->
     * payments.id
     *        ->
     * payments.student_id
     */
    SELECT
        COALESCE(SUM(pa.allocated_amount), 0)
    INTO v_total_paid
    FROM public.payment_allocations pa
    JOIN public.payments p
      ON p.id = pa.payment_id
    WHERE p.student_id = p_student_id
      AND COALESCE(pa.status, 'ACTIVE')
            NOT IN ('CANCELLED', 'REVERSED')
      AND COALESCE(p.status, 'POSTED')
            NOT IN ('CANCELLED', 'REVERSED');


    /*
     * ----------------------------------------------------------
     * TOTAL REFUNDED
     * ----------------------------------------------------------
     */
    SELECT
        COALESCE(SUM(r.amount), 0)
    INTO v_total_refunded
    FROM public.refunds r
    WHERE r.student_id = p_student_id
      AND COALESCE(r.status, 'APPROVED')
            IN ('APPROVED', 'PROCESSED', 'COMPLETED', 'POSTED');


    /*
     * ----------------------------------------------------------
     * SAFETY NORMALIZATION
     * ----------------------------------------------------------
     */
    v_total_charged :=
        GREATEST(COALESCE(v_total_charged, 0), 0);

    v_total_paid :=
        GREATEST(COALESCE(v_total_paid, 0), 0);

    v_total_refunded :=
        GREATEST(COALESCE(v_total_refunded, 0), 0);

    v_total_scholarship :=
        GREATEST(COALESCE(v_total_scholarship, 0), 0);

    v_total_waiver :=
        GREATEST(COALESCE(v_total_waiver, 0), 0);

    v_total_adjustments :=
        COALESCE(v_total_adjustments, 0);


    /*
     * ----------------------------------------------------------
     * UPSERT STUDENT FINANCIAL ACCOUNT
     * ----------------------------------------------------------
     *
     * current_balance is GENERATED ALWAYS and therefore is NOT
     * written directly here.
     *
     * Current balance formula from migration 024:
     *
     * total_charged - total_paid + total_refunded
     *
     * Scholarship, waiver and adjustment values remain
     * informational because they are already incorporated into
     * student_charges.net_amount.
     */
    INSERT INTO public.student_financial_accounts (
        student_id,
        total_charged,
        total_paid,
        total_refunded,
        total_scholarship,
        total_waiver,
        total_adjustments,
        last_calculated_at,
        updated_at
    )
    VALUES (
        p_student_id,
        v_total_charged,
        v_total_paid,
        v_total_refunded,
        v_total_scholarship,
        v_total_waiver,
        v_total_adjustments,
        now(),
        now()
    )
    ON CONFLICT (student_id)
    DO UPDATE SET
        total_charged      = EXCLUDED.total_charged,
        total_paid        = EXCLUDED.total_paid,
        total_refunded    = EXCLUDED.total_refunded,
        total_scholarship = EXCLUDED.total_scholarship,
        total_waiver      = EXCLUDED.total_waiver,
        total_adjustments = EXCLUDED.total_adjustments,
        last_calculated_at = now(),
        updated_at = now();

END;
$$;


COMMENT ON FUNCTION public.refresh_student_financial_account(uuid)
IS 'Recalculates a student financial account using authoritative net charges, payment allocations linked through payments.student_id, and valid refunds.';


-- Ensure backend/application roles can execute the function.
GRANT EXECUTE ON FUNCTION public.refresh_student_financial_account(uuid)
TO authenticated;

GRANT EXECUTE ON FUNCTION public.refresh_student_financial_account(uuid)
TO service_role;
