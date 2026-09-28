-- ============================================================
-- IDMC iMIS
-- Migration 029
-- Operations Core
-- Procurement, Inventory & Assets
-- Version: 20260917190000
-- ============================================================

BEGIN;

-- ============================================================
-- 1. SUPPLIERS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    institution_id uuid NOT NULL
        REFERENCES public.institutions(id)
        ON DELETE RESTRICT,

    supplier_code varchar(60) NOT NULL,
    supplier_name varchar(255) NOT NULL,

    supplier_type varchar(40) NOT NULL DEFAULT 'COMPANY'
        CHECK (
            supplier_type IN (
                'COMPANY',
                'INDIVIDUAL',
                'GOVERNMENT',
                'NGO',
                'OTHER'
            )
        ),

    registration_number varchar(100),
    tax_identification_number varchar(100),

    contact_person varchar(200),
    phone varchar(50),
    email varchar(255),

    physical_address text,
    postal_address text,

    bank_name varchar(255),
    bank_account_name varchar(255),
    bank_account_number varchar(100),

    status varchar(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE',
                'SUSPENDED'
            )
        ),

    notes text,

    created_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    updated_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_supplier_code
        UNIQUE (institution_id, supplier_code)
);


-- ============================================================
-- 2. PROCUREMENT REQUESTS
-- ============================================================

CREATE SEQUENCE IF NOT EXISTS public.procurement_request_number_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    NO CYCLE;


CREATE TABLE IF NOT EXISTS public.procurement_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    institution_id uuid NOT NULL
        REFERENCES public.institutions(id)
        ON DELETE RESTRICT,

    request_number varchar(60) NOT NULL UNIQUE,

    requested_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    department_id uuid NULL
        REFERENCES public.departments(id)
        ON DELETE SET NULL,

    request_date date NOT NULL DEFAULT current_date,

    required_date date,

    priority varchar(20) NOT NULL DEFAULT 'NORMAL'
        CHECK (
            priority IN (
                'LOW',
                'NORMAL',
                'HIGH',
                'URGENT'
            )
        ),

    request_status varchar(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (
            request_status IN (
                'DRAFT',
                'SUBMITTED',
                'UNDER_REVIEW',
                'APPROVED',
                'REJECTED',
                'CANCELLED',
                'FULFILLED',
                'CLOSED'
            )
        ),

    purpose text NOT NULL,

    estimated_total numeric(14,2) NOT NULL DEFAULT 0
        CHECK (estimated_total >= 0),

    justification text,

    approved_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    approved_at timestamptz,

    rejection_reason text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_procurement_request_dates
        CHECK (
            required_date IS NULL
            OR required_date >= request_date
        )
);


-- ============================================================
-- 3. PROCUREMENT REQUEST ITEMS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.procurement_request_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    procurement_request_id uuid NOT NULL
        REFERENCES public.procurement_requests(id)
        ON DELETE CASCADE,

    item_description text NOT NULL,

    quantity numeric(12,2) NOT NULL
        CHECK (quantity > 0),

    unit_of_measure varchar(50) NOT NULL DEFAULT 'UNIT',

    estimated_unit_price numeric(14,2) NOT NULL DEFAULT 0
        CHECK (estimated_unit_price >= 0),

    estimated_total numeric(14,2)
        GENERATED ALWAYS AS (
            quantity * estimated_unit_price
        ) STORED,

    specifications text,

    created_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 4. PURCHASE ORDERS
-- ============================================================

CREATE SEQUENCE IF NOT EXISTS public.purchase_order_number_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    NO CYCLE;


CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    institution_id uuid NOT NULL
        REFERENCES public.institutions(id)
        ON DELETE RESTRICT,

    procurement_request_id uuid NULL
        REFERENCES public.procurement_requests(id)
        ON DELETE SET NULL,

    supplier_id uuid NOT NULL
        REFERENCES public.suppliers(id)
        ON DELETE RESTRICT,

    purchase_order_number varchar(60) NOT NULL UNIQUE,

    order_date date NOT NULL DEFAULT current_date,

    expected_delivery_date date,

    currency varchar(10) NOT NULL DEFAULT 'TZS',

    subtotal numeric(14,2) NOT NULL DEFAULT 0
        CHECK (subtotal >= 0),

    tax_amount numeric(14,2) NOT NULL DEFAULT 0
        CHECK (tax_amount >= 0),

    discount_amount numeric(14,2) NOT NULL DEFAULT 0
        CHECK (discount_amount >= 0),

    total_amount numeric(14,2) NOT NULL DEFAULT 0
        CHECK (total_amount >= 0),

    order_status varchar(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (
            order_status IN (
                'DRAFT',
                'PENDING_APPROVAL',
                'APPROVED',
                'SENT',
                'PARTIALLY_RECEIVED',
                'RECEIVED',
                'CANCELLED',
                'CLOSED'
            )
        ),

    created_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    approved_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    approved_at timestamptz,

    notes text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_purchase_order_dates
        CHECK (
            expected_delivery_date IS NULL
            OR expected_delivery_date >= order_date
        )
);


-- ============================================================
-- 5. PURCHASE ORDER ITEMS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    purchase_order_id uuid NOT NULL
        REFERENCES public.purchase_orders(id)
        ON DELETE CASCADE,

    item_description text NOT NULL,

    quantity numeric(12,2) NOT NULL
        CHECK (quantity > 0),

    unit_of_measure varchar(50) NOT NULL DEFAULT 'UNIT',

    unit_price numeric(14,2) NOT NULL DEFAULT 0
        CHECK (unit_price >= 0),

    tax_amount numeric(14,2) NOT NULL DEFAULT 0
        CHECK (tax_amount >= 0),

    discount_amount numeric(14,2) NOT NULL DEFAULT 0
        CHECK (discount_amount >= 0),

    line_total numeric(14,2)
        GENERATED ALWAYS AS (
            (quantity * unit_price)
            + tax_amount
            - discount_amount
        ) STORED,

    specifications text,

    created_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 6. INVENTORY CATEGORIES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.inventory_categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    institution_id uuid NOT NULL
        REFERENCES public.institutions(id)
        ON DELETE RESTRICT,

    category_code varchar(60) NOT NULL,
    category_name varchar(150) NOT NULL,

    description text,

    status varchar(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE'
            )
        ),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_inventory_category
        UNIQUE (institution_id, category_code)
);


-- ============================================================
-- 7. INVENTORY ITEMS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.inventory_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    institution_id uuid NOT NULL
        REFERENCES public.institutions(id)
        ON DELETE RESTRICT,

    category_id uuid NULL
        REFERENCES public.inventory_categories(id)
        ON DELETE SET NULL,

    item_code varchar(80) NOT NULL,
    item_name varchar(255) NOT NULL,

    description text,

    unit_of_measure varchar(50) NOT NULL DEFAULT 'UNIT',

    minimum_stock_level numeric(14,2) NOT NULL DEFAULT 0
        CHECK (minimum_stock_level >= 0),

    maximum_stock_level numeric(14,2)
        CHECK (
            maximum_stock_level IS NULL
            OR maximum_stock_level >= minimum_stock_level
        ),

    reorder_level numeric(14,2) NOT NULL DEFAULT 0
        CHECK (reorder_level >= 0),

    current_quantity numeric(14,2) NOT NULL DEFAULT 0
        CHECK (current_quantity >= 0),

    unit_cost numeric(14,2) NOT NULL DEFAULT 0
        CHECK (unit_cost >= 0),

    storage_location varchar(255),

    status varchar(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE',
                'DISCONTINUED'
            )
        ),

    created_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    updated_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_inventory_item
        UNIQUE (institution_id, item_code)
);


-- ============================================================
-- 8. INVENTORY TRANSACTIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.inventory_transactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    inventory_item_id uuid NOT NULL
        REFERENCES public.inventory_items(id)
        ON DELETE RESTRICT,

    transaction_type varchar(30) NOT NULL
        CHECK (
            transaction_type IN (
                'RECEIPT',
                'ISSUE',
                'RETURN',
                'ADJUSTMENT_IN',
                'ADJUSTMENT_OUT',
                'TRANSFER'
            )
        ),

    transaction_number varchar(80) NOT NULL UNIQUE,

    quantity numeric(14,2) NOT NULL
        CHECK (quantity > 0),

    unit_cost numeric(14,2) NOT NULL DEFAULT 0
        CHECK (unit_cost >= 0),

    reference_type varchar(50),

    reference_id uuid,

    transaction_date timestamptz NOT NULL DEFAULT now(),

    balance_before numeric(14,2) NOT NULL DEFAULT 0
        CHECK (balance_before >= 0),

    balance_after numeric(14,2) NOT NULL DEFAULT 0
        CHECK (balance_after >= 0),

    performed_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    remarks text,

    created_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 9. ASSET CATEGORIES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.asset_categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    institution_id uuid NOT NULL
        REFERENCES public.institutions(id)
        ON DELETE RESTRICT,

    category_code varchar(60) NOT NULL,
    category_name varchar(150) NOT NULL,

    depreciation_method varchar(40)
        CHECK (
            depreciation_method IS NULL
            OR depreciation_method IN (
                'STRAIGHT_LINE',
                'DECLINING_BALANCE',
                'NONE'
            )
        ),

    default_useful_life_years integer
        CHECK (
            default_useful_life_years IS NULL
            OR default_useful_life_years > 0
        ),

    description text,

    status varchar(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE'
            )
        ),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_asset_category
        UNIQUE (institution_id, category_code)
);


-- ============================================================
-- 10. ASSETS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.assets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    institution_id uuid NOT NULL
        REFERENCES public.institutions(id)
        ON DELETE RESTRICT,

    category_id uuid NULL
        REFERENCES public.asset_categories(id)
        ON DELETE SET NULL,

    department_id uuid NULL
        REFERENCES public.departments(id)
        ON DELETE SET NULL,

    asset_tag varchar(80) NOT NULL UNIQUE,

    asset_name varchar(255) NOT NULL,

    description text,

    serial_number varchar(150),

    manufacturer varchar(150),
    model varchar(150),

    acquisition_date date,
    acquisition_cost numeric(14,2) NOT NULL DEFAULT 0
        CHECK (acquisition_cost >= 0),

    current_value numeric(14,2)
        CHECK (
            current_value IS NULL
            OR current_value >= 0
        ),

    useful_life_years integer
        CHECK (
            useful_life_years IS NULL
            OR useful_life_years > 0
        ),

    location varchar(255),

    condition_status varchar(30) NOT NULL DEFAULT 'GOOD'
        CHECK (
            condition_status IN (
                'NEW',
                'GOOD',
                'FAIR',
                'POOR',
                'DAMAGED',
                'DISPOSED'
            )
        ),

    asset_status varchar(30) NOT NULL DEFAULT 'ACTIVE'
        CHECK (
            asset_status IN (
                'ACTIVE',
                'UNDER_REPAIR',
                'LOST',
                'DISPOSED',
                'TRANSFERRED',
                'INACTIVE'
            )
        ),

    warranty_expiry_date date,

    notes text,

    created_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    updated_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_asset_serial
        UNIQUE (serial_number)
);


-- ============================================================
-- 11. ASSET ASSIGNMENTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.asset_assignments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    asset_id uuid NOT NULL
        REFERENCES public.assets(id)
        ON DELETE CASCADE,

    staff_id uuid NULL
        REFERENCES public.staff(id)
        ON DELETE SET NULL,

    department_id uuid NULL
        REFERENCES public.departments(id)
        ON DELETE SET NULL,

    assigned_date date NOT NULL DEFAULT current_date,

    returned_date date,

    assignment_status varchar(20) NOT NULL DEFAULT 'ASSIGNED'
        CHECK (
            assignment_status IN (
                'ASSIGNED',
                'RETURNED',
                'TRANSFERRED',
                'LOST'
            )
        ),

    assigned_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    received_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    return_condition varchar(30)
        CHECK (
            return_condition IS NULL
            OR return_condition IN (
                'NEW',
                'GOOD',
                'FAIR',
                'POOR',
                'DAMAGED'
            )
        ),

    notes text,

    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_asset_assignment_dates
        CHECK (
            returned_date IS NULL
            OR returned_date >= assigned_date
        ),

    CONSTRAINT chk_asset_assignment_owner
        CHECK (
            staff_id IS NOT NULL
            OR department_id IS NOT NULL
        )
);


-- ============================================================
-- 12. ASSET MAINTENANCE
-- ============================================================

CREATE TABLE IF NOT EXISTS public.asset_maintenance (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    asset_id uuid NOT NULL
        REFERENCES public.assets(id)
        ON DELETE CASCADE,

    maintenance_type varchar(30) NOT NULL
        CHECK (
            maintenance_type IN (
                'PREVENTIVE',
                'CORRECTIVE',
                'INSPECTION',
                'CALIBRATION',
                'OTHER'
            )
        ),

    maintenance_date date NOT NULL,

    service_provider varchar(255),

    description text NOT NULL,

    cost numeric(14,2) NOT NULL DEFAULT 0
        CHECK (cost >= 0),

    next_maintenance_date date,

    maintenance_status varchar(20) NOT NULL DEFAULT 'COMPLETED'
        CHECK (
            maintenance_status IN (
                'SCHEDULED',
                'IN_PROGRESS',
                'COMPLETED',
                'CANCELLED'
            )
        ),

    performed_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    notes text,

    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_asset_maintenance_dates
        CHECK (
            next_maintenance_date IS NULL
            OR next_maintenance_date >= maintenance_date
        )
);


-- ============================================================
-- 13. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_suppliers_institution
    ON public.suppliers(institution_id);

CREATE INDEX IF NOT EXISTS idx_suppliers_status
    ON public.suppliers(status);

CREATE INDEX IF NOT EXISTS idx_procurement_requests_institution
    ON public.procurement_requests(institution_id);

CREATE INDEX IF NOT EXISTS idx_procurement_requests_department
    ON public.procurement_requests(department_id);

CREATE INDEX IF NOT EXISTS idx_procurement_requests_status
    ON public.procurement_requests(request_status);

CREATE INDEX IF NOT EXISTS idx_procurement_request_items_request
    ON public.procurement_request_items(procurement_request_id);

CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier
    ON public.purchase_orders(supplier_id);

CREATE INDEX IF NOT EXISTS idx_purchase_orders_status
    ON public.purchase_orders(order_status);

CREATE INDEX IF NOT EXISTS idx_purchase_order_items_order
    ON public.purchase_order_items(purchase_order_id);

CREATE INDEX IF NOT EXISTS idx_inventory_categories_institution
    ON public.inventory_categories(institution_id);

CREATE INDEX IF NOT EXISTS idx_inventory_items_category
    ON public.inventory_items(category_id);

CREATE INDEX IF NOT EXISTS idx_inventory_items_status
    ON public.inventory_items(status);

CREATE INDEX IF NOT EXISTS idx_inventory_transactions_item
    ON public.inventory_transactions(inventory_item_id);

CREATE INDEX IF NOT EXISTS idx_inventory_transactions_date
    ON public.inventory_transactions(transaction_date);

CREATE INDEX IF NOT EXISTS idx_asset_categories_institution
    ON public.asset_categories(institution_id);

CREATE INDEX IF NOT EXISTS idx_assets_category
    ON public.assets(category_id);

CREATE INDEX IF NOT EXISTS idx_assets_department
    ON public.assets(department_id);

CREATE INDEX IF NOT EXISTS idx_assets_status
    ON public.assets(asset_status);

CREATE INDEX IF NOT EXISTS idx_asset_assignments_asset
    ON public.asset_assignments(asset_id);

CREATE INDEX IF NOT EXISTS idx_asset_assignments_staff
    ON public.asset_assignments(staff_id);

CREATE INDEX IF NOT EXISTS idx_asset_assignments_department
    ON public.asset_assignments(department_id);

CREATE INDEX IF NOT EXISTS idx_asset_maintenance_asset
    ON public.asset_maintenance(asset_id);

CREATE INDEX IF NOT EXISTS idx_asset_maintenance_date
    ON public.asset_maintenance(maintenance_date);


-- ============================================================
-- 14. UPDATED_AT TRIGGERS
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_suppliers_updated_at
ON public.suppliers;

CREATE TRIGGER trg_suppliers_updated_at
BEFORE UPDATE ON public.suppliers
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_procurement_requests_updated_at
ON public.procurement_requests;

CREATE TRIGGER trg_procurement_requests_updated_at
BEFORE UPDATE ON public.procurement_requests
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_purchase_orders_updated_at
ON public.purchase_orders;

CREATE TRIGGER trg_purchase_orders_updated_at
BEFORE UPDATE ON public.purchase_orders
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_inventory_categories_updated_at
ON public.inventory_categories;

CREATE TRIGGER trg_inventory_categories_updated_at
BEFORE UPDATE ON public.inventory_categories
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_inventory_items_updated_at
ON public.inventory_items;

CREATE TRIGGER trg_inventory_items_updated_at
BEFORE UPDATE ON public.inventory_items
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_asset_categories_updated_at
ON public.asset_categories;

CREATE TRIGGER trg_asset_categories_updated_at
BEFORE UPDATE ON public.asset_categories
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_assets_updated_at
ON public.assets;

CREATE TRIGGER trg_assets_updated_at
BEFORE UPDATE ON public.assets
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 15. PROCUREMENT REQUEST NUMBER
-- ============================================================

CREATE OR REPLACE FUNCTION public.generate_procurement_request_number()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    next_number bigint;
BEGIN

    IF NEW.request_number IS NULL
       OR btrim(NEW.request_number) = '' THEN

        next_number := nextval(
            'public.procurement_request_number_seq'
        );

        NEW.request_number :=
            'PR/' ||
            to_char(current_date, 'YYYY') ||
            '/' ||
            lpad(next_number::text, 6, '0');

    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_generate_procurement_request_number
ON public.procurement_requests;

CREATE TRIGGER trg_generate_procurement_request_number
BEFORE INSERT ON public.procurement_requests
FOR EACH ROW
EXECUTE FUNCTION public.generate_procurement_request_number();


-- ============================================================
-- 16. PURCHASE ORDER NUMBER
-- ============================================================

CREATE OR REPLACE FUNCTION public.generate_purchase_order_number()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    next_number bigint;
BEGIN

    IF NEW.purchase_order_number IS NULL
       OR btrim(NEW.purchase_order_number) = '' THEN

        next_number := nextval(
            'public.purchase_order_number_seq'
        );

        NEW.purchase_order_number :=
            'PO/' ||
            to_char(current_date, 'YYYY') ||
            '/' ||
            lpad(next_number::text, 6, '0');

    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_generate_purchase_order_number
ON public.purchase_orders;

CREATE TRIGGER trg_generate_purchase_order_number
BEFORE INSERT ON public.purchase_orders
FOR EACH ROW
EXECUTE FUNCTION public.generate_purchase_order_number();


-- ============================================================
-- 17. PERMISSIONS
-- ============================================================

INSERT INTO public.permissions (
    permission_code,
    permission_name,
    module_code,
    action_code
)
VALUES
    (
        'procurement.view',
        'View procurement',
        'OPERATIONS',
        'PROCUREMENT_VIEW'
    ),
    (
        'procurement.manage',
        'Manage procurement',
        'OPERATIONS',
        'PROCUREMENT_MANAGE'
    ),
    (
        'procurement.approve',
        'Approve procurement',
        'OPERATIONS',
        'PROCUREMENT_APPROVE'
    ),
    (
        'inventory.view',
        'View inventory',
        'OPERATIONS',
        'INVENTORY_VIEW'
    ),
    (
        'inventory.manage',
        'Manage inventory',
        'OPERATIONS',
        'INVENTORY_MANAGE'
    ),
    (
        'assets.view',
        'View assets',
        'OPERATIONS',
        'ASSETS_VIEW'
    ),
    (
        'assets.manage',
        'Manage assets',
        'OPERATIONS',
        'ASSETS_MANAGE'
    ),
    (
        'assets.assign',
        'Assign assets',
        'OPERATIONS',
        'ASSETS_ASSIGN'
    )
ON CONFLICT (permission_code)
DO NOTHING;


-- ============================================================
-- 18. ADMIN PERMISSIONS
-- ============================================================

INSERT INTO public.role_permissions (
    role_id,
    permission_id
)
SELECT
    r.id,
    p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.role_code = 'ADMIN'
  AND p.permission_code IN (
      'procurement.view',
      'procurement.manage',
      'procurement.approve',
      'inventory.view',
      'inventory.manage',
      'assets.view',
      'assets.manage',
      'assets.assign'
  )
ON CONFLICT DO NOTHING;


-- ============================================================
-- 19. OPERATIONS OFFICER ROLE
-- ============================================================

INSERT INTO public.roles (
    role_code,
    role_name,
    is_system_role,
    status
)
VALUES (
    'OPERATIONS_OFFICER',
    'Operations Officer',
    FALSE,
    'ACTIVE'
)
ON CONFLICT (role_code)
DO NOTHING;


INSERT INTO public.role_permissions (
    role_id,
    permission_id
)
SELECT
    r.id,
    p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.role_code = 'OPERATIONS_OFFICER'
  AND p.permission_code IN (
      'procurement.view',
      'procurement.manage',
      'procurement.approve',
      'inventory.view',
      'inventory.manage',
      'assets.view',
      'assets.manage',
      'assets.assign'
  )
ON CONFLICT DO NOTHING;


-- ============================================================
-- 20. PROCUREMENT SUMMARY
-- ============================================================

CREATE OR REPLACE VIEW public.procurement_request_summary
AS
SELECT
    pr.id,
    pr.request_number,
    pr.institution_id,
    pr.department_id,
    pr.requested_by,
    pr.request_date,
    pr.required_date,
    pr.priority,
    pr.request_status,
    pr.purpose,
    pr.estimated_total,
    pr.approved_by,
    pr.approved_at,
    pr.created_at,
    pr.updated_at
FROM public.procurement_requests pr;


-- ============================================================
-- 21. INVENTORY SUMMARY
-- ============================================================

CREATE OR REPLACE VIEW public.inventory_stock_summary
AS
SELECT
    ii.id,
    ii.institution_id,
    ii.category_id,
    ii.item_code,
    ii.item_name,
    ii.unit_of_measure,
    ii.minimum_stock_level,
    ii.maximum_stock_level,
    ii.reorder_level,
    ii.current_quantity,
    ii.unit_cost,

    CASE
        WHEN ii.current_quantity <= ii.reorder_level
        THEN TRUE
        ELSE FALSE
    END AS reorder_required,

    ii.storage_location,
    ii.status,

    ii.created_at,
    ii.updated_at

FROM public.inventory_items ii;


-- ============================================================
-- 22. ASSET SUMMARY
-- ============================================================

CREATE OR REPLACE VIEW public.asset_summary
AS
SELECT
    a.id,
    a.asset_tag,
    a.asset_name,
    a.institution_id,
    a.category_id,
    a.department_id,
    a.serial_number,
    a.manufacturer,
    a.model,
    a.acquisition_date,
    a.acquisition_cost,
    a.current_value,
    a.location,
    a.condition_status,
    a.asset_status,
    a.warranty_expiry_date,
    a.created_at,
    a.updated_at
FROM public.assets a;


-- ============================================================
-- 23. COMMENTS
-- ============================================================

COMMENT ON TABLE public.suppliers IS
'Approved suppliers and vendors used by the institution.';

COMMENT ON TABLE public.procurement_requests IS
'Internal procurement requests raised by institutional users.';

COMMENT ON TABLE public.purchase_orders IS
'Purchase orders issued to approved suppliers.';

COMMENT ON TABLE public.inventory_items IS
'Consumable and stock-controlled institutional items.';

COMMENT ON TABLE public.inventory_transactions IS
'Inventory receipt, issue, return and adjustment transactions.';

COMMENT ON TABLE public.assets IS
'Institutional fixed assets and equipment.';

COMMENT ON TABLE public.asset_assignments IS
'Assignment and custody records for institutional assets.';

COMMENT ON TABLE public.asset_maintenance IS
'Maintenance and service history for institutional assets.';


COMMIT;

-- ============================================================
-- END MIGRATION 029
-- ============================================================
