-- ============================================================
-- IDMC iMIS
-- Migration 028
-- HR Lifecycle, Leave Management & Staff Attendance
-- Version: 20260917180000
-- ============================================================

BEGIN;

-- ============================================================
-- 1. LEAVE TYPES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.staff_leave_types (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    institution_id uuid NOT NULL
        REFERENCES public.institutions(id)
        ON DELETE RESTRICT,

    leave_code varchar(50) NOT NULL,
    leave_name varchar(150) NOT NULL,

    annual_entitlement numeric(6,2) NOT NULL DEFAULT 0
        CHECK (annual_entitlement >= 0),

    requires_document boolean NOT NULL DEFAULT FALSE,

    requires_approval boolean NOT NULL DEFAULT TRUE,

    paid_leave boolean NOT NULL DEFAULT TRUE,

    carry_forward_allowed boolean NOT NULL DEFAULT FALSE,

    max_carry_forward_days numeric(6,2) NOT NULL DEFAULT 0
        CHECK (max_carry_forward_days >= 0),

    status varchar(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (
            status IN (
                'ACTIVE',
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
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_staff_leave_type
        UNIQUE (institution_id, leave_code)
);


-- ============================================================
-- 2. STAFF LEAVE BALANCES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.staff_leave_balances (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    staff_id uuid NOT NULL
        REFERENCES public.staff(id)
        ON DELETE CASCADE,

    leave_type_id uuid NOT NULL
        REFERENCES public.staff_leave_types(id)
        ON DELETE RESTRICT,

    leave_year integer NOT NULL,

    opening_balance numeric(6,2) NOT NULL DEFAULT 0
        CHECK (opening_balance >= 0),

    accrued_days numeric(6,2) NOT NULL DEFAULT 0
        CHECK (accrued_days >= 0),

    carried_forward_days numeric(6,2) NOT NULL DEFAULT 0
        CHECK (carried_forward_days >= 0),

    used_days numeric(6,2) NOT NULL DEFAULT 0
        CHECK (used_days >= 0),

    pending_days numeric(6,2) NOT NULL DEFAULT 0
        CHECK (pending_days >= 0),

    closing_adjustment numeric(6,2) NOT NULL DEFAULT 0,

    available_balance numeric(6,2)
        GENERATED ALWAYS AS (
            opening_balance
            + accrued_days
            + carried_forward_days
            + closing_adjustment
            - used_days
            - pending_days
        ) STORED,

    notes text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_staff_leave_balance
        UNIQUE (staff_id, leave_type_id, leave_year)
);


-- ============================================================
-- 3. STAFF LEAVE REQUESTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.staff_leave_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    staff_id uuid NOT NULL
        REFERENCES public.staff(id)
        ON DELETE RESTRICT,

    leave_type_id uuid NOT NULL
        REFERENCES public.staff_leave_types(id)
        ON DELETE RESTRICT,

    leave_year integer NOT NULL,

    request_number varchar(60) NOT NULL UNIQUE,

    start_date date NOT NULL,
    end_date date NOT NULL,

    days_requested numeric(6,2) NOT NULL
        CHECK (days_requested > 0),

    reason text NOT NULL,

    attachment_url text,

    request_status varchar(30) NOT NULL DEFAULT 'PENDING'
        CHECK (
            request_status IN (
                'DRAFT',
                'PENDING',
                'APPROVED',
                'PARTIALLY_APPROVED',
                'REJECTED',
                'CANCELLED',
                'WITHDRAWN'
            )
        ),

    submitted_at timestamptz,

    approved_days numeric(6,2) NOT NULL DEFAULT 0
        CHECK (approved_days >= 0),

    rejection_reason text,

    current_approver_user_id uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    final_approved_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    final_approved_at timestamptz,

    created_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    updated_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_leave_request_dates
        CHECK (end_date >= start_date),

    CONSTRAINT chk_leave_approved_days
        CHECK (approved_days <= days_requested)
);


-- ============================================================
-- 4. LEAVE APPROVALS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.staff_leave_approvals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    leave_request_id uuid NOT NULL
        REFERENCES public.staff_leave_requests(id)
        ON DELETE CASCADE,

    approval_level integer NOT NULL
        CHECK (approval_level > 0),

    approver_user_id uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    decision varchar(30) NOT NULL DEFAULT 'PENDING'
        CHECK (
            decision IN (
                'PENDING',
                'APPROVED',
                'REJECTED',
                'RETURNED',
                'CANCELLED'
            )
        ),

    approved_days numeric(6,2),

    comments text,

    actioned_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_leave_approval_level
        UNIQUE (leave_request_id, approval_level)
);


-- ============================================================
-- 5. STAFF ATTENDANCE
-- ============================================================

CREATE TABLE IF NOT EXISTS public.staff_attendance (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    staff_id uuid NOT NULL
        REFERENCES public.staff(id)
        ON DELETE RESTRICT,

    attendance_date date NOT NULL,

    attendance_status varchar(30) NOT NULL DEFAULT 'PRESENT'
        CHECK (
            attendance_status IN (
                'PRESENT',
                'ABSENT',
                'LATE',
                'HALF_DAY',
                'REMOTE',
                'ON_LEAVE',
                'OFF_DUTY'
            )
        ),

    check_in time NULL,
    check_out time NULL,

    late_minutes integer NOT NULL DEFAULT 0
        CHECK (late_minutes >= 0),

    worked_minutes integer NULL
        CHECK (
            worked_minutes IS NULL
            OR worked_minutes >= 0
        ),

    source varchar(30) NOT NULL DEFAULT 'MANUAL'
        CHECK (
            source IN (
                'MANUAL',
                'DEVICE',
                'IMPORT',
                'SYSTEM'
            )
        ),

    location varchar(255),

    remarks text,

    marked_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_staff_attendance_day
        UNIQUE (staff_id, attendance_date),

    CONSTRAINT chk_staff_attendance_time
        CHECK (
            check_out IS NULL
            OR check_in IS NULL
            OR check_out >= check_in
        )
);


-- ============================================================
-- 6. STAFF ATTENDANCE ADJUSTMENTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.staff_attendance_adjustments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    attendance_id uuid NOT NULL
        REFERENCES public.staff_attendance(id)
        ON DELETE CASCADE,

    requested_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    reviewed_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    old_status varchar(30),

    new_status varchar(30),

    old_check_in time,

    new_check_in time,

    old_check_out time,

    new_check_out time,

    adjustment_reason text NOT NULL,

    adjustment_status varchar(30) NOT NULL DEFAULT 'PENDING'
        CHECK (
            adjustment_status IN (
                'PENDING',
                'APPROVED',
                'REJECTED',
                'CANCELLED'
            )
        ),

    reviewed_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 7. STAFF LIFECYCLE EVENTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.staff_lifecycle_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    staff_id uuid NOT NULL
        REFERENCES public.staff(id)
        ON DELETE CASCADE,

    event_type varchar(50) NOT NULL
        CHECK (
            event_type IN (
                'HIRED',
                'APPOINTED',
                'CONFIRMED',
                'PROMOTED',
                'TRANSFERRED',
                'DEPARTMENT_CHANGED',
                'ROLE_CHANGED',
                'CONTRACT_STARTED',
                'CONTRACT_RENEWED',
                'CONTRACT_ENDED',
                'SUSPENDED',
                'RETURNED_FROM_SUSPENSION',
                'RESIGNED',
                'TERMINATED',
                'RETIRED',
                'RETURNED_FROM_LEAVE',
                'REACTIVATED',
                'STATUS_CHANGED',
                'OTHER'
            )
        ),

    effective_date date NOT NULL,

    previous_status varchar(40),

    new_status varchar(40),

    previous_department_id uuid NULL
        REFERENCES public.departments(id)
        ON DELETE SET NULL,

    new_department_id uuid NULL
        REFERENCES public.departments(id)
        ON DELETE SET NULL,

    previous_job_title varchar(150),

    new_job_title varchar(150),

    reason text,

    reference_number varchar(100),

    notes text,

    recorded_by uuid NULL
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    created_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 8. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_staff_leave_types_institution
    ON public.staff_leave_types(institution_id);

CREATE INDEX IF NOT EXISTS idx_staff_leave_types_status
    ON public.staff_leave_types(status);

CREATE INDEX IF NOT EXISTS idx_staff_leave_balances_staff
    ON public.staff_leave_balances(staff_id);

CREATE INDEX IF NOT EXISTS idx_staff_leave_balances_year
    ON public.staff_leave_balances(leave_year);

CREATE INDEX IF NOT EXISTS idx_staff_leave_requests_staff
    ON public.staff_leave_requests(staff_id);

CREATE INDEX IF NOT EXISTS idx_staff_leave_requests_status
    ON public.staff_leave_requests(request_status);

CREATE INDEX IF NOT EXISTS idx_staff_leave_requests_dates
    ON public.staff_leave_requests(start_date, end_date);

CREATE INDEX IF NOT EXISTS idx_staff_leave_approvals_request
    ON public.staff_leave_approvals(leave_request_id);

CREATE INDEX IF NOT EXISTS idx_staff_leave_approvals_approver
    ON public.staff_leave_approvals(approver_user_id);

CREATE INDEX IF NOT EXISTS idx_staff_attendance_staff
    ON public.staff_attendance(staff_id);

CREATE INDEX IF NOT EXISTS idx_staff_attendance_date
    ON public.staff_attendance(attendance_date);

CREATE INDEX IF NOT EXISTS idx_staff_attendance_status
    ON public.staff_attendance(attendance_status);

CREATE INDEX IF NOT EXISTS idx_staff_attendance_adjustments_attendance
    ON public.staff_attendance_adjustments(attendance_id);

CREATE INDEX IF NOT EXISTS idx_staff_attendance_adjustments_status
    ON public.staff_attendance_adjustments(adjustment_status);

CREATE INDEX IF NOT EXISTS idx_staff_lifecycle_events_staff
    ON public.staff_lifecycle_events(staff_id);

CREATE INDEX IF NOT EXISTS idx_staff_lifecycle_events_date
    ON public.staff_lifecycle_events(effective_date);

CREATE INDEX IF NOT EXISTS idx_staff_lifecycle_events_type
    ON public.staff_lifecycle_events(event_type);


-- ============================================================
-- 9. UPDATED_AT TRIGGERS
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


DROP TRIGGER IF EXISTS trg_staff_leave_types_updated_at
ON public.staff_leave_types;

CREATE TRIGGER trg_staff_leave_types_updated_at
BEFORE UPDATE ON public.staff_leave_types
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_staff_leave_balances_updated_at
ON public.staff_leave_balances;

CREATE TRIGGER trg_staff_leave_balances_updated_at
BEFORE UPDATE ON public.staff_leave_balances
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_staff_leave_requests_updated_at
ON public.staff_leave_requests;

CREATE TRIGGER trg_staff_leave_requests_updated_at
BEFORE UPDATE ON public.staff_leave_requests
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_staff_attendance_updated_at
ON public.staff_attendance;

CREATE TRIGGER trg_staff_attendance_updated_at
BEFORE UPDATE ON public.staff_attendance
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 10. LEAVE REQUEST NUMBER
-- ============================================================

CREATE SEQUENCE IF NOT EXISTS public.staff_leave_request_number_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    NO CYCLE;


CREATE OR REPLACE FUNCTION public.generate_staff_leave_request_number()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    next_number bigint;
BEGIN

    IF NEW.request_number IS NULL
       OR btrim(NEW.request_number) = '' THEN

        next_number := nextval(
            'public.staff_leave_request_number_seq'
        );

        NEW.request_number :=
            'LEAVE/' ||
            COALESCE(NEW.leave_year::text, to_char(current_date, 'YYYY')) ||
            '/' ||
            lpad(next_number::text, 6, '0');

    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_generate_staff_leave_request_number
ON public.staff_leave_requests;

CREATE TRIGGER trg_generate_staff_leave_request_number
BEFORE INSERT ON public.staff_leave_requests
FOR EACH ROW
EXECUTE FUNCTION public.generate_staff_leave_request_number();


-- ============================================================
-- 11. VALIDATE LEAVE REQUEST
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_staff_leave_request()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.end_date < NEW.start_date THEN
        RAISE EXCEPTION
            'Leave end date cannot be before start date';
    END IF;


    IF NEW.days_requested <= 0 THEN
        RAISE EXCEPTION
            'Leave days requested must be greater than zero';
    END IF;


    IF NEW.request_status IN (
        'PENDING',
        'APPROVED',
        'PARTIALLY_APPROVED'
    ) THEN

        IF EXISTS (
            SELECT 1
            FROM public.staff_leave_requests existing
            WHERE existing.staff_id = NEW.staff_id
              AND existing.id <> NEW.id
              AND existing.request_status IN (
                  'PENDING',
                  'APPROVED',
                  'PARTIALLY_APPROVED'
              )
              AND NEW.start_date <= existing.end_date
              AND NEW.end_date >= existing.start_date
        ) THEN

            RAISE EXCEPTION
                'Staff member already has an overlapping leave request';

        END IF;

    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_staff_leave_request
ON public.staff_leave_requests;

CREATE TRIGGER trg_validate_staff_leave_request
BEFORE INSERT OR UPDATE
ON public.staff_leave_requests
FOR EACH ROW
EXECUTE FUNCTION public.validate_staff_leave_request();


-- ============================================================
-- 12. PERMISSIONS
-- ============================================================

INSERT INTO public.permissions (
    permission_code,
    permission_name,
    module_code,
    action_code
)
VALUES
    (
        'leave.view',
        'View staff leave',
        'HUMAN_RESOURCES',
        'LEAVE_VIEW'
    ),
    (
        'leave.manage',
        'Manage staff leave',
        'HUMAN_RESOURCES',
        'LEAVE_MANAGE'
    ),
    (
        'leave.approve',
        'Approve staff leave',
        'HUMAN_RESOURCES',
        'LEAVE_APPROVE'
    ),
    (
        'staff.attendance.view',
        'View staff attendance',
        'HUMAN_RESOURCES',
        'STAFF_ATTENDANCE_VIEW'
    ),
    (
        'staff.attendance.manage',
        'Manage staff attendance',
        'HUMAN_RESOURCES',
        'STAFF_ATTENDANCE_MANAGE'
    ),
    (
        'staff.lifecycle.view',
        'View staff lifecycle',
        'HUMAN_RESOURCES',
        'STAFF_LIFECYCLE_VIEW'
    ),
    (
        'staff.lifecycle.manage',
        'Manage staff lifecycle',
        'HUMAN_RESOURCES',
        'STAFF_LIFECYCLE_MANAGE'
    )
ON CONFLICT (permission_code)
DO NOTHING;


-- ============================================================
-- 13. ADMIN PERMISSIONS
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
      'leave.view',
      'leave.manage',
      'leave.approve',
      'staff.attendance.view',
      'staff.attendance.manage',
      'staff.lifecycle.view',
      'staff.lifecycle.manage'
  )
ON CONFLICT DO NOTHING;


-- ============================================================
-- 14. HR OFFICER PERMISSIONS
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
WHERE r.role_code = 'HR_OFFICER'
  AND p.permission_code IN (
      'leave.view',
      'leave.manage',
      'leave.approve',
      'staff.attendance.view',
      'staff.attendance.manage',
      'staff.lifecycle.view',
      'staff.lifecycle.manage'
  )
ON CONFLICT DO NOTHING;


-- ============================================================
-- 15. STAFF LEAVE SUMMARY VIEW
-- ============================================================

CREATE OR REPLACE VIEW public.staff_leave_summary
AS
SELECT
    lr.id,
    lr.request_number,
    lr.staff_id,
    trim(
        concat_ws(
            ' ',
            s.first_name,
            s.middle_name,
            s.last_name
        )
    ) AS staff_name,

    s.employee_number,

    lr.leave_type_id,
    lt.leave_code,
    lt.leave_name,

    lr.leave_year,
    lr.start_date,
    lr.end_date,
    lr.days_requested,
    lr.approved_days,
    lr.request_status,
    lr.submitted_at,
    lr.final_approved_at,

    lr.created_at,
    lr.updated_at

FROM public.staff_leave_requests lr

INNER JOIN public.staff s
    ON s.id = lr.staff_id

INNER JOIN public.staff_leave_types lt
    ON lt.id = lr.leave_type_id;


-- ============================================================
-- 16. STAFF ATTENDANCE SUMMARY VIEW
-- ============================================================

CREATE OR REPLACE VIEW public.staff_attendance_summary
AS
SELECT
    sa.id,
    sa.staff_id,

    s.employee_number,

    trim(
        concat_ws(
            ' ',
            s.first_name,
            s.middle_name,
            s.last_name
        )
    ) AS staff_name,

    s.department_id,

    sa.attendance_date,
    sa.attendance_status,
    sa.check_in,
    sa.check_out,
    sa.late_minutes,
    sa.worked_minutes,
    sa.source,
    sa.location,
    sa.remarks,

    sa.created_at,
    sa.updated_at

FROM public.staff_attendance sa

INNER JOIN public.staff s
    ON s.id = sa.staff_id;


-- ============================================================
-- 17. COMMENTS
-- ============================================================

COMMENT ON TABLE public.staff_leave_types IS
'Institutional staff leave categories and entitlement rules.';

COMMENT ON TABLE public.staff_leave_balances IS
'Annual staff leave balances by leave type.';

COMMENT ON TABLE public.staff_leave_requests IS
'Staff leave requests and approval state.';

COMMENT ON TABLE public.staff_leave_approvals IS
'Approval workflow for staff leave requests.';

COMMENT ON TABLE public.staff_attendance IS
'Daily attendance records for institutional staff.';

COMMENT ON TABLE public.staff_attendance_adjustments IS
'Controlled corrections to staff attendance records.';

COMMENT ON TABLE public.staff_lifecycle_events IS
'Chronological employment lifecycle events for staff.';


COMMIT;

-- ============================================================
-- END MIGRATION 028
-- ============================================================
