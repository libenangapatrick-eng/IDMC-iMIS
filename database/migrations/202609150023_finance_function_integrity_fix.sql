-- ============================================================
-- 202609150023
-- FINANCE FUNCTION INTEGRITY FIX
-- Fixes post_financial_transaction() to use reference_number
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Replace the incorrect financial transaction function
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.post_financial_transaction(
    p_transaction_number varchar,
    p_student_id uuid,
    p_transaction_type varchar,
    p_debit numeric,
    p_credit numeric,
    p_reference varchar,
    p_description text,
    p_created_by uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_transaction_id uuid;
BEGIN

    -- Transaction number is required
    IF NULLIF(trim(p_transaction_number), '') IS NULL THEN
        RAISE EXCEPTION 'Transaction number is required';
    END IF;

    -- Transaction type is required
    IF NULLIF(trim(p_transaction_type), '') IS NULL THEN
        RAISE EXCEPTION 'Transaction type is required';
    END IF;

    -- Amounts must not be negative
    IF COALESCE(p_debit, 0) < 0 THEN
        RAISE EXCEPTION 'Debit amount cannot be negative';
    END IF;

    IF COALESCE(p_credit, 0) < 0 THEN
        RAISE EXCEPTION 'Credit amount cannot be negative';
    END IF;

    -- Exactly one side must contain an amount
    IF COALESCE(p_debit, 0) = 0
       AND COALESCE(p_credit, 0) = 0 THEN
        RAISE EXCEPTION 'Either debit or credit must be greater than zero';
    END IF;

    IF COALESCE(p_debit, 0) > 0
       AND COALESCE(p_credit, 0) > 0 THEN
        RAISE EXCEPTION 'Debit and credit cannot both be greater than zero';
    END IF;

    -- Prevent duplicate transaction numbers
    IF EXISTS (
        SELECT 1
        FROM public.financial_transactions
        WHERE transaction_number = p_transaction_number
    ) THEN
        RAISE EXCEPTION
            'Financial transaction number already exists: %',
            p_transaction_number;
    END IF;

    -- Insert using the ACTUAL column name: reference_number
    INSERT INTO public.financial_transactions (
        transaction_number,
        student_id,
        transaction_type,
        debit_amount,
        credit_amount,
        transaction_date,
        reference_number,
        description,
        status,
        created_by
    )
    VALUES (
        p_transaction_number,
        p_student_id,
        p_transaction_type,
        COALESCE(p_debit, 0),
        COALESCE(p_credit, 0),
        now(),
        p_reference,
        p_description,
        'POSTED',
        p_created_by
    )
    RETURNING id
    INTO v_transaction_id;

    -- Refresh student financial account where applicable
    IF p_student_id IS NOT NULL THEN
        PERFORM public.refresh_student_financial_account(p_student_id);
    END IF;

    RETURN v_transaction_id;
END;
$$;

-- ------------------------------------------------------------
-- 2. Remove direct execution privileges
-- Backend/service layer should control this operation.
-- ------------------------------------------------------------

REVOKE ALL
ON FUNCTION public.post_financial_transaction(
    varchar,
    uuid,
    varchar,
    numeric,
    numeric,
    varchar,
    text,
    uuid
)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.post_financial_transaction(
    varchar,
    uuid,
    varchar,
    numeric,
    numeric,
    varchar,
    text,
    uuid
)
FROM anon;

REVOKE ALL
ON FUNCTION public.post_financial_transaction(
    varchar,
    uuid,
    varchar,
    numeric,
    numeric,
    varchar,
    text,
    uuid
)
FROM authenticated;

-- ------------------------------------------------------------
-- 3. Row-level validation for financial transactions
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_financial_transaction_row()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NULLIF(trim(NEW.transaction_number), '') IS NULL THEN
        RAISE EXCEPTION 'Transaction number is required';
    END IF;

    IF NEW.debit_amount < 0 THEN
        RAISE EXCEPTION 'Debit amount cannot be negative';
    END IF;

    IF NEW.credit_amount < 0 THEN
        RAISE EXCEPTION 'Credit amount cannot be negative';
    END IF;

    IF NEW.debit_amount = 0
       AND NEW.credit_amount = 0 THEN
        RAISE EXCEPTION
            'Either debit or credit must be greater than zero';
    END IF;

    IF NEW.debit_amount > 0
       AND NEW.credit_amount > 0 THEN
        RAISE EXCEPTION
            'Debit and credit cannot both be greater than zero';
    END IF;

    IF NEW.transaction_date IS NULL THEN
        NEW.transaction_date := now();
    END IF;

    IF NEW.status IS NULL
       OR NULLIF(trim(NEW.status), '') IS NULL THEN
        NEW.status := 'POSTED';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_financial_transaction
ON public.financial_transactions;

CREATE TRIGGER trg_validate_financial_transaction
BEFORE INSERT OR UPDATE
ON public.financial_transactions
FOR EACH ROW
EXECUTE FUNCTION public.validate_financial_transaction_row();

-- ------------------------------------------------------------
-- 4. Protect posted transactions from financial tampering
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.protect_posted_financial_transaction()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.status = 'POSTED' THEN

        IF NEW.transaction_number IS DISTINCT FROM OLD.transaction_number THEN
            RAISE EXCEPTION
                'Posted transaction number cannot be changed';
        END IF;

        IF NEW.student_id IS DISTINCT FROM OLD.student_id THEN
            RAISE EXCEPTION
                'Posted transaction student cannot be changed';
        END IF;

        IF NEW.transaction_type IS DISTINCT FROM OLD.transaction_type THEN
            RAISE EXCEPTION
                'Posted transaction type cannot be changed';
        END IF;

        IF NEW.debit_amount IS DISTINCT FROM OLD.debit_amount THEN
            RAISE EXCEPTION
                'Posted debit amount cannot be changed';
        END IF;

        IF NEW.credit_amount IS DISTINCT FROM OLD.credit_amount THEN
            RAISE EXCEPTION
                'Posted credit amount cannot be changed';
        END IF;

        IF NEW.reference_number IS DISTINCT FROM OLD.reference_number THEN
            RAISE EXCEPTION
                'Posted transaction reference cannot be changed';
        END IF;

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_posted_financial_transaction
ON public.financial_transactions;

CREATE TRIGGER trg_protect_posted_financial_transaction
BEFORE UPDATE
ON public.financial_transactions
FOR EACH ROW
EXECUTE FUNCTION public.protect_posted_financial_transaction();

-- ------------------------------------------------------------
-- 5. Prevent hard deletion of financial transactions
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.prevent_financial_transaction_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'Financial transactions cannot be hard deleted. Use reversal/adjustment workflow.';
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_financial_transaction_delete
ON public.financial_transactions;

CREATE TRIGGER trg_prevent_financial_transaction_delete
BEFORE DELETE
ON public.financial_transactions
FOR EACH ROW
EXECUTE FUNCTION public.prevent_financial_transaction_delete();

COMMIT;
