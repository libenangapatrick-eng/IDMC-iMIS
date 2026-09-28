-- IDMC iMIS Section 21C-21H: completion, graduation, alumni and production controls.
-- Corrective/additive migration. No official academic or financial record is deleted.
BEGIN;

ALTER TABLE public.graduation_clearances DROP CONSTRAINT IF EXISTS graduation_clearances_type_chk;
ALTER TABLE public.graduation_clearances ADD CONSTRAINT graduation_clearances_type_chk CHECK
 (clearance_type IN ('ACADEMIC','FINANCE','LIBRARY','HOSTEL','DEPARTMENT','EXAMINATION','DISCIPLINE','DOCUMENTS'));

ALTER TABLE public.graduation_approvals DROP CONSTRAINT IF EXISTS graduation_approvals_stage_chk;
ALTER TABLE public.graduation_approvals ADD CONSTRAINT graduation_approvals_stage_chk CHECK
 (approval_stage IN ('DEPARTMENT','HOD','ACADEMIC','EXAMINATION','REGISTRAR','MANAGEMENT','GRADUATION_BOARD'));

CREATE TABLE IF NOT EXISTS public.graduation_eligibility_checks (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 graduation_candidate_id uuid NOT NULL REFERENCES public.graduation_candidates(id) ON DELETE RESTRICT,
 student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE RESTRICT,
 required_courses integer NOT NULL DEFAULT 0, passed_courses integer NOT NULL DEFAULT 0,
 failed_courses integer NOT NULL DEFAULT 0, outstanding_courses integer NOT NULL DEFAULT 0,
 required_credits numeric(10,2) NOT NULL DEFAULT 0, earned_credits numeric(10,2) NOT NULL DEFAULT 0,
 final_cgpa numeric(6,3), outstanding_balance numeric(18,2) NOT NULL DEFAULT 0,
 active_library_items integer NOT NULL DEFAULT 0, unpaid_library_fines numeric(18,2) NOT NULL DEFAULT 0,
 active_hostel_allocations integer NOT NULL DEFAULT 0, unverified_documents integer NOT NULL DEFAULT 0,
 eligible boolean NOT NULL DEFAULT false, reasons jsonb NOT NULL DEFAULT '[]'::jsonb,
 calculation_version varchar(30) NOT NULL DEFAULT '21C-1.0', checked_by uuid REFERENCES public.users(id),
 checked_at timestamptz NOT NULL DEFAULT now(), created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.graduation_clearance_history (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), graduation_clearance_id uuid NOT NULL REFERENCES public.graduation_clearances(id) ON DELETE RESTRICT,
 previous_status varchar(30), new_status varchar(30) NOT NULL,
 decision_by uuid REFERENCES public.users(id), comments text, supporting_document_id uuid,
 decided_at timestamptz NOT NULL DEFAULT now(), metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS public.student_lifecycle_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE RESTRICT,
 event_type varchar(80) NOT NULL, entity_type varchar(80), entity_id uuid,
 previous_state varchar(80), new_state varchar(80), reason text, actor_user_id uuid REFERENCES public.users(id),
 event_data jsonb NOT NULL DEFAULT '{}'::jsonb, occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_graduation_eligibility_latest
 ON public.graduation_eligibility_checks(graduation_candidate_id, checked_at);
CREATE INDEX IF NOT EXISTS idx_clearance_history_clearance ON public.graduation_clearance_history(graduation_clearance_id, decided_at DESC);
CREATE INDEX IF NOT EXISTS idx_lifecycle_events_student ON public.student_lifecycle_events(student_id, occurred_at DESC);

CREATE OR REPLACE FUNCTION public.idmc_add_examination_clearance() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO public.graduation_clearances(graduation_candidate_id,clearance_type)
 VALUES(NEW.id,'EXAMINATION') ON CONFLICT(graduation_candidate_id,clearance_type) DO NOTHING;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_idmc_add_examination_clearance ON public.graduation_candidates;
CREATE TRIGGER trg_idmc_add_examination_clearance AFTER INSERT ON public.graduation_candidates
 FOR EACH ROW EXECUTE FUNCTION public.idmc_add_examination_clearance();
INSERT INTO public.graduation_clearances(graduation_candidate_id,clearance_type)
 SELECT id,'EXAMINATION' FROM public.graduation_candidates
 ON CONFLICT(graduation_candidate_id,clearance_type) DO NOTHING;

INSERT INTO public.permissions(permission_code,permission_name,module_code,action_code,description,status) VALUES
 ('lifecycle_completion.view','View lifecycle completion','lifecycle_completion','view','View eligibility, clearance, graduation and alumni status','ACTIVE'),
 ('lifecycle_completion.evaluate','Evaluate graduation eligibility','lifecycle_completion','evaluate','Calculate official graduation eligibility from source records','ACTIVE'),
 ('lifecycle_completion.manage','Manage graduation approval','lifecycle_completion','manage','Review and approve graduation candidates','ACTIVE'),
 ('lifecycle_completion.finalize','Finalize graduation and alumni','lifecycle_completion','finalize','Create final award, certificate and alumni record','ACTIVE'),
 ('graduation.clearance.academic','Academic clearance','graduation','clearance_academic','Decide academic clearance','ACTIVE'),
 ('graduation.clearance.finance','Finance clearance','graduation','clearance_finance','Decide finance clearance','ACTIVE'),
 ('graduation.clearance.library','Library clearance','graduation','clearance_library','Decide library clearance','ACTIVE'),
 ('graduation.clearance.hostel','Hostel clearance','graduation','clearance_hostel','Decide hostel clearance','ACTIVE'),
 ('graduation.clearance.department','Department clearance','graduation','clearance_department','Decide department clearance','ACTIVE'),
 ('graduation.clearance.examination','Examination clearance','graduation','clearance_examination','Decide examination clearance','ACTIVE'),
 ('graduation.clearance.documents','Document clearance','graduation','clearance_documents','Decide document clearance','ACTIVE'),
 ('graduation.clearance.discipline','Discipline clearance','graduation','clearance_discipline','Decide discipline clearance','ACTIVE'),
 ('production_readiness.view','View production readiness','system','production_readiness','Run non-destructive readiness checks','ACTIVE')
ON CONFLICT(permission_code) DO UPDATE SET permission_name=EXCLUDED.permission_name,description=EXCLUDED.description,status='ACTIVE',updated_at=now();

INSERT INTO public.role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p
WHERE r.role_code IN ('SUPER_ADMIN','ADMIN','REGISTRAR','ACADEMIC_OFFICER','EXAMINATION_OFFICER','EXAM_OFFICER','HOD','DEPUTY_HOD')
 AND p.permission_code IN ('lifecycle_completion.view','lifecycle_completion.evaluate')
ON CONFLICT(role_id,permission_id) DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE
 (r.role_code IN ('SUPER_ADMIN','REGISTRAR') AND p.permission_code IN ('lifecycle_completion.manage','lifecycle_completion.finalize','production_readiness.view')) OR
 (r.role_code IN ('SUPER_ADMIN','REGISTRAR','ACADEMIC_OFFICER') AND p.permission_code='graduation.clearance.academic') OR
 (r.role_code IN ('SUPER_ADMIN','FINANCE_MANAGER','FINANCE_OFFICER','ACCOUNTANT') AND p.permission_code='graduation.clearance.finance') OR
 (r.role_code IN ('SUPER_ADMIN','LIBRARIAN') AND p.permission_code='graduation.clearance.library') OR
 (r.role_code IN ('SUPER_ADMIN','HOSTEL_OFFICER') AND p.permission_code='graduation.clearance.hostel') OR
 (r.role_code IN ('SUPER_ADMIN','HOD','DEPUTY_HOD') AND p.permission_code='graduation.clearance.department') OR
 (r.role_code IN ('SUPER_ADMIN','EXAMINATION_OFFICER','EXAM_OFFICER') AND p.permission_code='graduation.clearance.examination') OR
 (r.role_code IN ('SUPER_ADMIN','REGISTRAR') AND p.permission_code IN ('graduation.clearance.documents','graduation.clearance.discipline'))
ON CONFLICT(role_id,permission_id) DO NOTHING;

CREATE OR REPLACE VIEW public.historical_data_quality_v AS
SELECT s.admission_year AS cohort_year,count(*) AS total_students,
 count(*) FILTER(WHERE s.programme_id IS NULL) AS missing_programmes,
 count(*) FILTER(WHERE s.programme_version_id IS NULL) AS missing_programme_versions,
 count(*) FILTER(WHERE s.curriculum_id IS NULL) AS missing_curricula,
 count(*) FILTER(WHERE NOT EXISTS(SELECT 1 FROM public.student_course_attempts a WHERE a.student_id=s.id)) AS missing_results,
 count(*) FILTER(WHERE EXISTS(SELECT 1 FROM public.graduation_candidates g WHERE g.student_id=s.id AND g.candidate_status='GRADUATED')) AS graduated,
 count(*) FILTER(WHERE EXISTS(SELECT 1 FROM public.alumni_records a WHERE a.student_id=s.id)) AS alumni
FROM public.students s WHERE s.source_type IN ('HISTORICAL_IMPORT','MANUAL_ENTRY') GROUP BY s.admission_year;

COMMENT ON TABLE public.graduation_eligibility_checks IS 'Immutable eligibility calculation snapshots; backend source records remain authoritative.';
COMMENT ON TABLE public.student_lifecycle_events IS 'Append-only audit timeline from student through graduation and alumni.';
COMMIT;
