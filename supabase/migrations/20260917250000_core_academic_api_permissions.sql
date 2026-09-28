-- 035 Core Academic API RBAC reconciliation
-- Adds permission codes required by the core API routes and maps them to ADMIN.

DO $$
DECLARE
  r RECORD;
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS tmp_core_permissions (
    permission_code TEXT, permission_name TEXT, module_code TEXT, action_code TEXT, description TEXT
  ) ON COMMIT DROP;

  INSERT INTO tmp_core_permissions VALUES
    ('applications.view','View applications','APPLICATIONS','VIEW','View applicants and applications.'),
    ('applications.manage','Manage applications','APPLICATIONS','MANAGE','Create and update applicants and applications.'),
    ('admissions.view','View admissions','ADMISSIONS','VIEW','View admission decisions, offers and acceptances.'),
    ('admissions.manage','Manage admissions','ADMISSIONS','MANAGE','Manage admission decisions, offers and acceptances.'),
    ('students.view','View students','STUDENTS','VIEW','View student records.'),
    ('students.manage','Manage students','STUDENTS','MANAGE','Create and update student records.'),
    ('academics.view','View academics','ACADEMICS','VIEW','View academic structure and delivery data.'),
    ('academics.manage','Manage academics','ACADEMICS','MANAGE','Manage academic structure and delivery data.'),
    ('registration.view','View registration','REGISTRATION','VIEW','View registration records.'),
    ('registration.manage','Manage registration','REGISTRATION','MANAGE','Manage student and course registration.'),
    ('registration.approve','Approve registration','REGISTRATION','APPROVE','Approve registration workflows.'),
    ('timetable.view','View timetable','TIMETABLE','VIEW','View timetables and timetable entries.'),
    ('timetable.manage','Manage timetable','TIMETABLE','MANAGE','Create and edit timetables.'),
    ('timetable.publish','Publish timetable','TIMETABLE','PUBLISH','Publish timetables.'),
    ('assessment.view','View assessment','ASSESSMENT','VIEW','View assessments and marks.'),
    ('assessment.manage','Manage assessment','ASSESSMENT','MANAGE','Manage assessments and marks.'),
    ('assessment.corrections.manage','Manage assessment corrections','ASSESSMENT','CORRECTION','Review assessment mark corrections.'),
    ('examinations.view','View examinations','EXAMINATIONS','VIEW','View examination setup and records.'),
    ('examinations.manage','Manage examinations','EXAMINATIONS','MANAGE','Manage examination periods, papers and candidates.'),
    ('examinations.marks.manage','Manage examination marks','EXAMINATIONS','MARKS','Enter and manage examination marks.'),
    ('examinations.corrections.manage','Manage examination corrections','EXAMINATIONS','CORRECTION','Review examination mark corrections.'),
    ('results.view','View results','RESULTS','VIEW','View academic results.'),
    ('results.manage','Manage results','RESULTS','MANAGE','Manage calculated academic results.'),
    ('results.approve','Approve results','RESULTS','APPROVE','Approve semester and standing results.'),
    ('results.corrections.manage','Manage result corrections','RESULTS','CORRECTION','Review course result corrections.'),
    ('transcripts.view','View transcripts','TRANSCRIPTS','VIEW','View student transcripts.'),
    ('transcripts.manage','Manage transcripts','TRANSCRIPTS','MANAGE','Generate, approve and issue transcripts.'),
    ('graduation.view','View graduation','GRADUATION','VIEW','View graduation candidates, clearances and awards.'),
    ('graduation.manage','Manage graduation','GRADUATION','MANAGE','Manage graduation preparation records.'),
    ('graduation.approve','Approve graduation','GRADUATION','APPROVE','Approve graduation candidates and awards.'),
    ('alumni.view','View alumni','ALUMNI','VIEW','View alumni records.'),
    ('alumni.manage','Manage alumni','ALUMNI','MANAGE','Manage alumni records.');

  INSERT INTO public.permissions(permission_code,permission_name,module_code,action_code,description,status)
  SELECT permission_code,permission_name,module_code,action_code,description,'ACTIVE'
  FROM tmp_core_permissions t
  WHERE NOT EXISTS (SELECT 1 FROM public.permissions p WHERE p.permission_code=t.permission_code);

  FOR r IN SELECT id FROM public.roles WHERE role_code='ADMIN' AND status='ACTIVE' LOOP
    INSERT INTO public.role_permissions(role_id,permission_id)
    SELECT r.id,p.id FROM public.permissions p
    WHERE p.permission_code IN (SELECT permission_code FROM tmp_core_permissions)
      AND NOT EXISTS (SELECT 1 FROM public.role_permissions rp WHERE rp.role_id=r.id AND rp.permission_id=p.id);
  END LOOP;
END $$;
