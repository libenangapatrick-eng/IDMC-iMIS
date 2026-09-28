-- ============================================================
-- 202609150024
-- FINANCE BALANCE INTEGRITY HARDENING
--
-- Correct authoritative balance:
--
--   total_charged - total_paid + total_refunded
--
-- Scholarships, waivers and adjustments are already reflected
-- in student_charges.net_amount.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Temporarily remove dependent view
-- ------------------------------------------------------------

DROP VIEW IF EXISTS public.v_student_financial_summary;

-- ------------------------------------------------------------
-- 2. Replace current_balance generated formula
-- ------------------------------------------------------------

ALTER TABLE public.student_financial_accounts
DROP COLUMN current_balance;

ALTER TABLE public.student_financial_accounts
ADD COLUMN current_balance numeric
GENERATED ALWAYS AS (
    total_charged
    - total_paid
    + total_refunded
) STORED;

-- ------------------------------------------------------------
-- 3. Recreate the financial summary view
-- ------------------------------------------------------------

CREATE VIEW public.v_student_financial_summary
WITH (security_invoker = true)
AS
SELECT
    student_id,
    total_charged,
    total_paid,
    total_refunded,
    total_scholarship,
    total_waiver,
    total_adjustments,
    current_balance,
    account_status,
    last_calculated_at
FROM public.student_financial_accounts;

-- ------------------------------------------------------------
-- 4. Replace financial account refresh function
-- ------------------------------------------------------------

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
        RAISE EXCEPTION 'Student ID is required';
    END IF;

    -- Ensure financial account exists.
    PERFORM public.ensure_student_financial_account(p_student_id);

    -- --------------------------------------------------------
    -- Charges
    --
    -- net_amount is authoritative because it already contains:
    --
    -- original_amount
    -- - scholarship
    -- - waiver
    -- + adjustment
    -- --------------------------------------------------------

    SELECT
        COALESCE(SUM(
            CASE
                WHEN sc.status NOT IN ('CANCELLED', 'REVERSED')
                THEN sc.net_amount
                ELSE 0
            END
        ), 0),

        COALESCE(SUM(
            CASE
                WHEN sc.status NOT IN ('CANCELLED', 'REVERSED')
                THEN sc.scholarship_amount
                ELSE 0
            END
        ), 0),

        COALESCE(SUM(
            CASE
                WHEN sc.status NOT IN ('CANCELLED', 'REVERSED')
                THEN sc.waiver_amount
                ELSE 0
            END
        ), 0),

        COALESCE(SUM(
            CASE
                WHEN sc.status NOT IN ('CANCELLED', 'REVERSED')
                THEN sc.adjustment_amount
                ELSE 0
            END
        ), 0)

    INTO
        v_total_charged,
        v_total_scholarship,
        v_total_waiver,
        v_total_adjustments

    FROM public.student_charges sc
    WHERE sc.student_id = p_student_id;

    -- --------------------------------------------------------
    -- Payments
    --
    -- Only active allocations connected to non-reversed
    -- payments are included.
    -- --------------------------------------------------------

    SELECT
        COALESCE(SUM(pa.allocated_amount), 0)

    INTO v_total_paid

    FROM public.payment_allocations pa

    JOIN public.payments p
      ON p.id = pa.payment_id

    WHERE pa.student_id = p_student_id
      AND COALESCE(pa.status, 'ACTIVE')
            NOT IN ('CANCELLED', 'REVERSED')
      AND COALESCE(p.status, 'POSTED')
            NOT IN ('CANCELLED', 'REVERSED');

    -- --------------------------------------------------------
    -- Refunds
    -- --------------------------------------------------------

    SELECT
        COALESCE(SUM(r.amount), 0)

    INTO v_total_refunded

    FROM public.refunds r

    WHERE r.student_id = p_student_id
      AND COALESCE(r.status, 'APPROVED')
            IN ('APPROVED', 'COMPLETED', 'POSTED');

    -- --------------------------------------------------------
    -- Update account.
    --
    -- current_balance is generated automatically:
    --
    -- total_charged
    -- - total_paid
    -- + total_refunded
    --
    -- Scholarships, waivers and adjustments are informational
    -- aggregates only because they are already reflected in
    -- net_amount.
    -- --------------------------------------------------------

    UPDATE public.student_financial_accounts

    SET
        total_charged = v_total_charged,
        total_paid = v_total_paid,
        total_refunded = v_total_refunded,
        total_scholarship = v_total_scholarship,
        total_waiver = v_total_waiver,
        total_adjustments = v_total_adjustments,
        last_calculated_at = now(),
        updated_at = now()

    WHERE student_id = p_student_id;

END;
$$;

-- ------------------------------------------------------------
-- 5. Ensure one account per student
-- ------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS
uq_student_financial_account
ON public.student_financial_accounts(student_id);

-- ------------------------------------------------------------
-- 6. Amount safety
-- ------------------------------------------------------------

ALTER TABLE public.student_financial_accounts
DROP CONSTRAINT IF EXISTS chk_student_financial_account_amounts;

ALTER TABLE public.student_financial_accounts
ADD CONSTRAINT chk_student_financial_account_amounts
CHECK (
    total_charged >= 0
    AND total_paid >= 0
    AND total_refunded >= 0
    AND total_scholarship >= 0
    AND total_waiver >= 0
);

-- ------------------------------------------------------------
-- 7. Updated-at trigger
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS
trg_student_financial_accounts_updated_at
ON public.student_financial_accounts;

CREATE TRIGGER
trg_student_financial_accounts_updated_at
BEFORE UPDATE
ON public.student_financial_accounts
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- ------------------------------------------------------------
-- 8. Documentation
-- ------------------------------------------------------------

COMMENT ON COLUMN public.student_financial_accounts.total_charged
IS 'Authoritative net student charges based on student_charges.net_amount.';

COMMENT ON COLUMN public.student_financial_accounts.total_scholarship
IS 'Informational aggregate of scholarships already reflected in net charges.';

COMMENT ON COLUMN public.student_financial_accounts.total_waiver
IS 'Informational aggregate of waivers already reflected in net charges.';

COMMENT ON COLUMN public.student_financial_accounts.total_adjustments
IS 'Informational aggregate of adjustments already reflected in net charges.';

COMMENT ON COLUMN public.student_financial_accounts.current_balance
IS 'Authoritative student balance: total_charged - total_paid + total_refunded.';

COMMIT;
