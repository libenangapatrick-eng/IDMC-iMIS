-- ============================================================
-- IDMC iMIS
-- Migration 026: Finance RBAC Permissions
-- ============================================================

insert into public.permissions
    (permission_code, permission_name, module_code, action_code, description)
values
    ('finance.view', 'View Finance', 'finance', 'view',
        'View financial records and student financial information'),

    ('finance.manage', 'Manage Finance', 'finance', 'manage',
        'Manage institutional financial configuration'),

    ('finance.charges.view', 'View Student Charges', 'finance', 'charges_view',
        'View student charges'),

    ('finance.invoices.view', 'View Invoices', 'finance', 'invoices_view',
        'View student invoices'),

    ('finance.payments.view', 'View Payments', 'finance', 'payments_view',
        'View student payments'),

    ('finance.refunds.view', 'View Refunds', 'finance', 'refunds_view',
        'View student refunds'),

    ('finance.scholarships.view', 'View Scholarships', 'finance', 'scholarships_view',
        'View student scholarships'),

    ('finance.adjustments.view', 'View Adjustments', 'finance', 'adjustments_view',
        'View student financial adjustments'),

    ('finance.transactions.view', 'View Transactions', 'finance', 'transactions_view',
        'View student financial transactions')

on conflict (permission_code) do nothing;

-- ============================================================
-- SUPER ADMIN
-- ============================================================

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.role_code = 'SUPER_ADMIN'
  and p.module_code = 'finance'
on conflict (role_id, permission_id) do nothing;

-- ============================================================
-- ADMIN
-- ============================================================

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.role_code = 'ADMIN'
  and p.permission_code in (
      'finance.view',
      'finance.charges.view',
      'finance.invoices.view',
      'finance.payments.view',
      'finance.refunds.view',
      'finance.scholarships.view',
      'finance.adjustments.view',
      'finance.transactions.view'
  )
on conflict (role_id, permission_id) do nothing;

-- ============================================================
-- FINANCE OFFICER
-- ============================================================

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.role_code = 'FINANCE_OFFICER'
  and p.module_code = 'finance'
on conflict (role_id, permission_id) do nothing;

-- ============================================================
-- AUDITOR
-- ============================================================

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.role_code = 'AUDITOR'
  and p.permission_code in (
      'finance.view',
      'finance.charges.view',
      'finance.invoices.view',
      'finance.payments.view',
      'finance.refunds.view',
      'finance.scholarships.view',
      'finance.adjustments.view',
      'finance.transactions.view'
  )
on conflict (role_id, permission_id) do nothing;

comment on table public.permissions is
    'Fine-grained permissions for IDMC iMIS modules and actions, including Finance.';
