-- ============================================================
-- IDMC iMIS
-- Migration 020
-- Communication & Notification Core
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Dependency checks
-- ------------------------------------------------------------

DO $$
BEGIN
    IF to_regclass('public.students') IS NULL THEN
        RAISE EXCEPTION
            'Migration 020 dependency missing: public.students does not exist';
    END IF;
END
$$;


-- ============================================================
-- 2. Notification Templates
-- ============================================================

CREATE TABLE IF NOT EXISTS public.notification_templates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    template_code varchar(100) NOT NULL UNIQUE,
    template_name varchar(200) NOT NULL,

    channel varchar(30) NOT NULL,

    subject_template text,
    body_template text NOT NULL,

    description text,

    language_code varchar(20) NOT NULL DEFAULT 'en',

    is_active boolean NOT NULL DEFAULT true,

    version integer NOT NULL DEFAULT 1,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT notification_templates_channel_check
        CHECK (channel IN ('IN_APP', 'EMAIL', 'SMS', 'PUSH')),

    CONSTRAINT notification_templates_version_check
        CHECK (version > 0),

    CONSTRAINT notification_templates_language_check
        CHECK (length(trim(language_code)) > 0),

    CONSTRAINT notification_templates_name_check
        CHECK (length(trim(template_name)) > 0),

    CONSTRAINT notification_templates_code_check
        CHECK (length(trim(template_code)) > 0)
);


-- ============================================================
-- 3. Central Notifications
-- ============================================================

CREATE TABLE IF NOT EXISTS public.notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    notification_number varchar(100) NOT NULL UNIQUE,

    recipient_user_id uuid,
    recipient_student_id uuid REFERENCES public.students(id),

    template_id uuid
        REFERENCES public.notification_templates(id),

    notification_type varchar(50) NOT NULL,

    title text NOT NULL,
    body text NOT NULL,

    priority varchar(20) NOT NULL DEFAULT 'NORMAL',

    status varchar(30) NOT NULL DEFAULT 'PENDING',

    scheduled_at timestamptz,
    sent_at timestamptz,
    read_at timestamptz,

    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT notifications_priority_check
        CHECK (priority IN ('LOW', 'NORMAL', 'HIGH', 'URGENT')),

    CONSTRAINT notifications_status_check
        CHECK (
            status IN (
                'PENDING',
                'QUEUED',
                'PROCESSING',
                'SENT',
                'DELIVERED',
                'READ',
                'FAILED',
                'CANCELLED'
            )
        ),

    CONSTRAINT notifications_type_check
        CHECK (length(trim(notification_type)) > 0),

    CONSTRAINT notifications_title_check
        CHECK (length(trim(title)) > 0)
);


-- ============================================================
-- 4. Notification Deliveries
-- ============================================================

CREATE TABLE IF NOT EXISTS public.notification_deliveries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    notification_id uuid NOT NULL
        REFERENCES public.notifications(id)
        ON DELETE CASCADE,

    channel varchar(30) NOT NULL,

    provider varchar(100),

    provider_message_id varchar(255),

    destination_masked varchar(255),

    status varchar(30) NOT NULL DEFAULT 'PENDING',

    attempt_count integer NOT NULL DEFAULT 0,

    last_attempt_at timestamptz,

    delivered_at timestamptz,

    failed_at timestamptz,

    error_code varchar(100),

    error_message text,

    provider_response jsonb,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT notification_deliveries_channel_check
        CHECK (channel IN ('IN_APP', 'EMAIL', 'SMS', 'PUSH')),

    CONSTRAINT notification_deliveries_status_check
        CHECK (
            status IN (
                'PENDING',
                'QUEUED',
                'SENDING',
                'SENT',
                'DELIVERED',
                'FAILED',
                'CANCELLED'
            )
        ),

    CONSTRAINT notification_deliveries_attempt_check
        CHECK (attempt_count >= 0)
);


-- ============================================================
-- 5. Notification Queue
-- ============================================================

CREATE TABLE IF NOT EXISTS public.notification_queue (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    notification_id uuid NOT NULL
        REFERENCES public.notifications(id)
        ON DELETE CASCADE,

    delivery_id uuid
        REFERENCES public.notification_deliveries(id)
        ON DELETE CASCADE,

    available_at timestamptz NOT NULL DEFAULT now(),

    locked_at timestamptz,

    locked_by varchar(255),

    attempt_count integer NOT NULL DEFAULT 0,

    max_attempts integer NOT NULL DEFAULT 5,

    status varchar(30) NOT NULL DEFAULT 'QUEUED',

    last_error text,

    completed_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT notification_queue_status_check
        CHECK (
            status IN (
                'QUEUED',
                'PROCESSING',
                'COMPLETED',
                'FAILED',
                'CANCELLED'
            )
        ),

    CONSTRAINT notification_queue_attempt_check
        CHECK (attempt_count >= 0),

    CONSTRAINT notification_queue_max_attempts_check
        CHECK (max_attempts > 0),

    CONSTRAINT notification_queue_attempt_limit_check
        CHECK (attempt_count <= max_attempts)
);


-- ============================================================
-- 6. Indexes
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_notification_templates_channel
ON public.notification_templates(channel);

CREATE INDEX IF NOT EXISTS idx_notification_templates_active
ON public.notification_templates(is_active);

CREATE INDEX IF NOT EXISTS idx_notifications_recipient_user
ON public.notifications(recipient_user_id);

CREATE INDEX IF NOT EXISTS idx_notifications_recipient_student
ON public.notifications(recipient_student_id);

CREATE INDEX IF NOT EXISTS idx_notifications_status
ON public.notifications(status);

CREATE INDEX IF NOT EXISTS idx_notifications_type
ON public.notifications(notification_type);

CREATE INDEX IF NOT EXISTS idx_notifications_scheduled_at
ON public.notifications(scheduled_at);

CREATE INDEX IF NOT EXISTS idx_notifications_created_at
ON public.notifications(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_notification
ON public.notification_deliveries(notification_id);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_status
ON public.notification_deliveries(status);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_provider_message
ON public.notification_deliveries(provider_message_id);

CREATE INDEX IF NOT EXISTS idx_notification_queue_status
ON public.notification_queue(status);

CREATE INDEX IF NOT EXISTS idx_notification_queue_available
ON public.notification_queue(available_at);

CREATE INDEX IF NOT EXISTS idx_notification_queue_processing
ON public.notification_queue(status, available_at);


-- ============================================================
-- 7. Updated-at triggers
-- ============================================================

CREATE OR REPLACE FUNCTION public.touch_notification_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END
$$;


DROP TRIGGER IF EXISTS trg_touch_notification_templates_updated_at
ON public.notification_templates;

CREATE TRIGGER trg_touch_notification_templates_updated_at
BEFORE UPDATE
ON public.notification_templates
FOR EACH ROW
EXECUTE FUNCTION public.touch_notification_updated_at();


DROP TRIGGER IF EXISTS trg_touch_notifications_updated_at
ON public.notifications;

CREATE TRIGGER trg_touch_notifications_updated_at
BEFORE UPDATE
ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION public.touch_notification_updated_at();


DROP TRIGGER IF EXISTS trg_touch_notification_deliveries_updated_at
ON public.notification_deliveries;

CREATE TRIGGER trg_touch_notification_deliveries_updated_at
BEFORE UPDATE
ON public.notification_deliveries
FOR EACH ROW
EXECUTE FUNCTION public.touch_notification_updated_at();


DROP TRIGGER IF EXISTS trg_touch_notification_queue_updated_at
ON public.notification_queue;

CREATE TRIGGER trg_touch_notification_queue_updated_at
BEFORE UPDATE
ON public.notification_queue
FOR EACH ROW
EXECUTE FUNCTION public.touch_notification_updated_at();


-- ============================================================
-- 8. Notification Number Validation
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_notification_number()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF length(trim(NEW.notification_number)) = 0 THEN
        RAISE EXCEPTION 'Notification number cannot be empty';
    END IF;

    RETURN NEW;
END
$$;


DROP TRIGGER IF EXISTS trg_validate_notification_number
ON public.notifications;

CREATE TRIGGER trg_validate_notification_number
BEFORE INSERT OR UPDATE
ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION public.validate_notification_number();


-- ============================================================
-- 9. Delivery Integrity
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_notification_delivery()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = 'DELIVERED'
       AND NEW.delivered_at IS NULL THEN
        NEW.delivered_at = now();
    END IF;

    IF NEW.status = 'FAILED'
       AND NEW.failed_at IS NULL THEN
        NEW.failed_at = now();
    END IF;

    IF NEW.status IN ('SENT', 'DELIVERED')
       AND NEW.attempt_count = 0 THEN
        NEW.attempt_count = 1;
    END IF;

    RETURN NEW;
END
$$;


DROP TRIGGER IF EXISTS trg_validate_notification_delivery
ON public.notification_deliveries;

CREATE TRIGGER trg_validate_notification_delivery
BEFORE INSERT OR UPDATE
ON public.notification_deliveries
FOR EACH ROW
EXECUTE FUNCTION public.validate_notification_delivery();


-- ============================================================
-- 10. Queue Integrity
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_notification_queue()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = 'COMPLETED'
       AND NEW.completed_at IS NULL THEN
        NEW.completed_at = now();
    END IF;

    IF NEW.attempt_count > NEW.max_attempts THEN
        RAISE EXCEPTION
            'Notification queue attempt count cannot exceed max attempts';
    END IF;

    IF NEW.status = 'FAILED'
       AND NEW.last_error IS NULL THEN
        NEW.last_error = 'Notification delivery failed';
    END IF;

    RETURN NEW;
END
$$;


DROP TRIGGER IF EXISTS trg_validate_notification_queue
ON public.notification_queue;

CREATE TRIGGER trg_validate_notification_queue
BEFORE INSERT OR UPDATE
ON public.notification_queue
FOR EACH ROW
EXECUTE FUNCTION public.validate_notification_queue();


-- ============================================================
-- 11. RLS
-- ============================================================

ALTER TABLE public.notification_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_queue ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 12. Prevent deletion of communication history
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_notification_history_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'Notification history cannot be physically deleted. Use status changes instead.';
END
$$;


DROP TRIGGER IF EXISTS trg_prevent_notification_delete
ON public.notifications;

CREATE TRIGGER trg_prevent_notification_delete
BEFORE DELETE
ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION public.prevent_notification_history_delete();


DROP TRIGGER IF EXISTS trg_prevent_delivery_delete
ON public.notification_deliveries;

CREATE TRIGGER trg_prevent_delivery_delete
BEFORE DELETE
ON public.notification_deliveries
FOR EACH ROW
EXECUTE FUNCTION public.prevent_notification_history_delete();


COMMIT;

-- ============================================================
-- END MIGRATION 020
-- ============================================================
