-- IDMC iMIS corrective release: academic operations, NECTA registration
-- identity, historical reference data and safe Admissions archiving.
BEGIN;

ALTER TABLE public.students ADD COLUMN IF NOT EXISTS registration_number varchar(50);
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS source_index_number varchar(50);
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS source_exam_year integer;
CREATE UNIQUE INDEX IF NOT EXISTS ux_students_registration_number
 ON public.students(upper(registration_number)) WHERE registration_number IS NOT NULL;

ALTER TABLE public.applications ADD COLUMN IF NOT EXISTS archived_at timestamptz;
ALTER TABLE public.applications ADD COLUMN IF NOT EXISTS archived_by uuid REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.applications ADD COLUMN IF NOT EXISTS archive_reason text;

-- Earlier admissions hardening referenced column names that do not exist in
-- the authoritative admission_offers table.  Recreate the validation against
-- programme_id and decision_id so issuing a real offer cannot fail at runtime.
CREATE OR REPLACE FUNCTION public.validate_admission_offer()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF NOT EXISTS (
   SELECT 1 FROM public.application_choices ac
   WHERE ac.application_id=NEW.application_id AND ac.programme_id=NEW.programme_id
 ) THEN RAISE EXCEPTION 'Admission offer programme is not a selected application choice'; END IF;
 IF NEW.decision_id IS NOT NULL AND NOT EXISTS (
   SELECT 1 FROM public.admission_decisions ad
   WHERE ad.id=NEW.decision_id AND ad.application_id=NEW.application_id AND ad.decision_status='APPROVED'
 ) THEN RAISE EXCEPTION 'Admission offer must reference an approved decision for this application'; END IF;
 IF NEW.offer_status IN ('ISSUED','ACCEPTED') AND NEW.expiry_date IS NULL THEN
   RAISE EXCEPTION 'Issued or accepted offers require an expiry date';
 END IF;
 IF NEW.offer_status='ISSUED' AND NEW.expiry_date<current_date THEN
   RAISE EXCEPTION 'Cannot issue an expired admission offer';
 END IF;
 RETURN NEW;
END $$;

CREATE TABLE IF NOT EXISTS public.student_identifiers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE RESTRICT,
 identifier_type varchar(30) NOT NULL CHECK(identifier_type IN ('STUDENT_NUMBER','REGISTRATION_NUMBER','FORM_IV_INDEX')),
 identifier_value varchar(100) NOT NULL,
 is_primary boolean NOT NULL DEFAULT false,
 valid_from date NOT NULL DEFAULT current_date,
 valid_to date,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(identifier_type,identifier_value),
 UNIQUE(student_id,identifier_type)
);

CREATE OR REPLACE FUNCTION public.generate_idms_registration_number(p_index_number text,p_completion_year integer)
RETURNS varchar LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE v text:=upper(regexp_replace(coalesce(p_index_number,''),'[[:space:]]','','g')); v_year integer:=p_completion_year;
BEGIN
 IF v ~ '^S[0-9]{4}[-/][0-9]{4}/[0-9]{4}$' THEN
   v_year:=substring(v from '/([0-9]{4})$')::integer;
   v:=regexp_replace(v,'/([0-9]{4})$','');
 END IF;
 IF v !~ '^S[0-9]{4}[-/][0-9]{4}$' THEN RETURN NULL; END IF;
 IF v_year IS NULL OR v_year < 1950 OR v_year > extract(year from current_date)::integer THEN RETURN NULL; END IF;
 RETURN ('N'||replace(v,'-','/')||'/'||v_year::text)::varchar;
END $$;

CREATE OR REPLACE FUNCTION public.assign_student_registration_number() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE q record; generated varchar;
BEGIN
 IF NEW.registration_number IS NOT NULL THEN
   NEW.registration_number:=upper(trim(NEW.registration_number)); RETURN NEW;
 END IF;
 SELECT aq.index_number,aq.completion_year INTO q FROM public.academic_qualifications aq
 WHERE aq.applicant_id=NEW.applicant_id AND aq.index_number IS NOT NULL
 ORDER BY CASE WHEN upper(aq.award_name) IN ('CSE','CSEE') OR upper(aq.qualification_type) IN ('SECONDARY','ORDINARY LEVEL (CSE)') THEN 0 ELSE 1 END,aq.created_at LIMIT 1;
 generated:=public.generate_idms_registration_number(q.index_number,q.completion_year);
 IF generated IS NOT NULL THEN NEW.registration_number:=generated;NEW.source_index_number:=upper(q.index_number);NEW.source_exam_year:=q.completion_year;END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_assign_student_registration_number ON public.students;
CREATE TRIGGER trg_assign_student_registration_number BEFORE INSERT OR UPDATE OF applicant_id,registration_number ON public.students
 FOR EACH ROW EXECUTE FUNCTION public.assign_student_registration_number();

CREATE OR REPLACE FUNCTION public.sync_student_identifiers() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 INSERT INTO public.student_identifiers(student_id,identifier_type,identifier_value,is_primary)
 VALUES(NEW.id,'STUDENT_NUMBER',NEW.student_number,NEW.registration_number IS NULL)
 ON CONFLICT(student_id,identifier_type) DO UPDATE SET identifier_value=excluded.identifier_value,is_primary=excluded.is_primary,valid_to=NULL;
 IF NEW.registration_number IS NOT NULL THEN
   INSERT INTO public.student_identifiers(student_id,identifier_type,identifier_value,is_primary)
   VALUES(NEW.id,'REGISTRATION_NUMBER',NEW.registration_number,true)
   ON CONFLICT(student_id,identifier_type) DO UPDATE SET identifier_value=excluded.identifier_value,is_primary=true,valid_to=NULL;
 END IF;
 IF NEW.source_index_number IS NOT NULL THEN
   INSERT INTO public.student_identifiers(student_id,identifier_type,identifier_value,is_primary)
   VALUES(NEW.id,'FORM_IV_INDEX',NEW.source_index_number,false)
   ON CONFLICT(student_id,identifier_type) DO UPDATE SET identifier_value=excluded.identifier_value,valid_to=NULL;
 END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_sync_student_identifiers ON public.students;
CREATE TRIGGER trg_sync_student_identifiers AFTER INSERT OR UPDATE OF student_number,registration_number,source_index_number ON public.students
 FOR EACH ROW EXECUTE FUNCTION public.sync_student_identifiers();

WITH preferred AS (
 SELECT DISTINCT ON(aq.applicant_id) aq.applicant_id,aq.index_number,aq.completion_year
 FROM public.academic_qualifications aq WHERE aq.index_number IS NOT NULL
 ORDER BY aq.applicant_id,CASE WHEN upper(aq.award_name) IN ('CSE','CSEE') OR upper(aq.qualification_type) IN ('SECONDARY','ORDINARY LEVEL (CSE)') THEN 0 ELSE 1 END,aq.created_at
)
UPDATE public.students s SET registration_number=public.generate_idms_registration_number(q.index_number,q.completion_year),
 source_index_number=upper(q.index_number),source_exam_year=q.completion_year
FROM preferred q WHERE q.applicant_id=s.applicant_id AND s.registration_number IS NULL
 AND public.generate_idms_registration_number(q.index_number,q.completion_year) IS NOT NULL;

INSERT INTO public.student_identifiers(student_id,identifier_type,identifier_value,is_primary)
SELECT id,'STUDENT_NUMBER',student_number,registration_number IS NULL FROM public.students
ON CONFLICT(identifier_type,identifier_value) DO NOTHING;
INSERT INTO public.student_identifiers(student_id,identifier_type,identifier_value,is_primary)
SELECT id,'REGISTRATION_NUMBER',registration_number,true FROM public.students WHERE registration_number IS NOT NULL
ON CONFLICT(identifier_type,identifier_value) DO NOTHING;
INSERT INTO public.student_identifiers(student_id,identifier_type,identifier_value,is_primary)
SELECT id,'FORM_IV_INDEX',source_index_number,false FROM public.students WHERE source_index_number IS NOT NULL
ON CONFLICT(identifier_type,identifier_value) DO NOTHING;

INSERT INTO public.academic_years(year_code,year_name,start_date,end_date,status) VALUES
 ('2023/2024','Academic Year 2023/2024','2023-09-01','2024-08-31','CLOSED'),
 ('2024/2025','Academic Year 2024/2025','2024-09-01','2025-08-31','CLOSED'),
 ('2025/2026','Academic Year 2025/2026','2025-09-01','2026-08-31','CLOSED'),
 ('2026/2027','Academic Year 2026/2027','2026-09-01','2027-08-31','ACTIVE')
ON CONFLICT(year_code) DO NOTHING;

INSERT INTO public.semesters(academic_year_id,semester_code,semester_name,semester_number,start_date,end_date,status)
SELECT ay.id,'SEM1','Semester 1 - '||ay.year_code,1,ay.start_date,(ay.start_date+interval '5 months')::date,CASE WHEN ay.status='ACTIVE' THEN 'ACTIVE' ELSE 'CLOSED' END
FROM public.academic_years ay WHERE ay.year_code IN ('2023/2024','2024/2025','2025/2026','2026/2027')
-- An installation may already use another semester_code for semester 1.
-- Untargeted conflict handling covers both unique keys:
-- (academic_year_id, semester_code) and (academic_year_id, semester_number).
ON CONFLICT DO NOTHING;
INSERT INTO public.semesters(academic_year_id,semester_code,semester_name,semester_number,start_date,end_date,status)
SELECT ay.id,'SEM2','Semester 2 - '||ay.year_code,2,(ay.start_date+interval '5 months 1 day')::date,ay.end_date,CASE WHEN ay.status='ACTIVE' THEN 'PLANNED' ELSE 'CLOSED' END
FROM public.academic_years ay WHERE ay.year_code IN ('2023/2024','2024/2025','2025/2026','2026/2027')
ON CONFLICT DO NOTHING;

INSERT INTO public.programme_versions(programme_id,version_code,version_name,effective_from,effective_to,status)
SELECT p.id,y::text,y::text||' Curriculum',make_date(y,9,1),make_date(y+1,8,31),'RETIRED'
FROM public.programmes p CROSS JOIN generate_series(2023,2026)y WHERE p.status='ACTIVE'
ON CONFLICT(programme_id,version_code) DO NOTHING;
INSERT INTO public.curricula(programme_version_id,curriculum_code,curriculum_name,effective_from,effective_to,status)
SELECT pv.id,'LEGACY-'||pv.version_code,pv.version_name,pv.effective_from,pv.effective_to,'RETIRED'
FROM public.programme_versions pv WHERE pv.version_code IN ('2023','2024','2025','2026')
ON CONFLICT(programme_version_id,curriculum_code) DO NOTHING;

INSERT INTO public.permissions(permission_code,permission_name,module_code,action_code,description,status) VALUES
 ('applications.archive','Archive applications','applications','archive','Archive an incorrect application without deleting audit history','ACTIVE'),
 ('students.identifiers.manage','Manage student registration identifiers','students','identifiers','Generate and reconcile NECTA-derived registration numbers','ACTIVE')
ON CONFLICT(permission_code) DO UPDATE SET permission_name=excluded.permission_name,description=excluded.description,status='ACTIVE',updated_at=now();
INSERT INTO public.role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p
WHERE (r.role_code IN ('SUPER_ADMIN','ADMIN','REGISTRAR','ADMISSIONS_OFFICER') AND p.permission_code='applications.archive')
 OR (r.role_code IN ('SUPER_ADMIN','REGISTRAR') AND p.permission_code='students.identifiers.manage')
ON CONFLICT(role_id,permission_id) DO NOTHING;

ALTER TABLE public.student_identifiers ENABLE ROW LEVEL SECURITY;
COMMENT ON COLUMN public.students.student_number IS 'Immutable legacy/internal student identity retained for compatibility and audit.';
COMMENT ON COLUMN public.students.registration_number IS 'Official NECTA-derived registration number, e.g. NS2438/0009/2009.';
COMMIT;
