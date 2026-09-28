-- 033: Reports, Analytics & Dashboard Widgets

CREATE TABLE IF NOT EXISTS public.report_definitions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions(id),
    report_code varchar(100) NOT NULL,
    report_name varchar(255) NOT NULL,
    module_code varchar(100) NOT NULL,
    description text,
    source_type varchar(30) NOT NULL,
    source_name varchar(255) NOT NULL,
    parameter_schema jsonb NOT NULL DEFAULT '{}'::jsonb,
    output_formats jsonb NOT NULL DEFAULT '["JSON"]'::jsonb,
    required_permission varchar(150),
    status varchar(30) NOT NULL DEFAULT 'ACTIVE',
    is_scheduled boolean NOT NULL DEFAULT false,
    created_by uuid REFERENCES public.users(id),
    updated_by uuid REFERENCES public.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT report_definitions_source_type_ck
      CHECK (source_type IN ('VIEW','FUNCTION','API')),
    CONSTRAINT report_definitions_status_ck
      CHECK (status IN ('DRAFT','ACTIVE','INACTIVE','ARCHIVED'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_report_definition_code
  ON public.report_definitions(institution_id, report_code);

CREATE TABLE IF NOT EXISTS public.report_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id uuid NOT NULL REFERENCES public.report_definitions(id),
    run_number varchar(100) NOT NULL,
    requested_by uuid REFERENCES public.users(id),
    started_at timestamptz,
    completed_at timestamptz,
    status varchar(30) NOT NULL DEFAULT 'QUEUED',
    parameters jsonb NOT NULL DEFAULT '{}'::jsonb,
    output_format varchar(30) NOT NULL DEFAULT 'JSON',
    result_location text,
    row_count integer,
    error_message text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT report_runs_status_ck
      CHECK (status IN ('QUEUED','RUNNING','COMPLETED','FAILED','CANCELLED')),
    CONSTRAINT report_runs_row_count_ck
      CHECK (row_count IS NULL OR row_count >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_report_run_number
  ON public.report_runs(run_number);

CREATE TABLE IF NOT EXISTS public.report_schedules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id uuid NOT NULL REFERENCES public.report_definitions(id) ON DELETE CASCADE,
    schedule_code varchar(100) NOT NULL,
    cron_expression varchar(120) NOT NULL,
    timezone varchar(80) NOT NULL DEFAULT 'Africa/Dar_es_Salaam',
    output_format varchar(30) NOT NULL DEFAULT 'PDF',
    recipients jsonb NOT NULL DEFAULT '[]'::jsonb,
    is_active boolean NOT NULL DEFAULT true,
    next_run_at timestamptz,
    last_run_at timestamptz,
    created_by uuid REFERENCES public.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_report_schedule_code
  ON public.report_schedules(schedule_code);

CREATE TABLE IF NOT EXISTS public.dashboard_widgets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions(id),
    widget_code varchar(100) NOT NULL,
    widget_name varchar(255) NOT NULL,
    dashboard_code varchar(100) NOT NULL,
    module_code varchar(100),
    widget_type varchar(30) NOT NULL,
    data_source_type varchar(30) NOT NULL,
    data_source_name varchar(255) NOT NULL,
    configuration jsonb NOT NULL DEFAULT '{}'::jsonb,
    required_permission varchar(150),
    position_index integer NOT NULL DEFAULT 0,
    width_units integer NOT NULL DEFAULT 12,
    is_active boolean NOT NULL DEFAULT true,
    created_by uuid REFERENCES public.users(id),
    updated_by uuid REFERENCES public.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT dashboard_widgets_type_ck CHECK (widget_type IN ('KPI','TABLE','BAR','LINE','PIE','SCATTER','PROGRESS','LIST')),
    CONSTRAINT dashboard_widgets_source_ck CHECK (data_source_type IN ('VIEW','FUNCTION','API','STATIC')),
    CONSTRAINT dashboard_widgets_position_ck CHECK (position_index >= 0),
    CONSTRAINT dashboard_widgets_width_ck CHECK (width_units BETWEEN 1 AND 12)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_dashboard_widget_code
  ON public.dashboard_widgets(institution_id, dashboard_code, widget_code);

DO $$
BEGIN
    INSERT INTO public.roles(role_code, role_name, description, is_system_role)
    VALUES
      ('REPORTS_OFFICER','Reports and Analytics Officer','Manages report definitions and scheduled reporting.',true)
    ON CONFLICT (role_code) DO NOTHING;

    INSERT INTO public.permissions(permission_code, permission_name, module_code, action_code, description)
    VALUES
      ('reports.view','View reports','REPORTS','VIEW','View report definitions and results.'),
      ('reports.manage','Manage reports','REPORTS','MANAGE','Create and update report definitions.'),
      ('reports.run','Run reports','REPORTS','RUN','Run authorised reports.'),
      ('reports.schedule','Schedule reports','REPORTS','SCHEDULE','Manage scheduled reports.'),
      ('dashboard.widgets.view','View dashboard widgets','DASHBOARD','VIEW','View dashboard widget definitions.'),
      ('dashboard.widgets.manage','Manage dashboard widgets','DASHBOARD','MANAGE','Create and update dashboard widgets.')
    ON CONFLICT (permission_code) DO NOTHING;

    INSERT INTO public.role_permissions(role_id, permission_id)
    SELECT r.id, p.id FROM public.roles r CROSS JOIN public.permissions p
    WHERE r.role_code IN ('ADMIN','REPORTS_OFFICER')
      AND p.permission_code IN ('reports.view','reports.manage','reports.run','reports.schedule',
                               'dashboard.widgets.view','dashboard.widgets.manage')
    ON CONFLICT DO NOTHING;
END $$;

CREATE INDEX IF NOT EXISTS idx_report_definitions_module_status
  ON public.report_definitions(institution_id, module_code, status);
CREATE INDEX IF NOT EXISTS idx_report_runs_report_status
  ON public.report_runs(report_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_report_schedules_active
  ON public.report_schedules(is_active, next_run_at);
CREATE INDEX IF NOT EXISTS idx_dashboard_widgets_dashboard
  ON public.dashboard_widgets(institution_id, dashboard_code, position_index);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_report_definitions_updated_at') THEN
      CREATE TRIGGER trg_report_definitions_updated_at BEFORE UPDATE ON public.report_definitions
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_report_runs_updated_at') THEN
      CREATE TRIGGER trg_report_runs_updated_at BEFORE UPDATE ON public.report_runs
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_report_schedules_updated_at') THEN
      CREATE TRIGGER trg_report_schedules_updated_at BEFORE UPDATE ON public.report_schedules
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_dashboard_widgets_updated_at') THEN
      CREATE TRIGGER trg_dashboard_widgets_updated_at BEFORE UPDATE ON public.dashboard_widgets
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
END $$;
