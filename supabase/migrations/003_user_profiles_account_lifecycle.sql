-- ============================================================
-- IDMC iMIS
-- Migration 003
-- User Profiles & Account Lifecycle
-- PostgreSQL / Supabase Cloud
-- ============================================================

-- ============================================================
-- 1. USER PROFILES
-- One profile belongs to exactly one iMIS user.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.user_profiles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id uuid NOT NULL
        REFERENCES public.users(id)
        ON DELETE CASCADE,

    title varchar(30),

    date_of_birth date,

    gender varchar(30),

    nationality varchar(100),

    national_id_number varchar(100),

    passport_number varchar(100),

    marital_status varchar(30),

    occupation varchar(150),

    organisation varchar(200),

    biography text,

    preferred_language varchar(20) NOT NULL DEFAULT 'en',

    profile_completed boolean NOT NULL DEFAULT false,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_user_profiles_user
        UNIQUE (user_id),

    CONSTRAINT user_profiles_gender_check
        CHECK (
            gender IS NULL
            OR gender IN (
                'MALE',
                'FEMALE',
                'OTHER',
                'PREFER_NOT_TO_SAY'
            )
        ),

    CONSTRAINT user_profiles_marital_status_check
        CHECK (
            marital_status IS NULL
            OR marital_status IN (
                'SINGLE',
                'MARRIED',
                'DIVORCED',
                'WIDOWED',
                'SEPARATED',
                'PREFER_NOT_TO_SAY'
            )
        ),

    CONSTRAINT user_profiles_preferred_language_check
        CHECK (
            preferred_language IN ('en', 'sw')
        )
);


-- ============================================================
-- 2. USER ADDRESSES
-- Supports multiple addresses for one user.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.user_addresses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id uuid NOT NULL
        REFERENCES public.users(id)
        ON DELETE CASCADE,

    address_type varchar(30) NOT NULL DEFAULT 'PRIMARY',

    address_line_1 varchar(250),

    address_line_2 varchar(250),

    city varchar(100),

    district varchar(100),

    region varchar(100),

    country varchar(100) NOT NULL DEFAULT 'Tanzania',

    postal_code varchar(30),

    is_primary boolean NOT NULL DEFAULT false,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT user_addresses_type_check
        CHECK (
            address_type IN (
                'PRIMARY',
                'PERMANENT',
                'RESIDENTIAL',
                'POSTAL',
                'WORK',
                'OTHER'
            )
        )
);


-- ============================================================
-- 3. USER STATUS HISTORY
-- Keeps a complete history of account status changes.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.user_status_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id uuid NOT NULL
        REFERENCES public.users(id)
        ON DELETE CASCADE,

    old_status varchar(30),

    new_status varchar(30) NOT NULL,

    reason text,

    changed_by uuid
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    changed_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 4. USER PREFERENCES
-- Application-level preferences.
-- Authentication remains controlled by Supabase Auth.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.user_preferences (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id uuid NOT NULL
        REFERENCES public.users(id)
        ON DELETE CASCADE,

    timezone varchar(100) NOT NULL DEFAULT 'Africa/Dar_es_Salaam',

    date_format varchar(30) NOT NULL DEFAULT 'DD/MM/YYYY',

    time_format varchar(10) NOT NULL DEFAULT '24H',

    email_notifications boolean NOT NULL DEFAULT true,

    sms_notifications boolean NOT NULL DEFAULT true,

    push_notifications boolean NOT NULL DEFAULT true,

    in_app_notifications boolean NOT NULL DEFAULT true,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_user_preferences_user
        UNIQUE (user_id),

    CONSTRAINT user_preferences_time_format_check
        CHECK (
            time_format IN ('12H', '24H')
        )
);


-- ============================================================
-- 5. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_user_profiles_user
    ON public.user_profiles(user_id);

CREATE INDEX IF NOT EXISTS idx_user_profiles_national_id
    ON public.user_profiles(national_id_number);

CREATE INDEX IF NOT EXISTS idx_user_profiles_passport
    ON public.user_profiles(passport_number);

CREATE INDEX IF NOT EXISTS idx_user_profiles_nationality
    ON public.user_profiles(nationality);

CREATE INDEX IF NOT EXISTS idx_user_profiles_gender
    ON public.user_profiles(gender);

CREATE INDEX IF NOT EXISTS idx_user_addresses_user
    ON public.user_addresses(user_id);

CREATE INDEX IF NOT EXISTS idx_user_addresses_type
    ON public.user_addresses(address_type);

CREATE INDEX IF NOT EXISTS idx_user_addresses_primary
    ON public.user_addresses(user_id, is_primary);

CREATE INDEX IF NOT EXISTS idx_user_status_history_user
    ON public.user_status_history(user_id);

CREATE INDEX IF NOT EXISTS idx_user_status_history_changed_at
    ON public.user_status_history(changed_at);

CREATE INDEX IF NOT EXISTS idx_user_status_history_new_status
    ON public.user_status_history(new_status);

CREATE INDEX IF NOT EXISTS idx_user_preferences_user
    ON public.user_preferences(user_id);


-- ============================================================
-- 6. UPDATED_AT TRIGGERS
-- Uses the set_updated_at() function created in Migration 001.
-- ============================================================

DROP TRIGGER IF EXISTS trg_user_profiles_updated_at
    ON public.user_profiles;

CREATE TRIGGER trg_user_profiles_updated_at
BEFORE UPDATE ON public.user_profiles
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_user_addresses_updated_at
    ON public.user_addresses;

CREATE TRIGGER trg_user_addresses_updated_at
BEFORE UPDATE ON public.user_addresses
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


DROP TRIGGER IF EXISTS trg_user_preferences_updated_at
    ON public.user_preferences;

CREATE TRIGGER trg_user_preferences_updated_at
BEFORE UPDATE ON public.user_preferences
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 7. ROW LEVEL SECURITY
-- Backend service role will manage these records.
-- Application-level authorization will be handled by RBAC.
-- ============================================================

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.user_addresses ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.user_status_history ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 8. COMMENTS
-- ============================================================

COMMENT ON TABLE public.user_profiles IS
'General personal profile information for an IDMC iMIS user.';

COMMENT ON TABLE public.user_addresses IS
'Multiple physical or postal addresses associated with an iMIS user.';

COMMENT ON TABLE public.user_status_history IS
'Historical record of IDMC iMIS account status changes.';

COMMENT ON TABLE public.user_preferences IS
'Application-level preferences for an IDMC iMIS user.';

COMMENT ON COLUMN public.user_profiles.national_id_number IS
'National identification number where applicable.';

COMMENT ON COLUMN public.user_profiles.passport_number IS
'Passport number where applicable.';

COMMENT ON COLUMN public.user_profiles.profile_completed IS
'Indicates whether the required profile information has been completed.';


-- ============================================================
-- 9. INITIAL STATUS HISTORY
-- Existing users are not modified automatically.
-- New status changes will be recorded by the application layer.
-- ============================================================

-- Intentionally left empty.
-- The backend audit/workflow layer will create status history records.


-- ============================================================
-- END MIGRATION 003
-- ============================================================
