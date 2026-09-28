-- 032: Communications, Institutional Documents & Helpdesk
-- Adds general-purpose records without changing student/staff document tables.

CREATE TABLE IF NOT EXISTS public.announcements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions(id),
    announcement_number varchar(100) NOT NULL,
    title varchar(255) NOT NULL,
    summary text,
    body text NOT NULL,
    announcement_type varchar(50) NOT NULL DEFAULT 'GENERAL',
    priority varchar(20) NOT NULL DEFAULT 'NORMAL',
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    publish_at timestamptz,
    expire_at timestamptz,
    published_by uuid REFERENCES public.users(id),
    published_at timestamptz,
    created_by uuid REFERENCES public.users(id),
    updated_by uuid REFERENCES public.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT announcements_priority_ck CHECK (priority IN ('LOW','NORMAL','HIGH','URGENT')),
    CONSTRAINT announcements_status_ck CHECK (status IN ('DRAFT','SCHEDULED','PUBLISHED','EXPIRED','CANCELLED')),
    CONSTRAINT announcements_dates_ck CHECK (expire_at IS NULL OR publish_at IS NULL OR expire_at >= publish_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_announcements_number
    ON public.announcements(institution_id, announcement_number);

CREATE TABLE IF NOT EXISTS public.announcement_audiences (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    announcement_id uuid NOT NULL REFERENCES public.announcements(id) ON DELETE CASCADE,
    audience_type varchar(30) NOT NULL,
    audience_ref_id uuid,
    audience_label varchar(255),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT announcement_audiences_type_ck
      CHECK (audience_type IN ('ALL','ROLE','STUDENT','STAFF','DEPARTMENT','SCHOOL','PROGRAMME','CAMPUS','CUSTOM'))
);

CREATE TABLE IF NOT EXISTS public.documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions(id),
    document_number varchar(100) NOT NULL,
    title varchar(255) NOT NULL,
    document_type varchar(100) NOT NULL,
    module_code varchar(100),
    entity_type varchar(100),
    entity_id uuid,
    visibility varchar(30) NOT NULL DEFAULT 'PRIVATE',
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    current_version integer NOT NULL DEFAULT 1,
    file_name varchar(255),
    mime_type varchar(120),
    file_size_bytes bigint,
    file_url text,
    storage_path text,
    description text,
    owner_user_id uuid REFERENCES public.users(id),
    created_by uuid REFERENCES public.users(id),
    updated_by uuid REFERENCES public.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT documents_visibility_ck CHECK (visibility IN ('PRIVATE','INTERNAL','PUBLIC','ROLE_RESTRICTED')),
    CONSTRAINT documents_status_ck CHECK (status IN ('DRAFT','ACTIVE','ARCHIVED','EXPIRED','REVOKED')),
    CONSTRAINT documents_version_ck CHECK (current_version > 0),
    CONSTRAINT documents_file_size_ck CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_documents_number
    ON public.documents(institution_id, document_number);

CREATE TABLE IF NOT EXISTS public.document_versions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id uuid NOT NULL REFERENCES public.documents(id) ON DELETE CASCADE,
    version_number integer NOT NULL,
    file_name varchar(255),
    mime_type varchar(120),
    file_size_bytes bigint,
    file_url text,
    storage_path text,
    change_summary text,
    uploaded_by uuid REFERENCES public.users(id),
    uploaded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT document_versions_version_ck CHECK (version_number > 0),
    CONSTRAINT document_versions_size_ck CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_document_versions_number
    ON public.document_versions(document_id, version_number);

CREATE TABLE IF NOT EXISTS public.helpdesk_categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions(id),
    category_code varchar(80) NOT NULL,
    category_name varchar(150) NOT NULL,
    description text,
    default_priority varchar(20) NOT NULL DEFAULT 'NORMAL',
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT helpdesk_categories_priority_ck CHECK (default_priority IN ('LOW','NORMAL','HIGH','URGENT')),
    CONSTRAINT helpdesk_categories_status_ck CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_helpdesk_category_code
    ON public.helpdesk_categories(institution_id, category_code);

CREATE TABLE IF NOT EXISTS public.helpdesk_tickets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions(id),
    ticket_number varchar(100) NOT NULL,
    category_id uuid REFERENCES public.helpdesk_categories(id),
    requester_user_id uuid REFERENCES public.users(id),
    requester_student_id uuid REFERENCES public.students(id),
    assigned_to_user_id uuid REFERENCES public.users(id),
    subject varchar(255) NOT NULL,
    description text NOT NULL,
    priority varchar(20) NOT NULL DEFAULT 'NORMAL',
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    source varchar(30) NOT NULL DEFAULT 'WEB',
    due_at timestamptz,
    first_response_at timestamptz,
    resolved_at timestamptz,
    closed_at timestamptz,
    resolution_summary text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT helpdesk_tickets_priority_ck CHECK (priority IN ('LOW','NORMAL','HIGH','URGENT')),
    CONSTRAINT helpdesk_tickets_status_ck CHECK (status IN ('OPEN','IN_PROGRESS','WAITING_USER','RESOLVED','CLOSED','CANCELLED')),
    CONSTRAINT helpdesk_tickets_source_ck CHECK (source IN ('WEB','EMAIL','PHONE','IN_PERSON','SYSTEM'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_helpdesk_ticket_number
    ON public.helpdesk_tickets(institution_id, ticket_number);

CREATE TABLE IF NOT EXISTS public.helpdesk_messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id uuid NOT NULL REFERENCES public.helpdesk_tickets(id) ON DELETE CASCADE,
    sender_user_id uuid REFERENCES public.users(id),
    sender_student_id uuid REFERENCES public.students(id),
    message_type varchar(30) NOT NULL DEFAULT 'COMMENT',
    body text NOT NULL,
    is_internal boolean NOT NULL DEFAULT false,
    attachment_url text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT helpdesk_messages_type_ck CHECK (message_type IN ('COMMENT','RESPONSE','NOTE','SYSTEM'))
);

DO $$
BEGIN
    INSERT INTO public.roles(role_code, role_name, description, is_system_role)
    VALUES
      ('COMMUNICATIONS_OFFICER','Communications Officer','Manages announcements and institutional communications.',true),
      ('DOCUMENTS_OFFICER','Documents Officer','Manages institutional documents repository.',true),
      ('HELPDESK_OFFICER','Helpdesk Officer','Manages service desk tickets.',true)
    ON CONFLICT (role_code) DO NOTHING;

    INSERT INTO public.permissions(permission_code, permission_name, module_code, action_code, description)
    VALUES
      ('communications.view','View communications','COMMUNICATIONS','VIEW','View institutional announcements and communication records.'),
      ('communications.manage','Manage communications','COMMUNICATIONS','MANAGE','Create and update communication records.'),
      ('communications.publish','Publish communications','COMMUNICATIONS','PUBLISH','Publish scheduled institutional communications.'),
      ('documents.view','View institutional documents','DOCUMENTS','VIEW','View the document repository.'),
      ('documents.manage','Manage institutional documents','DOCUMENTS','MANAGE','Create and update document records and versions.'),
      ('helpdesk.view','View helpdesk','HELPDESK','VIEW','View helpdesk tickets and messages.'),
      ('helpdesk.manage','Manage helpdesk','HELPDESK','MANAGE','Create and update helpdesk records.'),
      ('helpdesk.assign','Assign helpdesk tickets','HELPDESK','ASSIGN','Assign tickets to officers.'),
      ('helpdesk.resolve','Resolve helpdesk tickets','HELPDESK','RESOLVE','Resolve and close helpdesk tickets.')
    ON CONFLICT (permission_code) DO NOTHING;

    INSERT INTO public.role_permissions(role_id, permission_id)
    SELECT r.id, p.id FROM public.roles r CROSS JOIN public.permissions p
    WHERE r.role_code IN ('ADMIN','COMMUNICATIONS_OFFICER')
      AND p.permission_code IN ('communications.view','communications.manage','communications.publish')
    ON CONFLICT DO NOTHING;

    INSERT INTO public.role_permissions(role_id, permission_id)
    SELECT r.id, p.id FROM public.roles r CROSS JOIN public.permissions p
    WHERE r.role_code IN ('ADMIN','DOCUMENTS_OFFICER')
      AND p.permission_code IN ('documents.view','documents.manage')
    ON CONFLICT DO NOTHING;

    INSERT INTO public.role_permissions(role_id, permission_id)
    SELECT r.id, p.id FROM public.roles r CROSS JOIN public.permissions p
    WHERE r.role_code IN ('ADMIN','HELPDESK_OFFICER')
      AND p.permission_code IN ('helpdesk.view','helpdesk.manage','helpdesk.assign','helpdesk.resolve')
    ON CONFLICT DO NOTHING;
END $$;

CREATE INDEX IF NOT EXISTS idx_announcements_status_publish
  ON public.announcements(institution_id, status, publish_at);
CREATE INDEX IF NOT EXISTS idx_document_entities
  ON public.documents(module_code, entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_helpdesk_tickets_queue
  ON public.helpdesk_tickets(institution_id, status, priority, assigned_to_user_id);
CREATE INDEX IF NOT EXISTS idx_helpdesk_messages_ticket
  ON public.helpdesk_messages(ticket_id, created_at);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_announcements_updated_at') THEN
      CREATE TRIGGER trg_announcements_updated_at BEFORE UPDATE ON public.announcements
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_documents_updated_at') THEN
      CREATE TRIGGER trg_documents_updated_at BEFORE UPDATE ON public.documents
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_helpdesk_categories_updated_at') THEN
      CREATE TRIGGER trg_helpdesk_categories_updated_at BEFORE UPDATE ON public.helpdesk_categories
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_helpdesk_tickets_updated_at') THEN
      CREATE TRIGGER trg_helpdesk_tickets_updated_at BEFORE UPDATE ON public.helpdesk_tickets
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
    END IF;
END $$;
