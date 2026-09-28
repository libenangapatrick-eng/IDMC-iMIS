-- ============================================================
-- IDMC iMIS
-- Migration 030
-- Hostel & Library Core
-- Version: 20260917200000
-- ============================================================

BEGIN;

-- ============================================================
-- 1. HOSTELS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.hostels (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    institution_id uuid NOT NULL
        REFERENCES public.institutions(id)
        ON DELETE RESTRICT,

    hostel_code varchar(60) NOT NULL,
    hostel_name varchar(150) NOT NULL,

    hostel_type varchar(30) NOT NULL DEFAULT 'GENERAL'
        CHECK (
            hostel_type IN (
                'MALE',
                'FEMALE',
                'MIXED',
                'GENERAL'
            )
        ),

    capacity integer NOT NULL DEFAULT 0
        CHECK (capacity >= 0),

    location varchar(255),

    warden_user_id uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    status varchar(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE',
                'CLOSED'
            )
        ),

    description text,

    created_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    updated_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_hostel_code
        UNIQUE (institution_id, hostel_code)
);


-- ============================================================
-- 2. HOSTEL ROOMS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.hostel_rooms (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    hostel_id uuid NOT NULL
        REFERENCES public.hostels(id)
        ON DELETE CASCADE,

    room_number varchar(50) NOT NULL,

    floor_number integer,

    room_type varchar(30) NOT NULL DEFAULT 'STANDARD'
        CHECK (
            room_type IN (
                'STANDARD',
                'SINGLE',
                'DOUBLE',
                'TRIPLE',
                'DORMITORY',
                'OTHER'
            )
        ),

    capacity integer NOT NULL DEFAULT 1
        CHECK (capacity > 0),

    status varchar(20) NOT NULL DEFAULT 'AVAILABLE'
        CHECK (
            status IN (
                'AVAILABLE',
                'FULL',
                'MAINTENANCE',
                'BLOCKED',
                'INACTIVE'
            )
        ),

    notes text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_hostel_room
        UNIQUE (hostel_id, room_number)
);


-- ============================================================
-- 3. HOSTEL BEDS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.hostel_beds (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    room_id uuid NOT NULL
        REFERENCES public.hostel_rooms(id)
        ON DELETE CASCADE,

    bed_number varchar(50) NOT NULL,

    bed_status varchar(20) NOT NULL DEFAULT 'AVAILABLE'
        CHECK (
            bed_status IN (
                'AVAILABLE',
                'OCCUPIED',
                'RESERVED',
                'MAINTENANCE',
                'INACTIVE'
            )
        ),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_hostel_bed
        UNIQUE (room_id, bed_number)
);


-- ============================================================
-- 4. HOSTEL ALLOCATIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.hostel_allocations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id uuid NOT NULL
        REFERENCES public.students(id)
        ON DELETE RESTRICT,

    hostel_id uuid NOT NULL
        REFERENCES public.hostels(id)
        ON DELETE RESTRICT,

    room_id uuid NOT NULL
        REFERENCES public.hostel_rooms(id)
        ON DELETE RESTRICT,

    bed_id uuid NULL
        REFERENCES public.hostel_beds(id)
        ON DELETE SET NULL,

    academic_year varchar(20) NOT NULL,

    allocation_date date NOT NULL DEFAULT current_date,

    move_in_date date,

    move_out_date date,

    allocation_status varchar(30) NOT NULL DEFAULT 'ALLOCATED'
        CHECK (
            allocation_status IN (
                'PENDING',
                'ALLOCATED',
                'ACTIVE',
                'CANCELLED',
                'VACATED'
            )
        ),

    remarks text,

    allocated_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_hostel_allocation_dates
        CHECK (
            move_out_date IS NULL
            OR move_in_date IS NULL
            OR move_out_date >= move_in_date
        )
);


-- ============================================================
-- 5. HOSTEL FEES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.hostel_fees (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    institution_id uuid NOT NULL
        REFERENCES public.institutions(id)
        ON DELETE RESTRICT,

    hostel_id uuid NULL
        REFERENCES public.hostels(id)
        ON DELETE SET NULL,

    academic_year varchar(20) NOT NULL,

    fee_name varchar(150) NOT NULL,

    amount numeric(14,2) NOT NULL
        CHECK (amount >= 0),

    currency varchar(10) NOT NULL DEFAULT 'TZS',

    status varchar(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE'
            )
        ),

    created_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 6. LIBRARY ITEMS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.library_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    institution_id uuid NOT NULL
        REFERENCES public.institutions(id)
        ON DELETE RESTRICT,

    accession_number varchar(80) NOT NULL UNIQUE,

    title varchar(500) NOT NULL,

    subtitle varchar(500),

    item_type varchar(40) NOT NULL DEFAULT 'BOOK'
        CHECK (
            item_type IN (
                'BOOK',
                'JOURNAL',
                'REFERENCE',
                'THESIS',
                'DISSERTATION',
                'REPORT',
                'E_RESOURCE',
                'OTHER'
            )
        ),

    isbn varchar(50),

    author varchar(500),
    publisher varchar(255),

    publication_year integer,

    edition varchar(100),

    subject varchar(255),

    call_number varchar(100),

    language varchar(100) DEFAULT 'English',

    total_copies integer NOT NULL DEFAULT 1
        CHECK (total_copies >= 0),

    available_copies integer NOT NULL DEFAULT 1
        CHECK (
            available_copies >= 0
            AND available_copies <= total_copies
        ),

    location varchar(255),

    item_status varchar(30) NOT NULL DEFAULT 'AVAILABLE'
        CHECK (
            item_status IN (
                'AVAILABLE',
                'PARTIALLY_AVAILABLE',
                'OUT_OF_STOCK',
                'LOST',
                'DAMAGED',
                'ARCHIVED',
                'INACTIVE'
            )
        ),

    description text,

    created_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    updated_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 7. LIBRARY MEMBERS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.library_members (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    institution_id uuid NOT NULL
        REFERENCES public.institutions(id)
        ON DELETE RESTRICT,

    student_id uuid NULL
        REFERENCES public.students(id)
        ON DELETE CASCADE,

    staff_id uuid NULL
        REFERENCES public.staff(id)
        ON DELETE CASCADE,

    membership_number varchar(80) NOT NULL UNIQUE,

    membership_type varchar(30) NOT NULL
        CHECK (
            membership_type IN (
                'STUDENT',
                'STAFF',
                'OTHER'
            )
        ),

    membership_status varchar(30) NOT NULL DEFAULT 'ACTIVE'
        CHECK (
            membership_status IN (
                'ACTIVE',
                'SUSPENDED',
                'EXPIRED',
                'CANCELLED'
            )
        ),

    registration_date date NOT NULL DEFAULT current_date,

    expiry_date date,

    max_active_loans integer NOT NULL DEFAULT 3
        CHECK (max_active_loans > 0),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_library_member_owner
        CHECK (
            student_id IS NOT NULL
            OR staff_id IS NOT NULL
        ),

    CONSTRAINT chk_library_member_expiry
        CHECK (
            expiry_date IS NULL
            OR expiry_date >= registration_date
        )
);


-- ============================================================
-- 8. LIBRARY LOANS
-- ============================================================

CREATE SEQUENCE IF NOT EXISTS public.library_loan_number_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    NO CYCLE;


CREATE TABLE IF NOT EXISTS public.library_loans (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    library_member_id uuid NOT NULL
        REFERENCES public.library_members(id)
        ON DELETE RESTRICT,

    library_item_id uuid NOT NULL
        REFERENCES public.library_items(id)
        ON DELETE RESTRICT,

    loan_number varchar(80) NOT NULL UNIQUE,

    loan_date date NOT NULL DEFAULT current_date,

    due_date date NOT NULL,

    return_date date,

    quantity integer NOT NULL DEFAULT 1
        CHECK (quantity > 0),

    loan_status varchar(30) NOT NULL DEFAULT 'ACTIVE'
        CHECK (
            loan_status IN (
                'ACTIVE',
                'RETURNED',
                'OVERDUE',
                'LOST',
                'CANCELLED'
            )
        ),

    issued_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    returned_to uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    notes text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_library_loan_dates
        CHECK (
            due_date >= loan_date
        ),

    CONSTRAINT chk_library_return_date
        CHECK (
            return_date IS NULL
            OR return_date >= loan_date
        )
);


-- ============================================================
-- 9. LIBRARY FINES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.library_fines (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    loan_id uuid NOT NULL
        REFERENCES public.library_loans(id)
        ON DELETE CASCADE,

    member_id uuid NOT NULL
        REFERENCES public.library_members(id)
        ON DELETE RESTRICT,

    fine_type varchar(30) NOT NULL
        CHECK (
            fine_type IN (
                'OVERDUE',
                'LOST_ITEM',
                'DAMAGED_ITEM',
                'OTHER'
            )
        ),

    amount numeric(14,2) NOT NULL
        CHECK (amount >= 0),

    amount_paid numeric(14,2) NOT NULL DEFAULT 0
        CHECK (
            amount_paid >= 0
            AND amount_paid <= amount
        ),

    currency varchar(10) NOT NULL DEFAULT 'TZS',

    fine_status varchar(20) NOT NULL DEFAULT 'OUTSTANDING'
        CHECK (
            fine_status IN (
                'OUTSTANDING',
                'PARTIALLY_PAID',
                'PAID',
                'WAIVED',
                'CANCELLED'
            )
        ),

    reason text,

    waived_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    waived_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 10. LIBRARY RESERVATIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.library_reservations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    library_member_id uuid NOT NULL
        REFERENCES public.library_members(id)
        ON DELETE RESTRICT,

    library_item_id uuid NOT NULL
        REFERENCES public.library_items(id)
        ON DELETE RESTRICT,

    reservation_date date NOT NULL DEFAULT current_date,

    expiry_date date,

    reservation_status varchar(30) NOT NULL DEFAULT 'ACTIVE'
        CHECK (
            reservation_status IN (
                'ACTIVE',
                'FULFILLED',
                'EXPIRED',
                'CANCELLED'
            )
        ),

    fulfilled_at timestamptz,

    notes text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_library_reservation_dates
        CHECK (
            expiry_date IS NULL
            OR expiry_date >= reservation_date
        )
);


-- ============================================================
-- 11. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_hostels_institution
    ON public.hostels(institution_id);

CREATE INDEX IF NOT EXISTS idx_hostels_status
    ON public.hostels(status);

CREATE INDEX IF NOT EXISTS idx_hostel_rooms_hostel
    ON public.hostel_rooms(hostel_id);

CREATE INDEX IF NOT EXISTS idx_hostel_rooms_status
    ON public.hostel_rooms(status);

CREATE INDEX IF NOT EXISTS idx_hostel_beds_room
    ON public.hostel_beds(room_id);

CREATE INDEX IF NOT EXISTS idx_hostel_beds_status
    ON public.hostel_beds(bed_status);

CREATE INDEX IF NOT EXISTS idx_hostel_allocations_student
    ON public.hostel_allocations(student_id);

CREATE INDEX IF NOT EXISTS idx_hostel_allocations_hostel
    ON public.hostel_allocations(hostel_id);

CREATE INDEX IF NOT EXISTS idx_hostel_allocations_room
    ON public.hostel_allocations(room_id);

CREATE INDEX IF NOT EXISTS idx_hostel_allocations_year
    ON public.hostel_allocations(academic_year);

CREATE INDEX IF NOT EXISTS idx_hostel_allocations_status
    ON public.hostel_allocations(allocation_status);

CREATE INDEX IF NOT EXISTS idx_library_items_institution
    ON public.library_items(institution_id);

CREATE INDEX IF NOT EXISTS idx_library_items_title
    ON public.library_items(title);

CREATE INDEX IF NOT EXISTS idx_library_items_author
    ON public.library_items(author);

CREATE INDEX IF NOT EXISTS idx_library_items_status
    ON public.library_items(item_status);

CREATE INDEX IF NOT EXISTS idx_library_members_student
    ON public.library_members(student_id);

CREATE INDEX IF NOT EXISTS idx_library_members_staff
    ON public.library_members(staff_id);

CREATE INDEX IF NOT EXISTS idx_library_members_status
    ON public.library_members(membership_status);

CREATE INDEX IF NOT EXISTS idx_library_loans_member
    ON public.library_loans(library_member_id);

CREATE INDEX IF NOT EXISTS idx_library_loans_item
    ON public.library_loans(library_item_id);

CREATE INDEX IF NOT EXISTS idx_library_loans_status
    ON public.library_loans(loan_status);

CREATE INDEX IF NOT EXISTS idx_library_loans_due_date
    ON public.library_loans(due_date);

CREATE INDEX IF NOT EXISTS idx_library_fines_member
    ON public.library_fines(member_id);

CREATE INDEX IF NOT EXISTS idx_library_fines_status
    ON public.library_fines(fine_status);

CREATE INDEX IF NOT EXISTS idx_library_reservations_member
    ON public.library_reservations(library_member_id);

CREATE INDEX IF NOT EXISTS idx_library_reservations_item
    ON public.library_reservations(library_item_id);

CREATE INDEX IF NOT EXISTS idx_library_reservations_status
    ON public.library_reservations(reservation_status);


-- ============================================================
-- 12. UPDATED_AT TRIGGERS
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


DROP TRIGGER IF EXISTS trg_hostels_updated_at
ON public.hostels;

CREATE TRIGGER trg_hostels_updated_at
BEFORE UPDATE ON public.hostels
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_hostel_rooms_updated_at
ON public.hostel_rooms;

CREATE TRIGGER trg_hostel_rooms_updated_at
BEFORE UPDATE ON public.hostel_rooms
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_hostel_beds_updated_at
ON public.hostel_beds;

CREATE TRIGGER trg_hostel_beds_updated_at
BEFORE UPDATE ON public.hostel_beds
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_hostel_allocations_updated_at
ON public.hostel_allocations;

CREATE TRIGGER trg_hostel_allocations_updated_at
BEFORE UPDATE ON public.hostel_allocations
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_hostel_fees_updated_at
ON public.hostel_fees;

CREATE TRIGGER trg_hostel_fees_updated_at
BEFORE UPDATE ON public.hostel_fees
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_library_items_updated_at
ON public.library_items;

CREATE TRIGGER trg_library_items_updated_at
BEFORE UPDATE ON public.library_items
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_library_members_updated_at
ON public.library_members;

CREATE TRIGGER trg_library_members_updated_at
BEFORE UPDATE ON public.library_members
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_library_loans_updated_at
ON public.library_loans;

CREATE TRIGGER trg_library_loans_updated_at
BEFORE UPDATE ON public.library_loans
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_library_fines_updated_at
ON public.library_fines;

CREATE TRIGGER trg_library_fines_updated_at
BEFORE UPDATE ON public.library_fines
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_library_reservations_updated_at
ON public.library_reservations;

CREATE TRIGGER trg_library_reservations_updated_at
BEFORE UPDATE ON public.library_reservations
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 13. LIBRARY LOAN NUMBER
-- ============================================================

CREATE OR REPLACE FUNCTION public.generate_library_loan_number()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    next_number bigint;
BEGIN

    IF NEW.loan_number IS NULL
       OR btrim(NEW.loan_number) = '' THEN

        next_number := nextval(
            'public.library_loan_number_seq'
        );

        NEW.loan_number :=
            'LIB/' ||
            to_char(current_date, 'YYYY') ||
            '/' ||
            lpad(next_number::text, 6, '0');

    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_generate_library_loan_number
ON public.library_loans;

CREATE TRIGGER trg_generate_library_loan_number
BEFORE INSERT ON public.library_loans
FOR EACH ROW
EXECUTE FUNCTION public.generate_library_loan_number();


-- ============================================================
-- 14. LIBRARY STATUS AUTOMATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_library_loan_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.return_date IS NOT NULL THEN
        NEW.loan_status = 'RETURNED';

    ELSIF NEW.due_date < current_date
          AND NEW.loan_status = 'ACTIVE' THEN
        NEW.loan_status = 'OVERDUE';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_update_library_loan_status
ON public.library_loans;

CREATE TRIGGER trg_update_library_loan_status
BEFORE INSERT OR UPDATE
ON public.library_loans
FOR EACH ROW
EXECUTE FUNCTION public.update_library_loan_status();


-- ============================================================
-- 15. PERMISSIONS
-- ============================================================

INSERT INTO public.permissions (
    permission_code,
    permission_name,
    module_code,
    action_code
)
VALUES
    (
        'hostel.view',
        'View hostel management',
        'OPERATIONS',
        'HOSTEL_VIEW'
    ),
    (
        'hostel.manage',
        'Manage hostel management',
        'OPERATIONS',
        'HOSTEL_MANAGE'
    ),
    (
        'hostel.allocate',
        'Allocate hostel accommodation',
        'OPERATIONS',
        'HOSTEL_ALLOCATE'
    ),
    (
        'library.view',
        'View library',
        'OPERATIONS',
        'LIBRARY_VIEW'
    ),
    (
        'library.manage',
        'Manage library',
        'OPERATIONS',
        'LIBRARY_MANAGE'
    ),
    (
        'library.issue',
        'Issue library materials',
        'OPERATIONS',
        'LIBRARY_ISSUE'
    ),
    (
        'library.return',
        'Return library materials',
        'OPERATIONS',
        'LIBRARY_RETURN'
    ),
    (
        'library.fines.manage',
        'Manage library fines',
        'OPERATIONS',
        'LIBRARY_FINES_MANAGE'
    )
ON CONFLICT (permission_code)
DO NOTHING;


-- ============================================================
-- 16. ADMIN PERMISSIONS
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
      'hostel.view',
      'hostel.manage',
      'hostel.allocate',
      'library.view',
      'library.manage',
      'library.issue',
      'library.return',
      'library.fines.manage'
  )
ON CONFLICT DO NOTHING;


-- ============================================================
-- 17. HOSTEL OFFICER
-- ============================================================

INSERT INTO public.roles (
    role_code,
    role_name,
    is_system_role,
    status
)
VALUES (
    'HOSTEL_OFFICER',
    'Hostel Officer',
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
WHERE r.role_code = 'HOSTEL_OFFICER'
  AND p.permission_code IN (
      'hostel.view',
      'hostel.manage',
      'hostel.allocate'
  )
ON CONFLICT DO NOTHING;


-- ============================================================
-- 18. LIBRARIAN
-- ============================================================

INSERT INTO public.roles (
    role_code,
    role_name,
    is_system_role,
    status
)
VALUES (
    'LIBRARIAN',
    'Librarian',
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
WHERE r.role_code = 'LIBRARIAN'
  AND p.permission_code IN (
      'library.view',
      'library.manage',
      'library.issue',
      'library.return',
      'library.fines.manage'
  )
ON CONFLICT DO NOTHING;


-- ============================================================
-- 19. HOSTEL SUMMARY
-- ============================================================

CREATE OR REPLACE VIEW public.hostel_occupancy_summary
AS
SELECT
    h.id AS hostel_id,
    h.institution_id,
    h.hostel_code,
    h.hostel_name,
    h.capacity,

    COUNT(DISTINCT hr.id) AS total_rooms,

    COUNT(DISTINCT hb.id) AS total_beds,

    COUNT(DISTINCT CASE
        WHEN hb.bed_status = 'OCCUPIED'
        THEN hb.id
    END) AS occupied_beds,

    COUNT(DISTINCT CASE
        WHEN hb.bed_status = 'AVAILABLE'
        THEN hb.id
    END) AS available_beds

FROM public.hostels h

LEFT JOIN public.hostel_rooms hr
    ON hr.hostel_id = h.id

LEFT JOIN public.hostel_beds hb
    ON hb.room_id = hr.id

GROUP BY
    h.id,
    h.institution_id,
    h.hostel_code,
    h.hostel_name,
    h.capacity;


-- ============================================================
-- 20. LIBRARY SUMMARY
-- ============================================================

CREATE OR REPLACE VIEW public.library_inventory_summary
AS
SELECT
    li.id,
    li.institution_id,
    li.accession_number,
    li.title,
    li.item_type,
    li.isbn,
    li.author,
    li.publisher,
    li.publication_year,
    li.subject,
    li.call_number,
    li.total_copies,
    li.available_copies,

    (
        li.total_copies - li.available_copies
    ) AS issued_copies,

    li.item_status,
    li.created_at,
    li.updated_at

FROM public.library_items li;


-- ============================================================
-- 21. COMMENTS
-- ============================================================

COMMENT ON TABLE public.hostels IS
'Institutional hostel/accommodation facilities.';

COMMENT ON TABLE public.hostel_rooms IS
'Rooms within institutional hostels.';

COMMENT ON TABLE public.hostel_beds IS
'Beds available for hostel allocation.';

COMMENT ON TABLE public.hostel_allocations IS
'Student hostel accommodation allocations.';

COMMENT ON TABLE public.hostel_fees IS
'Hostel accommodation fee configurations.';

COMMENT ON TABLE public.library_items IS
'Library books, journals, references and other resources.';

COMMENT ON TABLE public.library_members IS
'Institutional library membership records.';

COMMENT ON TABLE public.library_loans IS
'Library borrowing and return transactions.';

COMMENT ON TABLE public.library_fines IS
'Library overdue, lost and damaged item fines.';

COMMENT ON TABLE public.library_reservations IS
'Library material reservation records.';


COMMIT;

-- ============================================================
-- END MIGRATION 030
-- ============================================================
