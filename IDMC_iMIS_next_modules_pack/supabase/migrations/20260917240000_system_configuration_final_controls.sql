-- 034: System Configuration & Final Operational Controls

CREATE TABLE IF NOT EXISTS public.system_settings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions(id),
    setting_key varchar(150) NOT NULL,
    setting_name varchar(255) NOT NULL,
    value_type varchar(30) NOT NULL DEFAULT 'STRING',
    setting_value jsonb NOT NULL DEFAULT 'null'::jsonb,
    is_sensitive boolean NOT NULL DEFAULT false,
    is_editable boolean NOT NULL DEFAULT true,
    description text,
    updated_by uuid REFERENCES public.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT system_settings_value_type_ck
      CHECK (value_type IN ('STRING','NUMBER','BOOLEAN','JSON','DATE','DATETIME')),
    CONSTRAINT system_settings_key_ck CHECK (length(trim(setting_key)) > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_system_setting_key
  ON public.system_settings(institution_id, setting_key);

CREATE TABLE IF NOT EXISTS public.system_feature_flags (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions(id),
    feature_code varchar(150) NOT NULL,
    feature_name varchar(255) NOT NULL,
    is_enabled boolean NOT NULL DEFAULT false,
    rollout_percentage numeric(5,2) NOT NULL DEFAULT 100,
    description text,
    updated_by uuid REFERENCES public.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT system_feature_rollout_ck CHECK (rollout_percentage >= 0 AND rollout_percentage <= 100)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_system_feature_code
  ON public.system_feature_flags(institution_id, feature_code);

CREATE TABLE IF NOT EXISTS public.system_number_sequences (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions(id),
    sequence_code varchar(100) NOT NULL,
    sequence_name varchar(255) NOT NULL,
    prefix varchar(50),
    current_value bigint NOT NULL DEFAULT 0,
    padding_width integer NOT NULL DEFAULT 6,
    reset_period varchar(20) NOT NULL DEFAULT 'NEVER',
    is_active boolean NOT NULL DEFAULT true,
    updated_by uuid REFERENCES public.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT system_number_sequence_current_ck CHECK (current_value >= 0),
    CONSTRAINT system_number_sequence_padding_ck CHECK (padding_width BETWEEN 1 AND 20),
    CONSTRAINT system_number_sequence_reset_ck CHECK (reset_period IN ('NEVER','YEAR','MONTH'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_system_number_sequence_code
  ON public.system_number_sequences(institution_id, sequence_code);

CREATE TABLE IF NOT EXISTS public.system_maintenance_windows (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions(id),
    title varchar(255) NOT NULL,
    start_at timestamptz NOT NULL,
    end_at timestamptz NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'SCHEDULED',
    message text,
    created_by uuid REFERENCES public.users(id),
    updated_by uuid REFERENCES public.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT system_maintenance_dates_ck CHECK (end_at > start_at),
    CONSTRAINT system_maintenance_status_ck CHECK (status IN ('SCHEDULED','ACTIVE','COMPLETED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS public.system_workflows (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions(id),
    workflow_code varchar(100) NOT NULL,
    workflow_name varchar(255) NOT NULL,
    module_code varchar(100) NOT NULL,
    entity_type varchar(100) NOT NULL,
    version integer NOT NULL DEFAULT 1,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    description text,
    created_by uuid REFERENCES public.users(id),
    updated_by uuid REFERENCES public.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT system_workflows_version_ck CHECK (version > 0),
    CONSTRAINT system_workflows_status_ck CHECK (status IN ('DRAFT','ACTIVE','INACTIVE','ARCHIVED'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_system_workflow_code
  ON public.system_workflows(institution_id, workflow_code, version);

CREATE TABLE IF NOT EXISTS public.system_workflow_steps (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id uuid NOT NULL REFERENCES public.system_workflows(id) ON DELETE CASCADE,
    step_number integer NOT NULL,
    step_code varchar(100) NOT NULL,
    step_name varchar(255) NOT NULL,
    required_permission varchar(150),
    approver_role_code varchar(80),
    sla_hours numeric(10,2),
    is_final boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT system_workflow_step_number_ck CHECK (step_number > 0),
    CONSTRAINT system_workflow_step_sla_ck CHECK (sla_hours IS NULL OR sla_hours >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_system_workflow_step_number
  ON public.system_workflow_steps(workflow_id, step_number);

DO $$
BEGIN
    INSERT INTO public.roles(role_code, role_name, description, is_system_role)
    VALUES
      ('SYSTEM_ADMIN','System Administrator','Manages system configuration and operational controls.',true)
    ON CONFLICT (role_code) DO NOTHING;

    INSERT INTO public.permissions(permission_code, permission_name, module_code, action_code, description)
    VALUES
      ('system.config.view','View system configuration','SYSTEM','VIEW','View system configuration settings.'),
      ('system.config.manage','Manage system configuration','SYSTEM','MANAGE','Create and update system configuration.'),
      ('system.features.view','View feature flags','SYSTEM','VIEW_FEATURES','View feature flags.'),
      ('system.features.manage','Manage feature flags','SYSTEM','MANAGE_FEATURES','Manage feature flags.'),
      ('system.maintenance.view','View maintenance windows','SYSTEM','VIEW_MAINTENANCE','View scheduled maintenance windows.'),
      ('system.maintenance.manage','Manage maintenance windows','SYSTEM','MANAGE_MAINTENANCE','Manage maintenance windows.'),
      ('system.workflows.view','View system workflows','SYSTEM','VIEW_WORKFLOWS','View configured workflows.'),
      ('system.workflows.manage','Manage system workflows','SYSTEM','MANAGE_WORKFLOWS','Manage configured workflows.')
    ON CONFLICT (permission_code) DO NOTHING;

    INSERT INTO public.role_permissions(role_id, permission_id)
    SELECT r.id, p.id FROM public.roles r CROSS JOIN public.permissions p
    WHERE r.role_code IN ('ADMIN','SYSTEM_ADMIN')
      AND p.permission_code IN (
        'system.config.view','system.config.manage',
        'system.features.view','system.features.manage',
        'system.maintenance.view','system.maintenance.manage',
        'system.workflows.view','system.workflows.manage'
      )
    ON CONFLICT DO NOTHING;
END $$;

CREATE INDEX IF NOT EXISTS idx_system_settings_key
  ON public.system_settings(institution_id, setting_key);
CREATE INDEX IF NOT EXISTS idx_system_feature_flags_status
  ON public.system_feature_flags(institution_id, is_enabled);
CREATE INDEX IF NOT EXISTS idx_system_maintenance_window
  ON public.system_maintenance_windows(institution_id, status, start_at);
CREATE INDEX IF NOT EXISTS idx_system_workflows_module_status
  ON public.system_workflows(institution_id, module_code, entity_type, status);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_system_settings_updated_at') THEN
      CREATE TRIGGER trg_system_settings_updated_at BEFORE UPDATE ON public.system_settings
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_system_feature_flags_updated_at') THEN
      CREATE TRIGGER trg_system_feature_flags_updated_at BEFORE UPDATE ON public.system_feature_flags
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_system_number_sequences_updated_at') THEN
      CREATE TRIGGER trg_system_number_sequences_updated_at BEFORE UPDATE ON public.system_number_sequences
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_system_maintenance_windows_updated_at') THEN
      CREATE TRIGGER trg_system_maintenance_windows_updated_at BEFORE UPDATE ON public.system_maintenance_windows
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_system_workflows_updated_at') THEN
      CREATE TRIGGER trg_system_workflows_updated_at BEFORE UPDATE ON public.system_workflows
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_system_workflow_steps_updated_at') THEN
      CREATE TRIGGER trg_system_workflow_steps_updated_at BEFORE UPDATE ON public.system_workflow_steps
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
END $$;
