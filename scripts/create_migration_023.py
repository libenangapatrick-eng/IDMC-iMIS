from pathlib import Path

sql = r"""
-- ============================================================
-- IDMC iMIS
-- Migration 023
-- Finance Function & Schema Integrity Fix
-- ============================================================

begin;

-- ============================================================
-- 1. CORRECT FINANCIAL TRANSACTION POSTING FUNCTION
-- ============================================================

create or replace function public.post_financial_transaction(
    p_transaction_number varchar,
    p_student_id uuid,
    p_transaction_type varchar,
    p_debit numeric,
    p_credit numeric,
    p_reference varchar,
    p_description text,
    p_created_by uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id uuid;
begin

    -- --------------------------------------------------------
    -- Basic validation
    -- --------------------------------------------------------

    if p_transaction_number is null
       or btrim(p_transaction_number) = '' then
        raise exception 'transaction_number is required';
    end if;

    if p_transaction_type is null
       or btrim(p_transaction_type) = '' then
        raise exception 'transaction_type is required';
    end if;

    if coalesce(p_debit, 0) < 0 then
        raise exception 'debit_amount cannot be negative';
    end if;

    if coalesce(p_credit, 0) < 0 then
        raise exception 'credit_amount cannot be negative';
    end if;

    if coalesce(p_debit, 0) = 0
       and coalesce(p_credit, 0) = 0 then
        raise exception
            'Either debit_amount or credit_amount must be greater than zero';
    end if;

    if coalesce(p_debit, 0) > 0
       and coalesce(p_credit, 0) > 0 then
        raise exception
            'A financial transaction cannot have both debit and credit';
    end if;


    -- --------------------------------------------------------
    -- Prevent duplicate transaction numbers
    -- --------------------------------------------------------

    if exists (
        select 1
        from public.financial_transactions
        where transaction_number = p_transaction_number
    ) then
        raise exception
            'Financial transaction number already exists: %',
            p_transaction_number;
    end if;


    -- --------------------------------------------------------
    -- Insert ledger transaction
    --
    -- IMPORTANT:
    -- The real column is reference_number, not reference.
    -- --------------------------------------------------------

    insert into public.financial_transactions (
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
    values (
        p_transaction_number,
        p_student_id,
        p_transaction_type,
        coalesce(p_debit, 0),
        coalesce(p_credit, 0),
        now(),
        nullif(btrim(p_reference), ''),
        p_description,
        'POSTED',
        p_created_by
    )
    returning id
    into v_id;


    -- --------------------------------------------------------
    -- Refresh student financial account
    -- --------------------------------------------------------

    if p_student_id is not null then

        perform public.ensure_student_financial_account(
            p_student_id
        );

        perform public.refresh_student_financial_account(
            p_student_id
        );

    end if;


    return v_id;

end;
$$;


-- ============================================================
-- 2. FUNCTION SECURITY
-- ============================================================

revoke all on function public.post_financial_transaction(
    varchar,
    uuid,
    varchar,
    numeric,
    numeric,
    varchar,
    text,
    uuid
)
from public;

revoke all on function public.post_financial_transaction(
    varchar,
    uuid,
    varchar,
    numeric,
    numeric,
    varchar,
    text,
    uuid
)
from anon;

revoke all on function public.post_financial_transaction(
    varchar,
    uuid,
    varchar,
    numeric,
    numeric,
    varchar,
    text,
    uuid
)
from authenticated;


-- ============================================================
-- 3. FINANCIAL TRANSACTION INTEGRITY
-- ============================================================

create or replace function public.validate_financial_transaction_row()
returns trigger
language plpgsql
as $$
begin

    if new.transaction_number is null
       or btrim(new.transaction_number) = '' then
        raise exception 'transaction_number is required';
    end if;

    if new.transaction_type is null
       or btrim(new.transaction_type) = '' then
        raise exception 'transaction_type is required';
    end if;

    if coalesce(new.debit_amount, 0) < 0
       or coalesce(new.credit_amount, 0) < 0 then
        raise exception
            'Financial transaction amounts cannot be negative';
    end if;

    if coalesce(new.debit_amount, 0) = 0
       and coalesce(new.credit_amount, 0) = 0 then
        raise exception
            'Financial transaction must contain debit or credit';
    end if;

    if coalesce(new.debit_amount, 0) > 0
       and coalesce(new.credit_amount, 0) > 0 then
        raise exception
            'Financial transaction cannot contain both debit and credit';
    end if;

    if new.status is null then
        new.status := 'DRAFT';
    end if;

    if new.transaction_date is null then
        new.transaction_date := now();
    end if;

    return new;

end;
$$;


drop trigger if exists trg_validate_financial_transaction_row
on public.financial_transactions;

create trigger trg_validate_financial_transaction_row
before insert or update
on public.financial_transactions
for each row
execute function public.validate_financial_transaction_row();


-- ============================================================
-- 4. PROTECT POSTED FINANCIAL TRANSACTIONS
-- ============================================================

create or replace function public.protect_posted_financial_transaction()
returns trigger
language plpgsql
as $$
begin

    if old.status = 'POSTED' then

        if new.transaction_number
           is distinct from old.transaction_number then

            raise exception
                'Posted financial transaction number cannot be changed';

        end if;

        if new.student_id
           is distinct from old.student_id then

            raise exception
                'Posted financial transaction student cannot be changed';

        end if;

        if new.transaction_type
           is distinct from old.transaction_type then

            raise exception
                'Posted financial transaction type cannot be changed';

        end if;

        if new.debit_amount
           is distinct from old.debit_amount then

            raise exception
                'Posted financial transaction debit cannot be changed';

        end if;

        if new.credit_amount
           is distinct from old.credit_amount then

            raise exception
                'Posted financial transaction credit cannot be changed';

        end if;

        if new.reference_number
           is distinct from old.reference_number then

            raise exception
                'Posted financial transaction reference cannot be changed';

        end if;

    end if;

    return new;

end;
$$;


drop trigger if exists trg_protect_posted_financial_transaction
on public.financial_transactions;

create trigger trg_protect_posted_financial_transaction
before update
on public.financial_transactions
for each row
execute function public.protect_posted_financial_transaction();


-- ============================================================
-- 5. PREVENT HARD DELETE OF FINANCIAL LEDGER RECORDS
-- ============================================================

create or replace function public.prevent_financial_transaction_delete()
returns trigger
language plpgsql
as $$
begin

    raise exception
        'Financial transactions cannot be deleted. Use reversal transactions instead';

end;
$$;


drop trigger if exists trg_prevent_financial_transaction_delete
on public.financial_transactions;

create trigger trg_prevent_financial_transaction_delete
before delete
on public.financial_transactions
for each row
execute function public.prevent_financial_transaction_delete();


commit;

-- ============================================================
-- END MIGRATION 023
-- ============================================================
"""

paths = [
    Path(r"C:\Users\liben\Documents\IDMC_iMIS\database\migrations\202609150023_finance_function_integrity_fix.sql"),
    Path(r"C:\Users\liben\Documents\IDMC_iMIS\supabase\migrations\202609150023_finance_function_integrity_fix.sql")
]

for path in paths:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(sql, encoding="utf-8")

print("Migration 023 created successfully.")

for path in paths:
    print(f"{path}")
    print(f"Size: {path.stat().st_size} bytes")
