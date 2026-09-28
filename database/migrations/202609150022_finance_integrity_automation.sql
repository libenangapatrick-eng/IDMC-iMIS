
-- ============================================================
-- IDMC iMIS
-- Migration 022
-- Finance Integrity & Automation
-- ============================================================

begin;

-- ============================================================
-- 1. STUDENT FINANCIAL ACCOUNT
-- ============================================================

create table if not exists public.student_financial_accounts (
    id uuid primary key default gen_random_uuid(),

    student_id uuid not null
        references public.students(id),

    total_charged numeric(14,2) not null default 0,
    total_paid numeric(14,2) not null default 0,
    total_refunded numeric(14,2) not null default 0,

    total_scholarship numeric(14,2) not null default 0,
    total_waiver numeric(14,2) not null default 0,
    total_adjustments numeric(14,2) not null default 0,

    current_balance numeric(14,2)
        generated always as (
            total_charged
            - total_paid
            + total_refunded
            - total_scholarship
            - total_waiver
            + total_adjustments
        ) stored,

    account_status varchar(30) not null default 'ACTIVE'
        check (
            account_status in (
                'ACTIVE',
                'SUSPENDED',
                'CLOSED'
            )
        ),

    last_calculated_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint uq_student_financial_account
        unique (student_id),

    constraint chk_financial_totals_nonnegative
        check (
            total_charged >= 0
            and total_paid >= 0
            and total_refunded >= 0
            and total_scholarship >= 0
            and total_waiver >= 0
        )
);

create index if not exists idx_student_financial_accounts_student
    on public.student_financial_accounts(student_id);

create index if not exists idx_student_financial_accounts_status
    on public.student_financial_accounts(account_status);


-- ============================================================
-- 2. UPDATED_AT HELPER
-- ============================================================

create or replace function public.touch_finance_automation_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;


drop trigger if exists trg_student_financial_accounts_updated_at
on public.student_financial_accounts;

create trigger trg_student_financial_accounts_updated_at
before update on public.student_financial_accounts
for each row
execute function public.touch_finance_automation_updated_at();


-- ============================================================
-- 3. ENSURE STUDENT FINANCIAL ACCOUNT
-- ============================================================

create or replace function public.ensure_student_financial_account(
    p_student_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id uuid;
begin

    if p_student_id is null then
        raise exception 'student_id is required';
    end if;

    insert into public.student_financial_accounts(student_id)
    values (p_student_id)
    on conflict (student_id)
    do nothing;

    select id
    into v_id
    from public.student_financial_accounts
    where student_id = p_student_id;

    return v_id;
end;
$$;


-- ============================================================
-- 4. REFRESH STUDENT FINANCIAL ACCOUNT
-- ============================================================

create or replace function public.refresh_student_financial_account(
    p_student_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_charged numeric(14,2) := 0;
    v_paid numeric(14,2) := 0;
    v_refunded numeric(14,2) := 0;
    v_scholarship numeric(14,2) := 0;
    v_waiver numeric(14,2) := 0;
    v_adjustments numeric(14,2) := 0;
begin

    if p_student_id is null then
        return;
    end if;

    perform public.ensure_student_financial_account(p_student_id);

    /*
      Student charges are treated as the authoritative source
      for posted academic/administrative charges.
    */
    select
        coalesce(sum(
            case
                when status not in ('CANCELLED', 'REVERSED')
                then net_amount
                else 0
            end
        ), 0)
    into v_charged
    from public.student_charges
    where student_id = p_student_id;


    /*
      Active allocations represent actual money applied
      against student obligations.
    */
    select
        coalesce(sum(
            case
                when status = 'ACTIVE'
                then allocated_amount
                else 0
            end
        ), 0)
    into v_paid
    from public.payment_allocations
    where exists (
        select 1
        from public.payments p
        where p.id = payment_allocations.payment_id
          and p.student_id = p_student_id
          and p.status = 'CONFIRMED'
    );


    /*
      Paid refunds increase the amount the student still owes.
    */
    select
        coalesce(sum(
            case
                when status = 'PAID'
                then amount
                else 0
            end
        ), 0)
    into v_refunded
    from public.refunds
    where student_id = p_student_id;


    /*
      Scholarships and waivers already affect student charges
      through their net_amount. They are therefore kept here
      as reporting values only and must not be subtracted twice.
    */
    select
        coalesce(sum(scholarship_amount), 0),
        coalesce(sum(waiver_amount), 0),
        coalesce(sum(adjustment_amount), 0)
    into
        v_scholarship,
        v_waiver,
        v_adjustments
    from public.student_charges
    where student_id = p_student_id
      and status not in ('CANCELLED', 'REVERSED');


    update public.student_financial_accounts
    set
        total_charged = v_charged,
        total_paid = v_paid,
        total_refunded = v_refunded,

        /*
          These are informational values because net_amount
          already incorporates them.
        */
        total_scholarship = v_scholarship,
        total_waiver = v_waiver,
        total_adjustments = v_adjustments,

        last_calculated_at = now(),
        updated_at = now()

    where student_id = p_student_id;

end;
$$;


-- ============================================================
-- 5. REFRESH INVOICE
-- ============================================================

create or replace function public.refresh_invoice_financials(
    p_invoice_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_total numeric(14,2) := 0;
    v_paid numeric(14,2) := 0;
    v_balance numeric(14,2) := 0;
    v_status varchar(30);
    v_due_date date;
    v_student_id uuid;
begin

    select
        student_id,
        due_date
    into
        v_student_id,
        v_due_date
    from public.invoices
    where id = p_invoice_id;

    if v_student_id is null then
        return;
    end if;


    select
        coalesce(sum(line_total), 0)
    into v_total
    from public.invoice_items
    where invoice_id = p_invoice_id;


    select
        coalesce(sum(allocated_amount), 0)
    into v_paid
    from public.payment_allocations
    where invoice_id = p_invoice_id
      and status = 'ACTIVE'
      and exists (
          select 1
          from public.payments p
          where p.id = payment_allocations.payment_id
            and p.status = 'CONFIRMED'
      );


    v_balance := greatest(v_total - v_paid, 0);


    select status
    into v_status
    from public.invoices
    where id = p_invoice_id;


    if v_status in ('CANCELLED', 'VOID') then

        update public.invoices
        set
            subtotal = v_total,
            amount_paid = v_paid,
            balance_amount = v_balance,
            updated_at = now()
        where id = p_invoice_id;

        return;
    end if;


    if v_total = 0 then
        v_status := 'DRAFT';

    elsif v_paid >= v_total then
        v_status := 'PAID';

    elsif v_paid > 0 then
        v_status := 'PARTIALLY_PAID';

    elsif v_due_date is not null
          and v_due_date < current_date then
        v_status := 'OVERDUE';

    else
        if v_status = 'DRAFT' then
            v_status := 'ISSUED';
        end if;
    end if;


    update public.invoices
    set
        subtotal = v_total,
        total_amount = greatest(
            v_total
            - coalesce(discount_amount, 0)
            - coalesce(scholarship_amount, 0)
            + coalesce(adjustment_amount, 0),
            0
        ),
        amount_paid = v_paid,
        balance_amount = greatest(
            greatest(
                v_total
                - coalesce(discount_amount, 0)
                - coalesce(scholarship_amount, 0)
                + coalesce(adjustment_amount, 0),
                0
            ) - v_paid,
            0
        ),
        status = v_status,
        updated_at = now()
    where id = p_invoice_id;


end;
$$;


-- ============================================================
-- 6. REFRESH ALL INVOICE VALUES
-- ============================================================

create or replace function public.refresh_all_invoice_financials()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_count integer := 0;
    r record;
begin

    for r in
        select id
        from public.invoices
        where status not in ('CANCELLED', 'VOID')
    loop

        perform public.refresh_invoice_financials(r.id);
        v_count := v_count + 1;

    end loop;

    return v_count;
end;
$$;


-- ============================================================
-- 7. STUDENT CHARGE TRIGGER
-- ============================================================

create or replace function public.trg_refresh_student_financial_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

    if tg_op = 'DELETE' then

        perform public.refresh_student_financial_account(
            old.student_id
        );

        return old;

    else

        perform public.refresh_student_financial_account(
            new.student_id
        );

        if tg_op = 'UPDATE'
           and old.student_id is distinct from new.student_id then

            perform public.refresh_student_financial_account(
                old.student_id
            );

        end if;

        return new;

    end if;

end;
$$;


drop trigger if exists trg_student_charge_refresh_account
on public.student_charges;

create trigger trg_student_charge_refresh_account
after insert or update or delete
on public.student_charges
for each row
execute function public.trg_refresh_student_financial_account();


-- ============================================================
-- 8. PAYMENT ALLOCATION TRIGGER
-- ============================================================

create or replace function public.trg_refresh_financials_after_allocation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_student_id uuid;
    v_invoice_id uuid;
begin

    if tg_op = 'DELETE' then

        select student_id
        into v_student_id
        from public.payments
        where id = old.payment_id;

        v_invoice_id := old.invoice_id;

    else

        select student_id
        into v_student_id
        from public.payments
        where id = new.payment_id;

        v_invoice_id := new.invoice_id;

    end if;


    if v_invoice_id is not null then
        perform public.refresh_invoice_financials(v_invoice_id);
    end if;


    if v_student_id is not null then
        perform public.refresh_student_financial_account(v_student_id);
    end if;


    return coalesce(new, old);
end;
$$;


drop trigger if exists trg_payment_allocation_refresh_financials
on public.payment_allocations;

create trigger trg_payment_allocation_refresh_financials
after insert or update or delete
on public.payment_allocations
for each row
execute function public.trg_refresh_financials_after_allocation();


-- ============================================================
-- 9. PAYMENT STATUS TRIGGER
-- ============================================================

create or replace function public.trg_refresh_after_payment_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

    if new.student_id is not null then
        perform public.refresh_student_financial_account(
            new.student_id
        );
    end if;

    return new;
end;
$$;


drop trigger if exists trg_payment_refresh_student_account
on public.payments;

create trigger trg_payment_refresh_student_account
after insert or update of status, amount
on public.payments
for each row
execute function public.trg_refresh_after_payment_status();


-- ============================================================
-- 10. REFUND TRIGGER
-- ============================================================

create or replace function public.trg_refresh_after_refund()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

    if new.student_id is not null then
        perform public.refresh_student_financial_account(
            new.student_id
        );
    end if;

    return new;
end;
$$;


drop trigger if exists trg_refund_refresh_student_account
on public.refunds;

create trigger trg_refund_refresh_student_account
after insert or update of status, amount
on public.refunds
for each row
execute function public.trg_refresh_after_refund();


-- ============================================================
-- 11. INVOICE ITEM TRIGGER
-- ============================================================

create or replace function public.trg_refresh_invoice_after_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

    if tg_op = 'DELETE' then

        perform public.refresh_invoice_financials(
            old.invoice_id
        );

        return old;

    else

        perform public.refresh_invoice_financials(
            new.invoice_id
        );

        if tg_op = 'UPDATE'
           and old.invoice_id is distinct from new.invoice_id then

            perform public.refresh_invoice_financials(
                old.invoice_id
            );

        end if;

        return new;

    end if;

end;
$$;


drop trigger if exists trg_invoice_item_refresh
on public.invoice_items;

create trigger trg_invoice_item_refresh
after insert or update or delete
on public.invoice_items
for each row
execute function public.trg_refresh_invoice_after_item();


-- ============================================================
-- 12. FINANCIAL LEDGER POSTING
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

    if coalesce(p_debit, 0) < 0
       or coalesce(p_credit, 0) < 0 then

        raise exception
            'Debit and credit cannot be negative';

    end if;


    if coalesce(p_debit, 0) = 0
       and coalesce(p_credit, 0) = 0 then

        raise exception
            'Either debit or credit must be greater than zero';

    end if;


    if p_debit > 0 and p_credit > 0 then
        raise exception
            'A financial transaction cannot have both debit and credit';
    end if;


    insert into public.financial_transactions (
        transaction_number,
        student_id,
        transaction_type,
        debit_amount,
        credit_amount,
        transaction_date,
        reference,
        description,
        status,
        created_by
    )
    values (
        p_transaction_number,
        p_student_id,
        p_transaction_type,
        p_debit,
        p_credit,
        current_date,
        p_reference,
        p_description,
        'POSTED',
        p_created_by
    )
    returning id into v_id;


    if p_student_id is not null then
        perform public.refresh_student_financial_account(
            p_student_id
        );
    end if;


    return v_id;
end;
$$;


-- ============================================================
-- 13. FINANCE REPORTING VIEWS
-- ============================================================

create or replace view public.v_student_financial_summary
with (security_invoker = true)
as
select
    sfa.student_id,
    sfa.total_charged,
    sfa.total_paid,
    sfa.total_refunded,
    sfa.total_scholarship,
    sfa.total_waiver,
    sfa.total_adjustments,
    sfa.current_balance,
    sfa.account_status,
    sfa.last_calculated_at
from public.student_financial_accounts sfa;


create or replace view public.v_invoice_financial_summary
with (security_invoker = true)
as
select
    i.id,
    i.invoice_number,
    i.student_id,
    i.academic_year,
    i.semester,
    i.status,
    i.total_amount,
    i.amount_paid,
    i.balance_amount,
    i.due_date,
    case
        when i.balance_amount <= 0 then 'CLEARED'
        when i.due_date is not null
             and i.due_date < current_date
             then 'OVERDUE'
        when i.amount_paid > 0
             then 'PARTIAL'
        else 'UNPAID'
    end as payment_position
from public.invoices i;


-- ============================================================
-- 14. FINANCE RLS
-- ============================================================

alter table public.student_financial_accounts enable row level security;


-- ============================================================
-- 15. HARD DELETE PROTECTION
-- ============================================================

create or replace function public.prevent_financial_account_delete()
returns trigger
language plpgsql
as $$
begin
    raise exception
        'Student financial accounts cannot be deleted';
end;
$$;


drop trigger if exists trg_prevent_financial_account_delete
on public.student_financial_accounts;

create trigger trg_prevent_financial_account_delete
before delete
on public.student_financial_accounts
for each row
execute function public.prevent_financial_account_delete();


-- ============================================================
-- 16. GRANTS
-- ============================================================

revoke all on public.student_financial_accounts from anon;
revoke all on public.student_financial_accounts from authenticated;

revoke all on public.v_student_financial_summary from anon;
revoke all on public.v_invoice_financial_summary from anon;


commit;

-- ============================================================
-- END MIGRATION 022
-- ============================================================
