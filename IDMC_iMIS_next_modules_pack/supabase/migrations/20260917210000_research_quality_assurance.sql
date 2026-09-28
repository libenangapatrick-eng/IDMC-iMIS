-- 031: Research & Quality Assurance
-- Adds institution-wide research lifecycle and quality assurance structures.
-- No existing tables are dropped or altered.

CREATE TABLE IF NOT EXISTS public.research_projects (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions(id),
    department_id uuid REFERENCES public.departments(id),
    project_code varchar(80) NOT NULL,
    title varchar(255) NOT NULL,
    project_type varchar(40) NOT NULL DEFAULT 'RESEARCH',
    principal_investigator_user_id uuid REFERENCES public.users(id),
    start_date date,
    end_date date,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    budget_amount numeric(14,2) NOT NULL DEFAULT 0,
    funding_source varchar(255),
    abstract text,
    objectives text,
    ethics_required boolean NOT NULL DEFAULT false,
    ethics_status varchar(30) NOT NULL DEFAULT 'NOT_REQUIRED',
    created_by uuid REFERENCES public.users(id),
    updated_by uuid REFERENCES public.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT research_projects_project_type_ck
        CHECK (project_type IN ('RESEARCH','CONSULTANCY','COMMUNITY','INNOVATION','OTHER')),
    CONSTRAINT research_projects_status_ck
        CHECK (status IN ('DRAFT','SUBMITTED','APPROVED','ACTIVE','SUSPENDED','COMPLETED','CLOSED','REJECTED')),
    CONSTRAINT research_projects_ethics_status_ck
        CHECK (ethics_status IN ('NOT_REQUIRED','PENDING','SUBMITTED','APPROVED','CONDITIONAL','REJECTED','EXPIRED')),
    CONSTRAINT research_projects_budget_ck CHECK (budget_amount >= 0),
    CONSTRAINT research_projects_dates_ck CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_research_projects_code
    ON public.research_projects(project_code);

CREATE TABLE IF NOT EXISTS public.research_team_members (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES public.research_projects(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES public.users(id),
    role_title varchar(150) NOT NULL,
    allocation_percent numeric(5,2),
    joined_at date NOT NULL DEFAULT current_date,
    left_at date,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT research_team_members_allocation_ck
        CHECK (allocation_percent IS NULL OR (allocation_percent >= 0 AND allocation_percent <= 100)),
    CONSTRAINT research_team_members_dates_ck
        CHECK (left_at IS NULL OR left_at >= joined_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_research_team_member_active
    ON public.research_team_members(project_id, user_id)
    WHERE left_at IS NULL;

CREATE TABLE IF NOT EXISTS public.research_outputs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES public.research_projects(id) ON DELETE CASCADE,
    output_type varchar(40) NOT NULL,
    title varchar(255) NOT NULL,
    publication_date date,
    doi varchar(255),
    url text,
    file_url text,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    notes text,
    created_by uuid REFERENCES public.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT research_outputs_type_ck
        CHECK (output_type IN ('REPORT','ARTICLE','BOOK','CONFERENCE','POLICY_BRIEF','DATASET','SOFTWARE','THESIS','OTHER')),
    CONSTRAINT research_outputs_status_ck
        CHECK (status IN ('DRAFT','SUBMITTED','PUBLISHED','ARCHIVED','RETRACTED'))
);

CREATE TABLE IF NOT EXISTS public.research_funding (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES public.research_projects(id) ON DELETE CASCADE,
    source_name varchar(255) NOT NULL,
    reference_number varchar(150),
    amount_approved numeric(14,2) NOT NULL DEFAULT 0,
    amount_received numeric(14,2) NOT NULL DEFAULT 0,
    amount_spent numeric(14,2) NOT NULL DEFAULT 0,
    funding_status varchar(30) NOT NULL DEFAULT 'PROPOSED',
    received_date date,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT research_funding_amounts_ck
        CHECK (amount_approved >= 0 AND amount_received >= 0 AND amount_spent >= 0),
    CONSTRAINT research_funding_received_ck
        CHECK (amount_received <= amount_approved),
    CONSTRAINT research_funding_spent_ck
        CHECK (amount_spent <= amount_received),
    CONSTRAINT research_funding_status_ck
        CHECK (funding_status IN ('PROPOSED','APPROVED','PARTIALLY_RECEIVED','RECEIVED','CLOSED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS public.research_ethics_reviews (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES public.research_projects(id) ON DELETE CASCADE,
    submission_date date NOT NULL DEFAULT current_date,
    review_date date,
    decision varchar(30) NOT NULL DEFAULT 'PENDING',
    reviewer_user_id uuid REFERENCES public.users(id),
    reference_number varchar(150),
    conditions text,
    remarks text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT research_ethics_decision_ck
        CHECK (decision IN ('PENDING','APPROVED','CONDITIONAL','REJECTED','EXEMPT'))
);

CREATE TABLE IF NOT EXISTS public.quality_standards (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions(id),
    standard_code varchar(80) NOT NULL,
    standard_name varchar(255) NOT NULL,
    version varchar(40),
    description text,
    status varchar(30) NOT NULL DEFAULT 'ACTIVE',
    effective_date date,
    retired_date date,
    created_by uuid REFERENCES public.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT quality_standards_status_ck CHECK (status IN ('DRAFT','ACTIVE','RETIRED')),
    CONSTRAINT quality_standards_dates_ck CHECK (retired_date IS NULL OR effective_date IS NULL OR retired_date >= effective_date)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_quality_standard_code
    ON public.quality_standards(institution_id, standard_code);

CREATE TABLE IF NOT EXISTS public.quality_reviews (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions(id),
    standard_id uuid REFERENCES public.quality_standards(id),
    review_code varchar(80) NOT NULL,
    title varchar(255) NOT NULL,
    scope text,
    lead_user_id uuid REFERENCES public.users(id),
    start_date date,
    end_date date,
    status varchar(30) NOT NULL DEFAULT 'PLANNED',
    overall_rating numeric(5,2),
    findings_summary text,
    approved_by uuid REFERENCES public.users(id),
    approved_at timestamptz,
    created_by uuid REFERENCES public.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT quality_reviews_status_ck
        CHECK (status IN ('PLANNED','IN_PROGRESS','COMPLETED','APPROVED','CLOSED','CANCELLED')),
    CONSTRAINT quality_reviews_rating_ck
        CHECK (overall_rating IS NULL OR (overall_rating >= 0 AND overall_rating <= 100)),
    CONSTRAINT quality_reviews_dates_ck
        CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_quality_review_code
    ON public.quality_reviews(institution_id, review_code);

CREATE TABLE IF NOT EXISTS public.quality_findings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    review_id uuid NOT NULL REFERENCES public.quality_reviews(id) ON DELETE CASCADE,
    finding_code varchar(80) NOT NULL,
    category varchar(80),
    severity varchar(20) NOT NULL DEFAULT 'MEDIUM',
    finding text NOT NULL,
    root_cause text,
    evidence_url text,
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    owner_user_id uuid REFERENCES public.users(id),
    due_date date,
    resolution text,
    verified_by uuid REFERENCES public.users(id),
    verified_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT quality_findings_severity_ck CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT quality_findings_status_ck CHECK (status IN ('OPEN','IN_PROGRESS','RESOLVED','VERIFIED','CLOSED'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_quality_finding_code
    ON public.quality_findings(review_id, finding_code);

CREATE TABLE IF NOT EXISTS public.quality_actions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    finding_id uuid NOT NULL REFERENCES public.quality_findings(id) ON DELETE CASCADE,
    action_code varchar(80) NOT NULL,
    action_description text NOT NULL,
    responsible_user_id uuid REFERENCES public.users(id),
    due_date date,
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    completion_date date,
    evidence_url text,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT quality_actions_status_ck
        CHECK (status IN ('OPEN','IN_PROGRESS','COMPLETED','VERIFIED','CANCELLED')),
    CONSTRAINT quality_actions_dates_ck
        CHECK (completion_date IS NULL OR due_date IS NULL OR completion_date >= due_date)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_quality_action_code
    ON public.quality_actions(finding_id, action_code);

DO $$
BEGIN
    INSERT INTO public.roles(role_code, role_name, description, is_system_role)
    VALUES
      ('RESEARCH_OFFICER','Research Officer','Manages institutional research lifecycle.',true),
      ('QA_OFFICER','Quality Assurance Officer','Manages quality assurance activities.',true)
    ON CONFLICT (role_code) DO NOTHING;

    INSERT INTO public.permissions(permission_code, permission_name, module_code, action_code, description)
    VALUES
      ('research.view','View research','RESEARCH','VIEW','View research records.'),
      ('research.manage','Manage research','RESEARCH','MANAGE','Create and update research records.'),
      ('research.approve','Approve research','RESEARCH','APPROVE','Approve research workflow records.'),
      ('qa.view','View quality assurance','QUALITY_ASSURANCE','VIEW','View quality assurance records.'),
      ('qa.manage','Manage quality assurance','QUALITY_ASSURANCE','MANAGE','Create and update quality assurance records.'),
      ('qa.approve','Approve quality assurance','QUALITY_ASSURANCE','APPROVE','Approve quality assurance records.')
    ON CONFLICT (permission_code) DO NOTHING;

    INSERT INTO public.role_permissions(role_id, permission_id)
    SELECT r.id, p.id
    FROM public.roles r
    CROSS JOIN public.permissions p
    WHERE r.role_code IN ('ADMIN','RESEARCH_OFFICER')
      AND p.permission_code IN ('research.view','research.manage','research.approve')
    ON CONFLICT DO NOTHING;

    INSERT INTO public.role_permissions(role_id, permission_id)
    SELECT r.id, p.id
    FROM public.roles r
    CROSS JOIN public.permissions p
    WHERE r.role_code IN ('ADMIN','QA_OFFICER')
      AND p.permission_code IN ('qa.view','qa.manage','qa.approve')
    ON CONFLICT DO NOTHING;
END $$;

CREATE INDEX IF NOT EXISTS idx_research_projects_institution_status
    ON public.research_projects(institution_id, status);
CREATE INDEX IF NOT EXISTS idx_research_projects_pi
    ON public.research_projects(principal_investigator_user_id);
CREATE INDEX IF NOT EXISTS idx_research_team_members_project
    ON public.research_team_members(project_id);
CREATE INDEX IF NOT EXISTS idx_research_outputs_project_status
    ON public.research_outputs(project_id, status);
CREATE INDEX IF NOT EXISTS idx_quality_reviews_institution_status
    ON public.quality_reviews(institution_id, status);
CREATE INDEX IF NOT EXISTS idx_quality_findings_review_status
    ON public.quality_findings(review_id, status);
CREATE INDEX IF NOT EXISTS idx_quality_actions_finding_status
    ON public.quality_actions(finding_id, status);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_research_projects_updated_at') THEN
        CREATE TRIGGER trg_research_projects_updated_at
        BEFORE UPDATE ON public.research_projects
        FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_research_team_members_updated_at') THEN
        CREATE TRIGGER trg_research_team_members_updated_at
        BEFORE UPDATE ON public.research_team_members
        FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_research_outputs_updated_at') THEN
        CREATE TRIGGER trg_research_outputs_updated_at
        BEFORE UPDATE ON public.research_outputs
        FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_research_funding_updated_at') THEN
        CREATE TRIGGER trg_research_funding_updated_at
        BEFORE UPDATE ON public.research_funding
        FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_research_ethics_reviews_updated_at') THEN
        CREATE TRIGGER trg_research_ethics_reviews_updated_at
        BEFORE UPDATE ON public.research_ethics_reviews
        FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quality_standards_updated_at') THEN
        CREATE TRIGGER trg_quality_standards_updated_at
        BEFORE UPDATE ON public.quality_standards
        FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quality_reviews_updated_at') THEN
        CREATE TRIGGER trg_quality_reviews_updated_at
        BEFORE UPDATE ON public.quality_reviews
        FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quality_findings_updated_at') THEN
        CREATE TRIGGER trg_quality_findings_updated_at
        BEFORE UPDATE ON public.quality_findings
        FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quality_actions_updated_at') THEN
        CREATE TRIGGER trg_quality_actions_updated_at
        BEFORE UPDATE ON public.quality_actions
        FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
END $$;
