
BEGIN;

-- ============================================================
-- IDMC iMIS
-- Migration 021
-- Finance & Student Billing Core
-- ============================================================

DO $$
BEGIN
    IF to_regclass('public.students') IS NULL THEN
        RAISE EXCEPTION 'Migration 021 dependency missing: public.students does not exist';
    END IF;
END $$;

-- ============================================================
-- 1. FEE STRUCTURES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.fee_structures (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    fee_structure_code varchar(100) NOT NULL UNIQUE,
    fee_structure_name varchar(200) NOT NULL,

    academic_year varchar(20),
    semester varchar(50),

    description text,

    status varchar(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (status IN (
            'DRAFT',
            'ACTIVE',
            'INACTIVE',
            'ARCHIVED'
        )),

    currency_code varchar(10) NOT NULL DEFAULT 'TZS',

    effective_from date,
    effective_to date,

    created_by uuid,
    updated_by uuid,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_fee_structure_dates
        CHECK (
            effective_to IS NULL
            OR effective_from IS NULL
            OR effective_to >= effective_from
        )
);

-- ============================================================
-- 2. FEE ITEMS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.fee_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    fee_structure_id uuid NOT NULL
        REFERENCES public.fee_structures(id),

    fee_item_code varchar(100) NOT NULL,
    fee_item_name varchar(200) NOT NULL,

    category varchar(50) NOT NULL DEFAULT 'OTHER'
        CHECK (category IN (
            'TUITION',
            'REGISTRATION',
            'EXAMINATION',
            'LIBRARY',
            'HOSTEL',
            'MEDICAL',
            'STUDENT_ID',
            'ICT',
            'FIELD_PRACTICAL',
            'CLINICAL',
            'GRADUATION',
            'CERTIFICATION',
            'LATE_FEE',
            'OTHER'
        )),

    description text,

    amount numeric(18,2) NOT NULL DEFAULT 0
        CHECK (amount >= 0),

    is_mandatory boolean NOT NULL DEFAULT true,
    is_refundable boolean NOT NULL DEFAULT false,

    display_order integer NOT NULL DEFAULT 0,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_fee_item_structure_code
        UNIQUE (fee_structure_id, fee_item_code)
);

-- ============================================================
-- 3. STUDENT CHARGES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_charges (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL
        REFERENCES public.students(id),

    fee_structure_id uuid
        REFERENCES public.fee_structures(id),

    fee_item_id uuid
        REFERENCES public.fee_items(id),

    charge_number varchar(100) NOT NULL UNIQUE,

    description varchar(255) NOT NULL,

    academic_year varchar(20),
    semester varchar(50),

    original_amount numeric(18,2) NOT NULL
        CHECK (original_amount >= 0),

    scholarship_amount numeric(18,2) NOT NULL DEFAULT 0
        CHECK (scholarship_amount >= 0),

    waiver_amount numeric(18,2) NOT NULL DEFAULT 0
        CHECK (waiver_amount >= 0),

    adjustment_amount numeric(18,2) NOT NULL DEFAULT 0,

    net_amount numeric(18,2)
        GENERATED ALWAYS AS (
            original_amount
            - scholarship_amount
            - waiver_amount
            + adjustment_amount
        ) STORED,

    status varchar(30) NOT NULL DEFAULT 'POSTED'
        CHECK (status IN (
            'DRAFT',
            'POSTED',
            'PARTIALLY_PAID',
            'PAID',
            'WAIVED',
            'CANCELLED',
            'REVERSED'
        )),

    charge_date date NOT NULL DEFAULT CURRENT_DATE,

    due_date date,

    created_by uuid,
    updated_by uuid,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_student_charge_discount
        CHECK (
            scholarship_amount + waiver_amount <= original_amount
        ),

    CONSTRAINT chk_student_charge_net
        CHECK (net_amount >= 0),

    CONSTRAINT chk_student_charge_due_date
        CHECK (
            due_date IS NULL
            OR due_date >= charge_date
        )
);

-- ============================================================
-- 4. INVOICES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.invoices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL
        REFERENCES public.students(id),

    invoice_number varchar(100) NOT NULL UNIQUE,

    invoice_date date NOT NULL DEFAULT CURRENT_DATE,
    due_date date,

    academic_year varchar(20),
    semester varchar(50),

    subtotal numeric(18,2) NOT NULL DEFAULT 0
        CHECK (subtotal >= 0),

    discount_amount numeric(18,2) NOT NULL DEFAULT 0
        CHECK (discount_amount >= 0),

    scholarship_amount numeric(18,2) NOT NULL DEFAULT 0
        CHECK (scholarship_amount >= 0),

    adjustment_amount numeric(18,2) NOT NULL DEFAULT 0,

    total_amount numeric(18,2) NOT NULL DEFAULT 0
        CHECK (total_amount >= 0),

    amount_paid numeric(18,2) NOT NULL DEFAULT 0
        CHECK (amount_paid >= 0),

    balance_amount numeric(18,2) NOT NULL DEFAULT 0
        CHECK (balance_amount >= 0),

    status varchar(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (status IN (
            'DRAFT',
            'ISSUED',
            'PARTIALLY_PAID',
            'PAID',
            'OVERDUE',
            'CANCELLED',
            'VOID'
        )),

    currency_code varchar(10) NOT NULL DEFAULT 'TZS',

    notes text,

    issued_by uuid,
    issued_at timestamptz,

    created_by uuid,
    updated_by uuid,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_invoice_dates
        CHECK (
            due_date IS NULL
            OR due_date >= invoice_date
        ),

    CONSTRAINT chk_invoice_paid_not_exceed_total
        CHECK (amount_paid <= total_amount),

    CONSTRAINT chk_invoice_balance
        CHECK (balance_amount = total_amount - amount_paid)
);

-- ============================================================
-- 5. INVOICE ITEMS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.invoice_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    invoice_id uuid NOT NULL
        REFERENCES public.invoices(id)
        ON DELETE CASCADE,

    student_charge_id uuid
        REFERENCES public.student_charges(id),

    description varchar(255) NOT NULL,

    quantity numeric(12,2) NOT NULL DEFAULT 1
        CHECK (quantity > 0),

    unit_amount numeric(18,2) NOT NULL DEFAULT 0
        CHECK (unit_amount >= 0),

    discount_amount numeric(18,2) NOT NULL DEFAULT 0
        CHECK (discount_amount >= 0),

    line_total numeric(18,2)
        GENERATED ALWAYS AS (
            (quantity * unit_amount) - discount_amount
        ) STORED,

    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_invoice_item_discount
        CHECK (discount_amount <= quantity * unit_amount)
);

-- ============================================================
-- 6. PAYMENTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL
        REFERENCES public.students(id),

    payment_number varchar(100) NOT NULL UNIQUE,

    external_reference varchar(150),
    control_number varchar(100),

    payment_method varchar(50) NOT NULL
        CHECK (payment_method IN (
            'CASH',
            'BANK',
            'MOBILE_MONEY',
            'CARD',
            'CONTROL_NUMBER',
            'ONLINE',
            'SCHOLARSHIP',
            'WAIVER',
            'ADJUSTMENT',
            'OTHER'
        )),

    provider varchar(100),

    amount numeric(18,2) NOT NULL
        CHECK (amount > 0),

    currency_code varchar(10) NOT NULL DEFAULT 'TZS',

    payment_date timestamptz NOT NULL DEFAULT now(),

    status varchar(30) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN (
            'PENDING',
            'CONFIRMED',
            'FAILED',
            'REVERSED',
            'REFUNDED',
            'CANCELLED'
        )),

    payer_name varchar(200),
    payer_phone varchar(50),
    payer_email varchar(255),

    provider_transaction_id varchar(200),

    receipt_number varchar(100) UNIQUE,

    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

    confirmed_by uuid,
    confirmed_at timestamptz,

    created_by uuid,
    updated_by uuid,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_payment_external_reference
        UNIQUE (provider, external_reference)
);

-- ============================================================
-- 7. PAYMENT ALLOCATIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.payment_allocations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    payment_id uuid NOT NULL
        REFERENCES public.payments(id),

    invoice_id uuid
        REFERENCES public.invoices(id),

    student_charge_id uuid
        REFERENCES public.student_charges(id),

    allocated_amount numeric(18,2) NOT NULL
        CHECK (allocated_amount > 0),

    allocation_date timestamptz NOT NULL DEFAULT now(),

    allocation_reference varchar(100) UNIQUE,

    status varchar(30) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN (
            'ACTIVE',
            'REVERSED',
            'CANCELLED'
        )),

    created_by uuid,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_payment_allocation_target
        CHECK (
            invoice_id IS NOT NULL
            OR student_charge_id IS NOT NULL
        )
);

-- ============================================================
-- 8. REFUNDS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.refunds (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    payment_id uuid NOT NULL
        REFERENCES public.payments(id),

    student_id uuid NOT NULL
        REFERENCES public.students(id),

    refund_number varchar(100) NOT NULL UNIQUE,

    amount numeric(18,2) NOT NULL
        CHECK (amount > 0),

    reason text NOT NULL,

    refund_method varchar(50),

    status varchar(30) NOT NULL DEFAULT 'REQUESTED'
        CHECK (status IN (
            'REQUESTED',
            'APPROVED',
            'PROCESSING',
            'PAID',
            'REJECTED',
            'CANCELLED'
        )),

    requested_by uuid,
    approved_by uuid,
    processed_by uuid,

    requested_at timestamptz NOT NULL DEFAULT now(),
    approved_at timestamptz,
    processed_at timestamptz,

    external_reference varchar(150),

    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- 9. SCHOLARSHIPS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_scholarships (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL
        REFERENCES public.students(id),

    scholarship_code varchar(100) NOT NULL,
    scholarship_name varchar(200) NOT NULL,

    sponsor_name varchar(200),

    scholarship_type varchar(50) NOT NULL DEFAULT 'PARTIAL'
        CHECK (scholarship_type IN (
            'FULL',
            'PARTIAL',
            'FIXED_AMOUNT',
            'PERCENTAGE'
        )),

    amount numeric(18,2) NOT NULL DEFAULT 0
        CHECK (amount >= 0),

    percentage numeric(7,4)
        CHECK (
            percentage IS NULL
            OR (percentage >= 0 AND percentage <= 100)
        ),

    academic_year varchar(20),
    semester varchar(50),

    start_date date,
    end_date date,

    status varchar(30) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN (
            'PENDING',
            'APPROVED',
            'ACTIVE',
            'SUSPENDED',
            'EXPIRED',
            'CANCELLED'
        )),

    approval_reference varchar(100),

    approved_by uuid,
    approved_at timestamptz,

    notes text,

    created_by uuid,
    updated_by uuid,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_scholarship_dates
        CHECK (
            end_date IS NULL
            OR start_date IS NULL
            OR end_date >= start_date
        )
);

-- ============================================================
-- 10. WAIVERS / DISCOUNTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.student_fee_adjustments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL
        REFERENCES public.students(id),

    student_charge_id uuid
        REFERENCES public.student_charges(id),

    adjustment_number varchar(100) NOT NULL UNIQUE,

    adjustment_type varchar(30) NOT NULL
        CHECK (adjustment_type IN (
            'DISCOUNT',
            'WAIVER',
            'SURCHARGE',
            'CORRECTION',
            'CREDIT',
            'DEBIT'
        )),

    amount numeric(18,2) NOT NULL
        CHECK (amount > 0),

    reason text NOT NULL,

    status varchar(30) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN (
            'PENDING',
            'APPROVED',
            'POSTED',
            'REJECTED',
            'REVERSED'
        )),

    requested_by uuid,
    approved_by uuid,
    posted_by uuid,

    requested_at timestamptz NOT NULL DEFAULT now(),
    approved_at timestamptz,
    posted_at timestamptz,

    reference_number varchar(100),

    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- 11. FINANCIAL TRANSACTIONS / LEDGER
-- ============================================================

CREATE TABLE IF NOT EXISTS public.financial_transactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    transaction_number varchar(100) NOT NULL UNIQUE,

    student_id uuid
        REFERENCES public.students(id),

    payment_id uuid
        REFERENCES public.payments(id),

    invoice_id uuid
        REFERENCES public.invoices(id),

    charge_id uuid
        REFERENCES public.student_charges(id),

    refund_id uuid
        REFERENCES public.refunds(id),

    transaction_type varchar(50) NOT NULL
        CHECK (transaction_type IN (
            'CHARGE',
            'PAYMENT',
            'PAYMENT_REVERSAL',
            'REFUND',
            'SCHOLARSHIP',
            'WAIVER',
            'DISCOUNT',
            'ADJUSTMENT_DEBIT',
            'ADJUSTMENT_CREDIT',
            'OPENING_BALANCE',
            'WRITE_OFF'
        )),

    debit_amount numeric(18,2) NOT NULL DEFAULT 0
        CHECK (debit_amount >= 0),

    credit_amount numeric(18,2) NOT NULL DEFAULT 0
        CHECK (credit_amount >= 0),

    transaction_date timestamptz NOT NULL DEFAULT now(),

    reference_number varchar(150),

    description text NOT NULL,

    status varchar(30) NOT NULL DEFAULT 'POSTED'
        CHECK (status IN (
            'DRAFT',
            'POSTED',
            'REVERSED',
            'CANCELLED'
        )),

    reversal_of uuid
        REFERENCES public.financial_transactions(id),

    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

    created_by uuid,

    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_financial_transaction_amount
        CHECK (
            debit_amount > 0
            OR credit_amount > 0
        ),

    CONSTRAINT chk_financial_transaction_direction
        CHECK (
            NOT (
                debit_amount > 0
                AND credit_amount > 0
            )
        )
);

-- ============================================================
-- 12. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_fee_structures_status
    ON public.fee_structures(status);

CREATE INDEX IF NOT EXISTS idx_fee_items_structure
    ON public.fee_items(fee_structure_id);

CREATE INDEX IF NOT EXISTS idx_fee_items_category
    ON public.fee_items(category);

CREATE INDEX IF NOT EXISTS idx_student_charges_student
    ON public.student_charges(student_id);

CREATE INDEX IF NOT EXISTS idx_student_charges_status
    ON public.student_charges(status);

CREATE INDEX IF NOT EXISTS idx_student_charges_due_date
    ON public.student_charges(due_date);

CREATE INDEX IF NOT EXISTS idx_invoices_student
    ON public.invoices(student_id);

CREATE INDEX IF NOT EXISTS idx_invoices_status
    ON public.invoices(status);

CREATE INDEX IF NOT EXISTS idx_invoices_due_date
    ON public.invoices(due_date);

CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice
    ON public.invoice_items(invoice_id);

CREATE INDEX IF NOT EXISTS idx_payments_student
    ON public.payments(student_id);

CREATE INDEX IF NOT EXISTS idx_payments_status
    ON public.payments(status);

CREATE INDEX IF NOT EXISTS idx_payments_date
    ON public.payments(payment_date);

CREATE INDEX IF NOT EXISTS idx_payments_control_number
    ON public.payments(control_number);

CREATE INDEX IF NOT EXISTS idx_payment_allocations_payment
    ON public.payment_allocations(payment_id);

CREATE INDEX IF NOT EXISTS idx_payment_allocations_invoice
    ON public.payment_allocations(invoice_id);

CREATE INDEX IF NOT EXISTS idx_payment_allocations_charge
    ON public.payment_allocations(student_charge_id);

CREATE INDEX IF NOT EXISTS idx_refunds_payment
    ON public.refunds(payment_id);

CREATE INDEX IF NOT EXISTS idx_refunds_student
    ON public.refunds(student_id);

CREATE INDEX IF NOT EXISTS idx_refunds_status
    ON public.refunds(status);

CREATE INDEX IF NOT EXISTS idx_student_scholarships_student
    ON public.student_scholarships(student_id);

CREATE INDEX IF NOT EXISTS idx_student_scholarships_status
    ON public.student_scholarships(status);

CREATE INDEX IF NOT EXISTS idx_fee_adjustments_student
    ON public.student_fee_adjustments(student_id);

CREATE INDEX IF NOT EXISTS idx_fee_adjustments_charge
    ON public.student_fee_adjustments(student_charge_id);

CREATE INDEX IF NOT EXISTS idx_financial_transactions_student
    ON public.financial_transactions(student_id);

CREATE INDEX IF NOT EXISTS idx_financial_transactions_payment
    ON public.financial_transactions(payment_id);

CREATE INDEX IF NOT EXISTS idx_financial_transactions_invoice
    ON public.financial_transactions(invoice_id);

CREATE INDEX IF NOT EXISTS idx_financial_transactions_date
    ON public.financial_transactions(transaction_date);

CREATE INDEX IF NOT EXISTS idx_financial_transactions_type
    ON public.financial_transactions(transaction_type);

-- ============================================================
-- 13. UPDATED_AT TRIGGER
-- ============================================================

CREATE OR REPLACE FUNCTION public.touch_finance_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fee_structures_updated_at
    ON public.fee_structures;

CREATE TRIGGER trg_fee_structures_updated_at
BEFORE UPDATE ON public.fee_structures
FOR EACH ROW
EXECUTE FUNCTION public.touch_finance_updated_at();

DROP TRIGGER IF EXISTS trg_fee_items_updated_at
    ON public.fee_items;

CREATE TRIGGER trg_fee_items_updated_at
BEFORE UPDATE ON public.fee_items
FOR EACH ROW
EXECUTE FUNCTION public.touch_finance_updated_at();

DROP TRIGGER IF EXISTS trg_student_charges_updated_at
    ON public.student_charges;

CREATE TRIGGER trg_student_charges_updated_at
BEFORE UPDATE ON public.student_charges
FOR EACH ROW
EXECUTE FUNCTION public.touch_finance_updated_at();

DROP TRIGGER IF EXISTS trg_invoices_updated_at
    ON public.invoices;

CREATE TRIGGER trg_invoices_updated_at
BEFORE UPDATE ON public.invoices
FOR EACH ROW
EXECUTE FUNCTION public.touch_finance_updated_at();

DROP TRIGGER IF EXISTS trg_payments_updated_at
    ON public.payments;

CREATE TRIGGER trg_payments_updated_at
BEFORE UPDATE ON public.payments
FOR EACH ROW
EXECUTE FUNCTION public.touch_finance_updated_at();

DROP TRIGGER IF EXISTS trg_payment_allocations_updated_at
    ON public.payment_allocations;

CREATE TRIGGER trg_payment_allocations_updated_at
BEFORE UPDATE ON public.payment_allocations
FOR EACH ROW
EXECUTE FUNCTION public.touch_finance_updated_at();

DROP TRIGGER IF EXISTS trg_refunds_updated_at
    ON public.refunds;

CREATE TRIGGER trg_refunds_updated_at
BEFORE UPDATE ON public.refunds
FOR EACH ROW
EXECUTE FUNCTION public.touch_finance_updated_at();

DROP TRIGGER IF EXISTS trg_student_scholarships_updated_at
    ON public.student_scholarships;

CREATE TRIGGER trg_student_scholarships_updated_at
BEFORE UPDATE ON public.student_scholarships
FOR EACH ROW
EXECUTE FUNCTION public.touch_finance_updated_at();

DROP TRIGGER IF EXISTS trg_student_fee_adjustments_updated_at
    ON public.student_fee_adjustments;

CREATE TRIGGER trg_student_fee_adjustments_updated_at
BEFORE UPDATE ON public.student_fee_adjustments
FOR EACH ROW
EXECUTE FUNCTION public.touch_finance_updated_at();

-- ============================================================
-- 14. PAYMENT INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_payment_integrity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = 'CONFIRMED'
       AND NEW.confirmed_at IS NULL THEN
        NEW.confirmed_at = now();
    END IF;

    IF NEW.status = 'CONFIRMED'
       AND NEW.receipt_number IS NULL THEN
        NEW.receipt_number :=
            'IDMC-RCP-' ||
            to_char(CURRENT_DATE, 'YYYYMMDD') ||
            '-' ||
            upper(substr(replace(NEW.id::text, '-', ''), 1, 10));
    END IF;

    IF NEW.status = 'REVERSED'
       AND OLD.status = 'REVERSED' THEN
        RAISE EXCEPTION
            'Payment % is already reversed',
            NEW.payment_number;
    END IF;

    IF OLD.status = 'CONFIRMED'
       AND NEW.amount <> OLD.amount THEN
        RAISE EXCEPTION
            'Confirmed payment amount cannot be changed';
    END IF;

    IF OLD.status = 'CONFIRMED'
       AND NEW.student_id <> OLD.student_id THEN
        RAISE EXCEPTION
            'Confirmed payment student cannot be changed';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_payment_integrity
    ON public.payments;

CREATE TRIGGER trg_validate_payment_integrity
BEFORE INSERT OR UPDATE ON public.payments
FOR EACH ROW
EXECUTE FUNCTION public.validate_payment_integrity();

-- ============================================================
-- 15. PAYMENT ALLOCATION INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_payment_allocation_integrity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_payment_student uuid;
    v_invoice_student uuid;
    v_charge_student uuid;
    v_allocated numeric(18,2);
    v_payment_amount numeric(18,2);
BEGIN

    SELECT student_id, amount
    INTO v_payment_student, v_payment_amount
    FROM public.payments
    WHERE id = NEW.payment_id;

    IF v_payment_student IS NULL THEN
        RAISE EXCEPTION
            'Payment % does not exist',
            NEW.payment_id;
    END IF;

    IF NEW.invoice_id IS NOT NULL THEN

        SELECT student_id
        INTO v_invoice_student
        FROM public.invoices
        WHERE id = NEW.invoice_id;

        IF v_invoice_student IS NULL THEN
            RAISE EXCEPTION
                'Invoice % does not exist',
                NEW.invoice_id;
        END IF;

        IF v_invoice_student <> v_payment_student THEN
            RAISE EXCEPTION
                'Payment and invoice belong to different students';
        END IF;

    END IF;

    IF NEW.student_charge_id IS NOT NULL THEN

        SELECT student_id
        INTO v_charge_student
        FROM public.student_charges
        WHERE id = NEW.student_charge_id;

        IF v_charge_student IS NULL THEN
            RAISE EXCEPTION
                'Student charge % does not exist',
                NEW.student_charge_id;
        END IF;

        IF v_charge_student <> v_payment_student THEN
            RAISE EXCEPTION
                'Payment and student charge belong to different students';
        END IF;

    END IF;

    SELECT COALESCE(SUM(allocated_amount), 0)
    INTO v_allocated
    FROM public.payment_allocations
    WHERE payment_id = NEW.payment_id
      AND status = 'ACTIVE'
      AND id <> COALESCE(NEW.id, gen_random_uuid());

    IF v_allocated + NEW.allocated_amount > v_payment_amount THEN
        RAISE EXCEPTION
            'Payment allocation exceeds payment amount';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_payment_allocation
    ON public.payment_allocations;

CREATE TRIGGER trg_validate_payment_allocation
BEFORE INSERT OR UPDATE ON public.payment_allocations
FOR EACH ROW
EXECUTE FUNCTION public.validate_payment_allocation_integrity();

-- ============================================================
-- 16. REFUND INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_refund_integrity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_payment_amount numeric(18,2);
    v_refunded numeric(18,2);
BEGIN

    SELECT amount
    INTO v_payment_amount
    FROM public.payments
    WHERE id = NEW.payment_id;

    IF v_payment_amount IS NULL THEN
        RAISE EXCEPTION
            'Refund payment does not exist';
    END IF;

    SELECT COALESCE(SUM(amount), 0)
    INTO v_refunded
    FROM public.refunds
    WHERE payment_id = NEW.payment_id
      AND status IN ('APPROVED', 'PROCESSING', 'PAID')
      AND id <> COALESCE(NEW.id, gen_random_uuid());

    IF v_refunded + NEW.amount > v_payment_amount THEN
        RAISE EXCEPTION
            'Total refunds cannot exceed payment amount';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_refund_integrity
    ON public.refunds;

CREATE TRIGGER trg_validate_refund_integrity
BEFORE INSERT OR UPDATE ON public.refunds
FOR EACH ROW
EXECUTE FUNCTION public.validate_refund_integrity();

-- ============================================================
-- 17. FINANCIAL TRANSACTION INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_financial_transaction()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.transaction_type = 'PAYMENT'
       AND NEW.credit_amount <= 0 THEN
        RAISE EXCEPTION
            'Payment financial transaction must have a credit amount';
    END IF;

    IF NEW.transaction_type = 'CHARGE'
       AND NEW.debit_amount <= 0 THEN
        RAISE EXCEPTION
            'Charge financial transaction must have a debit amount';
    END IF;

    IF NEW.transaction_type = 'REFUND'
       AND NEW.debit_amount <= 0 THEN
        RAISE EXCEPTION
            'Refund financial transaction must have a debit amount';
    END IF;

    IF NEW.status = 'REVERSED'
       AND NEW.reversal_of IS NULL THEN
        RAISE EXCEPTION
            'A reversed transaction must reference the original transaction';
    END IF;

    IF NEW.reversal_of = NEW.id THEN
        RAISE EXCEPTION
            'A transaction cannot reverse itself';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_financial_transaction
    ON public.financial_transactions;

CREATE TRIGGER trg_validate_financial_transaction
BEFORE INSERT OR UPDATE ON public.financial_transactions
FOR EACH ROW
EXECUTE FUNCTION public.validate_financial_transaction();

-- ============================================================
-- 18. PREVENT DANGEROUS HARD DELETE
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_financial_history_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'Financial records cannot be hard deleted. Use reversal, cancellation, refund, or adjustment workflow.';
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_payment_delete
    ON public.payments;

CREATE TRIGGER trg_prevent_payment_delete
BEFORE DELETE ON public.payments
FOR EACH ROW
EXECUTE FUNCTION public.prevent_financial_history_delete();

DROP TRIGGER IF EXISTS trg_prevent_financial_transaction_delete
    ON public.financial_transactions;

CREATE TRIGGER trg_prevent_financial_transaction_delete
BEFORE DELETE ON public.financial_transactions
FOR EACH ROW
EXECUTE FUNCTION public.prevent_financial_history_delete();

DROP TRIGGER IF EXISTS trg_prevent_refund_delete
    ON public.refunds;

CREATE TRIGGER trg_prevent_refund_delete
BEFORE DELETE ON public.refunds
FOR EACH ROW
EXECUTE FUNCTION public.prevent_financial_history_delete();

-- ============================================================
-- 19. RLS
-- ============================================================

ALTER TABLE public.fee_structures ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_scholarships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_fee_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_transactions ENABLE ROW LEVEL SECURITY;

COMMIT;
